/* Smoke test for the Kaiser sinc resampler (src/glue/resamp.c).
 * DC in -> DC out (unity gain) once the 128-tap history has filled,
 * and the output count follows the rate ratio. */
#include <assert.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

#include "resamp.h"

int main(void)
{
    Resampler *r = rs_new();
    assert(r);
    int16_t in[400], out[2048];
    for (int i = 0; i < 400; i++)
        in[i] = 1000;
    int n = rs_run(r, in, 400, out, 2048, 7200.0, 7200.0);
    assert(n == 400); /* same rate: one output per input */
    /* After the group delay the constant input has fully filled the
     * history, so the output must be the input (kernel sums to 1). */
    for (int i = 200; i < n; i++)
        assert(out[i] == 1000);
    printf("test_resamp: same-rate DC ok (%d samples)\n", n);

    Resampler *r2 = rs_new();
    assert(r2);
    n = rs_run(r2, in, 400, out, 2048, 7200.0, 3600.0);
    assert(n >= 195 && n <= 205); /* half the rate, +/- group-delay edge */
    for (int i = 100; i < n; i++)
        assert(abs(out[i] - 1000) <= 1);
    printf("test_resamp: 2:1 downsample DC ok (%d samples)\n", n);
    rs_free(r);
    rs_free(r2);
    printf("test_resamp: PASS\n");
    return 0;
}
