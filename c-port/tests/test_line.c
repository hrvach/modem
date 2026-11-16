/* Smoke test for the telephone-line tone generators (src/glue/line.c). */
#include <assert.h>
#include <math.h>
#include <stdio.h>

#include "line.h"

int main(void)
{
    Tones t;
    dial_tone_init(&t, 3000);
    int32_t s0 = tones_next(&t);
    assert(s0 == 0); /* sin(0) + sin(0) */
    int32_t s1 = tones_next(&t);
    int32_t expect = (int32_t)((sin(2 * M_PI * 350.0 / 7200.0) +
                                sin(2 * M_PI * 440.0 / 7200.0)) * 3000.0);
    assert(s1 == expect);
    printf("test_line: dial tone s0=%d s1=%d (expected %d)\n", s0, s1, expect);

    Ringback rb;
    ringback_init(&rb, 0, 2500);
    assert(ringback_next(&rb) == 0); /* gated off: silence, phase frozen */
    rb.on = 1;
    assert(ringback_next(&rb) == 0); /* first tone sample is still 0 */
    assert(ringback_next(&rb) != 0);
    printf("test_line: PASS\n");
    return 0;
}
