/* Configuration: profiles (modem/sys/profiles.py), call.conf parsing,
 * and the override order CLI > config file > env > profile default.
 *
 * call.conf is plain `key = value`, one per line; `#` starts a comment,
 * values may be quoted. String values understand \r, \n, \t and \\.
 * Unknown keys are ignored (with a note on stderr) so old configs keep
 * loading; a misspelt known key is therefore silent, so keep call.conf
 * as the documented key list.
 */
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "config.h"

static const Profile PROFILES[] = {
    {
        .key = "sv25",
        .name = "previous image (SV25)",
        .flash = "fw/SV25.flash.bin", .nvram = "fw/nvram.bin",
        .cpu_hz = 25804800, .dsp_hz = 40320000, .iface = "25",
        .dsp_base_bytes = 55420, .hw_idx = 7,
    },
};

const Profile *profile_by_name(const char *name)
{
    if (!name)
        return NULL;
    for (size_t i = 0; i < sizeof(PROFILES) / sizeof(*PROFILES); i++)
        if (strcmp(PROFILES[i].key, name) == 0)
            return &PROFILES[i];
    return NULL;
}

/* Filename prefix -> profile: SV25 -> sv25. */
const Profile *profile_by_flash_name(const char *base)
{
    static const struct { const char *prefix, *key; } m[] = {
        { "SV25", "sv25" },
    };
    if (!base)
        return NULL;
    for (size_t i = 0; i < sizeof(m) / sizeof(*m); i++)
        if (strncmp(base, m[i].prefix, strlen(m[i].prefix)) == 0)
            return profile_by_name(m[i].key);
    return NULL;
}

/* ---- small parsing helpers ---- */

static void trim(char *s)
{
    size_t n = strlen(s);
    while (n && isspace((unsigned char)s[n - 1]))
        s[--n] = '\0';
    size_t i = 0;
    while (s[i] && isspace((unsigned char)s[i]))
        i++;
    if (i)
        memmove(s, s + i, strlen(s + i) + 1);
}

/* Unquote ("..." only) and expand \r \n \t \\ in place. */
static void unescape(char *s)
{
    size_t n = strlen(s);
    if (n >= 2 && s[0] == '"' && s[n - 1] == '"') {
        memmove(s, s + 1, n - 2);
        s[n - 2] = '\0';
    }
    char *w = s;
    for (char *r = s; *r; r++) {
        if (*r == '\\' && r[1]) {
            r++;
            *w++ = (*r == 'r') ? '\r' : (*r == 'n') ? '\n' :
                   (*r == 't') ? '\t' : *r;
        } else {
            *w++ = *r;
        }
    }
    *w = '\0';
}

static int parse_bool(const char *v)
{
    return strcmp(v, "1") == 0 || strcasecmp(v, "true") == 0 ||
           strcasecmp(v, "yes") == 0 || strcasecmp(v, "on") == 0;
}

static int parse_int(const char *v, int base)
{
    return (int)strtol(v, NULL, base);
}

/* Key/value store for one config file pass. */
#define KV_MAX 256
typedef struct { char key[64], val[CFG_MAX_STR]; } Kv;
typedef struct { Kv kv[KV_MAX]; int n; } KvList;

static const char *kv_get(const KvList *l, const char *key)
{
    for (int i = 0; i < l->n; i++)
        if (strcmp(l->kv[i].key, key) == 0)
            return l->kv[i].val;
    return NULL;
}

static int kv_has(const KvList *l, const char *key) { return kv_get(l, key) != NULL; }

static int read_kv_file(const char *path, KvList *out, char *err, size_t errlen)
{
    FILE *f = fopen(path, "r");
    if (!f) {
        if (err)
            snprintf(err, errlen, "cannot open config '%s'", path);
        return -1;
    }
    char line[2048];
    while (fgets(line, sizeof line, f)) {
        char *hash = strchr(line, '#');
        if (hash)
            *hash = '\0';
        char *eq = strchr(line, '=');
        if (!eq)
            continue;
        *eq = '\0';
        char k[64], v[CFG_MAX_STR];
        /* Truncating copies (keys are short by construction; values are
         * capped at CFG_MAX_STR). snprintf would warn -Wformat-truncation
         * for exactly this intended truncation. */
        size_t kl = strnlen(line, sizeof k - 1);
        memcpy(k, line, kl); k[kl] = '\0';
        size_t vl = strnlen(eq + 1, sizeof v - 1);
        memcpy(v, eq + 1, vl); v[vl] = '\0';
        trim(k);
        trim(v);
        if (!k[0] || !v[0])
            continue;
        if (out->n < KV_MAX) {
            snprintf(out->kv[out->n].key, sizeof out->kv[out->n].key, "%s", k);
            snprintf(out->kv[out->n].val, sizeof out->kv[out->n].val, "%s", v);
            unescape(out->kv[out->n].val);
            out->n++;
        }
    }
    fclose(f);
    return 0;
}

void config_resolve(const Config *cfg, const char *path, char *out, size_t outlen)
{
    if (!path || !path[0]) {
        snprintf(out, outlen, "%s", "");
        return;
    }
    if (path[0] == '/' || cfg->cfg_dir[0] == '\0') {
        snprintf(out, outlen, "%s", path);
        return;
    }
    snprintf(out, outlen, "%s/%s", cfg->cfg_dir, path);
}

/* Apply file keys onto cfg (only keys present in the file). */
static void apply_file(Config *cfg, const KvList *kv)
{
    const char *v;
    if ((v = kv_get(kv, "profile"))) snprintf(cfg->profile, sizeof cfg->profile, "%s", v);
    if ((v = kv_get(kv, "flash"))) snprintf(cfg->flash, sizeof cfg->flash, "%s", v);
    if ((v = kv_get(kv, "nvram"))) snprintf(cfg->nvram, sizeof cfg->nvram, "%s", v);
    if ((v = kv_get(kv, "dsp_base"))) snprintf(cfg->dsp_base, sizeof cfg->dsp_base, "%s", v);
    if ((v = kv_get(kv, "duration_seconds"))) cfg->duration_seconds = strtod(v, NULL);
    if ((v = kv_get(kv, "mode"))) snprintf(cfg->mode, sizeof cfg->mode, "%s", v);
    if ((v = kv_get(kv, "noise_amp"))) cfg->noise_amp = parse_int(v, 10);
    if ((v = kv_get(kv, "link_slice"))) cfg->link_slice = strtol(v, NULL, 10);
    if ((v = kv_get(kv, "link_mode"))) snprintf(cfg->link_mode, sizeof cfg->link_mode, "%s", v);
    if ((v = kv_get(kv, "line8k"))) cfg->line8k = parse_bool(v);
    if ((v = kv_get(kv, "gate"))) cfg->gate = parse_bool(v);
    if ((v = kv_get(kv, "echo"))) cfg->echo = strtod(v, NULL);
    if ((v = kv_get(kv, "gain"))) cfg->gain = strtod(v, NULL);
    if ((v = kv_get(kv, "wav_rate"))) cfg->wav_rate = parse_int(v, 10);
    if ((v = kv_get(kv, "wav"))) snprintf(cfg->wav_path, sizeof cfg->wav_path, "%s", v);
    if ((v = kv_get(kv, "log_dir"))) snprintf(cfg->log_dir, sizeof cfg->log_dir, "%s", v);
    if ((v = kv_get(kv, "setup_a"))) snprintf(cfg->setup_a, sizeof cfg->setup_a, "%s", v);
    if ((v = kv_get(kv, "setup_b"))) snprintf(cfg->setup_b, sizeof cfg->setup_b, "%s", v);
    if ((v = kv_get(kv, "phone"))) snprintf(cfg->phone, sizeof cfg->phone, "%s", v);
    if ((v = kv_get(kv, "send_text"))) snprintf(cfg->send_text, sizeof cfg->send_text, "%s", v);
    if ((v = kv_get(kv, "send_text_a"))) snprintf(cfg->send_text_a, sizeof cfg->send_text_a, "%s", v);
    if ((v = kv_get(kv, "send_file"))) snprintf(cfg->send_file, sizeof cfg->send_file, "%s", v);
    if ((v = kv_get(kv, "xint_mode"))) cfg->xint_mode = parse_int(v, 10);
    if ((v = kv_get(kv, "cycle_model"))) cfg->cycle_model = parse_int(v, 10);
    if ((v = kv_get(kv, "legacy"))) cfg->legacy = parse_int(v, 10);
    if ((v = kv_get(kv, "tdm_irqs"))) cfg->tdm_irqs = parse_bool(v);
    if ((v = kv_get(kv, "ac01_model"))) cfg->ac01_model = parse_bool(v);
    if ((v = kv_get(kv, "sec_frame"))) cfg->sec_frame = parse_bool(v);
    if ((v = kv_get(kv, "hb_timer"))) cfg->hb_timer = parse_bool(v);
    if ((v = kv_get(kv, "dsp_clk_fixed"))) cfg->dsp_clk_fixed = parse_bool(v);
    if ((v = kv_get(kv, "port_rb"))) cfg->port_rb = parse_bool(v);
    if ((v = kv_get(kv, "int23"))) cfg->int23 = parse_bool(v);
    if ((v = kv_get(kv, "ac01_filt"))) cfg->ac01_filt = parse_bool(v);
    if ((v = kv_get(kv, "ac01_lat"))) cfg->ac01_lat = parse_int(v, 10);
    if ((v = kv_get(kv, "cmd_ovr"))) snprintf(cfg->cmd_ovr, sizeof cfg->cmd_ovr, "%s", v);
    if ((v = kv_get(kv, "ac01_clamp"))) snprintf(cfg->ac01_clamp, sizeof cfg->ac01_clamp, "%s", v);
    if ((v = kv_get(kv, "p51div"))) cfg->p51div = parse_int(v, 10);
    if ((v = kv_get(kv, "cpu_scale"))) cfg->cpu_scale = strtod(v, NULL);
    if ((v = kv_get(kv, "ud_trap"))) cfg->ud_trap = parse_bool(v);
    if ((v = kv_get(kv, "delay_samples"))) cfg->delay_samples = parse_int(v, 10);
    if ((v = kv_get(kv, "dial_dwell"))) cfg->dial_dwell = strtod(v, NULL);
    if ((v = kv_get(kv, "ring_on"))) cfg->ring_on = strtod(v, NULL);
    if ((v = kv_get(kv, "ring_period"))) cfg->ring_period = strtod(v, NULL);
    if ((v = kv_get(kv, "cpu_model"))) cfg->cpu_model = parse_int(v, 10);
    if ((v = kv_get(kv, "cpu_hz"))) cfg->cpu_hz = strtol(v, NULL, 10);
    if ((v = kv_get(kv, "dsp_hz"))) cfg->dsp_hz = strtol(v, NULL, 10);
    if ((v = kv_get(kv, "patch_crc"))) cfg->patch_crc = parse_int(v, 0);
    if ((v = kv_get(kv, "nvram_mode"))) cfg->nvram_mode = parse_int(v, 10);
    if ((v = kv_get(kv, "fax_patch"))) cfg->fax_patch = parse_bool(v);
    if ((v = kv_get(kv, "cmpr"))) cfg->cmpr = parse_bool(v);
    if ((v = kv_get(kv, "tintslot"))) cfg->tintslot = parse_int(v, 0);
    if ((v = kv_get(kv, "inject_cmd"))) cfg->inject_cmd = (int)strtol(v, NULL, 0);
    if ((v = kv_get(kv, "inject_arg"))) cfg->inject_arg = (int)strtol(v, NULL, 0);
    if ((v = kv_get(kv, "inject_at"))) cfg->inject_at = strtod(v, NULL);
    if ((v = kv_get(kv, "dsp_rom"))) snprintf(cfg->dsp_rom, sizeof cfg->dsp_rom, "%s", v);
    if ((v = kv_get(kv, "bankwr"))) cfg->bankwr = parse_bool(v);
    if ((v = kv_get(kv, "hw_idx"))) cfg->hw_idx = parse_int(v, 10);
    if ((v = kv_get(kv, "voice_data_button"))) cfg->voice_data_button = parse_bool(v);
    if ((v = kv_get(kv, "boot_cycles"))) cfg->boot_cycles = strtol(v, NULL, 10);
    if ((v = kv_get(kv, "setup_cycles"))) cfg->setup_cycles = strtol(v, NULL, 10);
}

/* Env fallback: only for keys the file did not set. Env names are the
 * machine.py / link.py ones (NOISE, LINK_SLICE, ...). */
static void apply_env(Config *cfg, const KvList *kv)
{
    const char *e;
    /* Small helpers via macros: env name, config key, assignment. */
#define ENV_INT(envname, cfgkey, field) \
    do { if (!kv_has(kv, cfgkey) && (e = getenv(envname))) cfg->field = parse_int(e, 10); } while (0)
#define ENV_BOOL(envname, cfgkey, field) \
    do { if (!kv_has(kv, cfgkey) && (e = getenv(envname))) cfg->field = (strcmp(e, "0") != 0); } while (0)
#define ENV_DBL(envname, cfgkey, field) \
    do { if (!kv_has(kv, cfgkey) && (e = getenv(envname))) cfg->field = strtod(e, NULL); } while (0)
#define ENV_STR(envname, cfgkey, field) \
    do { if (!kv_has(kv, cfgkey) && (e = getenv(envname))) snprintf(cfg->field, sizeof cfg->field, "%s", e); } while (0)
    ENV_INT("NOISE", "noise_amp", noise_amp);
    ENV_INT("LINK_SLICE", "link_slice", link_slice);
    ENV_STR("LINK_MODE", "link_mode", link_mode);
    ENV_DBL("GAIN", "gain", gain);
    ENV_BOOL("LINE8K", "line8k", line8k);
    ENV_DBL("DIAL_DWELL", "dial_dwell", dial_dwell);
    ENV_DBL("RING_ON", "ring_on", ring_on);
    ENV_DBL("RING_PERIOD", "ring_period", ring_period);
    ENV_INT("DELAY_SAMPLES", "delay_samples", delay_samples);
    ENV_INT("XINT_MODE", "xint_mode", xint_mode);
    ENV_INT("XM", "xint_mode", xint_mode);
    ENV_INT("CYC_MODEL", "cycle_model", cycle_model);
    ENV_INT("CM", "cycle_model", cycle_model);
    ENV_INT("LEGACY", "legacy", legacy);
    ENV_BOOL("TDM", "tdm_irqs", tdm_irqs);
    ENV_BOOL("AC01_MODEL", "ac01_model", ac01_model);
    ENV_BOOL("SEC_FRAME", "sec_frame", sec_frame);
    ENV_BOOL("HB_TIMER", "hb_timer", hb_timer);
    ENV_BOOL("DSP_CLK_FIXED", "dsp_clk_fixed", dsp_clk_fixed);
    ENV_BOOL("PORT_RB", "port_rb", port_rb);
    ENV_BOOL("INT23", "int23", int23);
    ENV_BOOL("AC01_FILT", "ac01_filt", ac01_filt);
    ENV_INT("AC01_LAT", "ac01_lat", ac01_lat);
    ENV_STR("CMD_OVR", "cmd_ovr", cmd_ovr);
    ENV_STR("AC01_CLAMP", "ac01_clamp", ac01_clamp);
    ENV_INT("P51DIV", "p51div", p51div);
    ENV_DBL("CPU_SCALE", "cpu_scale", cpu_scale);
    ENV_BOOL("UD_TRAP", "ud_trap", ud_trap);
    ENV_INT("CPU_MODEL", "cpu_model", cpu_model);
    ENV_STR("DSP_ROM", "dsp_rom", dsp_rom);
    ENV_BOOL("BANKWR", "bankwr", bankwr);
    ENV_INT("HWID", "hw_idx", hw_idx);
    ENV_BOOL("VDBTN", "voice_data_button", voice_data_button);
    if (!kv_has(kv, "cmpr") && (e = getenv("CMPR")))
        cfg->cmpr = (strcmp(e, "1") == 0);
    if (!kv_has(kv, "tintslot") && (e = getenv("TINTSLOT")))
        cfg->tintslot = parse_int(e, 0);
    if (!kv_has(kv, "cpu_hz") && (e = getenv("CPU_HZ")))
        cfg->cpu_hz = strtol(e, NULL, 10);
    if (!kv_has(kv, "dsp_hz") && (e = getenv("DSP_HZ")))
        cfg->dsp_hz = strtol(e, NULL, 10);
#undef ENV_INT
#undef ENV_BOOL
#undef ENV_DBL
#undef ENV_STR
}

static void set_defaults(Config *cfg, const Profile *p)
{
    memset(cfg, 0, sizeof *cfg);
    snprintf(cfg->profile, sizeof cfg->profile, "%s", p->key);
    snprintf(cfg->flash, sizeof cfg->flash, "%s", p->flash);
    snprintf(cfg->nvram, sizeof cfg->nvram, "%s", p->nvram);
    snprintf(cfg->dsp_base, sizeof cfg->dsp_base, "%s", "fw/dsp_base.bin");
    cfg->duration_seconds = 70.0;
    snprintf(cfg->mode, sizeof cfg->mode, "auto");
    cfg->noise_amp = 8;
    cfg->link_slice = 1000;
    snprintf(cfg->link_mode, sizeof cfg->link_mode, "slice");
    cfg->line8k = 0;
    cfg->gate = 0;
    cfg->echo = 0.0;
    cfg->gain = 0.5; /* §62/§64 connecting value; zip default 1.0 stalls at 02 B000 */
    cfg->wav_rate = 22050;
    snprintf(cfg->wav_path, sizeof cfg->wav_path, "out/call_auto.wav");
    snprintf(cfg->log_dir, sizeof cfg->log_dir, "out");
    snprintf(cfg->setup_a, sizeof cfg->setup_a, "AT|ATQ0V1");
    snprintf(cfg->setup_b, sizeof cfg->setup_b, "AT|ATQ0V1X3");
    snprintf(cfg->phone, sizeof cfg->phone, "1");
    cfg->xint_mode = 1; cfg->cycle_model = 1; cfg->legacy = 0; cfg->tdm_irqs = 0;
    cfg->ac01_model = 1; cfg->sec_frame = 1; cfg->hb_timer = 1;
    cfg->dsp_clk_fixed = 1; cfg->port_rb = 1; cfg->int23 = 1;
    cfg->ac01_filt = 0; cfg->ac01_lat = 0;
    cfg->p51div = 0; cfg->cpu_scale = 1.0; cfg->ud_trap = 1;
    cfg->delay_samples = 0;
    cfg->dial_dwell = 0.5; cfg->ring_on = 1.0; cfg->ring_period = 6.0;
    cfg->cpu_model = 1;
    cfg->cpu_hz = 0; cfg->dsp_hz = 0; /* 0 = profile value */
    cfg->patch_crc = 0x1735;
    cfg->nvram_mode = -1; /* Link machines: none (machine.py Link default) */
    cfg->fax_patch = 0; cfg->cmpr = 0; cfg->tintslot = -1;
    cfg->inject_cmd = -1; cfg->inject_arg = 0; cfg->inject_at = 0;
    cfg->bankwr = 1; cfg->hw_idx = -1; cfg->voice_data_button = 0;
    cfg->boot_cycles = 900000000L;
    cfg->setup_cycles = 150000000L;
    cfg->prof = p;
}

int config_load(Config *cfg, const char *path, char *err, size_t errlen)
{
    KvList kv = { .n = 0 };
    if (path) {
        if (read_kv_file(path, &kv, err, errlen) != 0)
            return -1;
        /* Config directory for relative-path resolution. */
        const char *slash = strrchr(path, '/');
        if (slash) {
            size_t n = (size_t)(slash - path);
            if (n >= sizeof cfg->cfg_dir)
                n = sizeof cfg->cfg_dir - 1;
            memcpy(cfg->cfg_dir, path, n);
            cfg->cfg_dir[n] = '\0';
        }
    }
    /* Which profile? File `profile` > env PROFILE > FLASH filename match
     * (file flash, else env FLASH) > sv25 default. */
    const Profile *p = NULL;
    const char *v;
    if ((v = kv_get(&kv, "profile")))
        p = profile_by_name(v);
    if (!p && (v = getenv("PROFILE")))
        p = profile_by_name(v);
    if (!p) {
        const char *f = kv_get(&kv, "flash");
        if (!f)
            f = getenv("FLASH");
        if (f) {
            const char *base = strrchr(f, '/');
            p = profile_by_flash_name(base ? base + 1 : f);
        }
    }
    if (!p)
        p = profile_by_name("sv25");
    set_defaults(cfg, p);
    if (path) {
        /* cfg_dir was set above; set_defaults cleared it, restore it. */
        const char *slash = strrchr(path, '/');
        if (slash) {
            size_t n = (size_t)(slash - path);
            if (n >= sizeof cfg->cfg_dir)
                n = sizeof cfg->cfg_dir - 1;
            memcpy(cfg->cfg_dir, path, n);
            cfg->cfg_dir[n] = '\0';
        }
        /* A file `profile` key different from the one used for defaults
         * (e.g. file says sv25 while env said another profile) re-resolves: the
         * file wins, so redo defaults from the file's profile. */
        const Profile *fp = NULL;
        if ((v = kv_get(&kv, "profile")))
            fp = profile_by_name(v);
        if (fp && fp != p) {
            set_defaults(cfg, fp);
            const char *slash2 = strrchr(path, '/');
            if (slash2) {
                size_t n = (size_t)(slash2 - path);
                if (n >= sizeof cfg->cfg_dir)
                    n = sizeof cfg->cfg_dir - 1;
                memcpy(cfg->cfg_dir, path, n);
                cfg->cfg_dir[n] = '\0';
            }
            p = fp;
        }
    }
    apply_file(cfg, &kv);
    apply_env(cfg, &kv);
    /* Warn on unknown keys (helps catch misspellings). */
    static const char *known[] = {
        "profile", "flash", "nvram", "dsp_base", "duration_seconds", "mode",
        "noise_amp", "link_slice", "link_mode", "line8k", "gate", "echo", "gain", "wav_rate",
        "wav", "log_dir", "setup_a", "setup_b", "phone", "send_text", "send_text_a",
        "send_file", "xint_mode", "cycle_model", "legacy", "tdm_irqs",
        "ac01_model", "sec_frame", "hb_timer", "dsp_clk_fixed", "port_rb",
        "int23", "ac01_filt", "ac01_lat", "cmd_ovr", "ac01_clamp", "p51div",
        "cpu_scale", "ud_trap", "delay_samples", "dial_dwell", "ring_on",
        "ring_period", "cpu_model", "cpu_hz", "dsp_hz", "patch_crc",
        "nvram_mode", "fax_patch", "cmpr", "tintslot", "inject_cmd", "inject_arg", "inject_at", "dsp_rom", "bankwr",
        "hw_idx", "voice_data_button", "boot_cycles", "setup_cycles",
        "xmd", "decode", NULL
    };
    for (int i = 0; i < kv.n; i++) {
        int ok = 0;
        for (int j = 0; known[j]; j++)
            if (strcmp(kv.kv[i].key, known[j]) == 0) { ok = 1; break; }
        if (!ok)
            fprintf(stderr, "config: unknown key '%s' ignored\n", kv.kv[i].key);
    }
    cfg->prof = p;
    return 0;
}
