/* Telephone line signals (7200 Hz samples). Port of modem/sys/line.py. */
#include <math.h>

#include "line.h"

void tones_init(Tones *t, const double *freqs, int nfreqs, double amp)
{
    t->nfreqs = nfreqs > 2 ? 2 : nfreqs;
    for (int i = 0; i < t->nfreqs; i++)
        t->freqs[i] = freqs[i];
    t->amp = amp;
    t->n = 0;
}

int32_t tones_next(Tones *t)
{
    double v = 0.0;
    for (int i = 0; i < t->nfreqs; i++)
        v += sin(2 * M_PI * t->freqs[i] * t->n / LINE_FS);
    t->n++;
    return (int32_t)(v * t->amp); /* int() truncation, as in line.py */
}

void dial_tone_init(Tones *t, double amp)
{
    static const double f[2] = { 350.0, 440.0 };
    tones_init(t, f, 2, amp);
}

void ringback_init(Ringback *rb, int on, double amp)
{
    static const double f[2] = { 440.0, 480.0 };
    rb->on = on;
    tones_init(&rb->t, f, 2, amp);
}

int32_t ringback_next(Ringback *rb)
{
    /* line.py _RB calls the tone generator only when on, so the phase
     * freezes during the off part of the cadence. */
    return rb->on ? tones_next(&rb->t) : 0;
}
