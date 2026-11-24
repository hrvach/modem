/*
   i186.c -- 80186 (8086 plus the 186 extensions) instruction interpreter

   What it is
     A small CPU core with a 1 MB physical address space, a 16-bit I/O
     space, and callback hooks for memory-mapped pages and I/O ports.
     The peripherals (timers, interrupt controller, DMA, UART, the DSP
     mailbox) are not here; they live in the glue code.

   Quirks
     Where the core does something the 80C186EB manual does not describe,
     the comment is tagged QUIRK.  The firmware depends on these, so they
     are kept as they are.

   Cycle model
     Model 0 charges a flat 4 cycles per instruction.
     Model 1 charges approximate 80C186 clock counts from the manual's
     Appendix D, Table D-2: a base cost per opcode (BASE_CYCLES), plus
     extras for memory operands (modrm_extra_cycles) and for taken
     branches, multiplies, divides and so on where they are executed.
     i186_set_cycle_scale() multiplies the charge in model 1 only and
     carries the fractional remainder from one instruction to the next.

   Layout of this file
     1. constants and the CPU state
     2. flags, registers, memory and port access
     3. operand decoding and the arithmetic helpers
     4. one function per opcode group (exec_*)
     5. the opcode dispatch, instruction fetch and i186_run()

   Build:  gcc -O2 -Wall -Wextra -c src/cpu/i186.c
   Needs only the C standard library.
*/
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "i186.h"
#include "i186_opcodes.h"

/* ------------------------------------------------------------------
   Named constants (magic numbers, as the firmware expects them).
   ------------------------------------------------------------------ */

/* Address space. */
#define I186_MEM_SIZE (1u << 20) /* 1 MB physical space */
#define I186_MEM_MASK 0xFFFFFu   /* 20-bit wrap for linear addresses */
#define I186_PAGE_SHIFT 12       /* 4 KB pages */
#define I186_NPAGES 256          /* 256 pages cover 1 MB */
#define I186_IO_PORTS 65536      /* 16-bit I/O space */
#define I186_RING_SIZE 256       /* executed-PC ring buffer entries */
#define I186_RING_MASK 255

/* FLAGS word.  Bit 1 is always 1 and bits 15-12 read as 1, hence the
   0xF002 base in flags_get().  The flag bit positions follow (CF is bit 0). */
#define FLAG_BASE 0xF002u

#define FLAG_BIT_CF 0
#define FLAG_BIT_PF 2
#define FLAG_BIT_AF 4
#define FLAG_BIT_ZF 6
#define FLAG_BIT_SF 7
#define FLAG_BIT_TF 8
#define FLAG_BIT_IF 9
#define FLAG_BIT_DF 10
#define FLAG_BIT_OF 11

/* Reset state: CS:IP = FFFF:0000, i.e. linear 0xFFFF0. */
#define RESET_CS 0xFFFFu
#define RESET_IP 0x0000u
#define RESET_FLAGS 0x0002u

/* Interrupt vectors used internally (manual section 5.1, exceptions). */
#define INT_DIVIDE_ERROR 0 /* DIV/IDIV overflow, AAM by zero */
#define INT_SINGLE_STEP 1
#define INT_NMI 2
#define INT_BREAKPOINT 3
#define INT_OVERFLOW 4 /* INTO */
#define INT_BOUND 5
#define INT_BADOP 6 /* invalid opcode, only when ud_trap is on */

/* General registers and segment registers. */
enum { REG_AX, REG_CX, REG_DX, REG_BX, REG_SP, REG_BP, REG_SI, REG_DI };
enum { SEG_ES, SEG_CS, SEG_SS, SEG_DS };
#define SREG_COUNT 4

/* ------------------------------------------------------------------
   CPU state.  This layout is private to this file; the header only
   exposes it as the opaque type Cpu.
   ------------------------------------------------------------------ */
struct i186_cpu {
    /* Registers. */
    uint16_t gpr[8];
    uint16_t sreg[4];
    uint16_t ip;

    /* Flags kept as separate ints; assembled by flags_get(). */
    int flag_cf, flag_pf, flag_af, flag_zf, flag_sf;
    int flag_tf, flag_if, flag_df, flag_of;

    /* Memory and I/O. */
    uint8_t *mem;                        /* 1 MB RAM image */
    uint8_t mmio_page[I186_NPAGES];      /* 4 KB pages with MMIO hooks */
    uint8_t read_only_page[I186_NPAGES]; /* 4 KB pages that ignore writes (flash) */
    io_rd_fn io_rd;
    io_wr_fn io_wr;
    mm_rd_fn mm_rd;
    mm_wr_fn mm_wr;
    void *ctx;
    uint16_t *io_fallback; /* fallback I/O space, no hook installed */

    /* Run state. */
    int halted;
    int status;
    int stop;

    /* Interrupts. */
    int irq_pending; /* external maskable interrupt request */
    int irq_vec;
    int nmi_pending; /* latched NMI (type 2) */
    int irq_shadow;  /* interrupt shadow: set by STI and
                                           segment-register loads, covers the
                                           next instruction */

    /* REP string loops. */
    uint16_t prefix_start_ip; /* IP of the first prefix byte of the
                                           running instruction (REP restart) */
    int rep_resume;           /* a REP string loop yielded and is
                                           being resumed (no second start-up
                                           charge) */
    uint64_t run_end;         /* cycle budget end of the current
                                           i186_run (REP string loops stop
                                           there and resume) */

    int ud_trap; /* 1 = an undefined opcode raises type 6
                                           (invalid opcode, IP = the faulting
                                           instruction) instead of ST_BADOP */

    /* Timing. */
    double cycle_scale; /* CPU speed knob: charged clocks per
                                           instruction are multiplied by this
                                           (1.0 = manual Table D-2) */
    double cycle_frac;
    int cycle_model; /* 0 = legacy flat 4 cycles per
                                           instruction, 1 = approximate 80C186
                                           clock counts */
    uint64_t cycles;

    /* Debugging. */
    uint32_t *hits; /* per-address execution counts */
    uint32_t pc_ring[I186_RING_SIZE];
    uint32_t pc_ring_pos;
    uint8_t *breakpoints; /* one byte per physical address */
    uint32_t cur_pc;      /* linear PC of the running instruction */

    /* Instruction decode state. */
    int segment_override;
    int rep_prefix;
    int rep_is_repz;
    uint8_t opcode;
    int modrm_mod, modrm_reg, modrm_rm;
    uint16_t ea_seg, ea_off;

    uint32_t last_badop_pc;
    uint8_t last_badop;

    /* Never read or written anywhere; kept so the state keeps its shape. */
    uint32_t unmapped_log[64];
    int unmapped_n;
};

static void flags_set(Cpu *cpu, uint16_t f);
static void execute_one(Cpu *cpu);
static void do_interrupt(Cpu *cpu, int vec);

/* ------------------------------------------------------------------
   Tables.
   ------------------------------------------------------------------ */

/* Parity of the low byte of a result: PARITY_EVEN[n] is 1 when n has an
   even number of 1 bits.  One row per 16 values; the row base is in the
   comment. */
/* clang-format off */
static const uint8_t PARITY_EVEN[256] = {
    /* 0x00 */ 1, 0, 0, 1, 0, 1, 1, 0, 0, 1, 1, 0, 1, 0, 0, 1,
    /* 0x10 */ 0, 1, 1, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0, 1, 1, 0,
    /* 0x20 */ 0, 1, 1, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0, 1, 1, 0,
    /* 0x30 */ 1, 0, 0, 1, 0, 1, 1, 0, 0, 1, 1, 0, 1, 0, 0, 1,
    /* 0x40 */ 0, 1, 1, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0, 1, 1, 0,
    /* 0x50 */ 1, 0, 0, 1, 0, 1, 1, 0, 0, 1, 1, 0, 1, 0, 0, 1,
    /* 0x60 */ 1, 0, 0, 1, 0, 1, 1, 0, 0, 1, 1, 0, 1, 0, 0, 1,
    /* 0x70 */ 0, 1, 1, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0, 1, 1, 0,
    /* 0x80 */ 0, 1, 1, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0, 1, 1, 0,
    /* 0x90 */ 1, 0, 0, 1, 0, 1, 1, 0, 0, 1, 1, 0, 1, 0, 0, 1,
    /* 0xA0 */ 1, 0, 0, 1, 0, 1, 1, 0, 0, 1, 1, 0, 1, 0, 0, 1,
    /* 0xB0 */ 0, 1, 1, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0, 1, 1, 0,
    /* 0xC0 */ 1, 0, 0, 1, 0, 1, 1, 0, 0, 1, 1, 0, 1, 0, 0, 1,
    /* 0xD0 */ 0, 1, 1, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0, 1, 1, 0,
    /* 0xE0 */ 0, 1, 1, 0, 1, 0, 0, 1, 1, 0, 0, 1, 0, 1, 1, 0,
    /* 0xF0 */ 1, 0, 0, 1, 0, 1, 1, 0, 0, 1, 1, 0, 1, 0, 0, 1,
};
/* clang-format on */

/* Clock charges used outside the BASE_CYCLES table (cycle model 1 unless
   noted; manual App. D). */
#define CLOCKS_MEMORY_OPERAND 6 /* effective address + bus cycle of a memory operand */
#define CLOCKS_PREFIX 2         /* segment override or LOCK prefix */
#define CLOCKS_INTERRUPT_ENTRY 42
#define CLOCKS_JCC_TAKEN 9
#define CLOCKS_LOOP_TAKEN 10 /* LOOP, LOOPcc, JCXZ */
#define CLOCKS_CALL_NEAR_INDIRECT 10
#define CLOCKS_CALL_FAR_INDIRECT 28
#define CLOCKS_JMP_INDIRECT 8
#define CLOCKS_MUL_WORD 33
#define CLOCKS_MUL_BYTE 24
#define CLOCKS_DIV_WORD 35
#define CLOCKS_DIV_BYTE 26
#define CLOCKS_SHIFT_BY_1_REGISTER (-2) /* subtracts: see exec_shift_1_cl() */
#define CLOCKS_SHIFT_BY_1_MEMORY 5

/* Cycle model 0 (legacy): every instruction costs a flat figure, with a
   few extras. */
#define CLOCKS_LEGACY_INSTRUCTION 4
#define CLOCKS_LEGACY_JCC_TAKEN 12
#define CLOCKS_LEGACY_CALL_FAR 20

/* Approximate 80C186 clock counts per opcode, register forms.
   decode_modrm() adds 6 for a memory operand plus the per-form extra from
   modrm_extra_cycles(); taken branches, multiplies/divides, indirect calls and
   interrupt entry add their extra where executed.  One row per 16 opcodes; the row base is in the comment.
   Note the zeros that matter: 0x8D (LEA) charges a 0 base -- its cost is
   the 6 clocks decode_modrm() adds for the memory operand. */
/* clang-format off */
static const uint8_t BASE_CYCLES[256] = {
    /* 0x00 */  3,  3,  3,  3,  3,  4,  9,  8,  3,  3,  3,  3,  3,  4,  9,  3,
    /* 0x10 */  3,  3,  3,  3,  3,  4,  9,  8,  3,  3,  3,  3,  3,  4,  9,  8,
    /* 0x20 */  3,  3,  3,  3,  3,  4,  3,  4,  3,  3,  3,  3,  3,  4,  3,  4,
    /* 0x30 */  3,  3,  3,  3,  3,  4,  3,  7,  3,  3,  3,  3,  3,  4,  3,  7,
    /* 0x40 */  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,  3,
    /* 0x50 */ 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10, 10,
    /* 0x60 */ 36, 51, 27,  3,  3,  3,  3,  3, 10, 24, 10, 24,  5,  5,  5,  5,
    /* 0x70 */  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,  4,
    /* 0x80 */  4,  4,  4,  4,  3,  3,  4,  4,  2,  2,  2,  2,  2,  0,  2, 14,
    /* 0x90 */  3,  3,  3,  3,  3,  3,  3,  3,  2,  4, 23,  3,  9,  8,  3,  2,
    /* 0xA0 */  9,  9,  8,  8,  5,  5,  5,  5,  3,  3,  5,  5,  5,  5,  5,  5,
    /* 0xB0 */  3,  3,  3,  3,  3,  3,  3,  3,  4,  4,  4,  4,  4,  4,  4,  4,
    /* 0xC0 */  6,  6, 18, 16, 12, 12,  6,  6, 15,  8, 25, 22,  3,  5,  3, 28,
    /* 0xD0 */  4,  4,  4,  4, 19, 15,  3, 11,  3,  3,  3,  3,  3,  3,  3,  3,
    /* 0xE0 */  6,  6,  6,  6, 10, 10,  9,  9, 15, 14, 14, 14,  8,  8,  7,  7,
    /* 0xF0 */  3,  3,  3,  3,  2,  2,  3,  3,  2,  2,  2,  2,  2,  2,  3,  3,
};
/* clang-format on */

/* ------------------------------------------------------------------
   Flags and registers.
   ------------------------------------------------------------------ */

/* Assemble the FLAGS word.  Bits 15-12 and bit 1 read 1. */
static uint16_t flags_get(Cpu *cpu) {
    return (uint16_t)(FLAG_BASE | (cpu->flag_cf << FLAG_BIT_CF) | (cpu->flag_pf << FLAG_BIT_PF) |
                      (cpu->flag_af << FLAG_BIT_AF) | (cpu->flag_zf << FLAG_BIT_ZF) | (cpu->flag_sf << FLAG_BIT_SF) |
                      (cpu->flag_tf << FLAG_BIT_TF) | (cpu->flag_if << FLAG_BIT_IF) | (cpu->flag_df << FLAG_BIT_DF) |
                      (cpu->flag_of << FLAG_BIT_OF));
}

/* Split a FLAGS word back into the separate flag ints.
   Only the eight architected flag bits are read; the rest are ignored. */
static void flags_set(Cpu *cpu, uint16_t flags) {
    cpu->flag_cf = (flags >> FLAG_BIT_CF) & 1;
    cpu->flag_pf = (flags >> FLAG_BIT_PF) & 1;
    cpu->flag_af = (flags >> FLAG_BIT_AF) & 1;
    cpu->flag_zf = (flags >> FLAG_BIT_ZF) & 1;
    cpu->flag_sf = (flags >> FLAG_BIT_SF) & 1;
    cpu->flag_tf = (flags >> FLAG_BIT_TF) & 1;
    cpu->flag_if = (flags >> FLAG_BIT_IF) & 1;
    cpu->flag_df = (flags >> FLAG_BIT_DF) & 1;
    cpu->flag_of = (flags >> FLAG_BIT_OF) & 1;
}

/* The eight 8-bit registers are numbered AL, CL, DL, BL, AH, CH, DH, BH:
   numbers 0-3 are the low byte of AX..BX, numbers 4-7 are the high byte
   of AX..BX.  So number n >= FIRST_HIGH_BYTE_REG is the high byte of
   gpr[n - FIRST_HIGH_BYTE_REG]. */
#define FIRST_HIGH_BYTE_REG 4

/* Read one of the eight general registers.  is_word=1 reads the whole
   16-bit register; is_word=0 reads an 8-bit register (numbering above). */
static inline uint32_t reg_get(Cpu *cpu, int n, int is_word) {
    if (is_word) {
        return cpu->gpr[n];
    }
    if (n < FIRST_HIGH_BYTE_REG) {
        return cpu->gpr[n] & 0xFFu;
    }
    return cpu->gpr[n - FIRST_HIGH_BYTE_REG] >> 8;
}

/* Write one of the eight general registers.  A byte write preserves the
   other byte of the register. */
static inline void reg_set(Cpu *cpu, int n, int is_word, uint32_t value) {
    if (is_word) {
        cpu->gpr[n] = (uint16_t)value;
    } else if (n < FIRST_HIGH_BYTE_REG) {
        cpu->gpr[n] = (uint16_t)((cpu->gpr[n] & 0xFF00u) | (value & 0xFFu));
    } else {
        uint16_t *full = &cpu->gpr[n - FIRST_HIGH_BYTE_REG];

        *full = (uint16_t)((*full & 0xFFu) | ((value & 0xFFu) << 8));
    }
}

/* Operand masks for the current width. */
static inline uint32_t width_mask(int is_word) {
    return is_word ? 0xFFFFu : 0xFFu;
}
static inline uint32_t width_msb(int is_word) {
    return is_word ? 0x8000u : 0x80u;
}

/* ------------------------------------------------------------------
   Public API: lifetime, raw access, configuration, interrupts.
   ------------------------------------------------------------------ */

Cpu *i186_new(void) {
    Cpu *cpu = calloc(1, sizeof *cpu);
    if (!cpu) {
        return NULL;
    }

    cpu->cycle_scale = 1.0;
    cpu->segment_override = -1;
    cpu->mem = calloc(I186_MEM_SIZE, 1);
    cpu->hits = calloc(I186_MEM_SIZE, sizeof *cpu->hits);
    cpu->breakpoints = calloc(I186_MEM_SIZE, 1);
    cpu->io_fallback = calloc(I186_IO_PORTS, sizeof *cpu->io_fallback);

    if (!cpu->mem || !cpu->hits || !cpu->breakpoints || !cpu->io_fallback) {
        i186_free(cpu);
        return NULL;
    }
    return cpu;
}

void i186_free(Cpu *cpu) {
    if (!cpu) {
        return;
    }
    free(cpu->mem);
    free(cpu->hits);
    free(cpu->breakpoints);
    free(cpu->io_fallback);
    free(cpu);
}

uint8_t *i186_mem(Cpu *cpu) {
    return cpu->mem;
}
uint32_t *i186_hits(Cpu *cpu) {
    return cpu->hits;
}
uint32_t *i186_ring(Cpu *cpu) {
    return cpu->pc_ring;
}
uint32_t i186_ring_idx(Cpu *cpu) {
    return cpu->pc_ring_pos;
}
uint16_t *i186_ioarr(Cpu *cpu) {
    return cpu->io_fallback;
}

void i186_set_hooks(Cpu *cpu, io_rd_fn ir, io_wr_fn iw, mm_rd_fn mr, mm_wr_fn mw, void *ctx) {
    cpu->io_rd = ir;
    cpu->io_wr = iw;
    cpu->mm_rd = mr;
    cpu->mm_wr = mw;
    cpu->ctx = ctx;
}

void i186_set_mmio_page(Cpu *cpu, uint32_t page, int on) {
    if (page < I186_NPAGES) {
        cpu->mmio_page[page] = (uint8_t)on;
    }
}

void i186_set_ro_page(Cpu *cpu, uint32_t page, int on) {
    if (page < I186_NPAGES) {
        cpu->read_only_page[page] = (uint8_t)on;
    }
}

void i186_set_bp(Cpu *cpu, uint32_t phys, int on) {
    if (phys < I186_MEM_SIZE) {
        cpu->breakpoints[phys] = (uint8_t)on;
    }
}

void i186_stop(Cpu *cpu) {
    cpu->stop = 1;
}

void i186_irq(Cpu *cpu, int vec) {
    cpu->irq_pending = 1;
    cpu->irq_vec = vec & 0xFF;
}

void i186_nmi(Cpu *cpu) {
    cpu->nmi_pending = 1;
}
void i186_irq_clear(Cpu *cpu) {
    cpu->irq_pending = 0;
}
int i186_irq_pending(Cpu *cpu) {
    return cpu->irq_pending;
}

void i186_set_ud_trap(Cpu *cpu, int m) {
    cpu->ud_trap = m;
}
void i186_set_cycle_model(Cpu *cpu, int m) {
    cpu->cycle_model = m;
}

/* QUIRK: a non-positive scale is silently replaced by 1.0,
   and setting the scale always resets the fractional remainder. */
void i186_set_cycle_scale(Cpu *cpu, double f) {
    cpu->cycle_scale = f > 0 ? f : 1.0;
    cpu->cycle_frac = 0;
}

uint64_t i186_cycles(Cpu *cpu) {
    return cpu->cycles;
}
void i186_add_cycles(Cpu *cpu, uint64_t n) {
    cpu->cycles += n;
}

/* Low 24 bits = PC of the last bad opcode, high byte = opcode. */
uint32_t i186_get_badop(Cpu *cpu) {
    return cpu->last_badop_pc | ((uint32_t)cpu->last_badop << 24);
}

/* Register access by register id (the R_* constants in i186.h).  The ids
   are laid out as:
     R_AX .. R_DI   the eight general registers, same order as cpu->gpr[]
     R_ES .. R_DS   the four segment registers, same order as cpu->sreg[]
     R_IP, R_FLAGS  the instruction pointer and the FLAGS word
   An unknown id reads as 0 and is ignored on write.  Writing a 16-bit
   register truncates the 32-bit value. */
static int is_general_register(int id) {
    return id >= R_AX && id <= R_DI;
}

static int is_segment_register(int id) {
    return id >= R_ES && id <= R_DS;
}

uint32_t i186_get(Cpu *cpu, int id) {
    if (is_general_register(id)) {
        return cpu->gpr[id - R_AX];
    }
    if (is_segment_register(id)) {
        return cpu->sreg[id - R_ES];
    }
    if (id == R_IP) {
        return cpu->ip;
    }
    if (id == R_FLAGS) {
        return flags_get(cpu);
    }
    return 0;
}

void i186_set(Cpu *cpu, int id, uint32_t value) {
    if (is_general_register(id)) {
        cpu->gpr[id - R_AX] = (uint16_t)value;
    } else if (is_segment_register(id)) {
        cpu->sreg[id - R_ES] = (uint16_t)value;
    } else if (id == R_IP) {
        cpu->ip = (uint16_t)value;
    } else if (id == R_FLAGS) {
        flags_set(cpu, (uint16_t)value);
    }
}

/* Reset: CS=0xFFFF, IP=0, FLAGS=0x0002, cycle counter
   cleared, interrupt state cleared.  QUIRK: this resets ONLY those fields.
   Memory, hooks, MMIO/RO pages, breakpoints, ud_trap, cycle model/scale,
   the ring and hit counts all survive a reset. */
void i186_reset(Cpu *cpu) {
    memset(cpu->gpr, 0, sizeof cpu->gpr);
    memset(cpu->sreg, 0, sizeof cpu->sreg);
    cpu->sreg[SEG_CS] = RESET_CS;
    cpu->ip = RESET_IP;
    flags_set(cpu, RESET_FLAGS);
    cpu->halted = 0;
    cpu->cycles = 0;
    cpu->irq_pending = 0;
    cpu->nmi_pending = 0;
    cpu->irq_shadow = 0;
    cpu->irq_vec = 0;
}

/* ------------------------------------------------------------------
   Memory and I/O.
   ------------------------------------------------------------------ */

/* Segment:offset to a 20-bit linear address. */
static inline uint32_t linear_address(uint16_t seg, uint16_t off) {
    return (((uint32_t)seg << 4) + off) & I186_MEM_MASK;
}

/* A word access whose two bytes fall on pages that route differently
   (MMIO hook / read-only / RAM) is performed as two byte accesses, each
   through its own page's rule; same-routing words keep the single word
   call to the hook. */
static inline int word_crosses_boundary(Cpu *cpu, uint32_t first_addr, uint32_t second_addr) {
    uint32_t first_page = first_addr >> I186_PAGE_SHIFT;
    uint32_t second_page = second_addr >> I186_PAGE_SHIFT;

    return first_page != second_page && (cpu->mmio_page[first_page] != cpu->mmio_page[second_page] ||
                                         cpu->read_only_page[first_page] != cpu->read_only_page[second_page]);
}

/* Physical read.  is_word=1 reads a word (little-endian), is_word=0 a byte.
   The second byte wraps at 1 MB. */
static uint32_t mem_read(Cpu *cpu, uint32_t address, int is_word) {
    address &= I186_MEM_MASK;

    if (is_word) {
        uint32_t next_address = (address + 1) & I186_MEM_MASK;

        if (word_crosses_boundary(cpu, address, next_address)) {
            return mem_read(cpu, address, 0) | (mem_read(cpu, next_address, 0) << 8);
        }
    }

    if (cpu->mmio_page[address >> I186_PAGE_SHIFT] && cpu->mm_rd) {
        return cpu->mm_rd(cpu->ctx, address, is_word);
    }

    if (is_word) {
        return cpu->mem[address] | ((uint32_t)cpu->mem[(address + 1) & I186_MEM_MASK] << 8);
    }
    return cpu->mem[address];
}

/* Physical write.  MMIO pages go to the hook, read-only pages drop the
   write silently, everything else lands in RAM. */
static void mem_write(Cpu *cpu, uint32_t address, int is_word, uint32_t value) {
    address &= I186_MEM_MASK;

    if (is_word) {
        uint32_t next_address = (address + 1) & I186_MEM_MASK;

        if (word_crosses_boundary(cpu, address, next_address)) {
            mem_write(cpu, address, 0, value);
            mem_write(cpu, next_address, 0, value >> 8);
            return;
        }
    }

    if (cpu->mmio_page[address >> I186_PAGE_SHIFT] && cpu->mm_wr) {
        cpu->mm_wr(cpu->ctx, address, is_word, value);
        return;
    }
    if (cpu->read_only_page[address >> I186_PAGE_SHIFT]) {
        return;
    }

    cpu->mem[address] = (uint8_t)value;
    if (is_word) {
        cpu->mem[(address + 1) & I186_MEM_MASK] = (uint8_t)(value >> 8);
    }
}

/* Fetch the next code byte / word at CS:IP.  IP wraps at
   16 bits by virtue of being a uint16_t. */
static inline uint8_t fetch_byte(Cpu *cpu) {
    uint8_t value = (uint8_t)mem_read(cpu, linear_address(cpu->sreg[SEG_CS], cpu->ip), 0);
    cpu->ip++;
    return value;
}

static inline uint16_t fetch_word(Cpu *cpu) {
    uint16_t value = fetch_byte(cpu);
    value |= (uint16_t)(fetch_byte(cpu) << 8);
    return value;
}

static inline void push_word(Cpu *cpu, uint16_t value) {
    cpu->gpr[REG_SP] -= 2;
    mem_write(cpu, linear_address(cpu->sreg[SEG_SS], cpu->gpr[REG_SP]), 1, value);
}

static inline uint16_t pop_word(Cpu *cpu) {
    uint16_t value = (uint16_t)mem_read(cpu, linear_address(cpu->sreg[SEG_SS], cpu->gpr[REG_SP]), 1);
    cpu->gpr[REG_SP] += 2;
    return value;
}

/* I/O space.  With no read hook the fallback io_fallback array answers; with no
   write hook a byte write preserves the high byte of the port. */
static uint32_t port_read(Cpu *cpu, uint16_t port, int is_word) {
    if (cpu->io_rd) {
        return cpu->io_rd(cpu->ctx, port, is_word);
    }
    return cpu->io_fallback[port];
}

static void port_write(Cpu *cpu, uint16_t port, int is_word, uint32_t value) {
    if (cpu->io_wr) {
        /* QUIRK: when a write hook is installed the fallback array is NOT
           updated, so a later hook-less read of the same port sees stale
           data. */
        cpu->io_wr(cpu->ctx, port, is_word, value);
    } else {
        cpu->io_fallback[port] = (uint16_t)(is_word ? value : (cpu->io_fallback[port] & 0xFF00u) | (value & 0xFFu));
    }
}

/* ------------------------------------------------------------------
   ModR/M decoding.
   ------------------------------------------------------------------ */

/* Clocks of the memory form of an instruction: what the 80C186EB manual
   (Table D-2, 16-bit, fastest case) lists, minus what the emulator has
   already charged for it.  The emulator charges BASE_CYCLES[op] for the
   instruction and CLOCKS_MEMORY_OPERAND in decode_modrm(); this returns
   the remainder, so that the three add up to the manual's figure. */
static int memory_form_extra_clocks(uint8_t op, int manual_clocks) {
    return manual_clocks - BASE_CYCLES[op] - CLOCKS_MEMORY_OPERAND;
}

/* Extra clocks for a memory operand, added by decode_modrm() on top of
   BASE_CYCLES[op] + CLOCKS_MEMORY_OPERAND.  The figures in the comments are
   the manual's totals.  `reg` is the ModR/M reg field.

   Instructions not listed here get 0, which includes 0xC6 (MOV r/m, imm8):
   a quirk of the table.  The plain ALU forms (ADD/OR/ADC/SBB/AND/SUB/XOR/CMP
   with r/m and a register, opcodes below 0x40) take the fall-through at the
   end. */
static int modrm_extra_cycles(uint8_t op, int reg) {
    switch (op) {
    case OP_MOV_RM_REG_BYTE:
    case OP_MOV_RM_REG_WORD:
        return memory_form_extra_clocks(op, 12);

    case OP_MOV_REG_RM_BYTE:
    case OP_MOV_REG_RM_WORD:
    case OP_MOV_SREG_RM:
        return memory_form_extra_clocks(op, 9);

    case OP_MOV_RM_SREG:
        return memory_form_extra_clocks(op, 11);

    case OP_MOV_RM_IMM_WORD:
        return memory_form_extra_clocks(op, 13);

    case OP_ALU_IMM_BYTE ... OP_ALU_IMM_SIGNED:
        if (reg == ALU_CMP) {
            return memory_form_extra_clocks(op, 10); /* CMP only reads the operand */
        }
        return memory_form_extra_clocks(op, 16); /* read-modify-write */

    case OP_GROUP_FE:
        if (reg == FF_REG_INC || reg == FF_REG_DEC) {
            return memory_form_extra_clocks(op, 15);
        }
        return 0;

    case OP_GROUP_FF:
        if (reg == FF_REG_INC || reg == FF_REG_DEC) {
            return memory_form_extra_clocks(op, 15);
        }
        if (reg == FF_REG_PUSH) {
            return memory_form_extra_clocks(op, 16);
        }
        return 0;

    case OP_XCHG_RM_REG_BYTE:
    case OP_XCHG_RM_REG_WORD:
        return memory_form_extra_clocks(op, 17);

    case OP_TEST_RM_REG_BYTE:
    case OP_TEST_RM_REG_WORD:
        return memory_form_extra_clocks(op, 10);

    case OP_GROUP_F6:
    case OP_GROUP_F7:
        if (reg == F6F7_REG_TEST || reg == F6F7_REG_TEST_ALIAS) {
            return memory_form_extra_clocks(op, 10); /* TEST r/m, imm */
        }
        return 0;
    }

    if (op < OP_ALU_END && (op & ALU_FORM_MASK) <= ALU_FORM_REG_RM_WORD) {
        return memory_form_extra_clocks(op, 10); /* ALU r/m, reg and reg, r/m */
    }
    return 0;
}

/* Decode a ModR/M byte plus any displacement into cpu->modrm_mod/modrm_reg/modrm_rm and the
   effective address (cpu->ea_seg:cpu->ea_off).  Register form (mod==3) has no
   effective address and -- note -- charges NO cycles.
   The default segment is DS, except BP-based forms use SS; a segment
   prefix overrides either.  rm==6 with mod==0 is a 16-bit direct address. */
static void decode_modrm(Cpu *cpu) {
    /* The ModRM byte: mod (2 bits), reg (3 bits), r/m (3 bits). */
    uint8_t modrm_byte = fetch_byte(cpu);
    cpu->modrm_mod = modrm_byte >> 6;
    cpu->modrm_reg = (modrm_byte >> 3) & 7;
    cpu->modrm_rm = modrm_byte & 7;

    /* mod 3: the operand is a register, no address to compute. */
    if (cpu->modrm_mod == MODRM_MOD_REGISTER) {
        return;
    }

    /* Memory operand: EA + bus cycle, plus the per-form difference to
       Table D-2.  Charged before the displacement is fetched. */
    if (cpu->cycle_model) {
        cpu->cycles += CLOCKS_MEMORY_OPERAND + (uint64_t)modrm_extra_cycles(cpu->opcode, cpu->modrm_reg);
    }

    /* Base and index registers selected by r/m.  Addressing through BP
       defaults to the stack segment, everything else to the data segment. */
    uint16_t offset = 0;
    int default_segment = SEG_DS;

    switch (cpu->modrm_rm) {
    case MODRM_RM_BX_SI:
        offset = (uint16_t)(cpu->gpr[REG_BX] + cpu->gpr[REG_SI]);
        break;
    case MODRM_RM_BX_DI:
        offset = (uint16_t)(cpu->gpr[REG_BX] + cpu->gpr[REG_DI]);
        break;
    case MODRM_RM_BP_SI:
        offset = (uint16_t)(cpu->gpr[REG_BP] + cpu->gpr[REG_SI]);
        default_segment = SEG_SS;
        break;
    case MODRM_RM_BP_DI:
        offset = (uint16_t)(cpu->gpr[REG_BP] + cpu->gpr[REG_DI]);
        default_segment = SEG_SS;
        break;
    case MODRM_RM_SI:
        offset = cpu->gpr[REG_SI];
        break;
    case MODRM_RM_DI:
        offset = cpu->gpr[REG_DI];
        break;
    case MODRM_RM_BP_OR_DIRECT:
        if (cpu->modrm_mod == MODRM_MOD_NO_DISPLACEMENT) {
            offset = fetch_word(cpu); /* direct address */
        } else {
            offset = cpu->gpr[REG_BP];
            default_segment = SEG_SS;
        }
        break;
    case MODRM_RM_BX:
        offset = cpu->gpr[REG_BX];
        break;
    }

    /* Displacement: 8 bits sign-extended (mod 1) or 16 bits (mod 2). */
    if (cpu->modrm_mod == MODRM_MOD_DISPLACEMENT_8) {
        offset = (uint16_t)(offset + (int8_t)fetch_byte(cpu));
    } else if (cpu->modrm_mod == MODRM_MOD_DISPLACEMENT_16) {
        offset = (uint16_t)(offset + fetch_word(cpu));
    }

    int segment = cpu->segment_override >= 0 ? cpu->segment_override : default_segment;
    cpu->ea_off = offset;
    cpu->ea_seg = cpu->sreg[segment];
}

/* Read/write the ModR/M operand. */
static uint32_t modrm_read(Cpu *cpu, int is_word) {
    if (cpu->modrm_mod == MODRM_MOD_REGISTER) {
        return reg_get(cpu, cpu->modrm_rm, is_word);
    }
    return mem_read(cpu, linear_address(cpu->ea_seg, cpu->ea_off), is_word);
}

static void modrm_write(Cpu *cpu, int is_word, uint32_t value) {
    if (cpu->modrm_mod == MODRM_MOD_REGISTER) {
        reg_set(cpu, cpu->modrm_rm, is_word, value);
    } else {
        mem_write(cpu, linear_address(cpu->ea_seg, cpu->ea_off), is_word, value);
    }
}

/* ------------------------------------------------------------------
   ALU.
   ------------------------------------------------------------------ */

/* Set ZF/SF/PF from a result of the current width.
   AF/CF/OF are left alone here; the caller sets them. */
static inline void set_sign_zero_parity(Cpu *cpu, uint32_t result, int is_word) {
    result &= width_mask(is_word);
    cpu->flag_zf = result == 0;
    cpu->flag_sf = !!(result & width_msb(is_word));
    cpu->flag_pf = PARITY_EVEN[result & 0xFFu];
}

/* The eight ALU operations.  `op` is the ALU_* code above.
   QUIRK: the logic operations (OR/AND/XOR) clear CF and
   OF but leave AF untouched, exactly as the silicon does; ADD/ADC/SUB/SBB/
   CMP set AF from bit 3 exactly as written.  CMP (7) is SUB whose result
   the caller discards. */
static uint32_t alu_exec(Cpu *cpu, int alu_op, uint32_t left, uint32_t right, int is_word) {
    uint32_t mask = width_mask(is_word);
    uint32_t result;

    switch (alu_op) {
    case ALU_ADD:
    case ALU_ADC: {
        uint32_t carry_in = alu_op == ALU_ADC ? (uint32_t)cpu->flag_cf : 0;

        result = left + right + carry_in;
        cpu->flag_cf = result > mask;
        cpu->flag_af = ((left ^ right ^ result) >> 4) & 1;
        cpu->flag_of = ((left ^ result) & (right ^ result) & width_msb(is_word)) != 0;
        break;
    }

    case ALU_SUB:
    case ALU_SBB:
    case ALU_CMP: {
        uint32_t borrow_in = alu_op == ALU_SBB ? (uint32_t)cpu->flag_cf : 0;

        result = left - right - borrow_in;
        cpu->flag_cf = left < right + borrow_in;
        cpu->flag_af = ((left ^ right ^ result) >> 4) & 1;
        cpu->flag_of = ((left ^ right) & (left ^ result) & width_msb(is_word)) != 0;
        break;
    }

    case ALU_OR:
        result = left | right;
        cpu->flag_cf = 0;
        cpu->flag_of = 0;
        break;

    case ALU_AND:
        result = left & right;
        cpu->flag_cf = 0;
        cpu->flag_of = 0;
        break;

    default: /* ALU_XOR */
        result = left ^ right;
        cpu->flag_cf = 0;
        cpu->flag_of = 0;
        break;
    }

    set_sign_zero_parity(cpu, result, is_word);
    return result & mask;
}

/* INC/DEC.  CF is preserved across the operation. */
static uint32_t inc_dec(Cpu *cpu, uint32_t value, int is_dec, int is_word) {
    uint32_t result = is_dec ? value - 1 : value + 1;
    int saved_cf = cpu->flag_cf;

    cpu->flag_of = is_dec ? (value == width_msb(is_word)) : (value == width_msb(is_word) - 1);
    cpu->flag_af = ((value ^ 1 ^ result) >> 4) & 1;
    set_sign_zero_parity(cpu, result, is_word);
    cpu->flag_cf = saved_cf;

    return result & width_mask(is_word);
}

/* Shifts and rotates.  `n` is the raw count; the low
   five bits are used (n &= 0x1F).  A count of 0 after masking returns the
   value with NO flag change -- including the case n == 32, where the
   masked count is 0.
   QUIRKS preserved verbatim:
    - ROL/ROR/RCL/RCR never set ZF/SF/PF/AF, and their OF rule applies
      only when the masked count is exactly 1.
    - RCL/RCR rotate through CF one bit at a time; RCR computes its
      count-1 OF from the ORIGINAL value and the incoming CF, before the
      loop runs.
    - SHL with n == bits takes CF from bit 0 of the value (the
      (v >> (bits - n)) expression with n == bits shifts by 0).
    - SAR with n > bits uses a shift of bits-1 for both CF and the result.
*/
static uint32_t shift_rotate(Cpu *cpu, int kind, uint32_t value, int count, int is_word) {
    int bits = is_word ? 16 : 8;
    uint32_t mask = width_mask(is_word);
    uint32_t msb = width_msb(is_word);

    count &= 0x1F;
    if (!count) {
        return value;
    }

    value &= mask;
    uint32_t result = value;

    switch (kind) {
    case SHIFT_ROL: {
        int rotate_by = count % bits;

        result = rotate_by ? ((value << rotate_by) | (value >> (bits - rotate_by))) & mask : value;
        cpu->flag_cf = result & 1;
        if (count == 1) {
            cpu->flag_of = ((result & msb) != 0) ^ cpu->flag_cf;
        }
        return result;
    }

    case SHIFT_ROR: {
        int rotate_by = count % bits;

        result = rotate_by ? ((value >> rotate_by) | (value << (bits - rotate_by))) & mask : value;
        cpu->flag_cf = !!(result & msb);
        if (count == 1) {
            cpu->flag_of = ((result ^ (result << 1)) & msb) != 0;
        }
        return result;
    }

    case SHIFT_RCL:
        for (int i = 0; i < count; i++) {
            int next_cf = !!(result & msb);

            result = ((result << 1) | (uint32_t)cpu->flag_cf) & mask;
            cpu->flag_cf = next_cf;
        }
        if (count == 1) {
            cpu->flag_of = ((result & msb) != 0) ^ cpu->flag_cf;
        }
        return result;

    case SHIFT_RCR:
        if (count == 1) {
            cpu->flag_of = ((result & msb) != 0) ^ cpu->flag_cf;
        }
        for (int i = 0; i < count; i++) {
            int next_cf = result & 1;

            result = (result >> 1) | (cpu->flag_cf ? msb : 0);
            cpu->flag_cf = next_cf;
        }
        return result;

    case SHIFT_SHL:
    case SHIFT_SHL_ALIAS:
        if (count > bits) {
            cpu->flag_cf = 0;
            result = 0;
        } else {
            cpu->flag_cf = (value >> (bits - count)) & 1;
            result = (value << count) & mask;
        }
        if (count == 1) {
            cpu->flag_of = ((result & msb) != 0) ^ cpu->flag_cf;
        }
        set_sign_zero_parity(cpu, result, is_word);
        cpu->flag_af = 0;
        return result;

    case SHIFT_SHR:
        cpu->flag_cf = (count > bits) ? 0 : (value >> (count - 1)) & 1;
        result = count >= bits ? 0 : value >> count;
        if (count == 1) {
            cpu->flag_of = (value & msb) != 0;
        }
        set_sign_zero_parity(cpu, result, is_word);
        cpu->flag_af = 0;
        return result;

    default: { /* SHIFT_SAR */
        int32_t signed_value = is_word ? (int16_t)value : (int8_t)value;
        int shift_by = count >= bits ? bits - 1 : count;

        cpu->flag_cf = (uint32_t)(signed_value >> (count > bits ? bits - 1 : count - 1)) & 1;
        result = (uint32_t)(signed_value >> shift_by) & mask;
        cpu->flag_of = 0;
        set_sign_zero_parity(cpu, result, is_word);
        cpu->flag_af = 0;
        return result;
    }
    }
}

/* ------------------------------------------------------------------
   Interrupts, conditions, bad opcodes.
   ------------------------------------------------------------------ */

/* Take an interrupt/exception: push FLAGS, CS, IP in
   that order, clear IF and TF, and vector through the IVT at vec*4.
   Costs 42 clocks in cycle model 1, nothing in the legacy model. */
static void do_interrupt(Cpu *cpu, int vec) {
    if (cpu->cycle_model) {
        cpu->cycles += CLOCKS_INTERRUPT_ENTRY;
    }

    push_word(cpu, flags_get(cpu));
    push_word(cpu, cpu->sreg[SEG_CS]);
    push_word(cpu, cpu->ip);

    cpu->flag_if = 0;
    cpu->flag_tf = 0;
    cpu->ip = (uint16_t)mem_read(cpu, (uint32_t)(vec * 4), 1);
    cpu->sreg[SEG_CS] = (uint16_t)mem_read(cpu, (uint32_t)(vec * 4 + 2), 1);
}

/* Evaluate a Jcc condition code.  cc is the low nibble
   of the opcode; the low bit inverts the sense. */
static int condition_met(Cpu *cpu, int condition_code) {
    int is_taken;

    switch (condition_code >> 1) {
    case COND_OVERFLOW:
        is_taken = cpu->flag_of;
        break;
    case COND_BELOW:
        is_taken = cpu->flag_cf;
        break;
    case COND_EQUAL:
        is_taken = cpu->flag_zf;
        break;
    case COND_BELOW_OR_EQUAL:
        is_taken = cpu->flag_cf || cpu->flag_zf;
        break;
    case COND_SIGN:
        is_taken = cpu->flag_sf;
        break;
    case COND_PARITY:
        is_taken = cpu->flag_pf;
        break;
    case COND_LESS:
        is_taken = cpu->flag_sf != cpu->flag_of;
        break;
    default: /* COND_LESS_OR_EQUAL */
        is_taken = cpu->flag_zf || (cpu->flag_sf != cpu->flag_of);
        break;
    }

    return (condition_code & 1) ? !is_taken : is_taken;
}

/* Record an undefined opcode.  The run loop decides whether
   this ends the run (ST_BADOP) or vectors to INT 6 (ud_trap). */
static int bad_opcode(Cpu *cpu, uint8_t op) {
    cpu->status = ST_BADOP;
    cpu->last_badop = op;
    cpu->last_badop_pc = cpu->cur_pc;
    return 0;
}

/* ------------------------------------------------------------------
   String instructions (MOVS/CMPS/STOS/LODS/SCAS/INS/OUTS).
   ------------------------------------------------------------------ */

/* The seven string instructions.  The numbers index the cycle tables below
   (slot 5 is unused). */
enum string_kind {
    STRING_MOVS = 0,
    STRING_CMPS = 1,
    STRING_STOS = 2,
    STRING_LODS = 3,
    STRING_SCAS = 4,
    STRING_UNUSED = 5,
    STRING_INS = 6,
    STRING_OUTS = 7
};

/* Clocks per string instruction in cycle model 1 (manual App. D),
   indexed by enum string_kind:
     single            the instruction without REP
     per iteration     each pass of a REP loop
     REP setup         one-off cost added to the first pass of a REP loop
                       (8+8n MOVS/INS/OUTS, 5+22n CMPS, 5+15n SCAS,
                       6+11n LODS, 6+9n STOS) */
/* clang-format off */
static const uint8_t STRING_CLOCKS_SINGLE[8]        = { 14, 22, 10, 12, 15, 0, 14, 14 };
static const uint8_t STRING_CLOCKS_PER_ITERATION[8] = {  8, 22,  9, 11, 15, 0,  8,  8 };
static const uint8_t STRING_CLOCKS_REP_SETUP[8]     = {  8,  5,  6,  6,  5, 0,  8,  8 };
/* clang-format on */

static enum string_kind string_kind_of(uint8_t op) {
    switch (op & ~OP_WIDTH_BIT) {
    case OP_MOVS_BYTE:
        return STRING_MOVS;
    case OP_CMPS_BYTE:
        return STRING_CMPS;
    case OP_STOS_BYTE:
        return STRING_STOS;
    case OP_LODS_BYTE:
        return STRING_LODS;
    case OP_SCAS_BYTE:
        return STRING_SCAS;
    case OP_INS_BYTE:
        return STRING_INS;
    default:
        return STRING_OUTS;
    }
}

/* The two addresses a string instruction works on: the source is DS:SI
   (or the segment override), the destination is always ES:DI. */
static uint32_t source_address(Cpu *cpu, int source_segment) {
    return linear_address(cpu->sreg[source_segment], cpu->gpr[REG_SI]);
}

static uint32_t destination_address(Cpu *cpu) {
    return linear_address(cpu->sreg[SEG_ES], cpu->gpr[REG_DI]);
}

/* Move SI / DI on by one element (backwards when the direction flag is set). */
static void advance_si(Cpu *cpu, int step) {
    cpu->gpr[REG_SI] = (uint16_t)(cpu->gpr[REG_SI] + step);
}

static void advance_di(Cpu *cpu, int step) {
    cpu->gpr[REG_DI] = (uint16_t)(cpu->gpr[REG_DI] + step);
}

/* Do the work of one pass of a string instruction. */
static void string_step(Cpu *cpu, enum string_kind kind, int is_word, int step, int source_segment) {
    switch (kind) {
    case STRING_MOVS:
        mem_write(cpu, destination_address(cpu), is_word, mem_read(cpu, source_address(cpu, source_segment), is_word));
        advance_si(cpu, step);
        advance_di(cpu, step);
        break;

    case STRING_CMPS: {
        uint32_t left = mem_read(cpu, source_address(cpu, source_segment), is_word);
        uint32_t right = mem_read(cpu, destination_address(cpu), is_word);

        alu_exec(cpu, ALU_CMP, left, right, is_word);
        advance_si(cpu, step);
        advance_di(cpu, step);
        break;
    }

    case STRING_STOS:
        mem_write(cpu, destination_address(cpu), is_word, reg_get(cpu, REG_AX, is_word));
        advance_di(cpu, step);
        break;

    case STRING_LODS:
        reg_set(cpu, REG_AX, is_word, mem_read(cpu, source_address(cpu, source_segment), is_word));
        advance_si(cpu, step);
        break;

    case STRING_SCAS: {
        uint32_t right = mem_read(cpu, destination_address(cpu), is_word);

        alu_exec(cpu, ALU_CMP, reg_get(cpu, REG_AX, is_word), right, is_word);
        advance_di(cpu, step);
        break;
    }

    case STRING_INS:
        mem_write(cpu, destination_address(cpu), is_word, port_read(cpu, cpu->gpr[REG_DX], is_word));
        advance_di(cpu, step);
        break;

    case STRING_OUTS:
        port_write(cpu, cpu->gpr[REG_DX], is_word, mem_read(cpu, source_address(cpu, source_segment), is_word));
        advance_si(cpu, step);
        break;

    default:
        break;
    }
}

/* Clocks charged for one pass in cycle model 1.  execute_one() already
   charged BASE_CYCLES[op]; the first pass takes that back so the figure
   from the tables above replaces it. */
static uint64_t string_pass_clocks(uint8_t op, enum string_kind kind, int has_rep, int first_pass, int was_resumed) {
    int clocks;

    if (has_rep) {
        clocks = STRING_CLOCKS_PER_ITERATION[kind];
        if (first_pass && !was_resumed) {
            clocks += STRING_CLOCKS_REP_SETUP[kind];
        }
    } else {
        clocks = STRING_CLOCKS_SINGLE[kind];
    }

    uint64_t charge = (uint64_t)clocks;
    if (first_pass) {
        charge -= BASE_CYCLES[op];
    }
    return charge;
}

/* Should a REP loop pause between passes so an interrupt (or the end of the
   cycle budget) can be handled? */
static int rep_must_pause(Cpu *cpu) {
    if (cpu->nmi_pending) {
        return 1;
    }
    if (cpu->irq_pending && cpu->flag_if) {
        return 1;
    }
    if (cpu->cycle_model && cpu->cycles >= cpu->run_end) {
        return 1;
    }
    return 0;
}

/* Execute one string instruction, with or without a REP prefix.
   `op` is the full opcode; the low bit is the width.

   Cycle accounting in model 1 (manual App. D): see string_pass_clocks().
   A REP loop charges its setup cost on the first pass only, and NOT when it
   is resumed after a pause.  In the legacy model every pass costs a flat 4,
   on top of the flat 4 execute_one() already charged.

   A REP loop can pause between passes: if passes remain and rep_must_pause()
   says so, IP is set back to the start of the instruction (including its
   prefixes, cpu->prefix_start_ip) and rep_resume is set, so the run loop
   restarts the same instruction with the reduced CX.  This is also what
   keeps the DSP and the codec clock running during a long block move.

   CMPS and SCAS also stop early on the zero flag: REPE stops when ZF is 0,
   REPNE stops when ZF is 1 (a bare REP prefix on CMPS behaves as REPNE). */
static void string_op(Cpu *cpu, uint8_t op) {
    enum string_kind kind = string_kind_of(op);
    int is_word = op & OP_WIDTH_BIT;
    int step = (is_word ? 2 : 1) * (cpu->flag_df ? -1 : 1);
    int source_segment = cpu->segment_override >= 0 ? cpu->segment_override : SEG_DS;
    int has_rep = cpu->rep_prefix;
    int compares = kind == STRING_CMPS || kind == STRING_SCAS;

    uint32_t passes_left = has_rep ? cpu->gpr[REG_CX] : 1;
    int first_pass = 1;
    int was_resumed = cpu->rep_resume;
    cpu->rep_resume = 0;

    while (passes_left) {
        string_step(cpu, kind, is_word, step, source_segment);

        if (cpu->cycle_model) {
            cpu->cycles += string_pass_clocks(op, kind, has_rep, first_pass, was_resumed);
            first_pass = 0;
        } else {
            cpu->cycles += CLOCKS_LEGACY_INSTRUCTION;
        }

        if (!has_rep) {
            passes_left = 0;
            continue;
        }

        cpu->gpr[REG_CX]--;
        passes_left = cpu->gpr[REG_CX];

        if (compares) {
            int stop_on_zero_flag = cpu->rep_is_repz ? !cpu->flag_zf : cpu->flag_zf;
            if (stop_on_zero_flag) {
                break;
            }
        }

        if (passes_left && rep_must_pause(cpu)) {
            cpu->ip = cpu->prefix_start_ip;
            cpu->rep_resume = 1;
            return;
        }
    }
}

/* ------------------------------------------------------------------
   Instruction execution.  execute_one() fetches the prefixes and the
   opcode, charges the base cycles, then dispatches: first the ALU forms
   (op < 0x40), then dispatch() below.  Each handler implements one
   opcode group.

   A handler that calls bad_opcode() sets cpu->status = ST_BADOP; the run
   loop then restores CS:IP and either returns ST_BADOP or vectors to
   INT 6.  Nothing runs after dispatch() in execute_one(), so a handler
   can simply return after bad_opcode().
   ------------------------------------------------------------------ */

/* ALU forms: op < 0x40 with (op & 7) < 6.
   Returns 1 if the opcode was an ALU form, 0 otherwise. */
static int exec_alu_forms(Cpu *cpu, uint8_t op, int is_word) {
    if (op >= OP_ALU_END || (op & ALU_FORM_MASK) >= ALU_FORM_COUNT) {
        return 0;
    }
    int alu_kind = op >> ALU_OP_SHIFT;

    switch (op & ALU_FORM_MASK) {
    case ALU_FORM_RM_REG_BYTE:
    case ALU_FORM_RM_REG_WORD: { /* ALU r/m, reg */
        decode_modrm(cpu);
        uint32_t left = modrm_read(cpu, is_word);
        uint32_t right = reg_get(cpu, cpu->modrm_reg, is_word);
        uint32_t result = alu_exec(cpu, alu_kind, left, right, is_word);

        if (alu_kind != ALU_CMP) {
            modrm_write(cpu, is_word, result);
        }
        break;
    }

    case ALU_FORM_REG_RM_BYTE:
    case ALU_FORM_REG_RM_WORD: { /* ALU reg, r/m */
        decode_modrm(cpu);
        uint32_t left = reg_get(cpu, cpu->modrm_reg, is_word);
        uint32_t right = modrm_read(cpu, is_word);
        uint32_t result = alu_exec(cpu, alu_kind, left, right, is_word);

        if (alu_kind != ALU_CMP) {
            reg_set(cpu, cpu->modrm_reg, is_word, result);
        }
        break;
    }

    case ALU_FORM_AL_IMM: { /* ALU AL, imm8 */
        uint32_t result = alu_exec(cpu, alu_kind, reg_get(cpu, REG_AX, 0), fetch_byte(cpu), 0);

        if (alu_kind != ALU_CMP) {
            reg_set(cpu, REG_AX, 0, result);
        }
        break;
    }

    case ALU_FORM_AX_IMM: { /* ALU AX, imm16 */
        uint32_t result = alu_exec(cpu, alu_kind, cpu->gpr[REG_AX], fetch_word(cpu), 1);

        if (alu_kind != ALU_CMP) {
            cpu->gpr[REG_AX] = (uint16_t)result;
        }
        break;
    }
    }
    return 1;
}

/* PUSH/POP segment register.  Note there is no POP CS
   (0x0F): it falls through to the bad-opcode default.  POP of a segment
   register sets the interrupt shadow (irq_shadow). */
static void exec_seg_push_pop(Cpu *cpu, uint8_t op) {
    switch (op) {
    case OP_PUSH_ES:
        push_word(cpu, cpu->sreg[SEG_ES]);
        break;
    case OP_PUSH_CS:
        push_word(cpu, cpu->sreg[SEG_CS]);
        break;
    case OP_PUSH_SS:
        push_word(cpu, cpu->sreg[SEG_SS]);
        break;
    case OP_PUSH_DS:
        push_word(cpu, cpu->sreg[SEG_DS]);
        break;

    case OP_POP_ES:
        cpu->sreg[SEG_ES] = pop_word(cpu);
        cpu->irq_shadow = 1;
        break;
    case OP_POP_SS:
        cpu->sreg[SEG_SS] = pop_word(cpu);
        cpu->irq_shadow = 1;
        break;
    case OP_POP_DS:
        cpu->sreg[SEG_DS] = pop_word(cpu);
        cpu->irq_shadow = 1;
        break;
    }
}

/* Decimal (BCD) adjust constants: a low digit above BCD_DIGIT_MAX needs
   BCD_LOW_ADJUST added or subtracted; a byte above BCD_HIGH_LIMIT needs
   BCD_HIGH_ADJUST. */
#define BCD_DIGIT_MAX 9
#define BCD_LOW_ADJUST 6
#define BCD_HIGH_LIMIT 0x9F
#define BCD_HIGH_ADJUST 0x60

/* Decimal adjusts.
   DAA/DAS follow the 8086-family silicon: the +-6 adjust carries/borrows
   into CF, and the second test looks at the adjusted AL (> 0x9F).
   AAA/AAS adjust AL and AH separately: the AL +-6 does not carry into
   the AH adjust.  AAD truncates its result to 8 bits (see below). */
static void exec_decimal(Cpu *cpu, uint8_t op) {
    switch (op) {
    case OP_DAA: { /* DAA */
        int low_byte = cpu->gpr[REG_AX] & 0xFF;
        int carry = cpu->flag_cf;

        if ((low_byte & 0xF) > BCD_DIGIT_MAX || cpu->flag_af) {
            low_byte += BCD_LOW_ADJUST;
            carry |= low_byte > 0xFF;
            low_byte &= 0xFF;
            cpu->flag_af = 1;
        } else {
            cpu->flag_af = 0;
        }

        if (low_byte > BCD_HIGH_LIMIT || carry) {
            low_byte = (low_byte + BCD_HIGH_ADJUST) & 0xFF;
            carry = 1;
        }

        cpu->flag_cf = carry;
        reg_set(cpu, REG_AX, 0, (uint32_t)low_byte);
        set_sign_zero_parity(cpu, (uint32_t)low_byte, 0);
        break;
    }

    case OP_DAS: { /* DAS */
        int low_byte = cpu->gpr[REG_AX] & 0xFF;
        int carry = cpu->flag_cf;

        if ((low_byte & 0xF) > BCD_DIGIT_MAX || cpu->flag_af) {
            carry |= low_byte < BCD_LOW_ADJUST;
            low_byte = (low_byte - BCD_LOW_ADJUST) & 0xFF;
            cpu->flag_af = 1;
        } else {
            cpu->flag_af = 0;
        }

        if (low_byte > BCD_HIGH_LIMIT || carry) {
            low_byte = (low_byte - BCD_HIGH_ADJUST) & 0xFF;
            carry = 1;
        }

        cpu->flag_cf = carry;
        reg_set(cpu, REG_AX, 0, (uint32_t)low_byte);
        set_sign_zero_parity(cpu, (uint32_t)low_byte, 0);
        break;
    }

    case OP_AAA: /* AAA */
        if ((cpu->gpr[REG_AX] & 0xF) > BCD_DIGIT_MAX || cpu->flag_af) {
            cpu->gpr[REG_AX] =
                (uint16_t)(((cpu->gpr[REG_AX] & 0xFF00u) + 0x100u) | ((cpu->gpr[REG_AX] + BCD_LOW_ADJUST) & 0xFFu));
            cpu->flag_af = 1;
            cpu->flag_cf = 1;
        } else {
            cpu->flag_af = 0;
            cpu->flag_cf = 0;
        }
        cpu->gpr[REG_AX] &= 0xFF0Fu;
        break;

    case OP_AAS: /* AAS */
        if ((cpu->gpr[REG_AX] & 0xF) > BCD_DIGIT_MAX || cpu->flag_af) {
            cpu->gpr[REG_AX] =
                (uint16_t)(((cpu->gpr[REG_AX] & 0xFF00u) - 0x100u) | ((cpu->gpr[REG_AX] - BCD_LOW_ADJUST) & 0xFFu));
            cpu->flag_af = 1;
            cpu->flag_cf = 1;
        } else {
            cpu->flag_af = 0;
            cpu->flag_cf = 0;
        }
        cpu->gpr[REG_AX] &= 0xFF0Fu;
        break;

    case OP_AAM: { /* AAM imm8 */
        uint8_t base = fetch_byte(cpu);

        if (!base) {
            do_interrupt(cpu, INT_DIVIDE_ERROR);
            break;
        }
        uint8_t low_byte = (uint8_t)(cpu->gpr[REG_AX] & 0xFF);

        cpu->gpr[REG_AX] = (uint16_t)(((low_byte / base) << 8) | (low_byte % base));
        set_sign_zero_parity(cpu, cpu->gpr[REG_AX], 0);
        break;
    }

    case OP_AAD: { /* AAD imm8 */
        uint8_t base = fetch_byte(cpu);

        /* QUIRK: the sum is stored in a uint8_t, so a base
           that makes AL + AH*base exceed 255 wraps mod 256 instead of
           producing the textbook 16-bit result. */
        uint8_t low_byte = (uint8_t)((cpu->gpr[REG_AX] & 0xFF) + (cpu->gpr[REG_AX] >> 8) * base);

        cpu->gpr[REG_AX] = low_byte;
        set_sign_zero_parity(cpu, low_byte, 0);
        break;
    }
    }
}

/* INC/DEC register, 0x40-0x4F. */
static void exec_inc_dec_reg(Cpu *cpu, uint8_t op) {
    cpu->gpr[op & 7] = (uint16_t)inc_dec(cpu, cpu->gpr[op & 7], op >= OP_DEC_REG_FIRST, 1);
}

/* PUSH/POP register, 0x50-0x5F.
   QUIRK: 0x54 pushes the SP value from BEFORE the
   instruction (the 80186 behaviour, unlike the 8086); the sibling
   courier-emu agrees. */
static void exec_push_pop_reg(Cpu *cpu, uint8_t op) {
    if (op >= OP_PUSH_REG_FIRST && op <= OP_PUSH_REG_LAST) {
        if (op == OP_PUSH_SP) {
            uint16_t original_sp = cpu->gpr[REG_SP];

            push_word(cpu, original_sp);
        } else {
            push_word(cpu, cpu->gpr[op & 7]);
        }
    } else if (op >= OP_POP_REG_FIRST && op <= OP_POP_REG_LAST) {
        if (op == OP_POP_SP) {
            cpu->gpr[REG_SP] = pop_word(cpu);
        } else {
            cpu->gpr[op & 7] = pop_word(cpu);
        }
    }
}

/* PUSHA/POPA, 0x60/0x61.  PUSHA pushes the SP value
   from before the instruction; POPA discards the slot where SP would go. */
static void exec_pusha_popa(Cpu *cpu, uint8_t op) {
    if (op == OP_PUSHA) {
        uint16_t original_sp = cpu->gpr[REG_SP];

        push_word(cpu, cpu->gpr[REG_AX]);
        push_word(cpu, cpu->gpr[REG_CX]);
        push_word(cpu, cpu->gpr[REG_DX]);
        push_word(cpu, cpu->gpr[REG_BX]);
        push_word(cpu, original_sp);
        push_word(cpu, cpu->gpr[REG_BP]);
        push_word(cpu, cpu->gpr[REG_SI]);
        push_word(cpu, cpu->gpr[REG_DI]);
    } else {
        cpu->gpr[REG_DI] = pop_word(cpu);
        cpu->gpr[REG_SI] = pop_word(cpu);
        cpu->gpr[REG_BP] = pop_word(cpu);
        pop_word(cpu); /* the SP slot is discarded */
        cpu->gpr[REG_BX] = pop_word(cpu);
        cpu->gpr[REG_DX] = pop_word(cpu);
        cpu->gpr[REG_CX] = pop_word(cpu);
        cpu->gpr[REG_AX] = pop_word(cpu);
    }
}

/* BOUND, 0x62.  A register operand is a bad opcode; an
   out-of-range index takes INT 5, which is a trap: the pushed IP is the
   next instruction. */
static void exec_bound(Cpu *cpu, uint8_t op) {
    decode_modrm(cpu);
    if (cpu->modrm_mod == MODRM_MOD_REGISTER) {
        bad_opcode(cpu, op);
        return;
    }

    uint32_t bounds_address = linear_address(cpu->ea_seg, cpu->ea_off);
    uint32_t upper_address = linear_address(cpu->ea_seg, (uint16_t)(cpu->ea_off + 2));
    int16_t index = (int16_t)cpu->gpr[cpu->modrm_reg];
    int16_t lower_bound = (int16_t)mem_read(cpu, bounds_address, 1);
    int16_t upper_bound = (int16_t)mem_read(cpu, upper_address, 1);

    if (index < lower_bound || index > upper_bound) {
        do_interrupt(cpu, INT_BOUND);
    }
}

/* PUSH imm16 / PUSH imm8-sign-extended, 0x68/0x6A. */
static void exec_push_imm(Cpu *cpu, uint8_t op) {
    if (op == OP_PUSH_IMM16) {
        push_word(cpu, fetch_word(cpu));
    } else {
        push_word(cpu, (uint16_t)(int16_t)(int8_t)fetch_byte(cpu));
    }
}

/* IMUL r16, r/m16, imm -- 0x69 (imm16) / 0x6B (imm8 sign-extended).
   The 32-bit product is truncated to 16 bits; CF/OF are
   set when the product does not fit in 16 bits. */
static void exec_imul(Cpu *cpu, uint8_t op) {
    decode_modrm(cpu);
    int32_t multiplicand = (int16_t)modrm_read(cpu, 1);
    int32_t multiplier = op == OP_IMUL_IMM16 ? (int16_t)fetch_word(cpu) : (int8_t)fetch_byte(cpu);
    int32_t product = multiplicand * multiplier;

    cpu->gpr[cpu->modrm_reg] = (uint16_t)product;
    cpu->flag_cf = cpu->flag_of = (product != (int16_t)product);
}

/* Conditional jumps, 0x70-0x7F.  Taken: +9 clocks in model 1,
   +12 in the legacy model, on top of the base charge. */
static void exec_jcc(Cpu *cpu, uint8_t op) {
    int8_t displacement = (int8_t)fetch_byte(cpu);

    if (condition_met(cpu, op & 0xF)) {
        cpu->ip = (uint16_t)(cpu->ip + displacement);
        cpu->cycles += cpu->cycle_model ? CLOCKS_JCC_TAKEN : CLOCKS_LEGACY_JCC_TAKEN;
    }
}

/* ALU with an immediate operand, 0x80-0x83.  The immediate
   is fetched after the r/m operand is read.  For 0x83 the 8-bit immediate
   is sign-extended to the operand width. */
static void exec_alu_imm(Cpu *cpu, uint8_t op, int is_word) {
    decode_modrm(cpu);
    uint32_t left = modrm_read(cpu, is_word);
    uint32_t right;

    if (op == OP_ALU_IMM_WORD) {
        right = fetch_word(cpu);
    } else if (op == OP_ALU_IMM_SIGNED) {
        right = (uint16_t)(int16_t)(int8_t)fetch_byte(cpu);
    } else {
        right = fetch_byte(cpu);
    }
    if (op == OP_ALU_IMM_SIGNED && !is_word) {
        right &= 0xFFu;
    }

    uint32_t result = alu_exec(cpu, cpu->modrm_reg, left, right & width_mask(is_word), is_word);

    if (cpu->modrm_reg != ALU_CMP) {
        modrm_write(cpu, is_word, result);
    }
}

/* TEST / XCHG / MOV forms, 0x84-0x8F.
   LEA (0x8D) with a register operand is a no-op, not a bad opcode.
   MOV to a segment register (0x8E) sets the interrupt shadow. */
static void exec_test_xchg_mov(Cpu *cpu, uint8_t op, int is_word) {
    switch (op) {
    case OP_TEST_RM_REG_BYTE:
    case OP_TEST_RM_REG_WORD: /* TEST r/m, r */
        decode_modrm(cpu);
        alu_exec(cpu, ALU_AND, modrm_read(cpu, is_word), reg_get(cpu, cpu->modrm_reg, is_word), is_word);
        break;

    case OP_XCHG_RM_REG_BYTE:
    case OP_XCHG_RM_REG_WORD: { /* XCHG r/m, r */
        decode_modrm(cpu);
        uint32_t memory_value = modrm_read(cpu, is_word);
        uint32_t register_value = reg_get(cpu, cpu->modrm_reg, is_word);

        modrm_write(cpu, is_word, register_value);
        reg_set(cpu, cpu->modrm_reg, is_word, memory_value);
        break;
    }

    case OP_MOV_RM_REG_BYTE:
    case OP_MOV_RM_REG_WORD: /* MOV r/m, r */
        decode_modrm(cpu);
        modrm_write(cpu, is_word, reg_get(cpu, cpu->modrm_reg, is_word));
        break;

    case OP_MOV_REG_RM_BYTE:
    case OP_MOV_REG_RM_WORD: /* MOV r, r/m */
        decode_modrm(cpu);
        reg_set(cpu, cpu->modrm_reg, is_word, modrm_read(cpu, is_word));
        break;

    case OP_MOV_RM_SREG: /* MOV r/m, sreg */
        decode_modrm(cpu);
        if (cpu->modrm_reg >= SREG_COUNT) { /* there are only four segment registers */
            bad_opcode(cpu, op);
            return;
        }
        modrm_write(cpu, 1, cpu->sreg[cpu->modrm_reg]);
        break;

    case OP_LEA: /* LEA r, m */
        decode_modrm(cpu);
        if (cpu->modrm_mod != MODRM_MOD_REGISTER) {
            cpu->gpr[cpu->modrm_reg] = cpu->ea_off;
        }
        break;

    case OP_MOV_SREG_RM: /* MOV sreg, r/m */
        decode_modrm(cpu);
        if (cpu->modrm_reg >= SREG_COUNT) { /* there are only four segment registers */
            bad_opcode(cpu, op);
            return;
        }
        cpu->sreg[cpu->modrm_reg] = (uint16_t)modrm_read(cpu, 1);
        cpu->irq_shadow = 1;
        break;

    case OP_POP_RM: { /* POP r/m: EA is decoded BEFORE the pop */
        decode_modrm(cpu);
        if (cpu->modrm_reg != MODRM_REG_ONLY_FORM) {
            bad_opcode(cpu, op);
            return;
        }
        uint16_t value = pop_word(cpu);

        modrm_write(cpu, 1, value);
        break;
    }
    }
}

/* XCHG AX, reg, 0x91-0x97; 0x90 is NOP. */
static void exec_xchg_ax(Cpu *cpu, uint8_t op) {
    uint16_t saved_ax = cpu->gpr[REG_AX];

    cpu->gpr[REG_AX] = cpu->gpr[op & 7];
    cpu->gpr[op & 7] = saved_ax;
}

/* CBW / CWD. */
static void exec_cbw_cwd(Cpu *cpu, uint8_t op) {
    if (op == OP_CBW) {
        cpu->gpr[REG_AX] = (uint16_t)(int16_t)(int8_t)(cpu->gpr[REG_AX] & 0xFFu);
    } else {
        cpu->gpr[REG_DX] = (cpu->gpr[REG_AX] & 0x8000u) ? 0xFFFFu : 0;
    }
}

/* CALL far, 0x9A.  QUIRK: the extra 20 clocks are charged
   ONLY in the legacy model; in model 1 the BASE_CYCLES[0x9A] base (5) stands. */
static void exec_call_far(Cpu *cpu, uint8_t op) {
    (void)op;
    uint16_t offset = fetch_word(cpu);
    uint16_t segment = fetch_word(cpu);

    push_word(cpu, cpu->sreg[SEG_CS]);
    push_word(cpu, cpu->ip);
    cpu->ip = offset;
    cpu->sreg[SEG_CS] = segment;

    if (!cpu->cycle_model) {
        cpu->cycles += CLOCKS_LEGACY_CALL_FAR;
    }
}

/* PUSHF / POPF / SAHF / LAHF, 0x9C-0x9F.  SAHF loads
   only CF/PF/AF/ZF/SF from AH; OF/DF/IF/TF are untouched. */
static void exec_pushf_popf(Cpu *cpu, uint8_t op) {
    switch (op) {
    case OP_PUSHF:
        push_word(cpu, flags_get(cpu));
        break;

    case OP_POPF:
        flags_set(cpu, pop_word(cpu));
        break;

    case OP_SAHF: { /* SAHF */
        uint8_t ah = (uint8_t)(cpu->gpr[REG_AX] >> 8);

        cpu->flag_cf = ah & 1;
        cpu->flag_pf = (ah >> 2) & 1;
        cpu->flag_af = (ah >> 4) & 1;
        cpu->flag_zf = (ah >> 6) & 1;
        cpu->flag_sf = (ah >> 7) & 1;
        break;
    }

    case OP_LAHF: /* LAHF */
        cpu->gpr[REG_AX] = (uint16_t)((cpu->gpr[REG_AX] & 0xFFu) | ((flags_get(cpu) & 0xFFu) << 8));
        break;
    }
}

/* MOV AX, moffs / MOV moffs, AX, 0xA0-0xA3.  A segment
   prefix overrides the default DS. */
static void exec_moffs(Cpu *cpu, uint8_t op, int is_word) {
    uint16_t offset = fetch_word(cpu);
    uint16_t segment = cpu->sreg[cpu->segment_override >= 0 ? cpu->segment_override : SEG_DS];
    uint32_t address = linear_address(segment, offset);

    if (op == OP_MOV_AL_MOFFS || op == OP_MOV_AX_MOFFS) {
        reg_set(cpu, REG_AX, is_word, mem_read(cpu, address, is_word));
    } else {
        mem_write(cpu, address, is_word, reg_get(cpu, REG_AX, is_word));
    }
}

/* TEST accumulator, 0xA8/0xA9. */
static void exec_test_acc(Cpu *cpu, uint8_t op, int is_word) {
    (void)is_word;
    if (op == OP_TEST_AL_IMM) {
        alu_exec(cpu, ALU_AND, reg_get(cpu, REG_AX, 0), fetch_byte(cpu), 0);
    } else {
        alu_exec(cpu, ALU_AND, cpu->gpr[REG_AX], fetch_word(cpu), 1);
    }
}

/* MOV reg, imm, 0xB0-0xBF. */
static void exec_mov_imm(Cpu *cpu, uint8_t op) {
    if (op < OP_MOV_REG16_IMM_FIRST) {
        reg_set(cpu, op & 7, 0, fetch_byte(cpu));
    } else {
        cpu->gpr[op & 7] = fetch_word(cpu);
    }
}

/* Shifts by an 8-bit immediate, 0xC0/0xC1.
   QUIRK: the model-1 extra is (mod==3 ? 0 : 6) + (n & 31) - 1, so a
   shift count of 0 SUBTRACTS one clock (5+n reg / 17+n mem in the
   manual's terms, with n the masked count).  Kept verbatim, including
   the unsigned wrap of the subtraction. */
static void exec_shift_imm(Cpu *cpu, uint8_t op, int is_word) {
    decode_modrm(cpu);
    if (cpu->modrm_reg == SHIFT_SHL_ALIAS) { /* undefined as an opcode */
        bad_opcode(cpu, op);
        return;
    }

    uint32_t value = modrm_read(cpu, is_word);
    int count = fetch_byte(cpu);

    if (cpu->cycle_model) {
        cpu->cycles += (cpu->modrm_mod == MODRM_MOD_REGISTER ? 0 : CLOCKS_MEMORY_OPERAND) + (count & 31) - 1;
    }
    modrm_write(cpu, is_word, shift_rotate(cpu, cpu->modrm_reg, value, count, is_word));
}

/* RET / RETF, 0xC2/0xC3/0xCA/0xCB. */
static void exec_ret(Cpu *cpu, uint8_t op) {
    switch (op) {
    case OP_RET_NEAR_POP: {
        uint16_t extra_bytes = fetch_word(cpu);

        cpu->ip = pop_word(cpu);
        cpu->gpr[REG_SP] = (uint16_t)(cpu->gpr[REG_SP] + extra_bytes);
        break;
    }

    case OP_RET_NEAR:
        cpu->ip = pop_word(cpu);
        break;

    case OP_RET_FAR_POP: {
        uint16_t extra_bytes = fetch_word(cpu);

        cpu->ip = pop_word(cpu);
        cpu->sreg[SEG_CS] = pop_word(cpu);
        cpu->gpr[REG_SP] = (uint16_t)(cpu->gpr[REG_SP] + extra_bytes);
        break;
    }

    case OP_RET_FAR:
        cpu->ip = pop_word(cpu);
        cpu->sreg[SEG_CS] = pop_word(cpu);
        break;
    }
}

/* LES / LDS, 0xC4/0xC5.  A register operand is a bad opcode.
   The segment word is read from ea+2 (no 16-bit wrap on the offset). */
static void exec_les_lds(Cpu *cpu, uint8_t op) {
    decode_modrm(cpu);
    if (cpu->modrm_mod == MODRM_MOD_REGISTER) {
        bad_opcode(cpu, op);
        return;
    }

    uint32_t address = linear_address(cpu->ea_seg, cpu->ea_off);

    cpu->gpr[cpu->modrm_reg] = (uint16_t)mem_read(cpu, address, 1);
    cpu->sreg[op == OP_LES ? SEG_ES : SEG_DS] = (uint16_t)mem_read(cpu, address + 2, 1);
}

/* MOV r/m, imm, 0xC6/0xC7. */
static void exec_mov_rm_imm(Cpu *cpu, uint8_t op, int is_word) {
    decode_modrm(cpu);
    if (cpu->modrm_reg != MODRM_REG_ONLY_FORM) {
        bad_opcode(cpu, op);
        return;
    }

    uint32_t value = is_word ? fetch_word(cpu) : fetch_byte(cpu);

    modrm_write(cpu, is_word, value);
}

/* ENTER / LEAVE, 0xC8/0xC9.  ENTER pushes BP, then for
   nesting level > 1 pushes the chain of saved frame pointers from below
   the new frame (BP is decremented before each read), then pushes the
   new frame pointer; BP is set to it and SP drops by the frame size. */
static void exec_enter_leave(Cpu *cpu, uint8_t op) {
    if (op == OP_ENTER) {
        uint16_t frame_size = fetch_word(cpu);
        int nesting_level = fetch_byte(cpu) & 31;

        push_word(cpu, cpu->gpr[REG_BP]);
        uint16_t frame_pointer = cpu->gpr[REG_SP];

        if (nesting_level > 0) {
            for (int i = 1; i < nesting_level; i++) {
                cpu->gpr[REG_BP] = (uint16_t)(cpu->gpr[REG_BP] - 2);
                push_word(cpu, (uint16_t)mem_read(cpu, linear_address(cpu->sreg[SEG_SS], cpu->gpr[REG_BP]), 1));
            }
            push_word(cpu, frame_pointer);
        }

        cpu->gpr[REG_BP] = frame_pointer;
        cpu->gpr[REG_SP] = (uint16_t)(cpu->gpr[REG_SP] - frame_size);
    } else {
        cpu->gpr[REG_SP] = cpu->gpr[REG_BP];
        cpu->gpr[REG_BP] = pop_word(cpu);
    }
}

/* INT3 / INT imm / INTO / IRET, 0xCC-0xCF.  INTO takes
   INT 4 only when OF is set.  IRET pops IP, CS, then FLAGS. */
static void exec_int(Cpu *cpu, uint8_t op) {
    switch (op) {
    case OP_INT3:
        do_interrupt(cpu, INT_BREAKPOINT);
        break;

    case OP_INT_IMM:
        do_interrupt(cpu, fetch_byte(cpu));
        break;

    case OP_INTO:
        if (cpu->flag_of) {
            do_interrupt(cpu, INT_OVERFLOW);
        }
        break;

    case OP_IRET:
        cpu->ip = pop_word(cpu);
        cpu->sreg[SEG_CS] = pop_word(cpu);
        flags_set(cpu, pop_word(cpu));
        break;
    }
}

/* Shifts by 1 or by CL, 0xD0-0xD3.
   QUIRK: the model-1 extra for a by-1 register shift is -2 clocks (the
   expression is (mod==3 ? -2 : 5)), so a register shift-by-1 SUBTRACTS
   two clocks; a by-CL shift adds (mod==3 ? 0 : 6) + (n & 31) + 1.
   Kept verbatim, including the unsigned wrap. */
static void exec_shift_1_cl(Cpu *cpu, uint8_t op, int is_word) {
    decode_modrm(cpu);
    if (cpu->modrm_reg == SHIFT_SHL_ALIAS) { /* undefined as an opcode */
        bad_opcode(cpu, op);
        return;
    }

    uint32_t value = modrm_read(cpu, is_word);
    int by_cl = op == OP_SHIFT_CL_BYTE || op == OP_SHIFT_CL_WORD;
    int count = by_cl ? (cpu->gpr[REG_CX] & 0xFF) : 1;

    if (cpu->cycle_model) {
        cpu->cycles +=
            by_cl ? (cpu->modrm_mod == MODRM_MOD_REGISTER ? 0 : CLOCKS_MEMORY_OPERAND) + (count & 31) + 1
                  : (cpu->modrm_mod == MODRM_MOD_REGISTER ? CLOCKS_SHIFT_BY_1_REGISTER : CLOCKS_SHIFT_BY_1_MEMORY);
    }
    modrm_write(cpu, is_word, shift_rotate(cpu, cpu->modrm_reg, value, count, is_word));
}

/* XLAT, 0xD7.  The table is in the (possibly overridden)
   DS segment at BX + AL; the offset wraps at 16 bits. */
static void exec_xlat(Cpu *cpu, uint8_t op) {
    (void)op;
    uint16_t segment = cpu->sreg[cpu->segment_override >= 0 ? cpu->segment_override : SEG_DS];
    uint16_t offset = (uint16_t)(cpu->gpr[REG_BX] + (cpu->gpr[REG_AX] & 0xFFu));

    reg_set(cpu, REG_AX, 0, mem_read(cpu, linear_address(segment, offset), 0));
}

/* LOOP / LOOPcc / JCXZ, 0xE0-0xE3.  LOOP decrements CX
   first and branches while it is non-zero; 0xE0 also requires ZF==0,
   0xE1 requires ZF==1.  A taken branch adds 10 clocks in model 1 only.
   (The base BASE_CYCLES for 0xE0-0xE3 is 6 in both models.) */
static void exec_loop(Cpu *cpu, uint8_t op) {
    int8_t displacement = (int8_t)fetch_byte(cpu);
    int taken;

    if (op == OP_JCXZ) { /* JCXZ: tests CX without decrementing it */
        taken = cpu->gpr[REG_CX] == 0;
    } else {
        cpu->gpr[REG_CX]--;
        taken = cpu->gpr[REG_CX] != 0;
        if (op == OP_LOOPNE) {
            taken = taken && !cpu->flag_zf;
        } else if (op == OP_LOOPE) {
            taken = taken && cpu->flag_zf;
        }
    }

    if (taken) {
        cpu->ip = (uint16_t)(cpu->ip + displacement);
        if (cpu->cycle_model) {
            cpu->cycles += CLOCKS_LOOP_TAKEN;
        }
    }
}

/* IN/OUT with an 8-bit immediate port, 0xE4-0xE7. */
static void exec_in_out_imm(Cpu *cpu, uint8_t op, int is_word) {
    uint8_t port = fetch_byte(cpu);

    if (op == OP_IN_AL_IMM || op == OP_IN_AX_IMM) {
        reg_set(cpu, REG_AX, is_word, port_read(cpu, port, is_word));
    } else {
        port_write(cpu, port, is_word, reg_get(cpu, REG_AX, is_word));
    }
}

/* CALL/JMP, 0xE8-0xEB. */
static void exec_call_jmp(Cpu *cpu, uint8_t op) {
    switch (op) {
    case OP_CALL_NEAR: {
        int16_t displacement = (int16_t)fetch_word(cpu);

        push_word(cpu, cpu->ip);
        cpu->ip = (uint16_t)(cpu->ip + displacement);
        break;
    }

    case OP_JMP_NEAR: {
        int16_t displacement = (int16_t)fetch_word(cpu);

        cpu->ip = (uint16_t)(cpu->ip + displacement);
        break;
    }

    case OP_JMP_FAR: {
        uint16_t offset = fetch_word(cpu);
        uint16_t segment = fetch_word(cpu);

        cpu->ip = offset;
        cpu->sreg[SEG_CS] = segment;
        break;
    }

    case OP_JMP_SHORT: {
        int8_t displacement = (int8_t)fetch_byte(cpu);

        cpu->ip = (uint16_t)(cpu->ip + displacement);
        break;
    }
    }
}

/* IN/OUT through DX, 0xEC-0xEF. */
static void exec_in_out_dx(Cpu *cpu, uint8_t op, int is_word) {
    if (op == OP_IN_AL_DX || op == OP_IN_AX_DX) {
        reg_set(cpu, REG_AX, is_word, port_read(cpu, cpu->gpr[REG_DX], is_word));
    } else {
        port_write(cpu, cpu->gpr[REG_DX], is_word, reg_get(cpu, REG_AX, is_word));
    }
}

/* HLT / CMC, 0xF4/0xF5. */
static void exec_halt_cmc(Cpu *cpu, uint8_t op) {
    if (op == OP_HLT) {
        cpu->halted = 1;
    } else {
        cpu->flag_cf = !cpu->flag_cf;
    }
}

/* Group F6/F7: TEST / NOT / NEG / MUL / IMUL / DIV / IDIV.
   The immediate for TEST is fetched AFTER the r/m operand is read.
   MUL/IMUL/DIV/IDIV add their model-1 extra on top of the BASE_CYCLES base and
   of the decode_modrm memory charge (App. D: MUL r8 26-28, r16 35-37;
   IMUL r8 25-28, r16 34-37; DIV/IDIV r8 29, r16 38).
   DIV/IDIV overflow (including divide by zero) takes INT 0 with IP
   pointing at the next instruction. */
static void exec_group_f6f7(Cpu *cpu, uint8_t op, int is_word) {
    decode_modrm(cpu);
    if (cpu->modrm_reg == F6F7_REG_TEST_ALIAS) { /* undefined as an opcode */
        bad_opcode(cpu, op);
        return;
    }

    uint32_t operand = modrm_read(cpu, is_word);

    switch (cpu->modrm_reg) {
    case F6F7_REG_TEST:
    case F6F7_REG_TEST_ALIAS: /* TEST r/m, imm */
        alu_exec(cpu, ALU_AND, operand, is_word ? fetch_word(cpu) : fetch_byte(cpu), is_word);
        break;

    case F6F7_REG_NOT: /* NOT r/m */
        modrm_write(cpu, is_word, ~operand);
        break;

    case F6F7_REG_NEG: { /* NEG r/m: CF is set from the operand, not from the ALU */
        uint32_t result = alu_exec(cpu, ALU_SUB, 0, operand, is_word);

        cpu->flag_cf = operand != 0;
        modrm_write(cpu, is_word, result);
        break;
    }

    case F6F7_REG_MUL: /* MUL r/m */
        if (cpu->cycle_model) {
            cpu->cycles += is_word ? CLOCKS_MUL_WORD : CLOCKS_MUL_BYTE;
        }
        if (is_word) {
            uint32_t product = (uint32_t)cpu->gpr[REG_AX] * operand;

            cpu->gpr[REG_AX] = (uint16_t)product;
            cpu->gpr[REG_DX] = (uint16_t)(product >> 16);
            cpu->flag_cf = cpu->flag_of = (product >> 16) != 0;
        } else {
            uint32_t product = (cpu->gpr[REG_AX] & 0xFFu) * operand;

            cpu->gpr[REG_AX] = (uint16_t)product;
            cpu->flag_cf = cpu->flag_of = (product >> 8) != 0;
        }
        break;

    case F6F7_REG_IMUL: /* IMUL r/m */
        if (cpu->cycle_model) {
            cpu->cycles += is_word ? CLOCKS_MUL_WORD : CLOCKS_MUL_BYTE;
        }
        if (is_word) {
            int32_t product = (int32_t)(int16_t)cpu->gpr[REG_AX] * (int16_t)operand;

            cpu->gpr[REG_AX] = (uint16_t)product;
            cpu->gpr[REG_DX] = (uint16_t)(product >> 16);
            cpu->flag_cf = cpu->flag_of = (product != (int16_t)product);
        } else {
            int32_t product = (int8_t)cpu->gpr[REG_AX] * (int8_t)operand;

            cpu->gpr[REG_AX] = (uint16_t)product;
            cpu->flag_cf = cpu->flag_of = (product != (int8_t)product);
        }
        break;

    case F6F7_REG_DIV: /* DIV r/m */
        if (cpu->cycle_model) {
            cpu->cycles += is_word ? CLOCKS_DIV_WORD : CLOCKS_DIV_BYTE;
        }
        if (is_word) {
            uint32_t dividend = ((uint32_t)cpu->gpr[REG_DX] << 16) | cpu->gpr[REG_AX];

            if (!operand || dividend / operand > 0xFFFFu) {
                do_interrupt(cpu, INT_DIVIDE_ERROR);
                break;
            }
            cpu->gpr[REG_AX] = (uint16_t)(dividend / operand);
            cpu->gpr[REG_DX] = (uint16_t)(dividend % operand);
        } else {
            uint32_t dividend = cpu->gpr[REG_AX];

            if (!operand || dividend / operand > 0xFFu) {
                do_interrupt(cpu, INT_DIVIDE_ERROR);
                break;
            }
            cpu->gpr[REG_AX] = (uint16_t)(((dividend % operand) << 8) | (dividend / operand));
        }
        break;

    case F6F7_REG_IDIV: /* IDIV r/m */
        if (cpu->cycle_model) {
            cpu->cycles += is_word ? CLOCKS_DIV_WORD : CLOCKS_DIV_BYTE;
        }
        if (is_word) {
            int64_t dividend = (int32_t)(((uint32_t)cpu->gpr[REG_DX] << 16) | cpu->gpr[REG_AX]);
            int64_t divisor = (int16_t)operand;

            if (!divisor || dividend / divisor > 32767 || dividend / divisor < -32768) {
                do_interrupt(cpu, INT_DIVIDE_ERROR);
                break;
            }
            cpu->gpr[REG_AX] = (uint16_t)(dividend / divisor);
            cpu->gpr[REG_DX] = (uint16_t)(dividend % divisor);
        } else {
            int32_t dividend = (int16_t)cpu->gpr[REG_AX];
            int32_t divisor = (int8_t)operand;

            if (!divisor || dividend / divisor > 127 || dividend / divisor < -128) {
                do_interrupt(cpu, INT_DIVIDE_ERROR);
                break;
            }
            cpu->gpr[REG_AX] = (uint16_t)((((dividend % divisor) & 0xFF) << 8) | ((dividend / divisor) & 0xFF));
        }
        break;
    }
}

/* Flag operations, 0xF8-0xFD.  STI sets the interrupt
   shadow; CLI/STI act immediately on IF itself. */
static void exec_flag_ops(Cpu *cpu, uint8_t op) {
    switch (op) {
    case OP_CLC:
        cpu->flag_cf = 0;
        break;
    case OP_STC:
        cpu->flag_cf = 1;
        break;
    case OP_CLI:
        cpu->flag_if = 0;
        break;
    case OP_CLD:
        cpu->flag_df = 0;
        break;
    case OP_STD:
        cpu->flag_df = 1;
        break;

    case OP_STI:
        cpu->flag_if = 1;
        cpu->irq_shadow = 1;
        break;
    }
}

/* Group FE: INC/DEC r/m8, 0xFE.  reg > 1 is a bad opcode. */
static void exec_group_fe(Cpu *cpu, uint8_t op) {
    decode_modrm(cpu);
    if (cpu->modrm_reg > FF_REG_DEC) {
        bad_opcode(cpu, op);
        return;
    }
    modrm_write(cpu, 0, inc_dec(cpu, modrm_read(cpu, 0), cpu->modrm_reg, 0));
}

/* Group FF.  Far forms with a register operand are bad
   opcodes; anything else in reg 7 is a bad opcode.  The model-1 extras
   are +10 (near indirect CALL), +28 (far indirect CALL) and +8
   (indirect JMP). */
static void exec_group_ff(Cpu *cpu, uint8_t op) {
    decode_modrm(cpu);

    switch (cpu->modrm_reg) {
    case FF_REG_INC:
    case FF_REG_DEC: /* INC/DEC r/m16 */
        modrm_write(cpu, 1, inc_dec(cpu, modrm_read(cpu, 1), cpu->modrm_reg, 1));
        break;

    case FF_REG_CALL_NEAR: { /* CALL r/m16: the target is read before IP is pushed */
        uint16_t target = (uint16_t)modrm_read(cpu, 1);

        push_word(cpu, cpu->ip);
        cpu->ip = target;
        if (cpu->cycle_model) {
            cpu->cycles += CLOCKS_CALL_NEAR_INDIRECT;
        }
        break;
    }

    case FF_REG_CALL_FAR: { /* CALL far r/m */
        if (cpu->modrm_mod == MODRM_MOD_REGISTER) {
            bad_opcode(cpu, op);
            return;
        }
        uint32_t address = linear_address(cpu->ea_seg, cpu->ea_off);
        uint16_t offset = (uint16_t)mem_read(cpu, address, 1);
        uint16_t segment = (uint16_t)mem_read(cpu, address + 2, 1);

        push_word(cpu, cpu->sreg[SEG_CS]);
        push_word(cpu, cpu->ip);
        cpu->ip = offset;
        cpu->sreg[SEG_CS] = segment;
        if (cpu->cycle_model) {
            cpu->cycles += CLOCKS_CALL_FAR_INDIRECT;
        }
        break;
    }

    case FF_REG_JMP_NEAR: /* JMP r/m16 */
        cpu->ip = (uint16_t)modrm_read(cpu, 1);
        if (cpu->cycle_model) {
            cpu->cycles += CLOCKS_JMP_INDIRECT;
        }
        break;

    case FF_REG_JMP_FAR: { /* JMP far r/m */
        if (cpu->modrm_mod == MODRM_MOD_REGISTER) {
            bad_opcode(cpu, op);
            return;
        }
        uint32_t address = linear_address(cpu->ea_seg, cpu->ea_off);

        cpu->ip = (uint16_t)mem_read(cpu, address, 1);
        cpu->sreg[SEG_CS] = (uint16_t)mem_read(cpu, address + 2, 1);
        break;
    }

    case FF_REG_PUSH: { /* PUSH r/m16 */
        uint16_t value = (uint16_t)modrm_read(cpu, 1);

        push_word(cpu, value);
        break;
    }

    default:
        bad_opcode(cpu, op);
        break;
    }
}

/* ------------------------------------------------------------------
   Opcode dispatch.
   ALU forms are handled before this, in exec_alu_forms().  String
   opcodes go straight to string_op().  NOP and WAIT do nothing.  Anything
   not listed is a bad opcode.
   ------------------------------------------------------------------ */
static void dispatch(Cpu *cpu, uint8_t op, int is_word) {
    switch (op) {
    case OP_PUSH_ES:
    case OP_PUSH_CS:
    case OP_PUSH_SS:
    case OP_PUSH_DS:
    case OP_POP_ES:
    case OP_POP_SS:
    case OP_POP_DS:
        exec_seg_push_pop(cpu, op);
        break;

    case OP_DAA:
    case OP_DAS:
    case OP_AAA:
    case OP_AAS:
    case OP_AAM:
    case OP_AAD:
        exec_decimal(cpu, op);
        break;

    case OP_INC_REG_FIRST ... OP_DEC_REG_LAST:
        exec_inc_dec_reg(cpu, op);
        break;

    case OP_PUSH_REG_FIRST ... OP_POP_REG_LAST:
        exec_push_pop_reg(cpu, op);
        break;

    case OP_PUSHA:
    case OP_POPA:
        exec_pusha_popa(cpu, op);
        break;

    case OP_BOUND:
        exec_bound(cpu, op);
        break;

    case OP_PUSH_IMM16:
    case OP_PUSH_IMM8:
        exec_push_imm(cpu, op);
        break;

    case OP_IMUL_IMM16:
    case OP_IMUL_IMM8:
        exec_imul(cpu, op);
        break;

    case OP_INS_BYTE ... OP_OUTS_WORD:
    case OP_MOVS_BYTE ... OP_CMPS_WORD:
    case OP_STOS_BYTE ... OP_SCAS_WORD:
        string_op(cpu, op);
        break;

    case OP_JCC_FIRST ... OP_JCC_LAST:
        exec_jcc(cpu, op);
        break;

    case OP_ALU_IMM_BYTE ... OP_ALU_IMM_SIGNED:
        exec_alu_imm(cpu, op, is_word);
        break;

    case OP_TEST_RM_REG_BYTE ... OP_POP_RM:
        exec_test_xchg_mov(cpu, op, is_word);
        break;

    case OP_NOP:
    case OP_WAIT:
        break;

    case OP_XCHG_AX_FIRST ... OP_XCHG_AX_LAST:
        exec_xchg_ax(cpu, op);
        break;

    case OP_CBW:
    case OP_CWD:
        exec_cbw_cwd(cpu, op);
        break;

    case OP_CALL_FAR:
        exec_call_far(cpu, op);
        break;

    case OP_PUSHF ... OP_LAHF:
        exec_pushf_popf(cpu, op);
        break;

    case OP_MOV_AL_MOFFS ... OP_MOV_MOFFS_AX:
        exec_moffs(cpu, op, is_word);
        break;

    case OP_TEST_AL_IMM:
    case OP_TEST_AX_IMM:
        exec_test_acc(cpu, op, is_word);
        break;

    case OP_MOV_REG_IMM_FIRST ... OP_MOV_REG_IMM_LAST:
        exec_mov_imm(cpu, op);
        break;

    case OP_SHIFT_IMM_BYTE:
    case OP_SHIFT_IMM_WORD:
        exec_shift_imm(cpu, op, is_word);
        break;

    case OP_RET_NEAR_POP:
    case OP_RET_NEAR:
    case OP_RET_FAR_POP:
    case OP_RET_FAR:
        exec_ret(cpu, op);
        break;

    case OP_LES:
    case OP_LDS:
        exec_les_lds(cpu, op);
        break;

    case OP_MOV_RM_IMM_BYTE:
    case OP_MOV_RM_IMM_WORD:
        exec_mov_rm_imm(cpu, op, is_word);
        break;

    case OP_ENTER:
    case OP_LEAVE:
        exec_enter_leave(cpu, op);
        break;

    case OP_INT3:
    case OP_INT_IMM:
    case OP_INTO:
    case OP_IRET:
        exec_int(cpu, op);
        break;

    case OP_SHIFT_1_BYTE ... OP_SHIFT_CL_WORD:
        exec_shift_1_cl(cpu, op, is_word);
        break;

    case OP_XLAT:
        exec_xlat(cpu, op);
        break;

    case OP_ESC_FIRST ... OP_ESC_LAST:
        decode_modrm(cpu); /* coprocessor escape: decode the operand and ignore it */
        break;

    case OP_LOOPNE ... OP_JCXZ:
        exec_loop(cpu, op);
        break;

    case OP_IN_AL_IMM ... OP_OUT_IMM_AX:
        exec_in_out_imm(cpu, op, is_word);
        break;

    case OP_CALL_NEAR ... OP_JMP_SHORT:
        exec_call_jmp(cpu, op);
        break;

    case OP_IN_AL_DX ... OP_OUT_DX_AX:
        exec_in_out_dx(cpu, op, is_word);
        break;

    case OP_HLT:
    case OP_CMC:
        exec_halt_cmc(cpu, op);
        break;

    case OP_GROUP_F6:
    case OP_GROUP_F7:
        exec_group_f6f7(cpu, op, is_word);
        break;

    case OP_CLC ... OP_STD:
        exec_flag_ops(cpu, op);
        break;

    case OP_GROUP_FE:
        exec_group_fe(cpu, op);
        break;

    case OP_GROUP_FF:
        exec_group_ff(cpu, op);
        break;

    default:
        bad_opcode(cpu, op);
        break;
    }
}
/* Fetch the opcode, consuming any prefixes.  Segment overrides and LOCK
   cost 2 clocks each in cycle model 1 and nothing in the legacy model;
   REP/REPNE set the repeat state.  LOCK has no other effect. */
static uint8_t fetch_opcode(Cpu *cpu) {
    for (;;) {
        uint8_t op = fetch_byte(cpu);

        if (op == PREFIX_ES) {
            cpu->segment_override = SEG_ES;
        } else if (op == PREFIX_CS) {
            cpu->segment_override = SEG_CS;
        } else if (op == PREFIX_SS) {
            cpu->segment_override = SEG_SS;
        } else if (op == PREFIX_DS) {
            cpu->segment_override = SEG_DS;
        }

        if (op == PREFIX_ES || op == PREFIX_CS || op == PREFIX_SS || op == PREFIX_DS || op == PREFIX_LOCK) {
            if (cpu->cycle_model) {
                cpu->cycles += CLOCKS_PREFIX;
            }
        } else if (op == PREFIX_REPNE) {
            cpu->rep_prefix = 1;
            cpu->rep_is_repz = 0;
        } else if (op == PREFIX_REP) {
            cpu->rep_prefix = 1;
            cpu->rep_is_repz = 1;
        } else {
            return op;
        }
    }
}

/* Execute one instruction: trace it, fetch prefixes +
   opcode, charge the base cycles, dispatch. */
static void execute_one(Cpu *cpu) {
    uint32_t pc0 = linear_address(cpu->sreg[SEG_CS], cpu->ip);

    cpu->prefix_start_ip = cpu->ip;
    cpu->cur_pc = pc0;
    cpu->hits[pc0]++;
    cpu->pc_ring[cpu->pc_ring_pos++ & I186_RING_MASK] = pc0;

    cpu->segment_override = -1;
    cpu->rep_prefix = 0;
    cpu->rep_is_repz = 0;

    uint8_t op = fetch_opcode(cpu);
    int is_word = op & 1;

    cpu->opcode = op;
    cpu->cycles += cpu->cycle_model ? BASE_CYCLES[op] : CLOCKS_LEGACY_INSTRUCTION;

    if (exec_alu_forms(cpu, op, is_word)) {
        return;
    }
    dispatch(cpu, op, is_word);
}

/* ------------------------------------------------------------------
   Run loop.
   ------------------------------------------------------------------ */

/* Run until the cycle budget is exhausted; returns enum i186_status.

   Per iteration, in this order:
    1. Take a pending NMI (type 2), else a pending maskable IRQ if IF is
       set and the interrupt shadow (irq_shadow) from the previous instruction
       has expired.  Either clears HLT.  NMI also clears irq_shadow; the IRQ
       path relies on the irq_shadow=0 below.  A pending request with IF=0
       cannot wake a halted CPU (NMI can).
    2. If still halted, consume the rest of the budget and return ST_HLT.
    3. Breakpoint check -- skipped for the very first instruction of the
       run, even if a breakpoint is set at the entry PC.
    4. Clear the interrupt shadow (it covers exactly one instruction),
       execute one instruction, then apply the cycle scale: in model 1
       with cycle_scale != 1.0 the clocks charged by that instruction are
       multiplied by cycle_scale, the fractional remainder carried forward.
    5. Bad opcode: restore CS:IP to the faulting instruction; with
       ud_trap off return ST_BADOP, with it on take INT 6 (the pushed IP
       is the faulting instruction's, manual 5.1) and continue -- the
       single-step and stop checks are skipped for that iteration.
    6. Single-step trap: if TF was set at the start of the instruction
       and is still set afterwards (and the CPU did not halt), take
       INT 1.  Vectoring clears TF, so the trap fires once.
    7. If i186_stop() was called, return ST_STOP.
*/
int i186_run(Cpu *cpu, uint64_t budget) {
    uint64_t cycle_limit = cpu->cycles + budget;
    int is_first_instruction = 1;

    cpu->run_end = cycle_limit;
    cpu->stop = 0;
    cpu->status = ST_OK;

    while (cpu->cycles < cycle_limit) {
        /* Pending interrupts. */
        if (cpu->nmi_pending) {
            cpu->halted = 0;
            cpu->nmi_pending = 0;
            cpu->irq_shadow = 0;
            do_interrupt(cpu, INT_NMI);
        } else if (cpu->irq_pending && cpu->flag_if && !cpu->irq_shadow) {
            cpu->halted = 0;
            cpu->irq_pending = 0;
            do_interrupt(cpu, cpu->irq_vec);
        }

        if (cpu->halted) {
            cpu->cycles = cycle_limit;
            return ST_HLT;
        }

        /* Breakpoints (not on the first instruction of the run). */
        uint32_t fetch_addr = linear_address(cpu->sreg[SEG_CS], cpu->ip);

        if (!is_first_instruction && cpu->breakpoints[fetch_addr]) {
            return ST_BP;
        }
        is_first_instruction = 0;

        /* Execute one instruction. */
        uint16_t start_ip = cpu->ip;
        uint16_t start_cs = cpu->sreg[SEG_CS];
        int trap_flag_at_start = cpu->flag_tf;

        /* The shadow covers exactly one instruction; STI / segment loads
           set it again. */
        cpu->irq_shadow = 0;

        uint64_t cycles_before = cpu->cycles;

        execute_one(cpu);

        if (cpu->cycle_scale != 1.0 && cpu->cycle_model) {
            double charged = (double)(cpu->cycles - cycles_before) * cpu->cycle_scale + cpu->cycle_frac;
            uint64_t whole = (uint64_t)charged;

            cpu->cycle_frac = charged - (double)whole;
            cpu->cycles = cycles_before + whole;
        }

        /* Bad opcode: back to the faulting instruction. */
        if (cpu->status == ST_BADOP) {
            cpu->ip = start_ip;
            cpu->sreg[SEG_CS] = start_cs;
            if (!cpu->ud_trap) {
                return ST_BADOP;
            }
            cpu->status = ST_OK;
            do_interrupt(cpu, INT_BADOP);
            continue;
        }

        /* Single-step trap, then an external stop request. */
        if (trap_flag_at_start && cpu->flag_tf && !cpu->halted) {
            do_interrupt(cpu, INT_SINGLE_STEP);
        }
        if (cpu->stop) {
            return ST_STOP;
        }
    }
    return ST_OK;
}
