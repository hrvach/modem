/* c5x_core.h -- public ABI for the TMS320C5x (C51 flavour) emulator.
 *
 * This header declares the exact ABI the Python wrapper (modem/dsp/c5x.py,
 * ctypes) and any C glue link against.  The struct C5x itself is opaque:
 * callers only ever hold a C5x pointer, plus the flat memory / log / ring
 * views returned by the c5x_* accessors below.
 *
 * The diagnostic per-PC execution counters and recent-PC ring have been
 * removed; the remaining ABI is shared by the Python wrapper and C glue.
 *
 * ABI stability notes (do not change without updating c5x.py in lockstep):
 *  - IoEv / C5xIoEv field order and types are the ctypes layout:
 *    u64, u16, u16, u16, u8.
 *  - Register ids are the REG indices of c5x.py (PC=0 .. SETIDLE=41),
 *    including CYC_LO=27 and CYC_HI=28, which the provisional header
 *    omitted; they are added here.
 *  - Run statuses are RUN_OK=0, RUN_BP=1, RUN_BADOP=2, RUN_STOP=3.
 *  - Interrupt bit indices are INT1=0 .. INT4=8 (c5x.py INT1..INT4).
 *  - io_rd/io_wr callback signatures match IORD/IOWR in c5x.py.
 */
#ifndef COURIER_C5X_CORE_H
#define COURIER_C5X_CORE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct C5x C5x; /* opaque; defined in c5x_core.c */

/* One I/O-log event, as in c5x.py IoEv. */
typedef struct { uint64_t cyc; uint16_t pc, port, val; uint8_t wr; } C5xIoEv;
/* Alias used by the core implementation (same layout, same type). */
typedef C5xIoEv IoEv;

typedef uint16_t (*c5x_io_rd_fn)(void *ctx, uint16_t port);
typedef void (*c5x_io_wr_fn)(void *ctx, uint16_t port, uint16_t val);
/* Aliases used by the core implementation (same signatures). */
typedef c5x_io_rd_fn io_rd_fn;
typedef c5x_io_wr_fn io_wr_fn;

/* Register ids (c5x.py REG). */
enum {
    C5X_PC = 0, C5X_ACC = 1, C5X_ACCB = 2, C5X_PREG = 3,
    C5X_T0 = 4, C5X_T1 = 5, C5X_T2 = 6,
    C5X_AR0 = 7, C5X_AR1 = 8, C5X_AR2 = 9, C5X_AR3 = 10,
    C5X_AR4 = 11, C5X_AR5 = 12, C5X_AR6 = 13, C5X_AR7 = 14,
    C5X_ST0 = 20, C5X_ST1 = 21, C5X_PMST = 22, C5X_RPTC = 23,
    C5X_IFR = 24, C5X_IMR = 25, C5X_SP = 26,
    C5X_CYC_LO = 27, C5X_CYC_HI = 28,
    C5X_BMAR = 29, C5X_DBMR = 30, C5X_INDX = 31, C5X_ARCR = 32,
    C5X_DXR = 33, C5X_DRR = 34, C5X_TIM = 35, C5X_PRD = 36,
    C5X_IDLE = 37, C5X_PUSH = 40, C5X_SETIDLE = 41
};
/* C5X_REG_* aliases (same values); ARn = C5X_REG_AR0 + n, n = 0..7. */
enum {
    C5X_REG_PC = 0, C5X_REG_ACC = 1, C5X_REG_ACCB = 2, C5X_REG_PREG = 3,
    C5X_REG_T0 = 4, C5X_REG_T1 = 5, C5X_REG_T2 = 6,
    C5X_REG_AR0 = 7,
    C5X_REG_ST0 = 20, C5X_REG_ST1 = 21, C5X_REG_PMST = 22, C5X_REG_RPTC = 23,
    C5X_REG_IFR = 24, C5X_REG_IMR = 25, C5X_REG_SP = 26,
    C5X_REG_CYC_LO = 27, C5X_REG_CYC_HI = 28,
    C5X_REG_BMAR = 29, C5X_REG_DBMR = 30, C5X_REG_INDX = 31, C5X_REG_ARCR = 32,
    C5X_REG_DXR = 33, C5X_REG_DRR = 34, C5X_REG_TIM = 35, C5X_REG_PRD = 36,
    C5X_REG_IDLE = 37, C5X_REG_PUSH = 40, C5X_REG_SETIDLE = 41
};

/* Interrupt bits (c5x.py INT1..INT4): bit numbers into c5x_irq(). */
enum { C5X_INT1 = 0, C5X_INT2 = 1, C5X_INT3 = 2, C5X_TINT = 3,
       C5X_RINT = 4, C5X_XINT = 5, C5X_TRNT = 6, C5X_TXNT = 7, C5X_INT4 = 8 };

/* Run statuses (c5x.py RUN_OK..RUN_STOP). */
enum { C5X_RUN_OK = 0, C5X_RUN_BP = 1, C5X_RUN_BADOP = 2, C5X_RUN_STOP = 3 };
/* Unprefixed aliases used by the core implementation (same values). */
enum { RUN_OK = 0, RUN_BP = 1, RUN_BADOP = 2, RUN_STOP = 3 };

C5x *c5x_new(void);
uint16_t *c5x_pmem(C5x *c);
uint16_t *c5x_dmem(C5x *c);
uint16_t *c5x_iomem(C5x *c);
C5xIoEv *c5x_iolog(C5x *c);
uint32_t c5x_iolog_count(C5x *c);
int c5x_run(C5x *c, uint64_t cycles);
uint32_t c5x_get(C5x *c, int id);
void c5x_set(C5x *c, int id, uint32_t v);
void c5x_reset(C5x *c, uint16_t pc);
void c5x_irq(C5x *c, int bit);
void c5x_set_bp(C5x *c, uint16_t a, int on);
void c5x_iolog_enable(C5x *c, int on);
void c5x_iolog_clear(C5x *c);
void c5x_set_io(C5x *c, c5x_io_rd_fn rd, c5x_io_wr_fn wr, void *ctx);
void c5x_serial_tick(C5x *c, int16_t rx);
void c5x_set_ivec_ind(C5x *c, int bit, uint16_t daddr);
void c5x_set_cmpr_ar0(C5x *c, int v);
void c5x_set_xint_mode(C5x *c, int m);
void c5x_set_cycle_model(C5x *c, int m);
void c5x_set_legacy(C5x *c, int m);
uint64_t c5x_idle_cycles(C5x *c);
uint64_t c5x_timer_expiries(C5x *c);
uint64_t c5x_total_cycles(C5x *c);
uint32_t c5x_dxr_head(C5x *c);
uint16_t *c5x_dxr_ring(C5x *c);
void c5x_set_trace(C5x *c, int32_t pc);
void c5x_set_watch(C5x *c, int32_t a);
uint32_t c5x_watch_hits(C5x *c, uint32_t pc);
uint32_t c5x_trace_n(C5x *c);
void c5x_trace_get(C5x *c, uint32_t i, uint32_t *acc, uint16_t *ret, uint16_t *ret2);
uint32_t c5x_mmr_count(C5x *c, int wr, int a);
uint16_t c5x_mmr_pc(C5x *c, int wr, int a);
uint16_t c5x_mmr_val(C5x *c, int a);
uint32_t c5x_ff_count(C5x *c, int wr, int i);
uint32_t c5x_ext_count(C5x *c, int wr, int blk);
uint16_t c5x_rsv(C5x *c, int w);
void c5x_mmr_clear(C5x *c);
void c5x_stop(C5x *c);
void c5x_set_bio(C5x *c, int v);

#ifdef __cplusplus
}
#endif
#endif
