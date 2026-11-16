/* Minimal WAV writer (16-bit PCM). Only the C stdlib; file I/O lives
 * here and in main.c, kept out of the machine/link glue so the cores
 * stay Emscripten-friendly.
 */
#ifndef COURIER_WAV_H
#define COURIER_WAV_H

#include <stdint.h>
#include <stdio.h>

/* Write n stereo frames (left/right int16) at `rate` Hz to path.
 * Returns 0 on success, -1 on error. */
int wav_write_stereo(const char *path, const int16_t *left,
                     const int16_t *right, int n, int rate);

#endif
