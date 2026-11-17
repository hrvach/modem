/* Smoke tests for DSP direct and indirect effective-address paths. */
#include <assert.h>
#include <stdint.h>
#include <stdio.h>

#include "c5x_core.h"

int main(void)
{
    C5x *c = c5x_new();
    uint16_t *pmem = c5x_pmem(c);
    uint16_t *dmem = c5x_dmem(c);

    c5x_reset(c, 0);
    dmem[0x60] = 0x1234;
    pmem[0] = 0x1060; /* LACC direct address 0x60 */
    assert(c5x_run(c, 1) == C5X_RUN_OK);
    assert(c5x_get(c, C5X_REG_ACC) == 0x1234);

    c5x_reset(c, 0);
    c5x_set(c, C5X_REG_ACC, 0xABCD1234);
    pmem[0] = 0x9861; /* SACH direct address 0x61 */
    assert(c5x_run(c, 1) == C5X_RUN_OK);
    assert(dmem[0x61] == 0xABCD);

    c5x_reset(c, 0);
    c5x_set(c, C5X_REG_AR0, 0x60);
    dmem[0x60] = 0x5678;
    pmem[0] = 0x1090; /* LACC indirect, decrement AR0 after addressing */
    assert(c5x_run(c, 1) == C5X_RUN_OK);
    assert(c5x_get(c, C5X_REG_ACC) == 0x5678);
    assert(c5x_get(c, C5X_REG_AR0) == 0x5f);

    puts("dsp_core_smoke: PASS");
    return 0;
}
