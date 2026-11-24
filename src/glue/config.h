/* Configuration: profiles, call.conf parsing, override order.
 *
 * Override order (highest first), documented in README.md and call.conf:
 *   1. command-line options (--mode, --duration, --config, --out)
 *   2. call.conf keys
 *   3. environment variables (only for keys absent from call.conf)
 *   4. the selected profile's built-in defaults (profiles.py)
 *
 * So the config file is the source of truth; env vars are a fallback for
 * keys the file does not set, never a requirement. A key present in the
 * file always beats the same env var.
 *
 * Profiles are the per-firmware settings from modem/sys/profiles.py:
 * Profile: sv25 is the only one (see call.conf).
 */
#ifndef COURIER_CONFIG_H
#define COURIER_CONFIG_H

#include <stdint.h>

#define CFG_MAX_PATH 512
#define CFG_MAX_STR 1024

typedef struct {
    const char *key;
    const char *name;
    const char *flash; /* default flash path (relative to the c/ tree) */
    const char *nvram;
    long cpu_hz;
    long dsp_hz;
    const char *iface; /* "403" or "25" */
    int hw_idx;
} Profile;

const Profile *profile_by_name(const char *name);
const Profile *profile_by_flash_name(const char *flash_basename);

typedef struct {
    char profile[64];
    char flash[CFG_MAX_PATH];
    char nvram[CFG_MAX_PATH];
    char dsp_base[CFG_MAX_PATH]; /* informational: start_dsp uses the
                                    supervisor's captured bursts, not this
                                    file; kept so the image is on disk */
    double duration_seconds;
    char mode[32]; /* auto | v21 | v22 | echo | gate */
    int noise_amp;
    long link_slice;
    char link_mode[16]; /* slice | frame; slice = fixed-slice lockstep
                           (verified baseline, default); frame = one codec
                           sample frame per modem per pass, with a per-side
                           CPU/DSP clock tally + debt repayment (see link.h) */
    int line8k;
    int gate;
    double echo;
    double gain; /* line gain (link.py Link.gain; call_data.py GAIN env):
                    default 0.5 = the fable-progress §62/§64 operating point
                    that connects. 1.0 = zip default (verified baseline);
                    1.0 overloads the receiver (+6 dB net with codec gain)
                    and the handshake never starts (fable §31/§62). */
    int wav_rate;
    char wav_path[CFG_MAX_PATH];
    char log_dir[CFG_MAX_PATH];
    char setup_a[CFG_MAX_STR];
    char setup_b[CFG_MAX_STR];
    char phone[64];
    char send_text[CFG_MAX_STR];   /* caller (B) payload after its CONNECT */
    char send_text_a[CFG_MAX_STR]; /* answerer (A) payload after its CONNECT */
    char send_file[CFG_MAX_PATH];
    /* Experiment toggles machine.py read from env (see call.conf). */
    int xint_mode, cycle_model, legacy, tdm_irqs;
    int ac01_model, sec_frame, hb_timer, dsp_clk_fixed, port_rb, int23;
    int ac01_filt, ac01_lat;
    char cmd_ovr[CFG_MAX_STR];
    char ac01_clamp[CFG_MAX_STR];
    int p51div;
    double cpu_scale;
    int ud_trap;
    int delay_samples;
    double dial_dwell, ring_on, ring_period;
    int cpu_model;
    long cpu_hz, dsp_hz; /* 0 = take from profile */
    int patch_crc;       /* -1 = do not patch */
    int nvram_mode;      /* -1 = none (Link machines); else value for 0x5F1 */
    int fax_patch;
    int cmpr;
    int tintslot; /* -1 = unset */
    /* Test hook: post host->DSP command inject_cmd with argument inject_arg to
     * both modems at inject_at seconds. inject_cmd -1 = off (default). */
    int inject_cmd; int inject_arg; double inject_at;
    char dsp_rom[CFG_MAX_PATH];
    int bankwr;
    int hw_idx; /* -1 = take from profile */
    int voice_data_button;
    long boot_cycles;
    long setup_cycles;
    const Profile *prof; /* resolved profile (owned by the table) */
    char cfg_dir[CFG_MAX_PATH]; /* directory of the config file, or "" */
} Config;

/* Fill cfg with profile defaults (profile from env PROFILE / FLASH name,
 * else sv25), then apply the file at path (NULL = defaults only), then
 * env fallbacks for keys the file did not set. Returns 0 on success,
 * -1 on error (message in err, if non-NULL). */
int config_load(Config *cfg, const char *path, char *err, size_t errlen);

/* Resolve a possibly-relative path against the config file's directory.
 * Absolute paths pass through unchanged. */
void config_resolve(const Config *cfg, const char *path,
                    char *out, size_t outlen);

#endif
