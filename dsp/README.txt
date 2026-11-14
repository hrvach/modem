DSP (TMS320C51) program images extracted from SV25.flash.bin.
Loader: 80186 code at flash 0xE4AB (full load, ctrl port 0x18) and 0xE60A/0xE61B (overlay load, ctrl port 0x1E);
data via ports 0x40..0x4E (low byte, high byte, 4 words per burst). Overlay table: cs:0xE741, 6-byte records (start,end,arg).
Words are little-endian in flash. 'arg' is believed to be the DSP program-memory load address.
dsp_base.bin flash 0x296E0 len 0xD87C load 0x8000
dsp_ov6.bin  flash 0x36F60 len 0x59EC load 0x9D00 (mode 6)
dsp_ov7.bin  flash 0x3C950 len 0x3A96 load 0xB000 (mode 7)
dsp_ov8.bin  flash 0x403F0 len 0x396C load 0xDC00 (mode 8)
