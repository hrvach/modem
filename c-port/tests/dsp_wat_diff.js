// Replays cases from tests/dsp_wat_diff.c on the WAT core and compares results.
// Usage: ./tests/dsp_wat_diff 20000 | node tests/dsp_wat_diff.js lib/c5x_core.wasm
'use strict';
const fs = require('fs');

const SET = { acc: 0, preg: 1, t0: 2, t1: 3, t2: 4, dp: 5, sxm: 6, ovm: 7,
              c: 8, ov: 9, pm: 10, trm: 11, pc: 12,
              ar0: 20, arp: 28, indx: 29, arcr: 30, ndx: 31, cbcr: 32,
              cbsr1: 33, cber1: 34, cbsr2: 35, cber2: 36, arb: 37,
              sp: 38, tc: 39, bio: 40, stk0: 41, hm: 50, xf: 51, cnf: 52, accb: 53, intm: 54, rptc: 55, bmar: 58,
              braf: 59, pasr: 60, paer: 61, brcr: 62 };
const GET = { acc: 0, preg: 1, t0: 2, t1: 3, t2: 4, c: 8, ov: 9, pc: 12,
              ar0: 20, arp: 28, indx: 29, arcr: 30, arb: 37,
              sp: 38, tc: 39, stk0: 41, sxm: 6, ovm: 7, hm: 50, xf: 51, cnf: 52, accb: 53, intm: 54, rptc: 55, bmar: 58,
              braf: 59, pasr: 60, paer: 61, brcr: 62 };

const [wasmPath] = process.argv.slice(2);
if (!wasmPath) {
  console.error('usage: node tests/dsp_wat_diff.js <core.wasm> < cases.txt');
  process.exit(2);
}

WebAssembly.instantiate(fs.readFileSync(wasmPath)).then(({ instance }) => {
  const w = instance.exports;
  const lines = fs.readFileSync(0, 'utf8').split('\n').filter((l) => l.includes('|'));
  let bad = 0;

  for (const line of lines) {
    const [inS, outS] = line.split('|');
    const v = inS.trim().split(/\s+/).map(Number);
    const [op, dp, sxm, ovm, c, ov, pm, trm, acc, preg, t0, t1, t2, addr, d0, d1,
           arp, arb, indx, arcr, ndx, cbcr, cbsr1, cber1, cbsr2, cber2] = v;
    const ar = v.slice(26, 34);
    const [tc, bio, imm, hm, xf, accb, intm, budget, pm2, p0, bmarIn, pm3, brc] = v.slice(34, 47);
    const want = outS.trim().split(/\s+/).map(Number);

    w.set(SET.pc, 0);
    w.set(SET.hm, hm);
    w.set(SET.xf, xf);
    w.set(SET.cnf, 0);
    w.set(SET.accb, accb);
    w.set(SET.intm, intm);
    w.set(SET.rptc, 0);
    w.set(SET.bmar, bmarIn);
    w.pm_wr(imm, p0);
    w.pm_wr(2, pm2);
    w.pm_wr(3, pm3);
    w.set(SET.brcr, brc);
    w.set(SET.braf, 0);
    w.set(SET.tc, tc);
    w.set(SET.bio, bio);
    w.set(SET.sp, 0);
    for (let i = 0; i < 8; i++) w.set(SET.stk0 + i, 0);
    w.pm_wr(1, imm);
    w.set(SET.dp, dp);
    w.set(SET.sxm, sxm);
    w.set(SET.ovm, ovm);
    w.set(SET.c, c);
    w.set(SET.ov, ov);
    w.set(SET.pm, pm);
    w.set(SET.trm, trm);
    w.set(SET.acc, acc);
    w.set(SET.preg, preg);
    w.set(SET.t0, t0);
    w.set(SET.t1, t1);
    w.set(SET.t2, t2);
    w.set(SET.arp, arp);
    w.set(SET.arb, arb);
    w.set(SET.indx, indx);
    w.set(SET.arcr, arcr);
    w.set(SET.ndx, ndx);
    w.set(SET.cbcr, cbcr);
    w.set(SET.cbsr1, cbsr1);
    w.set(SET.cber1, cber1);
    w.set(SET.cbsr2, cbsr2);
    w.set(SET.cber2, cber2);
    ar.forEach((x, i) => w.set(SET.ar0 + i, x));
    w.dm_wr(addr, d0);
    w.dm_wr((addr + 1) & 0xffff, d1);
    w.pm_wr(0, op);

    const status = w.run(budget);
    const next = (addr + 1) & 0xffff;
    const got = [w.get(GET.acc), w.get(GET.preg), w.get(GET.t0), w.get(GET.t1),
                 w.get(GET.t2), w.get(GET.c), w.get(GET.ov), w.dm_rd(addr), w.dm_rd(next)];
    for (let i = 0; i < 8; i++) got.push(w.get(GET.ar0 + i));
    got.push(w.get(GET.arp), w.get(GET.arb), w.get(GET.indx), w.get(GET.arcr));
    got.push(w.get(GET.tc), w.get(GET.pc), w.get(GET.sp));
    for (let i = 0; i < 8; i++) got.push(w.get(GET.stk0 + i));
    got.push(w.get(GET.ovm), w.get(GET.sxm), w.get(GET.cnf), w.get(GET.hm), w.get(GET.xf), w.get(5), w.get(GET.accb), w.get(GET.intm), w.get(GET.rptc), w.get(GET.bmar));
    got.push(w.get(GET.braf), w.get(GET.pasr), w.get(GET.paer), w.get(GET.brcr));
    got.forEach((x, i) => { got[i] = x >>> 0; });
    const wantU = want.map((x) => x >>> 0);

    if (status !== 0 || got.some((v, i) => v !== wantU[i])) {
      if (bad < 5) {
        console.log(`MISMATCH status=${status} in: ${inS.trim()}`);
        console.log(`  want: ${wantU.join(' ')}`);
        console.log(`  got:  ${got.join(' ')}`);
      }
      bad++;
    }
  }

  console.log(`dsp_wat_diff: ${lines.length} cases, ${bad} mismatches`);
  process.exit(bad ? 1 : 0);
});
