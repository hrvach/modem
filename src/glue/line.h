/* Telephone line signals for the emulated modems (7200 Hz samples,
 * DXR/DRR units). Port of modem/sys/line.py.
 *
 * A Tones generator sums sine tones, one sample per call. dial_tone() is
 * the 350 + 440 Hz dial tone; ringback is the caller's 440 + 480 Hz tone,
 * gated by the callee's ring cadence (see link.c).
 */
#ifndef COURIER_LINE_H
#define COURIER_LINE_H

#include <stdint.h>

#define LINE_FS 7200

typedef struct {
    double freqs[2];
    int nfreqs;
    double amp;
    long n; /* sample counter */
} Tones;

void tones_init(Tones *t, const double *freqs, int nfreqs, double amp);
int32_t tones_next(Tones *t); /* one sample, rounded to int (as in line.py) */

/* Dial tone: 350 + 440 Hz. */
void dial_tone_init(Tones *t, double amp);

/* Ringback tone for the caller while the callee is in the 'on' part of
 * its ring cadence. The tone generator keeps running while gated off, so
 * the phase is continuous across cadence gaps (as in line.py _RB). */
typedef struct {
    int on;
    Tones t;
} Ringback;

void ringback_init(Ringback *rb, int on, double amp);
int32_t ringback_next(Ringback *rb);

#endif
