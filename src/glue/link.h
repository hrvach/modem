/* Two emulated modems on one simulated phone line. Port of
 * modem/sys/link.py.
 *
 * Central-office state machine: dial tone -> (caller dials, DTMF
 * detected) -> ring -> callee answers -> audio connected both ways.
 *
 * TIME POLICY (link.py): both machines are advanced against ONE shared
 * absolute clock (gt, in CPU cycles). Every slice the clock moves by
 * slice; each machine is then run for (clock - its own elapsed cycles),
 * so a machine whose last instruction/event ran past the slice gets a
 * shorter budget next time and the overshoot is repaid. Samples are
 * handed over once per slice (latency <= one slice); the call state
 * machine (co_step) is fed 100k-cycle windows whatever the slice is.
 *
 * a = callee (answers), b = caller. Stereo WAV: left = caller B,
 * right = answerer A (link.py write_wav).
 *
 * FRAME MODE (link_mode = frame; opt-in, Hrvoje's design; default is
 * slice, the verified baseline):
 * A slice boundary is after one frame is processed — one codec sample
 * frame per modem (one machine_sample() period: sample_cyc CPU cycles,
 * dsp_cps DSP cycles), not a fixed 1000-cycle chunk. Each pass runs
 * each machine until it has completed one frame, exchanges samples,
 * then the next frame.
 * Clocks are tallied per side and per device (f_cpu[] / f_dsp[] are
 * cumulative CPU / DSP cycles consumed; f_frames[] counts completed
 * frames). If a side uses more clocks in one go it gets proportionally
 * less budget in the following passes — a debt/credit tally, not a
 * fixed budget per pass. Concretely, f_debt[side] is the overshoot
 * past the frame boundary just completed (the +1 cycle that forces
 * machine_run to service the due sample inside the call, plus the
 * whole-instruction overshoot of i186_run past the run budget).
 * Repayment is automatic via the machine's own next_samp grid: the
 * next pass's budget is the distance to the next grid boundary, which
 * is shorter by exactly the debt, so the debt is re-measured (not
 * accumulated) each pass. Before the DSP starts (next_samp == INF)
 * there is no grid, so the nominal frame is sample_cyc and the debt
 * is repaid explicitly by subtracting it from the nominal budget.
 * DSP cycles are slaved to CPU frames (machine_sample runs exactly
 * dsp_cps DSP cycles per frame), so the DSP tally has no independent
 * lever: it is measured per side and reported, and the corrective
 * lever is the CPU frame budget. The two tallies stay proportional
 * by construction (dsp_hz / cpu_hz per frame).
 * Drift stats (f_*_drift) are the per-pass cumulative |A - B|
 * imbalance, CPU and DSP separately; the run prints max / mean /
 * final values. The co_step 100k-cycle windows are advanced by the
 * B-side CPU cycles consumed per pass (B is the call-time reference,
 * as in link_samples).
 */
#ifndef COURIER_LINK_H
#define COURIER_LINK_H

#include <stdint.h>

#include "config.h"
#include "line.h"
#include "machine.h"
#include "resamp.h"

#define LINK_FS 7200

typedef struct {
    Machine *a, *b;
    long slice; /* CPU cycles per lockstep slice (default 1000) */
    double gain, echo;
    int gate;
    int delay_samples;
    int line8k;
    double dial_dwell, ring_on, ring_period;

    /* Recorded audio (signed samples, as in link.py audio['a'/'b']). */
    int32_t *audio_a, *audio_b;
    size_t audio_a_n, audio_a_cap, audio_b_n, audio_b_cap;

    /* Call state machine. */
    char state[16]; /* idle | dialtone | digit | dialing | ringing | answering | connected */
    int64_t t_state; /* samples() at the last set_state */
    struct { double t; char st[16]; } *events;
    size_t events_n, events_cap;
    uint8_t *txt_a, *txt_b; size_t txt_a_n, txt_a_cap, txt_b_n, txt_b_cap;
    /* Live trace line buffers per side (0 = A, 1 = B): text is printed
     * when a line ends, not per character. */
    char tr_buf[2][256]; size_t tr_n[2]; double tr_t[2];
    const char *tr_dir[2]; int64_t tr_last[2]; /* direction label, last char time */
    int answer_on_ring;
    int64_t ring_seen_at; /* samples() when 'RING' was last seen in A text */
    int64_t ring_t0;
    Tones dial_tone_gen;
    Ringback ringback;
    int rb_on;

    /* Shared absolute clock (slice mode). */
    int64_t gt;
    uint64_t off_a, off_b;
    int clock_started;

    /* Frame mode (link_mode = frame). Index 0 = A (callee), 1 = B (caller). */
    int mode_frame;
    int64_t f_debt[2];     /* CPU cycles past the last completed frame boundary */
    uint64_t f_frames[2];  /* codec frames completed */
    int64_t f_cpu[2], f_dsp[2]; /* cumulative CPU / DSP cycles consumed */
    /* Per-pass cumulative |A - B| drift, CPU and DSP separately. */
    int64_t f_max_abs_cpu_drift, f_max_abs_dsp_drift;
    int64_t f_sum_abs_cpu_drift, f_sum_abs_dsp_drift;
    uint64_t f_passes;

    /* 100k-cycle co_step accumulation windows. */
    int32_t *acc_a, *acc_b; size_t acc_a_n, acc_a_cap, acc_b_n, acc_b_cap;
    int64_t acc_cyc;
    /* Per-direction resamplers for the LINE8K path (persistent). */
    Resampler *line_ab[2], *line_ba[2];
    double rs_ab_phase, rs_ab_last; /* linear-interp state, A->B */
    double rs_ba_phase, rs_ba_last; /* linear-interp state, B->A */
    int32_t *delay_q_a, *delay_q_b; size_t delay_q_a_n, delay_q_b_n;
    int64_t base_samples; /* _base for samples() */
    int base_set;
} Link;

Link *link_new(const Config *cfg);
void link_free(Link *l);
/* Call time in 7200 Hz units, counted from the last reset of audio. */
int64_t link_samples(Link *l);
void link_set_state(Link *l, const char *st);
void link_start_call(Link *l, const char *number);
/* Host -> modem bytes (side 0 = A, 1 = B), traced on stdout, then queued. */
void link_send(Link *l, int side, const uint8_t *s, size_t n);
/* Live serial trace: text is collected per side and printed one line at a
 * time (on CR or LF), with the time of the line's first character. */
void link_trace(Link *l, int side, const char *dir, const uint8_t *s, size_t n);
void link_co_step(Link *l, const int32_t *ta, size_t ta_n,
                  const int32_t *tb, size_t tb_n);
void link_run(Link *l, uint64_t cycles);
/* Stereo WAV (left = caller B, right = answerer A) at `rate` Hz, using
 * link.py write_wav semantics: cut at codec-rate changes, resample
 * each constant-rate segment to `rate`. Returns 0 on success. */
int link_write_wav(Link *l, const char *path, int rate);
/* Drain both machines' DTE output (as link.py text()). */
void link_text(Link *l, uint8_t *a_out, size_t *a_len, uint8_t *b_out, size_t *b_len);

#endif
