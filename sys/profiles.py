"""Per-firmware profiles: everything that belongs to one firmware image / board rather than to the emulator.
Default profile: id20_403 = USRobotics Courier V.Everything (external, HST / V.32bis / x2 / V.90), supervisor 7.4.16 (04/30/98),
DSP 3.1.2 (09/09/98), the community 'ID_SDL v4.03d 24/01/00' build (ATI7: 'Russia (ex. US/Canada) External', clock 20.16 MHz, 512k flash, 64k RAM).
PROFILE=<name> selects another one; FLASH=<path> alone picks a profile from the file name. Environment variables (CPU_HZ, DSP_HZ, IFACE, NVRAM, ...) still override single values."""
import os
_HERE = os.path.dirname(os.path.abspath(__file__)); _ROOT = os.path.join(_HERE, '..')
PROFILES = {
    'id20_403': dict(
        name='USRobotics Courier V.Everything, supervisor 7.4.16 / DSP 3.1.2 (ID_SDL v4.03d)',
        flash=os.path.join(_ROOT, 'fw', 'decoded', 'ID20_403.flash.bin'), nvram=os.path.join(_HERE, 'nvram_ID20_403.bin'),
        cpu_hz=20160000,            # 40.32 MHz board oscillator / 2 (80C186); ATI7 'Clock Freq 20.16Mhz'
        dsp_hz=40320000,            # fixed DSP clock (CLKIN from the ASIC); CLKMD straps not read, see fable-progress.md section 42
        iface='403',                # CPU side of the DSP mailbox as on this supervisor (courier-emu docs/dsp-cpu-link.md)
        sender_scan=True,           # find the DSP message sender's OUT 005E/005F in the loaded image
        dsp_base_bytes=None,        # resident bank: 28327 words, take whatever the supervisor sends
        isr_presets=None,           # the DSP firmware clears and installs its own interrupt pointer table (data 0x60-0x7F)
        int0_unset=((0, 0),),       # IVT INT0 (0x30/0x32) values that mean 'handler not installed yet'
        hw_idx=7,                   # board strap scan answer: not verified for this supervisor
        match=('ID20', 'ID25', 'V90XX', 'IDSDL')),
    'sv20': dict(
        name='USRobotics Courier V.Everything, US/Canada external, supervisor 7.2.4 (10/01/97) / DSP 2.2.7 (06/06/97), options HST V32bis x2 (ATI7)',
        flash=os.path.join(_ROOT, 'fw', 'decoded', 'SV20.flash.bin'), nvram=os.path.join(_HERE, 'nvram_SV20.bin'),
        cpu_hz=20160000,            # ATI7 'Clock Freq 20.16Mhz'
        dsp_hz=40320000,            # same board family: 40.32 MHz oscillator, DSP clock fixed
        iface='403', sender_scan=True, dsp_base_bytes=None, isr_presets=None, int0_unset=((0, 0),), hw_idx=7,
        match=('SV20',)),
    'sv25': dict(
        name='previous image (SV25)',
        flash=os.path.join(_ROOT, 'SV25.flash.bin'), nvram=os.path.join(_HERE, 'nvram.bin'),
        cpu_hz=25804800, dsp_hz=40320000, iface='25', sender_scan=False, dsp_base_bytes=55420,
        isr_presets={'all': 0x81AE, 0x65: 0x8189, 0x68: 0x820C, 0x69: 0x81B7}, int0_unset=((0, 0x305), (0, 0)), hw_idx=7, match=('SV25',)),
}
def current():
    name = os.environ.get('PROFILE')
    if not name:
        f = os.path.basename(os.environ.get('FLASH', '')).upper()
        name = next((k for k, v in PROFILES.items() if f and f.startswith(v.get('match', ()))), 'id20_403')
    p = dict(PROFILES[name]); p['key'] = name
    return p
