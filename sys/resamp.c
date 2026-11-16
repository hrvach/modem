/* Streaming band-limited resampler (Kaiser-windowed sinc, 128 taps, 1024 phases), after courier-emu's codec_line_sample.
 * Used by link.py for the 8 kHz PCM telephone line between two modems whose codecs run at 7200..10267 Hz.
 * Group delay is 63.5 input samples. gcc -O2 -shared -fPIC -o libresamp.so resamp.c -lm */
#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#define TAPS 128
#define PH 1024
typedef struct { double hist[TAPS], pos, cutoff; double (*k)[TAPS]; } RS;
static double i0(double x) { double t = 1, s = 1; for (int k = 1; t > 1e-12 * s; k++) { t *= (x / (2 * k)) * (x / (2 * k)); s += t; } return s; }
void *rs_new(void) { RS *r = calloc(1, sizeof *r); r->k = malloc(sizeof(double) * TAPS * (PH + 1)); return r; }
void rs_free(void *p) { RS *r = p; free(r->k); free(r); }
static void build(RS *r, double cut) {
    double norm = i0(8); r->cutoff = cut;
    for (int ph = 0; ph <= PH; ph++) {
        double tot = 0;
        for (int k = 0; k < TAPS; k++) {
            double t = k - 63 - (double)ph / PH, x = 2 * cut * t, ratio = t / 64;
            double sinc = x == 0 ? 1 : sin(M_PI * x) / (M_PI * x);
            double w = fabs(ratio) < 1 ? i0(8 * sqrt(1 - ratio * ratio)) / norm : 0;
            tot += (r->k[ph][k] = 2 * cut * sinc * w);
        }
        for (int k = 0; k < TAPS; k++) r->k[ph][k] /= tot;
    }
}
int rs_run(void *p, const int16_t *in, int n, int16_t *out, int maxout, double r_in, double r_out) {
    RS *r = p; double cut = 0.5 * (r_out < r_in ? r_out / r_in : 1.0);
    if (cut != r->cutoff) build(r, cut);
    double step = r_in / r_out; int m = 0;
    for (int i = 0; i < n; i++) {
        for (int k = 0; k < TAPS - 1; k++) r->hist[k] = r->hist[k + 1];
        r->hist[TAPS - 1] = in[i];
        while (r->pos < 1.0 && m < maxout) {
            const double *kk = r->k[(int)lround(r->pos * PH)]; double v = 0;
            for (int k = 0; k < TAPS; k++) v += r->hist[k] * kk[k];
            v = round(v); out[m++] = v > 32767 ? 32767 : v < -32768 ? -32768 : (int16_t)v;
            r->pos += step;
        }
        r->pos -= 1.0;
    }
    return m;
}
