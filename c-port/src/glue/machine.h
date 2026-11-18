/* Full-system SV25 machine: 80C186EB + DSP + peripherals.
 * Port of modem/sys/machine.py (661 lines). Time base: cpu.cycles are CPU
 * clocks; one codec sample (7200 Hz) = CPU_HZ/7200 CPU clocks. Timers
 * count at CPU/4. See modem/sys/FULL_SYSTEM.md sections 5-8 for where
 * each hardware fact comes from.
 *
 * The struct is public so link.c / main.c can read the diagnostics the
 * Python code exposed as attributes (cmd_log16, rate_idx, tx_all, ...).
 * The cores are called only through the c5x_core.h / i186.h ABIs.
 *
 * Memory note: several Python lists were unbounded (log, dsp_log, rx_log).
 * The C port caps them (see MACHINE_LOG_CAP etc. in machine.c) and stops
 * appending past the cap, so a long call cannot grow memory without
 * bound; the cap is documented in README.md. tx_all / audio stay exact.
 */
#ifndef COURIER_MACHINE_H
#define COURIER_MACHINE_H

#include <stddef.h>
#include <stdint.h>

#include "config.h"
#include "line.h"

/* Core ABIs — forward declarations, NOT the core headers.
 *
 * src/cpu/i186.h and src/dsp/c5x_core.h are owned by the core agents
 * and are used as-is to build the cores, but they cannot both be
 * included in one translation unit: each defines plain `io_rd_fn` /
 * `io_wr_fn` typedefs with different signatures. The glue therefore
 * repeats the exact prototypes it uses here (opaque handles, prefixed
 * callback typedefs, register ids and status codes copied verbatim
 * from those headers and from modem/sys/i186.py / modem/dsp/c5x.py).
 * If a core header changes a signature, this block must change with
 * it; the linker will catch a renamed symbol, and the values below
 * are checked against the headers in README.md.
 */
typedef struct I186Cpu I186Cpu; /* opaque; defined in i186.c as `C` */
typedef struct C5x C5x;         /* opaque; defined in c5x_core.c */
typedef uint32_t (*glue_i186_io_rd_fn)(void *ctx, uint16_t port, int w);
typedef void (*glue_i186_io_wr_fn)(void *ctx, uint16_t port, int w, uint32_t v);
typedef uint32_t (*glue_i186_mm_rd_fn)(void *ctx, uint32_t addr, int w);
typedef void (*glue_i186_mm_wr_fn)(void *ctx, uint32_t addr, int w, uint32_t v);
typedef uint16_t (*glue_c5x_io_rd_fn)(void *ctx, uint16_t port);
typedef void (*glue_c5x_io_wr_fn)(void *ctx, uint16_t port, uint16_t val);
enum { GLUE_I186_AX = 0, GLUE_I186_CX = 1, GLUE_I186_DX = 2, GLUE_I186_BX = 3,
       GLUE_I186_SP = 4, GLUE_I186_BP = 5, GLUE_I186_SI = 6, GLUE_I186_DI = 7,
       GLUE_I186_ES = 8, GLUE_I186_CS = 9, GLUE_I186_SS = 10, GLUE_I186_DS = 11,
       GLUE_I186_IP = 12, GLUE_I186_FLAGS = 13 };
enum { GLUE_I186_ST_OK = 0, GLUE_I186_ST_BP = 1, GLUE_I186_ST_BADOP = 2,
       GLUE_I186_ST_HLT = 3, GLUE_I186_ST_STOP = 4 };
enum { GLUE_C5X_PC = 0, GLUE_C5X_INT2 = 1, GLUE_C5X_INT3 = 2,
       GLUE_C5X_TRNT = 6, GLUE_C5X_TXNT = 7 };
I186Cpu *i186_new(void);
uint8_t *i186_mem(I186Cpu *c);
int i186_run(I186Cpu *c, uint64_t budget);
uint32_t i186_get(I186Cpu *c, int id);
void i186_reset(I186Cpu *c);
void i186_set_hooks(I186Cpu *c, glue_i186_io_rd_fn ir, glue_i186_io_wr_fn iw,
                    glue_i186_mm_rd_fn mr, glue_i186_mm_wr_fn mw, void *ctx);
void i186_set_mmio_page(I186Cpu *c, uint32_t page, int on);
void i186_set_ro_page(I186Cpu *c, uint32_t page, int on);
void i186_set_bp(I186Cpu *c, uint32_t phys, int on);
void i186_irq(I186Cpu *c, int vec);
void i186_stop(I186Cpu *c);
void i186_irq_clear(I186Cpu *c);
int i186_irq_pending(I186Cpu *c);
void i186_set_cycle_model(I186Cpu *c, int m);
void i186_set_cycle_scale(I186Cpu *c, double f);
void i186_set_ud_trap(I186Cpu *c, int m);
uint64_t i186_cycles(I186Cpu *c);
C5x *c5x_new(void);
uint16_t *c5x_pmem(C5x *c);
uint16_t *c5x_dmem(C5x *c);
int c5x_run(C5x *c, uint64_t cycles);
void c5x_pm_invalidate(C5x *c);
void c5x_set_diag(C5x *c, int on);
uint32_t c5x_get(C5x *c, int id);
void c5x_reset(C5x *c, uint16_t pc);
void c5x_irq(C5x *c, int bit);
void c5x_set_io(C5x *c, glue_c5x_io_rd_fn rd, glue_c5x_io_wr_fn wr, void *ctx);
void c5x_serial_tick(C5x *c, int16_t rx);
void c5x_set_ivec_ind(C5x *c, int bit, uint16_t daddr);
void c5x_set_cmpr_ar0(C5x *c, int v);
void c5x_set_xint_mode(C5x *c, int m);
void c5x_set_cycle_model(C5x *c, int m);
void c5x_set_legacy(C5x *c, int m);
uint64_t c5x_timer_expiries(C5x *c);
uint64_t c5x_total_cycles(C5x *c);
uint32_t c5x_pc_hits(C5x *c, uint32_t pc);
void c5x_pc_hits_clear(C5x *c);
uint32_t c5x_dm_writes(C5x *c, uint32_t a);
uint32_t c5x_dxr_head(C5x *c);
uint16_t *c5x_dxr_ring(C5x *c);

#define MACHINE_INF ((int64_t)1 << 62)

/* Interrupt sources in default priority order (machine.py SRC):
 * (name, vector type, IMASK bit, control register). */
enum {
    S_T0 = 0, S_T1, S_T2, S_S0RX, S_S0TX, S_INT4, S_INT0, S_INT1, S_INT2, S_INT3,
    SRC_N = 10
};

typedef struct {
    uint32_t cnt, cmpa, cmpb, con;
    int64_t last;
    int run;
    int64_t nxt;
} MachineTimer;

typedef struct {
    uint32_t cmp, con, sts, rbuf;
    int64_t rx_t, tx_t;
    int bit, sh, pu;
} MachineUart;

/* 3-wire Microwire EEPROM (93C66-like, 256 x 16 bit), as driven by the
 * firmware's bit-bang routines. See machine.py Eeprom. */
enum { EE_IDLE = 0, EE_CMD, EE_READ, EE_WDATA };
typedef struct {
    int n;
    uint16_t w[256];
    int ewen, dirty;
    int state;
    int bits[16], nbits;
    int do_bit, addr, rdn;
} Eeprom;

/* 6th-order low-pass (Chebyshev I, 0.15 dB ripple) as 3 biquads, bilinear
 * transform, unity DC gain. Port of machine.py _Lp6. */
typedef struct {
    double sec[3][5]; /* b0, b1, b2, a1, a2 per section */
    double st[3][2];
    int nsec; /* 0 = transparent (corner at/above Nyquist) */
    long key_fc, key_fs; /* rounded (fc, fs) the sections were designed for */
    int designed;
} Lp6;

void lp6_set(Lp6 *f, double fc, double fs);
double lp6_call(Lp6 *f, double x);

/* --- diagnostic log entries (capped dynamic arrays in machine.c) --- */
typedef struct { char kind; uint16_t port; int w; uint32_t val, pc; } IoLogEnt;
typedef struct { uint64_t cyc; uint16_t q, v; } DspLogEnt;
typedef struct { int64_t t; uint16_t c, x; } Cmd16Ent; /* t = sample count */
typedef struct { uint64_t cyc; int cmd, arg; } CmdEnt;
typedef struct { int64_t t; uint16_t w0, w1, w2, w3; uint64_t cyc; } MsgEnt;
typedef struct { int64_t idx; int rate; } RateIdxEnt;
typedef struct { double t; int rate; } RateLogEnt;
typedef struct { double t; int reg, val; } AicLogEnt;
typedef struct { double t; int port, val; uint16_t flags56; } FlagLogEnt;
typedef struct { uint64_t cyc; uint32_t addr; int len; } OvlLoadEnt;

/* Small hash set of uint32 (sec_abs) and hash counter (wr/rd/port5 pcs).
 * Defined here so they can live in the Machine; implemented in machine.c. */
typedef struct { uint32_t *keys; uint8_t *st; size_t cap, n; } U32Set;
typedef struct { uint64_t *keys; uint32_t *vals; uint8_t *st; size_t cap; } Counter;
void u32set_init(U32Set *s);
int u32set_has(U32Set *s, uint32_t x);
void u32set_add(U32Set *s, uint32_t x);
void u32set_del(U32Set *s, uint32_t x);
void counter_init(Counter *c);
void counter_inc(Counter *c, uint64_t key);

typedef struct Machine Machine;
struct Machine {
    I186Cpu *cpu;
    C5x *dsp; /* NULL until the supervisor starts it (port 0x18 <- 4) */

    const Config *cfg;
    const Profile *prof;
    long cpu_hz, dsp_hz;
    long dsp_cps_7200; /* DSP_HZ // 7200 (5600 at 40.32 MHz) */
    int sample_cyc;    /* CPU_HZ // 7200, floor division as in machine.py */
    int dsp_cps;       /* DSP cycles per codec sample at the current rate */
    int rate;          /* current codec rate, Hz (7200 or 9600 ...) */

    /* Experiment toggles (config keys; see call.conf). */
    int p51div, hb_timer, dsp_clk_fixed, port_rb, sec_frame, int23;
    int ac01_model, ac01_filt, ac01_lat;
    int xint_mode, cycle_model, legacy, tdm_irqs, bankwr, cmpr, tintslot;
    char cmd_ovr[CFG_MAX_STR];
    int ac01_clamp_keys[16], ac01_clamp_vals[16], ac01_clamp_n;
    double cpu_scale;
    int ud_trap, cpu_model;
    int patch_crc; /* -1 = do not patch */
    int nvram_mode; /* -1 = none */
    int fax_patch;
    int dte_speed_code; /* 0x02 */

    /* I/O ports and PCB. ports[] holds full values; ports_set[] marks
     * keys ever written (machine.py dict .get(p, 0) vs .get(p, 0xFF)
     * differ by call site, see _hw_id_bit). */
    uint32_t ports[65536];
    uint8_t ports_set[65536];
    uint8_t pcb[65536]; /* PCB register bytes, r and r+1 */
    int pcb_mem;        /* RELREG bit12 moved the PCB to memory space */
    uint8_t port_in[256];
    int logging;
    char tag;           /* 'A' or 'B' (live trace prefix, set by link_new) */
    IoLogEnt *log; size_t log_n, log_cap;
    IoLogEnt *pcblog; size_t pcblog_n, pcblog_cap;

    uint8_t *dte_out; size_t dte_out_n, dte_out_cap;
    uint8_t *txq; size_t txq_head, txq_n, txq_cap; /* bytes to type */
    int64_t line_free;
    int line; /* DTE TXD as the modem sees it: 1 = mark/idle */
    struct { int64_t t; int lv; } *edges; size_t edges_head, edges_n, edges_cap;
    int dte_baud, dte_gap;

    uint16_t *rxbuf; size_t rxbuf_head, rxbuf_n, rxbuf_cap;
    long rx_under;
    int32_t *rx_log; size_t rx_log_n, rx_log_cap;
    uint16_t cur_rx;
    uint32_t tx_seen; /* dxr_head at the last take_tx */
    int32_t *tx_all; size_t tx_all_n, tx_all_cap;
    uint64_t lk_seen; /* link.c: tx_all index already handed to the line */

    /* DSP mailbox / overlay / AC01 state. */
    uint16_t h2d[8], d2h[8]; /* words 0x58..0x5F */
    /* Instrumentation only: a DSP word overwritten before the 186 read it. */
    uint8_t d2h_unread[8];
    uint64_t d2h_overwrites;
    uint8_t ovl_bytes[256];
    uint8_t *ovl_data; size_t ovl_data_n, ovl_data_cap;
    uint32_t ovl_addr;
    int ovl_status;
    OvlLoadEnt *ovl_loads; size_t ovl_loads_n, ovl_loads_cap;
    uint16_t flags56, flagsD;
    FlagLogEnt flag_log[400]; size_t flag_log_n;
    int h2d_pending, d2h_valid, evt, int0_req, evt_seen, evt4_n;
    uint16_t data_word; int data_full;
    long data_words_sent, data_words_read;
    uint16_t port_store[256];
    int aic[7]; /* AC01 registers 1..6; aic[1]=A, aic[2]=B, aic[4]=gains */
    int aic_req, mclk_n;
    uint32_t aic_h; /* dxr_head at the last _aic_feed */
    U32Set sec_abs; /* absolute dxr indices holding secondary words */
    Counter wr_pcs, rd_pcs, port5_pcs; /* diagnostic (port, PC) counters */
    int sec_n;
    long hb_ticks, hb_count;
    uint64_t hb_e; /* dsp timer_expiries() at the last sample */
    int hb_pending, heartbeat;
    int32_t noise_amp;
    uint32_t seed; /* line-noise LCG state, seed 12345 */
    int ring_on;
    int (*rx_gen)(void *ctx); /* optional line-sample generator */
    void *rx_gen_ctx;
    Tones *rx_gen_tones; /* owned by the caller (link.c dial tone) */
    int rom_replies;
    uint64_t dsp_started_at, tick_dc;
    int tx_req; int32_t tx_hold; /* signed, as in Python: v & ~3 keeps sign */
    uint8_t *dsp_bursts; /* flat, 8 bytes per burst */
    size_t dsp_bursts_n, dsp_bursts_cap;
    uint8_t burst_tmp[256];

    CmdEnt *cmd_log; size_t cmd_log_n, cmd_log_cap;
    Cmd16Ent *cmd_log16; size_t cmd_log16_n, cmd_log16_cap;
    MsgEnt *msg_log; size_t msg_log_n, msg_log_cap;
    DspLogEnt *dsp_log; size_t dsp_log_n, dsp_log_cap;
    RateIdxEnt *rate_idx; size_t rate_idx_n, rate_idx_cap;
    RateLogEnt *rate_log; size_t rate_log_n, rate_log_cap;
    AicLogEnt *aic_log; size_t aic_log_n, aic_log_cap;
    int32_t *rx_trace; size_t rx_trace_n, rx_trace_cap; /* RX_TRACE only */

    /* Interrupt controller. */
    uint16_t req; /* latched requests, bit = SRC index */
    uint32_t msk; /* IMASK */
    int primsk;
    int icon[256]; /* xCON without the mask bit, by control register */
    int isv_present[256], isv_val[256]; /* in service: IMASK bit -> level */
    int offered; /* SRC index offered to the CPU, or -1 */
    long irq_count[256]; /* by vector type */

    MachineTimer tm[3];
    MachineUart uart[2];

    Eeprom eeprom;
    int p2pin;
    int hw_idx, voice_data_button;
    int flash_id;
    int nvram_done;
    uint32_t dxr_h; /* dxr_head at the last _sample */
    int64_t next_samp;
    Lp6 adc_lp, dac_lp;
    int adc_lp_set, dac_lp_set;
    double adc_hp[2]; int adc_hp_set;
    int32_t *lat_q; size_t lat_q_head, lat_q_n, lat_q_cap;

    /* _cmd_override parser state (built lazily from cmd_ovr). */
    int ovr_built;
    int ovr_arg[256], ovr_arg_set[256];
    int ovr_pos[256][7], ovr_pos_set[256][7]; /* (cmd, 1..6) */
    int ovr_ren[256], ovr_ren_set[256];
    int ovr_cnt[256];

    char dsp_rom[CFG_MAX_PATH];
};

Machine *machine_new(const Config *cfg);
void machine_free(Machine *m);
int machine_run(Machine *m, uint64_t cycles); /* i186 status code */
void machine_host_cmd(Machine *m, int cmd, int arg); /* test hook: see config inject_cmd */
void machine_send(Machine *m, const uint8_t *text, size_t len);
void machine_send_str(Machine *m, const char *text);
/* Drain dte_out into out (dropping 0xFF bytes, as in machine.py
 * dte_text); returns the byte count. */
size_t machine_dte_text(Machine *m, uint8_t *out, size_t maxout);
uint32_t machine_phys_pc(Machine *m);
uint8_t machine_rd8(Machine *m, uint32_t a);
uint16_t machine_rd16(Machine *m, uint32_t a);
void machine_wr8(Machine *m, uint32_t a, uint8_t v);
void machine_set_rate(Machine *m, int rate);
void machine_start_dsp(Machine *m);
/* DSP output samples produced since the last call (also appended to
 * tx_all). Returns the count written to out. */
size_t machine_take_tx(Machine *m, int32_t *out, size_t maxout);
const char *machine_icu_state(Machine *m, char *buf, size_t len);

#endif
