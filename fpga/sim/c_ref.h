// c_ref.h -- C reference-model wrapper for the co-sim harness.
//
// The reference is the C core in
//   research_notes/courier-firmware/c-port/c/src/dsp/c5x_core.c
// (the spec for the RTL). This wrapper does NOT modify the C tree:
// c_ref.cpp #includes the C translation unit once, which gives the
// harness white-box read access to the full architectural state
// (including the hardware stack, which the public ABI in c5x_core.h
// does not expose). If the C core is refactored, this wrapper is the
// one place that adapts.
#ifndef C5X_COSIM_C_REF_H
#define C5X_COSIM_C_REF_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct C5x C5x;

// Full architectural state after one instruction (C side).
//
// RTL observation (see docs/cosim.md): the full AR file and stack
// are observable from the top level (ar_all_o / stack_all_o) and
// are compared per instruction, as are the mem-owned registers
// (obs_*_o). ar_cur / stack_top are the AR[ARP] / stack[sp]
// shortcuts, kept for the smoke-gate checkpoint prints.
typedef struct {
    uint16_t pc, op;             // next PC, opcode just executed
    uint32_t acc, accb, preg;
    uint16_t treg0, treg1, treg2;
    uint16_t ar[8];
    uint16_t ar_cur;             // ar[arp]
    uint16_t arp;
    uint16_t st0, st1, pmst;     // computed status registers
    int32_t  rptc, brcr;
    uint16_t sp;
    uint16_t stack[8];
    uint16_t stack_top;          // stack[sp]
    uint16_t ifr, imr;
    uint16_t tim, prd, dxr, drr;
    uint16_t bmar, dbmr, indx, arcr;
    uint16_t pasr, paer;
    uint16_t greg, spc, tcr, pdwsr, iowsr, cwsr;
    uint16_t spc_rd; // SPC as an MMR read returns it: (spc & 0xC0FE)
                     // | rsrfull<<13 | xsrempty<<12 | xrdy<<11 |
                     // rrdy<<10 (C mmr_rd 0x22). The RTL's spc_o is
                     // the same composed read value, so spc_rd is
                     // what the harness compares; spc is the raw
                     // stored field, kept for reference.
    uint64_t cycles;
    int      idle;
    int      status;             // last c5x_run() return value
} CState;

// One host-IO event, as logged by the C core (c5x_iolog).
typedef struct {
    uint64_t cyc;
    uint16_t pc, port, val;
    int      wr;                 // 1 = write, 0 = read
} CIoEv;

C5x *cref_new(void);
void cref_free(C5x *c);

// Load the SV25 base image (dsp_base.bin, little-endian words) at PM
// 0x8000, apply the sv25-profile DMEM presets (ivec 0x60+i = 0x81AE,
// dm[0x65]=0x8189, dm[0x68]=0x820C, dm[0x69]=0x81B7), set cycle model
// on and diagnostics off (as the C driver does), and reset to 0x8000.
// Returns 0 on success, -1 if the image cannot be read.
int cref_load_firmware(C5x *c, const char *image_path);

// Load a small program image (words, little-endian host order) at PM
// `base`, no DMEM presets, cycle model on, diagnostics off, reset to
// `base`. Used by the smoke test.
void cref_load_program(C5x *c, const uint16_t *words, int nwords,
                       uint16_t base);

// Load dsp_base.bin into PMEM ONLY (no overlays, no DMEM presets,
// no ivec_ind setup), cycle model on, diagnostics ON (the smoke
// vector's recent_pcs come from the pcring, which is gated by
// diag), IO logging on, reset to 0x8000. Returns 0 on success, -1
// if the image cannot be read. Used by the DSP smoke gate.
int cref_load_smoke(C5x *c, const char *image_path);

// Diagnostics toggle (the pcring is gated by diag; the C driver
// runs with diag off).
void cref_set_diag(C5x *c, int on);

// Smoke-gate counters and rings (public C accessors, see
// c5x_core.h). dxr_ring is the 65536-entry DXR write ring;
// pcring is the 256-entry recent-PC ring, pcring_idx its head.
uint64_t cref_idle_cycles(C5x *c);
uint64_t cref_timer_expiries(C5x *c);
uint32_t cref_dxr_head(C5x *c);
uint16_t *cref_dxr_ring(C5x *c);
uint16_t *cref_pcring(C5x *c);
uint32_t cref_pcring_idx(C5x *c);

// Interrupt-vector indirection entry i (0..15), as set by
// c5x_set_ivec_ind. The harness drives the RTL's ivec_ind_i from
// these so the two models agree on the vector indirection.
uint16_t cref_ivec_ind(C5x *c, int i);

// Step exactly one instruction: c5x_run(c, 1). With a 1-cycle budget
// the main loop executes exactly one instruction (each instruction
// charges >= 1 cycle), including its post-instruction tail (RPT/RPTB,
// timer advance, XC hold, interrupt entry). An idle core consumes
// exactly 1 cycle and executes nothing. Returns the c5x_run status
// (0 = RUN_OK). The RPTB block-replay fast path never fires on a
// 1-cycle budget, so single-stepping always takes the slow path.
int cref_step(C5x *c);

// Run for a cycle budget: c5x_run(c, cycles). Returns the c5x_run
// status (0 = RUN_OK). Used by the DSP smoke gate (1M-cycle
// segments).
int cref_run(C5x *c, uint64_t cycles);

// Snapshot the full architectural state (CState) after a step.
void cref_get_state(C5x *c, CState *s);

// Raw memory views (owned by the C core; do not free).
uint16_t *cref_pmem(C5x *c);
uint16_t *cref_dmem(C5x *c);
uint16_t *cref_iomem(C5x *c);

// IO event log: number of events, and event i (0 = oldest).
uint32_t cref_iolog_count(C5x *c);
void cref_iolog_enable(C5x *c, int on);
int cref_iolog_entry(C5x *c, uint32_t i, CIoEv *ev);

uint64_t cref_total_cycles(C5x *c);

#ifdef __cplusplus
}
#endif

#endif
