/* courier-call: fake call between two emulated Couriers.
 * Port of modem/sys/linkcall.py, driven by call.conf (see README.md).
 *
 * Flow (linkcall.py): boot both machines (900M cycles), type the AT
 * setup strings (150M cycles each), clear the capture buffers, dial,
 * run for duration_seconds, then write exactly ONE stereo WAV
 * (left = caller B, right = answerer A) plus call.log and
 * transferred.txt into the log directory.
 *
 * File I/O and argument parsing live here (and in wav.c / config.c);
 * the machine/link glue makes no OS calls, so it stays
 * Emscripten-friendly.
 */
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <time.h>

#include "config.h"
#include "link.h"
#include "machine.h"

static void usage(FILE *f)
{
    fprintf(f,
        "usage: courier-call [--config PATH] [--mode auto|v21|v22|echo|gate]\n"
        "                    [--duration SECONDS] [--out DIR] [--help]\n"
        "\n"
        "Defaults come from call.conf (default: ./call.conf, or the path\n"
        "given with --config). Override order: CLI > call.conf > env >\n"
        "profile default. See README.md and call.conf for the key list.\n");
}

static int mkdir_p(const char *path)
{
    if (!path || !*path)
        return 0;
    char tmp[CFG_MAX_PATH];
    snprintf(tmp, sizeof tmp, "%s", path);
    for (char *p = tmp + 1; *p; p++) {
        if (*p == '/') {
            *p = '\0';
            if (mkdir(tmp, 0777) != 0 && errno != EEXIST)
                return -1;
            *p = '/';
        }
    }
    if (mkdir(tmp, 0777) != 0 && errno != EEXIST)
        return -1;
    return 0;
}

static void dir_of(const char *path, char *out, size_t len)
{
    const char *slash = strrchr(path, '/');
    if (!slash) {
        snprintf(out, len, ".");
        return;
    }
    size_t n = (size_t)(slash - path);
    if (n >= len)
        n = len - 1;
    memcpy(out, path, n);
    out[n] = '\0';
    if (n == 0)
        snprintf(out, len, "/");
}

/* Split a '|' separated setup string into tokens (in place). */
static int split_setup(char *s, char **toks, int max)
{
    int n = 0;
    char *save = NULL;
    for (char *t = strtok_r(s, "|", &save); t && n < max;
         t = strtok_r(NULL, "|", &save))
        toks[n++] = t;
    return n;
}

static void print_bytes(const char *label, const uint8_t *b, size_t n)
{
    printf("%s:", label);
    if (n == 0) {
        printf(" (none)\n");
        return;
    }
    printf(" ");
    fwrite(b, 1, n, stdout);
    printf("\n");
}

int main(int argc, char **argv)
{
    /* Line-buffered so the live serial/DSP trace shows up while the run
     * is going, even when stdout is redirected to a file. */
    setvbuf(stdout, NULL, _IOLBF, 0);
    const char *cfg_path = "call.conf";
    const char *cli_mode = NULL;
    double cli_duration = -1;
    const char *cli_out = NULL;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--help") == 0 || strcmp(argv[i], "-h") == 0) {
            usage(stdout);
            return 0;
        } else if (strcmp(argv[i], "--config") == 0 && i + 1 < argc) {
            cfg_path = argv[++i];
        } else if (strcmp(argv[i], "--mode") == 0 && i + 1 < argc) {
            cli_mode = argv[++i];
        } else if (strcmp(argv[i], "--duration") == 0 && i + 1 < argc) {
            cli_duration = strtod(argv[++i], NULL);
        } else if (strcmp(argv[i], "--out") == 0 && i + 1 < argc) {
            cli_out = argv[++i];
        } else {
            fprintf(stderr, "courier-call: unknown argument '%s'\n", argv[i]);
            usage(stderr);
            return 2;
        }
    }

    Config cfg;
    char err[256] = "";
    if (config_load(&cfg, cfg_path, err, sizeof err) != 0) {
        fprintf(stderr, "courier-call: %s\n", err);
        return 1;
    }
    if (cli_mode)
        snprintf(cfg.mode, sizeof cfg.mode, "%s", cli_mode);
    if (cli_duration >= 0)
        cfg.duration_seconds = cli_duration;
    if (cli_out)
        snprintf(cfg.log_dir, sizeof cfg.log_dir, "%s", cli_out);
    if (strcmp(cfg.mode, "auto") && strcmp(cfg.mode, "v21") &&
        strcmp(cfg.mode, "v22") && strcmp(cfg.mode, "echo") &&
        strcmp(cfg.mode, "gate")) {
        fprintf(stderr, "courier-call: unknown mode '%s'\n", cfg.mode);
        return 2;
    }

    char flash_path[CFG_MAX_PATH], nvram_path[CFG_MAX_PATH];
    char wav_path[CFG_MAX_PATH], log_dir[CFG_MAX_PATH];
    config_resolve(&cfg, cfg.flash, flash_path, sizeof flash_path);
    config_resolve(&cfg, cfg.nvram, nvram_path, sizeof nvram_path);
    config_resolve(&cfg, cfg.wav_path, wav_path, sizeof wav_path);
    config_resolve(&cfg, cfg.log_dir, log_dir, sizeof log_dir);
    char wav_dir[CFG_MAX_PATH];
    dir_of(wav_path, wav_dir, sizeof wav_dir);
    if (mkdir_p(log_dir) != 0 || mkdir_p(wav_dir) != 0) {
        fprintf(stderr, "courier-call: cannot create output directory\n");
        return 1;
    }

    time_t wall_start = time(NULL);
    /* All run output goes to <log_dir>/log.txt. */
    char logtxt[CFG_MAX_PATH + 32];
    snprintf(logtxt, sizeof logtxt, "%s/log.txt", log_dir);
    if (!freopen(logtxt, "w", stdout)) {
        fprintf(stderr, "courier-call: cannot write '%s'\n", logtxt);
        return 1;
    }
    setvbuf(stdout, NULL, _IOLBF, 0);
    printf("courier-call: profile %s (%s)\n", cfg.prof->key, cfg.prof->name);
    printf("  flash: %s\n  nvram: %s\n  mode: %s  duration: %.0f s  wav_rate: %d  gain: %g  slice: %ld\n",
           flash_path, nvram_path, cfg.mode, cfg.duration_seconds, cfg.wav_rate,
           cfg.gain, cfg.link_slice);

    Link *l = link_new(&cfg);
    if (!l) {
        fprintf(stderr, "courier-call: failed to create machines (see above)\n");
        return 1;
    }
    if (strcmp(cfg.mode, "echo") == 0)
        l->echo = 0.1;
    if (strcmp(cfg.mode, "gate") == 0)
        l->gate = 1;

    /* Boot (linkcall.py: L.run(900_000_000); L.text()). */
    link_run(l, (uint64_t)cfg.boot_cycles);
    uint8_t drain[8192];
    size_t dl_a, dl_b;
    link_text(l, drain, &dl_a, drain, &dl_b);

    /* Setup strings, A (callee) first, then B (caller). */
    char setup_a[CFG_MAX_STR], setup_b[CFG_MAX_STR];
    snprintf(setup_a, sizeof setup_a, "%s", cfg.setup_a);
    snprintf(setup_b, sizeof setup_b, "%s", cfg.setup_b);
    char *toks_a[32], *toks_b[32];
    int na = split_setup(setup_a, toks_a, 32);
    int nb = split_setup(setup_b, toks_b, 32);
    /* Mode extras, exactly as in linkcall.py. */
    const char *extra_a = NULL, *extra_b = NULL;
    if (strcmp(cfg.mode, "v21") == 0) { extra_a = "AT&N1\r"; extra_b = "AT&N1\r"; }
    if (strcmp(cfg.mode, "v22") == 0) { extra_a = "AT&N3\r"; extra_b = "AT&N3\r"; }
    for (int i = 0; i < na; i++) {
        link_send(l, 0, (const uint8_t *)(toks_a[i]), strlen(toks_a[i]));
        link_run(l, (uint64_t)cfg.setup_cycles);
    }
    if (extra_a) {
        link_send(l, 0, (const uint8_t *)(extra_a), strlen(extra_a));
        link_run(l, (uint64_t)cfg.setup_cycles);
        link_send(l, 0, (const uint8_t *)("ATB0\r"), strlen("ATB0\r"));
        link_run(l, (uint64_t)cfg.setup_cycles);
    }
    for (int i = 0; i < nb; i++) {
        link_send(l, 1, (const uint8_t *)(toks_b[i]), strlen(toks_b[i]));
        link_run(l, (uint64_t)cfg.setup_cycles);
    }
    if (extra_b) {
        link_send(l, 1, (const uint8_t *)(extra_b), strlen(extra_b));
        link_run(l, (uint64_t)cfg.setup_cycles);
        link_send(l, 1, (const uint8_t *)("ATB0\r"), strlen("ATB0\r"));
        link_run(l, (uint64_t)cfg.setup_cycles);
    }
    uint8_t setup_a_txt[8192], setup_b_txt[8192];
    size_t setup_a_n, setup_b_n;
    link_text(l, setup_a_txt, &setup_a_n, setup_b_txt, &setup_b_n);

    /* Clear the capture buffers (linkcall.py), keeping rate_idx etc. */
    l->a->tx_all_n = 0; l->a->lk_seen = 0;
    l->b->tx_all_n = 0; l->b->lk_seen = 0;
    l->a->cmd_log16_n = 0; l->b->cmd_log16_n = 0;
    l->a->dsp_log_n = 0; l->b->dsp_log_n = 0;
    l->audio_a_n = 0; l->audio_b_n = 0;
    l->events_n = 0;
    l->txt_a_n = 0; l->txt_b_n = 0;

    link_start_call(l, cfg.phone);

    /* Optional user payload after CONNECT (default: none). */
    int payload_sent = 0;
    size_t payload_len = 0;
    uint8_t *payload = NULL;
    if (cfg.send_file[0]) {
        char sp[CFG_MAX_PATH];
        config_resolve(&cfg, cfg.send_file, sp, sizeof sp);
        FILE *f = fopen(sp, "rb");
        if (f) {
            fseek(f, 0, SEEK_END);
            long n = ftell(f);
            fseek(f, 0, SEEK_SET);
            if (n > 0) {
                payload = malloc((size_t)n);
                payload_len = fread(payload, 1, (size_t)n, f);
            }
            fclose(f);
        } else {
            fprintf(stderr, "courier-call: cannot read send_file '%s'\n", sp);
        }
    } else if (cfg.send_text[0]) {
        payload_len = strlen(cfg.send_text);
        payload = malloc(payload_len + 2);
        memcpy(payload, cfg.send_text, payload_len);
        payload[payload_len++] = '\r';   /* end the message with CR LF */
        payload[payload_len++] = '\n';
    }

    /* Answerer (A) payload: sent once after A's CONNECT. */
    uint8_t *payload_a = NULL;
    size_t payload_a_n = strlen(cfg.send_text_a);
    int payload_a_sent = 0;
    if (payload_a_n) {
        payload_a = malloc(payload_a_n + 2);
        memcpy(payload_a, cfg.send_text_a, payload_a_n);
        payload_a[payload_a_n++] = '\r';   /* end the message with CR LF */
        payload_a[payload_a_n++] = '\n';
    }

    int64_t target_samples = (int64_t)(cfg.duration_seconds * LINK_FS);
    while (link_samples(l) < target_samples) {
        link_run(l, 10000000);
        if (payload && !payload_sent && l->txt_b_n &&
            memmem(l->txt_b, l->txt_b_n, "CONNECT", 7)) {
            /* Caller (B) payload, once B reports CONNECT. */
            link_send(l, 1, payload, payload_len);
            payload_sent = 1;
        }
        if (payload_a && !payload_a_sent && l->txt_a_n &&
            memmem(l->txt_a, l->txt_a_n, "CONNECT", 7)) {
            /* Answerer (A) payload, once A reports CONNECT. */
            link_send(l, 0, payload_a, payload_a_n);
            payload_a_sent = 1;
        }
        /* Stop as soon as each side has the other side's message. */
        if (payload_sent && payload_a_sent &&
            memmem(l->txt_a, l->txt_a_n, cfg.send_text, strlen(cfg.send_text)) &&
            memmem(l->txt_b, l->txt_b_n, cfg.send_text_a, strlen(cfg.send_text_a)))
            break;
    }
    free(payload_a);
    free(payload);

    /* Debug aid for verification (not part of normal output): if the
     * COURIER_DUMP_RAW env var names a path prefix, write the raw
     * per-modem audio (<prefix>_A.raw, <prefix>_B.raw, int16, 7200 Hz,
     * same signed samples as Python linkcall.py's mono WAVs) so the
     * emulator's audio can be compared sample-by-sample against Python
     * without the WAV export resampler in the way. */
    {
        const char *dp = getenv("COURIER_DUMP_RAW");
        if (dp) {
            const int32_t *aud[2] = { l->audio_a, l->audio_b };
            const size_t an[2] = { l->audio_a_n, l->audio_b_n };
            const char suf[2] = { 'A', 'B' };
            for (int ch = 0; ch < 2; ch++) {
                char rp[CFG_MAX_PATH + 16];
                snprintf(rp, sizeof rp, "%s_%c.raw", dp, suf[ch]);
                FILE *rf = fopen(rp, "wb");
                if (rf) {
                    for (size_t i = 0; i < an[ch]; i++) {
                        int32_t v = aud[ch][i];
                        int16_t s = (int16_t)(v > 32767 ? 32767 : v < -32768 ? -32768 : v);
                        fwrite(&s, sizeof s, 1, rf);
                    }
                    fclose(rf);
                }
            }
        }
    }

    /* ---- outputs ---- */
    if (link_write_wav(l, wav_path, cfg.wav_rate) != 0) {
        fprintf(stderr, "courier-call: cannot write WAV '%s'\n", wav_path);
        link_free(l);
        return 1;
    }
    char log_path[CFG_MAX_PATH + 32], tr_path[CFG_MAX_PATH + 32];
    snprintf(log_path, sizeof log_path, "%s/call.log", log_dir);
    snprintf(tr_path, sizeof tr_path, "%s/transferred.txt", log_dir);
    FILE *lf = fopen(log_path, "wb");
    if (lf) {
        fprintf(lf, "courier-call log: profile %s mode %s duration %.0f s\n",
                cfg.prof->key, cfg.mode, cfg.duration_seconds);
        fprintf(lf, "setup replies:\n  A: ");
        fwrite(setup_a_txt, 1, setup_a_n, lf);
        fprintf(lf, "\n  B: ");
        fwrite(setup_b_txt, 1, setup_b_n, lf);
        fprintf(lf, "\nevents:\n");
        for (size_t i = 0; i < l->events_n; i++)
            fprintf(lf, "  %.2f %s\n", l->events[i].t, l->events[i].st);
        fprintf(lf, "A (callee) DTE text:\n");
        fwrite(l->txt_a, 1, l->txt_a_n, lf);
        fprintf(lf, "\nB (caller) DTE text:\n");
        fwrite(l->txt_b, 1, l->txt_b_n, lf);
        fprintf(lf, "\nDSP commands after 12 s:\n");
        Machine *ms[2] = { l->a, l->b };
        const char *names[2] = { "A", "B" };
        for (int k = 0; k < 2; k++) {
            fprintf(lf, "  %s:", names[k]);
            int shown = 0;
            for (size_t i = 0; i < ms[k]->cmd_log16_n && shown < 40; i++) {
                Cmd16Ent *e = &ms[k]->cmd_log16[i];
                if (e->t > 12 * LINK_FS) {
                    fprintf(lf, " (%.2f,%04X,%04X)", (double)e->t / LINK_FS,
                            e->c, e->x);
                    shown++;
                }
            }
            fprintf(lf, "\n");
        }
        fclose(lf);
    }
    FILE *tf = fopen(tr_path, "w");
    if (tf) {
        fprintf(tf, "DTE text transferred, both directions\n");
        fprintf(tf, "A (callee) -> %zu bytes, B (caller) -> %zu bytes\n",
                l->txt_a_n, l->txt_b_n);
        fprintf(tf, "user payload sent: %s (%zu bytes)\n",
                payload_sent ? "yes" : "no",
                payload_sent ? payload_len : 0);
        fprintf(tf, "--- A (callee) ---\n");
        fwrite(l->txt_a, 1, l->txt_a_n, tf);
        fprintf(tf, "\n--- B (caller) ---\n");
        fwrite(l->txt_b, 1, l->txt_b_n, tf);
        fprintf(tf, "\n");
        fclose(tf);
    }

    printf("== mode %s setup replies: A=", cfg.mode);
    fwrite(setup_a_txt, 1, setup_a_n, stdout);
    printf(" B=");
    fwrite(setup_b_txt, 1, setup_b_n, stdout);
    printf("\nevents:");
    for (size_t i = 0; i < l->events_n; i++)
        printf(" (%.2f,%s)", l->events[i].t, l->events[i].st);
    printf("\n");
    print_bytes("A (callee) DTE text", l->txt_a, l->txt_a_n);
    print_bytes("B (caller) DTE text", l->txt_b, l->txt_b_n);
    Machine *ms[2] = { l->a, l->b };
    const char *names[2] = { "A", "B" };
    for (int k = 0; k < 2; k++) {
        printf("%s DSP commands after 12 s:", names[k]);
        int shown = 0;
        for (size_t i = 0; i < ms[k]->cmd_log16_n && shown < 40; i++) {
            Cmd16Ent *e = &ms[k]->cmd_log16[i];
            if (e->t > 12 * LINK_FS)
                printf(" (%.2f,%04X,%04X)", (double)e->t / LINK_FS, e->c, e->x), shown++;
        }
        printf("\n");
    }
    long wall = (long)(time(NULL) - wall_start);
    printf("wrote %s (%zu/%zu samples A/B), %s, %s\n", wav_path,
           l->audio_a_n, l->audio_b_n, log_path, tr_path);
    printf("wall time: %ld s\n", wall);
    link_free(l);
    return 0;
}
