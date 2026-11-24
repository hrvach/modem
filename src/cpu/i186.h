/*
   i186.h -- public interface of the 80C186EB CPU core (i186.c)

   The CPU state is opaque: callers hold a Cpu pointer and use the
   i186_* functions below.  Register indices, status codes and hook
   signatures are fixed; other code relies on the values.

   Older spellings (I186Cpu, i186_io_rd_fn, I186_AX, I186_ST_OK, ...) are
   kept below as aliases so existing glue code compiles unchanged.

   Cycle counts follow the 80C186EB User's Manual, Appendix D, Table D-2.
*/
#ifndef I186_H
#define I186_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Opaque CPU state.  All i186_* functions take a pointer to it. */
typedef struct i186_cpu Cpu;
/* Alias used by the provisional header / early glue code. */
typedef Cpu I186Cpu;

/* Hook signatures.  `w` is 1 for a word access, 0 for a
   byte access.  I/O hooks take a 16-bit port; MMIO hooks a 20-bit physical
   address.  A NULL hook means "no peripheral": I/O reads then fall back to
   the internal ioarr array, MMIO accesses fall through to RAM. */
typedef uint32_t (*io_rd_fn)(void *ctx, uint16_t port, int w);
typedef void (*io_wr_fn)(void *ctx, uint16_t port, int w, uint32_t v);
typedef uint32_t (*mm_rd_fn)(void *ctx, uint32_t addr, int w);
typedef void (*mm_wr_fn)(void *ctx, uint32_t addr, int w, uint32_t v);
/* Aliases used by the provisional header. */
typedef io_rd_fn i186_io_rd_fn;
typedef io_wr_fn i186_io_wr_fn;
typedef mm_rd_fn i186_mm_rd_fn;
typedef mm_wr_fn i186_mm_wr_fn;

/* Register indices for i186_get/i186_set.  Values are fixed:
   AX=0 .. DI=7, ES=8 .. DS=11, IP=12, FLAGS=13. */
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

/* Status codes returned by i186_run . */
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

/* Cycle-model selector for i186_set_cycle_model :
     0 = legacy flat 4 cycles per instruction,
     1 = approximate 80C186 clock counts (manual Table D-2). */
enum i186_cycle_model {
    I186_CYCLE_LEGACY = 0,
    I186_CYCLE_TABLE = 1
};

/* --- lifetime / raw access --- */
Cpu *i186_new(void);
void i186_free(Cpu *cpu);
uint8_t *i186_mem(Cpu *cpu);        /* 1 MB physical RAM image */
uint32_t *i186_hits(Cpu *cpu);      /* per-physical-address execution counts */
uint32_t *i186_ring(Cpu *cpu);      /* ring of the last 256 executed PCs */
uint32_t i186_ring_idx(Cpu *cpu);   /* monotonic count of executed instructions */
uint16_t *i186_ioarr(Cpu *cpu);     /* fallback I/O space, used when no io hook */

/* --- configuration --- */
void i186_set_hooks(Cpu *cpu, io_rd_fn ir, io_wr_fn iw, mm_rd_fn mr, mm_wr_fn mw,
                    void *ctx);
void i186_set_mmio_page(Cpu *cpu, uint32_t page, int on); /* 4 KB page -> MMIO hook */
void i186_set_ro_page(Cpu *cpu, uint32_t page, int on);   /* 4 KB page ignores writes */
void i186_set_bp(Cpu *cpu, uint32_t phys, int on);        /* breakpoint, 20-bit addr */
void i186_set_ud_trap(Cpu *cpu, int m);   /* 1 = bad opcode raises INT 6, not ST_BADOP */
void i186_set_cycle_model(Cpu *cpu, int m);
void i186_set_cycle_scale(Cpu *cpu, double f); /* >0, else 1.0; resets the fraction */

/* --- interrupts / control --- */
void i186_stop(Cpu *cpu);
void i186_irq(Cpu *cpu, int vec);   /* maskable interrupt request, vector 0-255 */
void i186_nmi(Cpu *cpu);            /* latched non-maskable interrupt (type 2) */
void i186_irq_clear(Cpu *cpu);
int i186_irq_pending(Cpu *cpu);

/* --- counters --- */
uint64_t i186_cycles(Cpu *cpu);
void i186_add_cycles(Cpu *cpu, uint64_t n);
/* Low 24 bits = physical PC of the last bad opcode, high byte = the opcode. */
uint32_t i186_get_badop(Cpu *cpu);

/* --- registers / reset / run --- */
uint32_t i186_get(Cpu *cpu, int id);
void i186_set(Cpu *cpu, int id, uint32_t v);
void i186_reset(Cpu *cpu);          /* CS=0xFFFF, IP=0, FLAGS=0x0002; see i186.c */
int i186_run(Cpu *cpu, uint64_t budget); /* returns enum i186_status */

#ifdef __cplusplus
}
#endif

#endif /* I186_H */
