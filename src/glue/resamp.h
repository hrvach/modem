/* Streaming band-limited resampler (Kaiser-windowed sinc).
 *
 * Readable port of modem/sys/resamp.c (same formulas, same constants):
 * 128 taps, 1024 phases, Kaiser beta 8, group delay 63.5 input samples.
 * Used by link.c for the 8 kHz PCM telephone line and by wav.c for the
 * WAV export (per-segment resampling to the output rate).
 * Only the C stdlib + libm; no OS calls, so it is Emscripten-friendly.
 */
#ifndef COURIER_RESAMP_H
#define COURIER_RESAMP_H

#include <stdint.h>

typedef struct Resampler Resampler;

Resampler *rs_new(void);
void rs_free(Resampler *r);
/* Resample n input samples (r_in Hz) to r_out Hz, writing at most maxout
 * output samples. Returns the number written. Stateful: history and
 * fractional position carry across calls, exactly as in resamp.c. */
int rs_run(Resampler *r, const int16_t *in, int n, int16_t *out,
           int maxout, double r_in, double r_out);

#endif
