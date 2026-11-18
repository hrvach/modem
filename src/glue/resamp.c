/* Streaming band-limited resampler (Kaiser-windowed sinc, 128 taps,
 * 1024 phases), after courier-emu's codec_line_sample.
 * Used by link.c for the 8 kHz PCM telephone line between two modems whose
 * codecs run at 7200..10267 Hz, and by wav.c for the WAV export.
 * Group delay is 63.5 input samples.
 *
 * Faithful to modem/sys/resamp.c: same tap/phase counts, same Kaiser beta
 * (8), same kernel normalisation (each phase sums to 1), same rounding and
 * clamping of outputs. Only the layout is cleaned up for readability.
 */
#include <math.h>
#include <stdint.h>
#include <stdlib.h>

#include "resamp.h"

#define RS_TAPS 128
#define RS_PHASES 1024
#define RS_KAISER_BETA 8.0
/* Centre tap index: taps are k - 63 - phase/1024, so the filter is
 * centred between taps 63 and 64 (63.5-sample group delay). */
#define RS_CENTRE 63.0
#define RS_HALF_SPAN 64.0

struct Resampler {
    double hist[RS_TAPS];
    double pos;      /* fractional input-sample position, in [0, 1) */
    double cutoff;   /* cutoff the kernel table was built for (0 = none) */
    double (*kernel)[RS_TAPS]; /* [phase][tap], phases 0..RS_PHASES */
};

/* Modified Bessel function I0, by its power series (as in resamp.c). */
static double bessel_i0(double x)
{
    double term = 1.0, sum = 1.0;
    for (int k = 1; term > 1e-12 * sum; k++) {
        term *= (x / (2 * k)) * (x / (2 * k));
        sum += term;
    }
    return sum;
}

static void build_kernel(Resampler *r, double cut)
{
    double norm = bessel_i0(RS_KAISER_BETA);
    r->cutoff = cut;
    for (int ph = 0; ph <= RS_PHASES; ph++) {
        double tot = 0.0;
        for (int k = 0; k < RS_TAPS; k++) {
            double t = k - RS_CENTRE - (double)ph / RS_PHASES;
            double x = 2 * cut * t;
            double ratio = t / RS_HALF_SPAN;
            double sinc = (x == 0.0) ? 1.0 : sin(M_PI * x) / (M_PI * x);
            double w = (fabs(ratio) < 1.0)
                ? bessel_i0(RS_KAISER_BETA * sqrt(1.0 - ratio * ratio)) / norm
                : 0.0;
            tot += (r->kernel[ph][k] = 2 * cut * sinc * w);
        }
        /* Normalise each phase so its taps sum to 1 (unity DC gain). */
        for (int k = 0; k < RS_TAPS; k++)
            r->kernel[ph][k] /= tot;
    }
}

Resampler *rs_new(void)
{
    Resampler *r = calloc(1, sizeof *r);
    if (!r)
        return NULL;
    r->kernel = malloc(sizeof(double) * RS_TAPS * (RS_PHASES + 1));
    if (!r->kernel) {
        free(r);
        return NULL;
    }
    return r;
}

void rs_free(Resampler *r)
{
    if (!r)
        return;
    free(r->kernel);
    free(r);
}

int rs_run(Resampler *r, const int16_t *in, int n, int16_t *out,
           int maxout, double r_in, double r_out)
{
    /* Anti-alias cutoff: half the output/input ratio when downsampling,
     * Nyquist (0.5) when upsampling. Rebuild the kernel on change. */
    double cut = 0.5 * (r_out < r_in ? r_out / r_in : 1.0);
    if (cut != r->cutoff)
        build_kernel(r, cut);
    double step = r_in / r_out;
    int m = 0;
    for (int i = 0; i < n; i++) {
        /* Shift history, newest sample last. */
        for (int k = 0; k < RS_TAPS - 1; k++)
            r->hist[k] = r->hist[k + 1];
        r->hist[RS_TAPS - 1] = in[i];
        while (r->pos < 1.0 && m < maxout) {
            const double *kk = r->kernel[(int)lround(r->pos * RS_PHASES)];
            double v = 0.0;
            for (int k = 0; k < RS_TAPS; k++)
                v += r->hist[k] * kk[k];
            v = round(v);
            out[m++] = (int16_t)(v > 32767 ? 32767 : v < -32768 ? -32768 : v);
            r->pos += step;
        }
        r->pos -= 1.0;
    }
    return m;
}
