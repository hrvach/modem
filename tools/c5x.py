"""TMS320C5x (C50/C51/C52...) disassembler -- Python port of MAME's tms320c5x_dasm.cpp
(license BSD-3-Clause, (c) Ville Linde). Words are 16-bit; fetch(addr)->int.
dis(fetch, pc) -> (length_in_words, text, info) where info is a dict with
  kind: None | 'jmp' | 'call' | 'cond' | 'ret' | 'ijmp' | 'icall'; target: int|None; delayed: bool
"""

ZL = ["", "gt", "neq", "gt", "", "lt", "neq", "lt", "", "gt", "eq", "geq", "", "lt", "eq", "leq"]
CV = ["", "nc", "nov", "nc nov", "", "c", "nov", "c nov", "", "nc", "ov", "nc ov", "", "c", "ov", "c ov"]
TP = ["bio", "tc", "ntc", ""]


def _ea(mode, a):
    if mode:
        n = a & 7
        m = (a >> 3) & 0xF
        base = {0x0: "*", 0x2: "*-", 0x4: "*+", 0x8: "*br0-", 0xA: "*0-", 0xC: "*0+", 0xE: "*br0+"}
        if m in base:
            return base[m]
        if (m & 1) and (m - 1) in base:
            return "%s, ar%d" % (base[m - 1], n)
        return "??? (indirect)"
    return "#%02X" % a


def _sh(s):
    return ", %d" % s if s > 0 else ""


def _cc(pp, zl, cv, tp):
    out = ""
    for s in (ZL[zl], CV[cv], TP[tp]):
        if s:
            out += (", " if pp else "") + s
            pp = True
    return out


_BE = {
    0x00: "abs", 0x01: "cmpl", 0x02: "neg", 0x03: "pac", 0x04: "apac", 0x05: "spac", 0x09: "sfl", 0x0A: "sfr",
    0x0C: "rol", 0x0D: "ror", 0x10: "addb", 0x11: "adcb", 0x12: "andb", 0x13: "orb", 0x14: "rolb", 0x15: "rorb",
    0x16: "sflb", 0x17: "sfrb", 0x18: "sbb", 0x19: "sbbb", 0x1A: "xorb", 0x1B: "crgt", 0x1C: "crlt", 0x1D: "exar",
    0x1E: "sacb", 0x1F: "lacb", 0x20: "bacc", 0x21: "baccd", 0x22: "idle", 0x23: "idle2", 0x30: "cala", 0x32: "pop",
    0x38: "reti", 0x3A: "rete", 0x3C: "push", 0x3D: "calad", 0x40: "clrc    intm", 0x41: "setc    intm",
    0x42: "clrc    ovm", 0x43: "setc    ovm", 0x44: "clrc    cnf", 0x45: "setc    cnf", 0x46: "clrc    sxm",
    0x47: "setc    sxm", 0x48: "clrc    hold", 0x49: "setc    hold", 0x4A: "clrc    tc", 0x4B: "setc    tc",
    0x4C: "clrc    xf", 0x4D: "setc    xf", 0x4E: "clrc    carry", 0x4F: "setc    carry", 0x51: "trap",
    0x52: "nmi", 0x58: "zpr", 0x59: "zap", 0x5A: "sath", 0x5B: "satl",
}


def dis(fetch, pc):
    npc = [pc]

    def F():
        v = fetch(npc[0]) & 0xFFFF
        npc[0] += 1
        return v

    info = {"kind": None, "target": None, "delayed": False}
    op = F()
    base = (op >> 8) & 0xFF
    mode = (op >> 7) & 1
    a = op & 0x7F
    E = lambda: _ea(mode, a)
    X = lambda: _ea(1, a)          # branch/call/banz always use indirect field
    t = None

    def br(name, kind, delayed=False):
        tgt = F()
        info.update(kind=kind, target=tgt, delayed=delayed)
        return "%-7s %04X, %s" % (name, tgt, X())

    def cond(op):
        zlm = op & 0xF
        zlcv = (op >> 4) & 0xF
        zl = (zlcv & 0xC) | ((zlm >> 2) & 3)
        cv = ((zlcv << 2) & 0xC) | (zlm & 3)
        tp = (op >> 8) & 3
        return zl, cv, tp

    if base <= 0x07:
        t = "lar     ar%d, %s" % (base & 7, E())
    elif base == 0x08: t = "lamm    " + E()
    elif base == 0x09: t = "smmr    %s, #%04X" % (E(), F())
    elif base == 0x0A: t = "subc    " + E()
    elif base == 0x0B: t = "rpt     " + E()
    elif base == 0x0C: t = "out     %s, #%04X" % (E(), F())
    elif base == 0x0D: t = "ldp     " + E()
    elif base == 0x0E: t = "lst     0, " + E()
    elif base == 0x0F: t = "lst     1, " + E()
    elif 0x10 <= base <= 0x1F: t = "lacc    %s %s" % (E(), _sh(base & 0xF))
    elif 0x20 <= base <= 0x2F: t = "add     %s %s" % (E(), _sh(base & 0xF))
    elif 0x30 <= base <= 0x3F: t = "sub     %s %s" % (E(), _sh(base & 0xF))
    elif 0x40 <= base <= 0x4F: t = "bit     %d, %s" % (base & 0xF, E())
    elif base in (0x50, 0x51, 0x52, 0x53, 0x54, 0x55, 0x57, 0x58, 0x59, 0x5A, 0x5B):
        t = "%-7s %s" % ({0x50: "mpya", 0x51: "mpys", 0x52: "sqra", 0x53: "sqrs", 0x54: "mpy", 0x55: "mpyu", 0x57: "bldp",
                          0x58: "xpl", 0x59: "opl", 0x5A: "apl", 0x5B: "cpl"}[base], E())
    elif base in (0x5C, 0x5D, 0x5E, 0x5F):
        t = "%-7s %s, #%04X" % ({0x5C: "xpl", 0x5D: "opl", 0x5E: "apl", 0x5F: "cpl"}[base], E(), F())
    elif 0x60 <= base <= 0x6F:
        n = {0x60: "addc", 0x61: "add", 0x62: "adds", 0x63: "addt", 0x64: "subb", 0x65: "sub", 0x66: "subs", 0x67: "subt",
             0x68: "zalr", 0x69: "lacl", 0x6A: "lacc", 0x6B: "lact", 0x6C: "xor", 0x6D: "or", 0x6E: "and", 0x6F: "bitt"}[base]
        t = "%-7s %s%s" % (n, E(), " << 16" if base in (0x61, 0x65, 0x6A) else "")
    elif 0x70 <= base <= 0x77:
        t = "%-7s %s" % ({0x70: "lta", 0x71: "ltp", 0x72: "ltd", 0x73: "lt", 0x74: "lts", 0x75: "lph", 0x76: "pshd", 0x77: "dmov"}[base], E())
    elif base == 0x78: t = "adrk    #%02X" % (op & 0xFF)
    elif base == 0x79: t = br("b", "jmp")
    elif base == 0x7A: t = br("call", "call")
    elif base == 0x7B: t = br("banz", "cond")
    elif base == 0x7C: t = "sbrk    #%02X" % (op & 0xFF)
    elif base == 0x7D: t = br("bd", "jmp", True)
    elif base == 0x7E: t = br("calld", "call", True)
    elif base == 0x7F: t = br("banzd", "cond", True)
    elif 0x80 <= base <= 0x87: t = "sar     ar%d, %s" % (base & 7, E())
    elif base == 0x88: t = "samm    " + E()
    elif base == 0x89: t = "lmmr    %s, #%04X" % (E(), F())
    elif base == 0x8A: t = "popd    " + E()
    elif base == 0x8B: t = "nop" if (op & 0xFF) == 0 else "mar     " + E()
    elif base == 0x8C: t = "spl     " + E()
    elif base == 0x8D: t = "sph     " + E()
    elif base == 0x8E: t = "sst     0, " + E()
    elif base == 0x8F: t = "sst     1, " + E()
    elif 0x90 <= base <= 0x97: t = "sacl    %s %s" % (E(), _sh(base & 7))
    elif 0x98 <= base <= 0x9F: t = "sach    %s %s" % (E(), _sh(base & 7))
    elif base == 0xA0: t = "norm    %s, #%04X" % (E(), F())
    elif base == 0xA2: t = "mac     %s, #%04X" % (E(), F())
    elif base == 0xA3: t = "macd    " + E()
    elif base == 0xA4: t = "blpd    " + E()
    elif base == 0xA5: t = "blpd    %s, #%04X" % (E(), F())
    elif base == 0xA6: t = "tblr    " + E()
    elif base == 0xA7: t = "tblw    " + E()
    elif base in (0xA8, 0xA9): t = "bldd    %s, #%04X" % (E(), F())
    elif base == 0xAA: t = "mads    " + E()
    elif base == 0xAB: t = "madd    " + E()
    elif base in (0xAC, 0xAD): t = "bldd    " + E()
    elif base == 0xAE: t = "splk    %s, #%04X" % (E(), F())
    elif base == 0xAF: t = "in      %s, #%04X" % (E(), F())
    elif 0xB0 <= base <= 0xB7: t = "lar     ar%d, #%02X" % (base & 7, op & 0xFF)
    elif base == 0xB8: t = "add     #%02X" % (op & 0xFF)
    elif base == 0xB9: t = "lacl    #%02X" % (op & 0xFF)
    elif base == 0xBA: t = "sub     #%02X" % (op & 0xFF)
    elif base == 0xBB: t = "rpt     #%02X" % (op & 0xFF)
    elif base in (0xBC, 0xBD): t = "ldp     #%03X" % (op & 0x1FF)
    elif base == 0xBE:
        s = op & 0xFF
        if s in _BE:
            t = _BE[s]
            if s in (0x20, 0x21, 0x30, 0x3D): info.update(kind="ijmp" if s in (0x20, 0x21) else "icall", delayed=s in (0x21, 0x3D))
            if s in (0x38, 0x3A): info["kind"] = "ret"
        elif 0x60 <= s <= 0x7F: t = "intr    %d" % (op & 0x1F)
        elif s == 0x80: t = "mpy     #%04X" % F()
        elif s == 0x81: t = "and     #%04X" % (F() << 16)
        elif s == 0x82: t = "or      #%04X" % (F() << 16)
        elif s == 0x83: t = "xor     #%04X" % (F() << 16)
        elif s == 0xC4: t = "rpt     #%04X" % F()
        elif s == 0xC5: t = "rptz    #%04X" % F()
        elif s == 0xC6: t = "rptb    #%04X" % F()
        else: t = "???     (group be)"
    elif base == 0xBF:
        sub = (op >> 4) & 0xF
        sh = op & 0xF
        if sub == 0:
            t = "lar     ar%d, #%04X" % (op & 7, F()) if op & 8 else "spm     #%02X" % (op & 3)
        elif sub == 4: t = "cmpr    " + ["ar = arcr", "ar < arcr", "ar > arcr", "ar != arcr"][op & 3]
        elif sub in (8, 9, 0xA, 0xB, 0xC, 0xD):
            t = "%-7s #%04X" % ({8: "lacc", 9: "add", 0xA: "sub", 0xB: "and", 0xC: "or", 0xD: "xor"}[sub], F() << sh)
        elif sub == 0xE: t = "bsar    %d" % (sh + 1)
        else: t = "???     (group bf)"
    elif 0xE0 <= base <= 0xE3 or 0xE8 <= base <= 0xEB or 0xF0 <= base <= 0xF3 or 0xF8 <= base <= 0xFB:
        zl, cv, tp = cond(op)
        n = {0xE0: ("bcnd", "cond", False), 0xE8: ("cc", "call", False), 0xF0: ("bcndd", "cond", True), 0xF8: ("ccd", "call", True)}[base & 0xF8]
        tgt = F()
        info.update(kind=n[1] if n[1] != "cond" else "cond", target=tgt, delayed=n[2])
        if n[1] == "call": info["kind"] = "ccall"
        t = "%-7s %04X%s" % (n[0], tgt, _cc(True, zl, cv, tp))
    elif base in (0xE4, 0xE5, 0xE6, 0xE7, 0xF4, 0xF5, 0xF6, 0xF7):
        zl, cv, tp = cond(op)
        t = "xc      %d%s" % (((op >> 12) & 1) + 1, _cc(True, zl, cv, tp))
    elif 0xEC <= base <= 0xEF or 0xFC <= base <= 0xFF:
        zl, cv, tp = cond(op)
        d = base >= 0xFC
        if op in (0xEF00, 0xFF00):
            t = "retd" if d else "ret"
            info.update(kind="ret", delayed=d)
        else:
            t = ("retcd   " if d else "retc    ") + _cc(False, zl, cv, tp)
            info.update(kind="cret", delayed=d)
    else:
        t = "???     ($%04X)" % op
    if info["kind"] == "jmp" and False: pass
    return npc[0] - pc, t, info
