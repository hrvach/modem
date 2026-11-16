/* Minimal 16-bit PCM stereo WAV writer. */
#include <string.h>

#include "wav.h"

static void put_u16le(uint8_t *p, unsigned v) { p[0] = v & 0xFF; p[1] = (v >> 8) & 0xFF; }
static void put_u32le(uint8_t *p, unsigned long v)
{
    p[0] = v & 0xFF; p[1] = (v >> 8) & 0xFF;
    p[2] = (v >> 16) & 0xFF; p[3] = (v >> 24) & 0xFF;
}

int wav_write_stereo(const char *path, const int16_t *left,
                     const int16_t *right, int n, int rate)
{
    FILE *f = fopen(path, "wb");
    if (!f)
        return -1;
    uint32_t data_bytes = (uint32_t)n * 4;
    uint8_t hdr[44];
    memcpy(hdr, "RIFF", 4);
    put_u32le(hdr + 4, 36 + data_bytes);
    memcpy(hdr + 8, "WAVEfmt ", 8);
    put_u32le(hdr + 16, 16);          /* PCM fmt chunk size */
    put_u16le(hdr + 20, 1);           /* PCM */
    put_u16le(hdr + 22, 2);           /* stereo */
    put_u32le(hdr + 24, (unsigned)rate);
    put_u32le(hdr + 28, (unsigned)rate * 4); /* byte rate */
    put_u16le(hdr + 32, 4);           /* block align */
    put_u16le(hdr + 34, 16);          /* bits per sample */
    memcpy(hdr + 36, "data", 4);
    put_u32le(hdr + 40, data_bytes);
    if (fwrite(hdr, 1, 44, f) != 44) {
        fclose(f);
        return -1;
    }
    for (int i = 0; i < n; i++) {
        uint8_t fr[4];
        put_u16le(fr, (uint16_t)left[i]);
        put_u16le(fr + 2, (uint16_t)right[i]);
        if (fwrite(fr, 1, 4, f) != 4) {
            fclose(f);
            return -1;
        }
    }
    return fclose(f) == 0 ? 0 : -1;
}
