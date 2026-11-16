/* Smoke test for config parsing + override order (src/glue/config.c).
 * File beats env; env fills keys the file does not set; profile
 * defaults fill the rest. */
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "config.h"

int main(void)
{
    const char *path = "/tmp/courier_test_call.conf";
    FILE *f = fopen(path, "w");
    assert(f);
    fprintf(f, "profile = sv25\n");
    fprintf(f, "duration_seconds = 12.5\n");
    fprintf(f, "noise_amp = 5\n");
    fprintf(f, "mode = v21\n");
    fclose(f);

    setenv("NOISE", "3", 1);      /* file has noise_amp: file must win */
    setenv("LINK_SLICE", "777", 1); /* absent from file: env must fill */
    setenv("PROFILE", "id20_403", 1); /* file profile must win */
    Config cfg;
    char err[256] = "";
    assert(config_load(&cfg, path, err, sizeof err) == 0);
    assert(strcmp(cfg.prof->key, "sv25") == 0);
    assert(cfg.prof->cpu_hz == 25804800);
    assert(cfg.duration_seconds == 12.5);
    assert(strcmp(cfg.mode, "v21") == 0);
    assert(cfg.noise_amp == 5);
    assert(cfg.link_slice == 777);
    assert(cfg.wav_rate == 22050); /* profile/config default */
    printf("test_config: profile=%s cpu_hz=%ld noise=%d slice=%ld wav_rate=%d\n",
           cfg.prof->key, cfg.prof->cpu_hz, cfg.noise_amp, cfg.link_slice,
           cfg.wav_rate);

    /* Unknown profile name falls back to sv25 via env-free path. */
    unsetenv("PROFILE");
    Config cfg2;
    assert(config_load(&cfg2, NULL, err, sizeof err) == 0);
    assert(strcmp(cfg2.prof->key, "sv25") == 0);
    printf("test_config: PASS\n");
    return 0;
}
