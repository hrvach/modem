// i186_ref.h -- C reference-model wrapper for the 80C186EB co-sim harness.
// FPGA-only: Verilator co-sim harness, not synthesizable RTL.
//
// The reference is the C core in
//   research_notes/courier-firmware/c-port/c/src/cpu/i186.c
// (the spec for the RTL) plus a "machine-lite" glue layer that
// reproduces the glue semantics of
//   research_notes/courier-firmware/c-port/c/src/glue/machine.c
// for the subset the co-sim exercises: the 186 boots from the real
// SV25 flash image (fw/SV25.flash.bin, 512 KB, loaded at physical
// 0x80000, pages 0x80-0xFF read-only), MMIO pages 0xFF/0x0F, the IO
// port map (DSP mailbox 0x40-0x5E, flags 0x18/0x1A, evt 0x1C,
// ovl_status 0x1E, data 0x60/0x62, DTE 0x00/0x0A, DIP 0x10/0x12/0x14,
// PCB register file via IO 0xFF00+ or MMIO 0x0FF00+ once RELREG moves
// it), the PCB timers/UARTs/ICU, and the Microwire EEPROM (NVRAM
// image fw/nvram.bin). The DSP is ABSENT (no c5x core attached):
// mailbox reads return "no DSP" values, port 0x18 reads 0x03, and a
// write of 4 to port 0x18 (start DSP) is recorded and ignored. The
// DTE input is empty: no characters are ever fed to UART0.
//
// This wrapper does NOT modify the C tree: it links i186.c through
// the public ABI in i186.h only. Config matches the production
// driver defaults for the sv25 profile (config.c): cycle model 1
// (Table D-2), cycle scale 1.0, ud_trap on, diag ON (harness needs ring_idx), cpu_hz
// 25804800, hw_idx 7, DIP switches 3/5/8/9 ON, voice/data button
// released, line (DTE TXD) idle-high.
//
// Stepping: i186_run(c, 1) executes exactly one instruction in
// practice (every opcode charges >= 1 cycle in model 1; the only
// known 0-cycle form is LEA with mod==3, an invalid encoding the
// firmware never executes -- the harness checks the ring-index delta
// after every step and reports it). A REP string loop yields after
// one iteration per 1-cycle budget (rep_resume), so one step is one
// iteration. Interrupts are serviced by the harness calling
// iref_service() after each step (timer lazy-update + ICU eval),
// which mirrors the production driver's machine_run loop
// (service -> icu_eval -> run -> sync_ack) at instruction
// granularity instead of sample granularity; see KNOWN-DIFF in
// docs/i186_cosim.md.
#ifndef I186_COSIM_REF_H
#define I186_COSIM_REF_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct i186_cpu I186C;
typedef struct IRef IRef;

// Full architectural state after one instruction (C side).
typedef struct {
    uint16_t ax, cx, dx, bx, sp, bp, si, di;
    uint16_t es, cs, ss, ds, ip, flags;
    uint64_t cycles;
    int      halted;
    int      status;   // last i186_run() return value
    uint32_t ring_idx; // monotonic executed-instruction count
} IState;

// One bus/IO event, as logged by the machine-lite glue.
typedef struct {
    uint64_t cyc;
    uint32_t addr;   // IO port (16-bit) or physical address (20-bit)
    uint32_t val;
    int      w;      // 1 = word, 0 = byte
    int      is_io;  // 1 = IO port, 0 = MMIO
    int      is_wr;  // 1 = write, 0 = read
    uint32_t pc;     // physical PC of the accessing instruction
} ILogEv;

IRef *iref_new(void);
void iref_free(IRef *r);
I186C *iref_cpu(IRef *r);

// Load fw/SV25.flash.bin at physical 0x80000, fw/nvram.bin into the
// EEPROM, set RO pages 0x80-0xFF, MMIO pages 0xFF/0x0F, hooks, config
// (model 1, scale 1.0, ud_trap 1, diag 1), and reset (CS=0xFFFF,
// IP=0, FLAGS=0x0002). Returns 0 on success, -1 if an image cannot
// be read. `c_dir` is the c-port/c directory (for fw/... paths).
int iref_load_firmware(IRef *r, const char *c_dir);

// Step exactly one instruction: i186_run(cpu, 1). Returns the
// i186_run status (0 = ST_OK). The ring-index delta for this step
// (instructions executed) is returned through *delta_out when
// non-NULL (normally 1).
int iref_step(IRef *r, uint32_t *delta_out);

// Service step: advance timers/UARTs to the current CPU cycle
// count, evaluate the ICU (may raise i186_irq). Call after each
// iref_step(), mirroring the production driver's service order.
void iref_service(IRef *r);

// Snapshot the full architectural state (IState) after a step.
void iref_get_state(IRef *r, IState *s);

// Raw memory view (owned by the C core; do not free). 1 MB.
uint8_t *iref_mem(IRef *r);

// IO/MMIO event log: number of events, and event i (0 = oldest).
uint32_t iref_log_count(IRef *r);
int iref_log_entry(IRef *r, uint32_t i, ILogEv *ev);

// DTE output bytes captured from port 0x0A writes and UART0 TDR
// writes (the bytes the firmware "transmits" to the DTE).
uint32_t iref_dte_count(IRef *r);
uint8_t iref_dte_byte(IRef *r, uint32_t i);

// Distinct-port enumeration (for the port-map audit): bitmask over
// the 64K IO space is too big to return; instead the harness asks
// per port. Returns 1 if the port was ever read/written.
int iref_port_touched(IRef *r, uint16_t port, int wr);
// Distinct MMIO physical addresses touched (0x0F000-0x0FFFF,
// 0xFF000-0xFFFFF only). Returns 1 if touched.
int iref_mmio_touched(IRef *r, uint32_t addr);

uint64_t iref_total_cycles(IRef *r);
uint32_t iref_total_instrs(IRef *r);
// Number of port-0x18 writes with value 4 (DSP start requests).
uint32_t iref_dsp_starts(IRef *r);

#ifdef __cplusplus
}
#endif

#endif
