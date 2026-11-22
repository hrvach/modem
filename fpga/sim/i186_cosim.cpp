// i186_cosim.cpp -- 80C186EB co-sim harness (C model vs RTL).
// FPGA-only: Verilator co-sim harness, not synthesizable RTL.
//
// Loads the real SV25 firmware image into BOTH models (the C core
// via i186_ref, the RTL via the harness RAM behind the top's h_*
// port), steps both instruction-by-instruction, and diffs the full
// architectural state after every step. The first mismatch stops
// the run with BOTH states printed.
//
// Stepping (see i186_ref.h): the C side steps with i186_run(cpu, 1),
// which executes exactly one instruction (or one REP iteration, or
// one interrupt entry) and returns a status. The RTL side is then
// clocked until the core starts the next instruction (pc_o changes)
// or a timeout of (C charge * 4 + 1000) clocks -- the RTL bus latency
// (~4 clocks per harness transaction through the sys FSM) exceeds
// the Table D-2 charge for short instructions (KD-13), so wall
// clocks != charged cycles; the RTL cycles_o runs ahead of the C
// cycles by the accumulated bus-latency overhead, which is tracked
// and reported separately, NOT required to be zero. After the RTL
// retires, its state is read through the core's verilator-public
// signals (top->i186_top->u_core->gpr/sreg/ip/flags/cycles) and
// compared field by field with the C state from iref_get_state().
// The FLAGS word is rebuilt from the RTL's individual flag bits
// with the 8086 layout (FLAG_BASE 0xF002, CF=0 PF=2 AF=4 ZF=6 SF=7
// TF=8 IF=9 DF=10 OF=11). A REP string loop yields one iteration
// per C step (rep_resume: IP stays at the instruction start and
// CX decrements); the harness accumulates C iterations until the
// IP changes, then clocks the RTL once for the whole REP (the RTL
// core executes a REP internally without returning to FETCH).
// pc_o does not change for a jump-to-self, so the timeout path
// covers it: after the timeout the state is compared anyway.
//
// The C glue is serviced after each C step (iref_service), which
// advances the C timers/UARTs/ICU to the new cycle count and may
// raise i186_irq in the C model. The RTL sys peripherals run on
// MODEL time, not wall clocks: the harness drives model_tick_en
// for exactly the C charged cycles of each step's RTL window
// (the first charge clocks), so the sys timers (1 count per 4
// enabled clocks) and the UART TX countdowns stay in lockstep
// with the C model despite the RTL bus-latency overhead (the
// core consumes ~4 clocks per harness transaction more than the
// C charge). Timer-register and UART-TDR writes are latched in
// the sys at the bus commit and applied at the next retire
// (pc_o change), matching the C model's last = now at the end
// of the write instruction. Both models therefore raise the
// same interrupt at the same instruction boundary; the state
// comparison catches any divergence.
//
// Interrupts on the RTL side are handled entirely by the sys/top
// (the ICU offers, the top pulses irq_i, the core latches and
// takes it, the top derives irq_ack from the IVT read). The
// harness does not inject interrupts; it only drives the
// outside-world inputs (line idle-high, no DTE RX, no NMI).
//
// HLT and BADOP stop the run: HLT freezes the RTL cycle counter
// while the C run loop burns the remaining budget (KD-5), so the
// cycle counts diverge by design after a HLT; the harness reports
// the halt and the state at the halt instead of comparing cycles.
// A bad opcode (ud_trap off) is terminal in both models.
//
// DTE output: the harness logs every byte the RTL transmits
// (dte_tx_valid pulses, from port 0x0A and UART0 TDR) and, at the
// end of a clean run, compares the byte sequence with the C
// model's DTE log (iref_dte_count / iref_dte_byte).
//
// Build: sim/Makefile target `cosim-i186` (Verilator --cc/--exe,
// i186.c compiled with gcc and linked in; see the Makefile).
// Usage: i186_cosim [c_dir] [max_instructions]
//   c_dir defaults to the c-port/c tree; max_instructions
//   defaults to 200000.
#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <vector>

#include "verilated.h"
#include "Vi186_top.h"
#include "Vi186_top_i186_top.h"
#include "Vi186_top_i186_core.h"
#include "i186_ref.h"

static const char *DEFAULT_C_DIR =
    "/home/hatch/workspace/research_notes/courier-firmware/c-port/c";

/* Harness RAM: 1 MB physical memory (the flash image is loaded at
   0x80000 by the harness, exactly as the C ref does). */
static uint8_t harness_ram[1 << 20];
static int harness_flash_id = 0;

/* DTE bytes transmitted by the RTL (port 0x0A + UART0 TDR). */
static std::vector<uint8_t> rtl_dte;

static Vi186_top *top;

/* One clock period. Services the h_* port combinationally before
   the rising edge (h_ack + h_rdata), then clocks. A write is
   performed exactly once per h_req assertion (h_served flag). */
static int h_served = 0;

/* Model-time tick enable (global catch-up): the harness enables
   the sys timers/UART TX countdowns whenever the delivered
   enabled-clock count is behind the C model's cycle count.
   Normally this delivers exactly the C charge per window. After
   an interrupt take straddles windows (the entry's cycles happen
   in one window but belong to the next C step), the deficit is
   carried over and caught up over the next few windows instead of
   being lost. tick_active is set only inside a step window; all
   other clocks (reset, EEPROM load, HLT settle) run with tick_en
   low, so no peripheral time passes there. */
static int tick_active = 0;
static uint64_t enabled_delivered = 0;
static uint64_t c_target = 0;

static void serve_h_read(void) {
    uint32_t a = top->h_addr & 0xFFFFF;
    uint16_t v;
    if (top->h_is_mmio && harness_flash_id && a >= 0xFFFF0 && a <= 0xFFFF3) {
        /* Flash-ID override (C mmrd, flash_id set). Word reads only;
           the firmware reads it as a word. */
        v = (a == 0xFFFF0) ? 0x0089 : 0x4470;
    } else {
        if (top->h_word)
            v = (uint16_t)(harness_ram[a] |
                           (harness_ram[(a + 1) & 0xFFFFF] << 8));
        else
            v = harness_ram[a];
    }
    top->h_rdata = v;
}

static void serve_h_write(void) {
    uint32_t a = top->h_addr & 0xFFFFF;
    if (top->h_is_mmio && a >= 0xFFFF0 && a <= 0xFFFF1) {
        /* Flash command (C mmwr): 0x90 sets flash_id, 0xFF clears it.
           Byte and word writes both carry the command in the low byte. */
        uint8_t cmd = (uint8_t)(top->h_wdata & 0xFF);
        if (cmd == 0x90) harness_flash_id = 1;
        else if (cmd == 0xFF) harness_flash_id = 0;
        return;
    }
    if (top->h_word) {
        harness_ram[a] = (uint8_t)(top->h_wdata & 0xFF);
        harness_ram[(a + 1) & 0xFFFFF] = (uint8_t)((top->h_wdata >> 8) & 0xFF);
    } else {
        harness_ram[a] = (uint8_t)(top->h_wdata & 0xFF);
    }
}

static void tick(void) {
    /* Model-time tick enable (global catch-up): on while the
       delivered enabled-clock count is behind the C model's cycle
       count. Set before the rising edge so the sys samples it with
       the clock. */
    int tick_en = (tick_active && enabled_delivered < c_target) ? 1 : 0;
    top->model_tick_en = tick_en;
    top->clk = 0;
    top->eval();
    /* h_req is settled after the falling edge. Answer it now so the
       sys samples h_ack on the next rising edge. */
    if (top->h_req) {
        if (top->h_wr) {
            /* Writes land once, when the transaction is first seen. */
            if (!h_served) {
                serve_h_write();
                h_served = 1;
            }
            top->h_rdata = 0;
        } else {
            serve_h_read();
        }
        top->h_ack = 1;
    } else {
        top->h_ack = 0;
        h_served = 0;
    }
    top->eval();
    top->clk = 1;
    top->eval();
    if (tick_en) enabled_delivered++;
    /* Log a DTE byte transmitted on this rising edge. */
    if (top->dte_tx_valid)
        rtl_dte.push_back(top->dte_tx_byte);
}

static void clock_n(uint64_t n) {
    for (uint64_t i = 0; i < n; i++)
        tick();
}

/* Read the RTL architectural state through the core's public signals. */
typedef struct {
    uint16_t ax, cx, dx, bx, sp, bp, si, di;
    uint16_t es, cs, ss, ds, ip, flags;
    uint64_t cycles;
    int halted;
} RtlState;

static void rtl_get_state(RtlState *s) {
    Vi186_top_i186_core *core = top->i186_top->u_core;
    memset(s, 0, sizeof *s);
    s->ax = core->gpr[0];
    s->cx = core->gpr[1];
    s->dx = core->gpr[2];
    s->bx = core->gpr[3];
    s->sp = core->gpr[4];
    s->bp = core->gpr[5];
    s->si = core->gpr[6];
    s->di = core->gpr[7];
    s->es = core->sreg[0];
    s->cs = core->sreg[1];
    s->ss = core->sreg[2];
    s->ds = core->sreg[3];
    /* Architectural IP is pc_o (instr_start_pc, the linear PC of
       the instruction currently being fetched), NOT the core's ip
       register: ip is the fetch pointer and has already advanced
       past the opcode of the instruction pc_o points at. Linear
       PC = CS*16 + IP, so IP = pc_o - CS*16. */
    s->ip = (uint16_t)((top->core_pc - ((uint32_t)core->sreg[1] << 4)) & 0xFFFF);
    /* 8086 FLAGS layout (C FLAG_BASE 0xF002: bits 15-12 and bit 1 read 1). */
    s->flags = (uint16_t)(0xF002 |
                          (core->cf << 0) | (core->pf << 2) |
                          (core->af << 4) | (core->zf << 6) |
                          (core->sf << 7) | (core->tf << 8) |
                          (core->ifl << 9) | (core->df << 10) |
                          (core->of << 11));
    s->cycles = core->cycles;
    s->halted = core->halted;
}

static void print_state(const char *label, const IState *c, const RtlState *r) {
    printf("%s\n", label);
    printf("  C:   AX=%04X CX=%04X DX=%04X BX=%04X SP=%04X BP=%04X SI=%04X DI=%04X\n",
           c->ax, c->cx, c->dx, c->bx, c->sp, c->bp, c->si, c->di);
    printf("  RTL: AX=%04X CX=%04X DX=%04X BX=%04X SP=%04X BP=%04X SI=%04X DI=%04X\n",
           r->ax, r->cx, r->dx, r->bx, r->sp, r->bp, r->si, r->di);
    printf("  C:   ES=%04X CS=%04X SS=%04X DS=%04X IP=%04X FL=%04X cyc=%llu ring=%u\n",
           c->es, c->cs, c->ss, c->ds, c->ip, c->flags,
           (unsigned long long)c->cycles, c->ring_idx);
    printf("  RTL: ES=%04X CS=%04X SS=%04X DS=%04X IP=%04X FL=%04X cyc=%llu halted=%d\n",
           r->es, r->cs, r->ss, r->ds, r->ip, r->flags,
           (unsigned long long)r->cycles, r->halted);
}

/* Returns the number of differing fields (0 = match). */
static int diff_state(const IState *c, const RtlState *r, uint64_t step) {
    int diffs = 0;
#define CMP(field, fmt) \
    if (c->field != r->field) { \
        printf("  MISMATCH step %llu: " #field " C=" fmt " RTL=" fmt "\n", \
               (unsigned long long)step, c->field, r->field); \
        diffs++; \
    }
    CMP(ax, "%04X") CMP(cx, "%04X") CMP(dx, "%04X") CMP(bx, "%04X")
    CMP(sp, "%04X") CMP(bp, "%04X") CMP(si, "%04X") CMP(di, "%04X")
    CMP(es, "%04X") CMP(cs, "%04X") CMP(ss, "%04X") CMP(ds, "%04X")
    CMP(ip, "%04X") CMP(flags, "%04X")
#undef CMP
    /* Cycles are NOT compared here: the RTL wall clocks run ahead
       of the C charged cycles by the bus-latency overhead (KD-13);
       the caller tracks and reports the cumulative overhead. */
    return diffs;
}

int main(int argc, char **argv) {
    const char *c_dir = (argc > 1) ? argv[1] : DEFAULT_C_DIR;
    uint64_t max_instr = (argc > 2) ? strtoull(argv[2], NULL, 10) : 200000;

    Verilated::commandArgs(argc, argv);
    top = new Vi186_top;
    RtlState zero_rtl;
    memset(&zero_rtl, 0, sizeof zero_rtl);

    /* --- C reference model --- */
    IRef *ref = iref_new();
    if (iref_load_firmware(ref, c_dir) != 0) {
        printf("COSIM FAIL: cannot load firmware from %s\n", c_dir);
        return 1;
    }
    /* The C ref owns its own 1 MB RAM; the harness RAM is a separate
       copy. Load the same flash image into the harness RAM. */
    {
        char path[1024];
        snprintf(path, sizeof path, "%s/fw/SV25.flash.bin", c_dir);
        FILE *f = fopen(path, "rb");
        if (!f) {
            printf("COSIM FAIL: cannot open %s\n", path);
            return 1;
        }
        memset(harness_ram, 0, sizeof harness_ram);
        size_t n = fread(harness_ram + 0x80000, 1, 0x80000, f);
        fclose(f);
        if (n != 0x80000) {
            printf("COSIM FAIL: short flash image (%zu bytes)\n", n);
            return 1;
        }
    }
    /* NVRAM image into the RTL EEPROM (harness writes while rst_n==0). */
    uint8_t nvram[512];
    {
        char path[1024];
        snprintf(path, sizeof path, "%s/fw/nvram.bin", c_dir);
        FILE *f = fopen(path, "rb");
        if (!f) {
            printf("COSIM FAIL: cannot open %s\n", path);
            return 1;
        }
        size_t n = fread(nvram, 1, sizeof nvram, f);
        fclose(f);
        if (n != sizeof nvram) {
            printf("COSIM FAIL: short NVRAM image (%zu bytes)\n", n);
            return 1;
        }
    }

    /* --- RTL reset + configuration --- */
    top->rst_n = 0;
    top->clk = 0;
    top->model_tick_en = 0;
    top->nmi_req = 0;
    top->cyc_model = 1;
    top->ud_trap = 1;
    top->h_rdata = 0;
    top->h_ack = 0;
    top->dte_rx_valid = 0;
    top->dte_rx_byte = 0;
    top->line = 1;
    top->port_in_10 = 0x00;
    top->port_in_12 = 0x9A;
    top->port_in_14 = 0x44;
    top->hw_idx = 7;
    top->ring_on = 0;
    top->hb_count = 0;
    top->hb_ticks = 3;
    top->p2pin_in = 0x40;
    top->ee_load_en = 0;
    top->ee_load_addr = 0;
    top->ee_load_data = 0;
    top->eval();

    /* Load the EEPROM while reset is held. */
    for (int i = 0; i < 256; i++) {
        top->ee_load_en = 1;
        top->ee_load_addr = (uint8_t)i;
        top->ee_load_data = (uint16_t)(nvram[2 * i] |
                                       (nvram[2 * i + 1] << 8));
        tick();
    }
    top->ee_load_en = 0;
    top->eval();

    /* Release reset. No settle clocks: the RTL cycle counter must
       start at 0, exactly like the C model's, so the per-step
       charge comparison is exact. The core starts fetching on the
       first clock of the first step. */
    top->rst_n = 1;
    top->eval();

    /* Sanity: both models at the reset vector. */
    {
        IState cs;
        RtlState rs;
        iref_get_state(ref, &cs);
        rtl_get_state(&rs);
        if (cs.cs != 0xFFFF || cs.ip != 0x0000 || cs.flags != 0xF002 ||
            rs.cs != 0xFFFF || rs.ip != 0x0000 || rs.flags != 0xF002) {
            printf("COSIM FAIL: reset state wrong\n");
            print_state("reset state:", &cs, &rs);
            return 1;
        }
        printf("COSIM reset OK: CS=FFFF IP=0000 FLAGS=F002 (both)\n");
    }

    /* --- Main step loop --- */
    uint64_t step = 0;
    int rc = 0;
    uint64_t total_overhead = 0; /* RTL cycles - C cycles, cumulative */
    uint64_t max_overhead = 0;   /* largest single-step overhead */
    uint64_t rep_accum = 0;      /* C steps folded into one RTL clocking */
    for (step = 0; step < max_instr; step++) {
        IState before, after;
        RtlState rtl;
        uint32_t delta = 0;
        iref_get_state(ref, &before);
        /* Pre-step sync check: the RTL pc_o (next instruction to
           fetch) must equal the C IP (next instruction to execute).
           If they differ here, the models were already out of sync
           before this step (a retire-detection or REP issue), not
           because of this instruction. */
        {
            uint16_t rtl_ip_pre = (uint16_t)((top->core_pc -
                ((uint32_t)top->i186_top->u_core->sreg[1] << 4)) & 0xFFFF);
            if (rtl_ip_pre != before.ip || top->i186_top->u_core->sreg[1] != before.cs) {
                printf("COSIM step %llu: PRE-STEP DESYNC: C=%04X:%04X, "
                       "RTL pc_o=%05X (ip=%04X cs=%04X)\n",
                       (unsigned long long)step, before.cs, before.ip,
                       (unsigned)top->core_pc, rtl_ip_pre,
                       (unsigned)top->i186_top->u_core->sreg[1]);
            }
        }
        int st = iref_step(ref, &delta);
        iref_service(ref);
        iref_get_state(ref, &after);

        if (delta != 1) {
            printf("COSIM step %llu: C executed %u instructions (expected 1); "
                   "stopping\n", (unsigned long long)step, delta);
            print_state("C state at the unexpected step:", &after,
                        &zero_rtl);
            rc = 2;
            break;
        }
        if (st == 3 /* ST_HLT */) {
            clock_n(4);
            rtl_get_state(&rtl);
            printf("COSIM step %llu: C HALTED (ST_HLT); RTL halted=%d "
                   "cycles C=%llu RTL=%llu\n",
                   (unsigned long long)step, rtl.halted,
                   (unsigned long long)after.cycles,
                   (unsigned long long)rtl.cycles);
            print_state("state at HLT:", &after, &rtl);
            if (!rtl.halted) {
                printf("COSIM FAIL: C halted but RTL did not\n");
                rc = 2;
            } else {
                printf("COSIM HALT: both models halted at step %llu\n",
                       (unsigned long long)step);
                rc = 0;
            }
            step++;
            break;
        }
        if (st == 2 /* ST_BADOP */) {
            clock_n(4);
            rtl_get_state(&rtl);
            printf("COSIM step %llu: C BADOP (ST_BADOP); RTL badop=%d pc=%05X op=%02X\n",
                   (unsigned long long)step, (int)top->core_badop,
                   (unsigned)top->core_badop_pc, (unsigned)top->core_badop_opcode);
            print_state("state at BADOP:", &after, &rtl);
            rc = top->core_badop ? 0 : 2;
            step++;
            break;
        }
        if (st != 0 && st != 4 /* ST_STOP */) {
            printf("COSIM step %llu: unexpected C status %d; stopping\n",
                   (unsigned long long)step, st);
            print_state("C state:", &after, &zero_rtl);
            rc = 2;
            break;
        }
        /* ST_STOP (4): the glue called i186_stop() from inside a
           hook (PCB timer/UART/ICU write) to end the driver's run
           chunk. The instruction executed fully; the state is valid
           and the step is normal. The RTL has no equivalent. */

        /* REP accumulation: one C step is one iteration (IP stays at
           the instruction start, CX decrements). Keep stepping the C
           model (no RTL clocks yet) until the IP moves (REP done)
           or CX stops decreasing. A jump-to-self also leaves IP
           unchanged but does not touch CX, so it is not accumulated. */
        uint64_t charge = after.cycles - before.cycles;
        if (charge == 0) {
            printf("COSIM step %llu: C charged 0 cycles; stopping\n",
                   (unsigned long long)step);
            print_state("C state:", &after, &zero_rtl);
            rc = 2;
            break;
        }
        while (after.ip == before.ip && after.cx < before.cx) {
            IState rep_before = after;
            uint32_t rep_delta = 0;
            int rep_st = iref_step(ref, &rep_delta);
            iref_service(ref);
            iref_get_state(ref, &after);
            if (rep_delta != 1 || (rep_st != 0 && rep_st != 4)) {
                printf("COSIM step %llu: REP iteration status %d delta %u; stopping\n",
                       (unsigned long long)step, rep_st, rep_delta);
                print_state("C state:", &after, &zero_rtl);
                rc = 2;
                break;
            }
            charge += after.cycles - rep_before.cycles;
            rep_accum++;
            /* REP iterations are part of ONE instruction: they do
               not consume the step budget (step counts outer
               instructions). Cap at 65536 (CX is 16-bit); exceeding
               it means the REP never terminates. */
            if (rep_accum > 65536) {
                printf("COSIM step %llu: REP iteration cap exceeded; stopping\n",
                       (unsigned long long)step);
                print_state("C state:", &after, &zero_rtl);
                rc = 2;
                break;
            }
        }
        if (rc != 0) break;

        /* Clock the RTL until it starts the next instruction
           (pc_o changes) or the timeout (charge + 64 clocks).
           pc_o does not change for a jump-to-self, so the timeout
           path covers it. */
        uint32_t start_pc = top->core_pc;
        /* Timeout scales with the charge: a REP accumulates many
           iterations, each costing bus-latency overhead on top of
           its C charge, so a fixed +64 is far too small (a 600-
           iteration REP needs ~4x its charge). The pc_o change is
           the real retire signal; the timeout only covers
           jump-to-self (pc_o never changes). */
        uint64_t timeout = charge * 4 + 1000;
        uint64_t used = 0;
        int retired = 0;
        uint32_t pc_trace[16];
        uint64_t trace_n = 0;
        /* Model time for this window: the catch-up target is the C
           cycle count after this step. The RTL never retires in
           fewer clocks than the charge in this workload (measured
           over 7,769 steps), so the window is long enough to
           deliver the charge; the timers see exactly charge
           enabled clocks per step. */
        c_target = after.cycles;
        tick_active = 1;
        while (used < timeout) {
            tick();
            used++;
            if (trace_n < 16) pc_trace[trace_n++] = top->core_pc;
            if (top->core_pc != start_pc) { retired = 1; break; }
        }
        tick_active = 0;
        rtl_get_state(&rtl);
        /* Interrupt-take alignment: the C model's i186_run(cpu, 1)
           is a cycle-budget loop -- one iteration is (do_int if an
           IRQ is pending) + one instruction. So when the C takes an
           external interrupt, the step charges the entry (42) PLUS
           the first handler instruction, and the C lands past the
           handler entry (e.g. 44 = 42 + 2 for the STI at 030C).
           The RTL window stops when pc_o reaches the handler entry,
           so the RTL is one instruction behind. Detect it (both
           models pushed an interrupt frame, SP-6, and the C is past
           the handler entry) and extend the RTL window until it
           executes the first handler instruction too. A fault or an
           INT instruction also pushes a frame, but lands AT the
           handler entry (no handler instruction executed), so the
           after.IP != pc_o check keeps this from firing there.
           The model-time target for this step is already met
           (charge includes the handler instruction's cycles), so
           the extension clocks run with tick_en off -- the
           peripherals have already advanced by exactly charge. */
        if (after.sp == (uint16_t)(before.sp - 6) &&
            rtl.sp == (uint16_t)(before.sp - 6)) {
            uint32_t c_lin = ((uint32_t)after.cs << 4) + after.ip;
            if (c_lin != top->core_pc) {
                uint32_t handler_pc = top->core_pc;
                uint64_t ext_used = 0;
                uint64_t ext_timeout = charge * 4 + 1000;
                while (ext_used < ext_timeout) {
                    tick();
                    ext_used++;
                    if (top->core_pc != handler_pc) break;
                }
                used += ext_used;
                rtl_get_state(&rtl);
            }
        }
        /* Interrupt-take alignment (RTL early): the core takes an
           interrupt at the finish of the current instruction, so
           the RTL window can end with the entry already taken
           (SP-6, pc_o at the handler) while the C model has not
           taken it yet -- it takes it at the top of the NEXT
           iref_step. Step the C once more (the interrupt take:
           entry + first handler instruction) and extend the RTL
           window through the first handler instruction, so both
           land past the handler entry and can be compared. The
           extra C step's cycles join the catch-up target; the
           extension runs with tick_en on, so the entry's cycles
           are delivered over the next few windows. The extra C
           step consumed one more instruction, so step is advanced
           once here (the loop increments it once more) and the
           next iteration is the instruction after the handler
           instruction. The handler's first instruction is not a
           REP in this firmware (STI/PUSHA), so no REP accumulation
           is needed here. */
        if (rtl.sp == (uint16_t)(before.sp - 6) &&
            after.sp == before.sp) {
            IState after2;
            uint32_t delta2 = 0;
            int st2 = iref_step(ref, &delta2);
            iref_service(ref);
            iref_get_state(ref, &after2);
            if (delta2 != 1 || st2 != 0) {
                printf("COSIM step %llu: interrupt-take follow-up step "
                       "status %d delta %u; stopping\n",
                       (unsigned long long)step, st2, delta2);
                print_state("C state:", &after2, &zero_rtl);
                rc = 2;
                break;
            }
            charge += after2.cycles - after.cycles;
            after = after2;
            c_target = after.cycles;
            {
                uint32_t handler_pc = top->core_pc;
                uint64_t ext_used = 0;
                uint64_t ext_timeout = charge * 4 + 1000;
                tick_active = 1;
                while (ext_used < ext_timeout) {
                    tick();
                    ext_used++;
                    if (top->core_pc != handler_pc) break;
                }
                tick_active = 0;
                used += ext_used;
                rtl_get_state(&rtl);
            }
            step++;
        }
        int64_t cum_overhead = (int64_t)rtl.cycles - (int64_t)after.cycles;
        uint64_t step_overhead = 0;
        if (cum_overhead > (int64_t)total_overhead)
            step_overhead = (uint64_t)(cum_overhead - (int64_t)total_overhead);
        if (cum_overhead > 0) total_overhead = (uint64_t)cum_overhead;
        if (step_overhead > max_overhead) max_overhead = step_overhead;
        if (!retired) {
            printf("COSIM step %llu: pc_o did not change after %llu clocks "
                   "(charge=%llu, C pc=%04X:%04X); comparing state anyway\n",
                   (unsigned long long)step, (unsigned long long)used,
                   (unsigned long long)charge, after.cs, after.ip);
        }

        if (diff_state(&after, &rtl, step) != 0) {
            printf("COSIM FAIL: first mismatch at step %llu "
                   "(C pc=%04X:%04X, RTL pc=%04X:%04X, charge=%llu, "
                   "rtl_clocks=%llu, retired=%d, overhead=%llu, start_pc=%05X)\n",
                   (unsigned long long)step, after.cs, after.ip,
                   rtl.cs, rtl.ip, (unsigned long long)charge,
                   (unsigned long long)used, retired,
                   (unsigned long long)total_overhead, start_pc);
            printf("  pc_o trace (%llu ticks):", (unsigned long long)trace_n);
            for (uint64_t ti = 0; ti < trace_n; ti++)
                printf(" %05X", pc_trace[ti]);
            printf("\n");
            {
                uint8_t *mem = iref_mem(ref);
                uint32_t lin = ((uint32_t)before.cs << 4) + before.ip;
                printf("  bytes at C %04X:%04X (lin %05X):",
                       before.cs, before.ip, lin);
                for (int bi = 0; bi < 8; bi++)
                    printf(" %02X", mem[(lin + bi) & 0xFFFFF]);
                printf("\n");
            }
            print_state("C state:", &after, &rtl);
            printf("  RTL core_pc=%05X badop=%d halted=%d\n",
                   (unsigned)top->core_pc, (int)top->core_badop,
                   rtl.halted);
            rc = 1;
            step++;
            break;
        }
    }

    if (rc == 0 && step >= max_instr) {
        IState cs;
        RtlState rs;
        iref_get_state(ref, &cs);
        rtl_get_state(&rs);
        printf("COSIM CLEAN: %llu instructions, C cycles=%llu, RTL cycles=%llu\n",
               (unsigned long long)step,
               (unsigned long long)cs.cycles,
               (unsigned long long)rs.cycles);
        printf("  bus-latency overhead: cumulative RTL-C=%llu cycles, "
               "max single-step=%llu, REP iterations folded=%llu\n",
               (unsigned long long)total_overhead,
               (unsigned long long)max_overhead,
               (unsigned long long)rep_accum);
        printf("  final C: CS=%04X IP=%04X ring=%u\n", cs.cs, cs.ip, cs.ring_idx);
        printf("  final RTL: CS=%04X IP=%04X core_pc=%05X\n",
               rs.cs, rs.ip, (unsigned)top->core_pc);
    }

    /* DTE byte comparison (only meaningful on a clean run). */
    if (rc == 0) {
        uint32_t nc = iref_dte_count(ref);
        printf("  DTE bytes: C=%u RTL=%zu\n", nc, rtl_dte.size());
        uint32_t ncmp = nc < rtl_dte.size() ? nc : (uint32_t)rtl_dte.size();
        uint32_t first_diff = 0xFFFFFFFF;
        for (uint32_t i = 0; i < ncmp; i++) {
            if (iref_dte_byte(ref, i) != rtl_dte[i]) {
                first_diff = i;
                break;
            }
        }
        if (nc != rtl_dte.size() || first_diff != 0xFFFFFFFF) {
            printf("COSIM DTE MISMATCH: counts C=%u RTL=%zu", nc, rtl_dte.size());
            if (first_diff != 0xFFFFFFFF)
                printf(", first differing byte %u (C=%02X RTL=%02X)",
                       first_diff, iref_dte_byte(ref, first_diff),
                       rtl_dte[first_diff]);
            printf("\n");
            rc = 3;
        } else {
            printf("  DTE bytes match (%u bytes)\n", nc);
        }
    }

    iref_free(ref);
    delete top;
    if (rc == 0)
        printf("COSIM PASS\n");
    else
        printf("COSIM FAIL (rc=%d)\n", rc);
    return rc;
}
