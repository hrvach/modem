/* i186.h -- public ABI for the 80C186EB CPU core (i186.c).
 *
 * This header is the contract the glue code links against.  It must stay
 * compatible with the ctypes wrapper in modem/sys/i186.py (register
 * indices, status codes, hook signatures).  The CPU state itself is opaque
 * here; its layout lives in i186.c and is not part of the ABI.
 *
 * This header replaces the provisional one that shipped with the verbatim
 * copy of the core; the old spelling (I186Cpu, i186_io_rd_fn, I186_AX,
 * I186_ST_OK) is kept below as aliases so existing glue code still
 * compiles unchanged.
 *
 * Behavioural reference: the 80C186EB User's Manual (in particular
 * Appendix D, Table D-2, for the cycle model) and the original compact
 * implementation this core was rewritten from,
 *   modem/sys/i186.c  (453 lines)
 * Line references of the form "orig. L<n>" in i186.c point at that file.
 */
#ifndef I186_H
#define I186_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Opaque CPU state.  All i186_* functions take a pointer to it. */
typedef struct i186_cpu C;
/* Alias used by the provisional header / early glue code. */
typedef C I186Cpu;

/* Hook signatures (orig. L14-L17).  `w` is 1 for a word access, 0 for a
 * byte access.  I/O hooks take a 16-bit port; MMIO hooks a 20-bit physical
 * address.  A NULL hook means "no peripheral": I/O reads then fall back to
 * the internal ioarr array, MMIO accesses fall through to RAM. */
typedef uint32_t (*io_rd_fn)(void *ctx, uint16_t port, int w);
typedef void (*io_wr_fn)(void *ctx, uint16_t port, int w, uint32_t v);
typedef uint32_t (*mm_rd_fn)(void *ctx, uint32_t addr, int w);
typedef void (*mm_wr_fn)(void *ctx, uint32_t addr, int w, uint32_t v);
/* Aliases used by the provisional header. */
typedef io_rd_fn i186_io_rd_fn;
typedef io_wr_fn i186_io_wr_fn;
typedef mm_rd_fn i186_mm_rd_fn;
typedef mm_wr_fn i186_mm_wr_fn;

/* Register indices for i186_get/i186_set.  Values must match the R dict
 * in modem/sys/i186.py: AX=0 .. DI=7, ES=8 .. DS=11, IP=12, FLAGS=13. */
enum i186_reg {
    R_AX = 0, R_CX = 1, R_DX = 2, R_BX = 3,
    R_SP = 4, R_BP = 5, R_SI = 6, R_DI = 7,
    R_ES = 8, R_CS = 9, R_SS = 10, R_DS = 11,
    R_IP = 12, R_FLAGS = 13
};
/* Aliases used by the provisional header. */
enum {
    I186_AX = R_AX, I186_CX = R_CX, I186_DX = R_DX, I186_BX = R_BX,
    I186_SP = R_SP, I186_BP = R_BP, I186_SI = R_SI, I186_DI = R_DI,
    I186_ES = R_ES, I186_CS = R_CS, I186_SS = R_SS, I186_DS = R_DS,
    I186_IP = R_IP, I186_FLAGS = R_FLAGS
};

/* Status codes returned by i186_run (orig. L22). */
enum i186_status {
    ST_OK = 0,     /* cycle budget exhausted, nothing pending */
    ST_BP = 1,     /* hit a breakpoint (not on the first instruction) */
    ST_BADOP = 2,  /* undefined opcode and ud_trap is off */
    ST_HLT = 3,    /* HLT with no pending interrupt to wake it */
    ST_STOP = 4    /* i186_stop() was called (e.g. from inside a hook) */
};
/* Aliases used by the provisional header. */
enum {
    I186_ST_OK = ST_OK, I186_ST_BP = ST_BP, I186_ST_BADOP = ST_BADOP,
    I186_ST_HLT = ST_HLT, I186_ST_STOP = ST_STOP
};

/* Cycle-model selector for i186_set_cycle_model (orig. L49-50):
 *   0 = legacy flat 4 cycles per instruction,
 *   1 = approximate 80C186 clock counts (manual Table D-2). */
enum i186_cycle_model {
    I186_CYCLE_LEGACY = 0,
    I186_CYCLE_TABLE = 1
};

/* --- lifetime / raw access --- */
C *i186_new(void);
void i186_free(C *c);
uint8_t *i186_mem(C *c);        /* 1 MB physical RAM image */
uint32_t *i186_hits(C *c);      /* per-physical-address execution counts */
uint32_t *i186_ring(C *c);      /* ring of the last 256 executed PCs */
uint32_t i186_ring_idx(C *c);   /* monotonic count of executed instructions */
uint16_t *i186_ioarr(C *c);     /* fallback I/O space, used when no io hook */

/* --- configuration --- */
void i186_set_hooks(C *c, io_rd_fn ir, io_wr_fn iw, mm_rd_fn mr, mm_wr_fn mw,
                    void *ctx);
void i186_set_mmio_page(C *c, uint32_t page, int on); /* 4 KB page -> MMIO hook */
void i186_set_ro_page(C *c, uint32_t page, int on);   /* 4 KB page ignores writes */
void i186_set_bp(C *c, uint32_t phys, int on);        /* breakpoint, 20-bit addr */
void i186_set_ud_trap(C *c, int m);   /* 1 = bad opcode raises INT 6, not ST_BADOP */
void i186_set_cycle_model(C *c, int m);
void i186_set_cycle_scale(C *c, double f); /* >0, else 1.0; resets the fraction */

/* --- interrupts / control --- */
void i186_stop(C *c);
void i186_irq(C *c, int vec);   /* maskable interrupt request, vector 0-255 */
void i186_nmi(C *c);            /* latched non-maskable interrupt (type 2) */
void i186_irq_clear(C *c);
int i186_irq_pending(C *c);

/* --- counters --- */
uint64_t i186_cycles(C *c);
void i186_add_cycles(C *c, uint64_t n);
/* Low 24 bits = physical PC of the last bad opcode, high byte = the opcode. */
uint32_t i186_get_badop(C *c);

/* --- registers / reset / run --- */
uint32_t i186_get(C *c, int id);
void i186_set(C *c, int id, uint32_t v);
void i186_reset(C *c);          /* CS=0xFFFF, IP=0, FLAGS=0x0002; see i186.c */
int i186_run(C *c, uint64_t budget); /* returns enum i186_status */

#ifdef __cplusplus
}
#endif

#endif /* I186_H */
