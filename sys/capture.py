"""Run the emulated modem, issue a command, capture the DSP's DAC stream (DXR writes) as WAV (7200 Hz, mono, 16-bit)."""
import sys, wave, struct, math
sys.path.insert(0, '.')
from machine import *
def capture(cmd="ATA\r", seconds=3.0, fs=7200, wait_cmd=0x12, wav=None, nvram_mode=None):
    m = Machine(nvram_mode=nvram_mode); cpu = m.cpu; m.logging = False
    m.run(900_000_000); n0 = len(m.cmd_log)
    m.send(cmd)
    if wait_cmd is not None:
        while not any(a == wait_cmd for c, a, b in m.cmd_log[n0:]): m.run(5_000_000)
    m.dsp.log(True); m.dsp.log_clear()
    need = int(seconds * fs); got = []
    while len(got) < need:
        m.run(20_000_000)
        ev = m.dsp.events(); got += [v for _, _, p, v, w in ev if p == 0x8021]; m.dsp.log_clear()
    s = [(v - 65536 if v > 32767 else v) for v in got[:need]]
    if wav:
        with wave.open(wav, 'wb') as w:
            w.setnchannels(1); w.setsampwidth(2); w.setframerate(fs); w.writeframes(struct.pack('<%dh' % len(s), *s))
    return m, s
if __name__ == "__main__":
    m, s = capture(seconds=float(sys.argv[1]) if len(sys.argv) > 1 else 3.0, wav='../out/ata_dxr.wav')
    print(len(s), "samples; peak", max(map(abs, s)))
