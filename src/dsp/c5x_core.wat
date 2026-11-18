;; TMS320C5x core in WAT, v1.
;;
;; Scope: direct-addressed LACC/ADD/SUB (with shift), ADDS, SUBS, LACL, LT,
;; MPY, MPYA, SACL, SACH.  step() returns 2 for indirect addressing and 3 for
;; any other opcode, leaving state untouched.  Semantics mirror
;; src/dsp/c5x_core.c; the cycle model and interrupts are not implemented.
;;
;; Memory: data RAM as u16 words at byte 0 (addr * 2); program RAM at byte 131072.
(module
  (memory (export "mem") 8)

  (global $acc (mut i32) (i32.const 0))
  (global $preg (mut i32) (i32.const 0))
  (global $t0 (mut i32) (i32.const 0))
  (global $t1 (mut i32) (i32.const 0))
  (global $t2 (mut i32) (i32.const 0))
  (global $pc (mut i32) (i32.const 0))
  (global $dp (mut i32) (i32.const 0))
  (global $sxm (mut i32) (i32.const 0))
  (global $ovm (mut i32) (i32.const 0))
  (global $c (mut i32) (i32.const 0))
  (global $ov (mut i32) (i32.const 0))
  (global $pm (mut i32) (i32.const 0))
  (global $trm (mut i32) (i32.const 0))
  (global $cnf (mut i32) (i32.const 0))
  (global $ovly (mut i32) (i32.const 0))
  (global $arp (mut i32) (i32.const 0))
  (global $arb (mut i32) (i32.const 0))
  (global $indx (mut i32) (i32.const 0))
  (global $arcr (mut i32) (i32.const 0))
  (global $ndx (mut i32) (i32.const 0))
  (global $cbcr (mut i32) (i32.const 0))
  (global $cbsr1 (mut i32) (i32.const 0))
  (global $cber1 (mut i32) (i32.const 0))
  (global $cbsr2 (mut i32) (i32.const 0))
  (global $cber2 (mut i32) (i32.const 0))
  (global $ar0dirty (mut i32) (i32.const 0))
  (global $sp (mut i32) (i32.const 0))
  (global $tc (mut i32) (i32.const 0))
  (global $bio (mut i32) (i32.const 0))
  (global $hm (mut i32) (i32.const 0))
  (global $xf (mut i32) (i32.const 0))
  (global $accb (mut i32) (i32.const 0))
  (global $intm (mut i32) (i32.const 0))
  (global $rptc (mut i32) (i32.const 0))
  (global $rpt_start (mut i32) (i32.const 0))
  (global $rpt_end (mut i32) (i32.const 0))
  (global $bmar (mut i32) (i32.const 0))
  (global $braf (mut i32) (i32.const 0))
  (global $pasr (mut i32) (i32.const 0))
  (global $paer (mut i32) (i32.const 0))
  (global $brcr (mut i32) (i32.const 0))
  (global $iptr (mut i32) (i32.const 0))
  (global $avis (mut i32) (i32.const 0))
  (global $ram (mut i32) (i32.const 0))
  (global $mpmc (mut i32) (i32.const 0))

  (func $dm_rd (param $a i32) (result i32)
    (i32.load16_u (i32.shl (local.get $a) (i32.const 1))))

  (func $dm_wr (param $a i32) (param $d i32)
    (i32.store16 (i32.shl (local.get $a) (i32.const 1)) (local.get $d)))

  (func $pm_rd (param $a i32) (result i32)
    (i32.load16_u offset=131072 (i32.shl (local.get $a) (i32.const 1))))

  ;; Data -> ACC with shift, honouring SXM.
  (func $ext (param $d i32) (param $sh i32) (result i32)
    (if (result i32) (global.get $sxm)
      (then (i32.shl (i32.extend16_s (local.get $d)) (local.get $sh)))
      (else (i32.shl (i32.and (local.get $d) (i32.const 0xffff)) (local.get $sh)))))

  ;; 32-bit add; sets C (carry) and OV, saturates when OVM is set.
  (func $add (param $a i32) (param $b i32) (result i32)
    (local $r i64) (local $res i32)
    (local.set $r (i64.add (i64.extend_i32_u (local.get $a)) (i64.extend_i32_u (local.get $b))))
    (local.set $res (i32.wrap_i64 (local.get $r)))
    (global.set $c (i32.and (i32.wrap_i64 (i64.shr_u (local.get $r) (i64.const 32))) (i32.const 1)))
    (if (i32.and
          (i32.and (i32.xor (local.get $a) (local.get $res)) (i32.xor (local.get $b) (local.get $res)))
          (i32.const 0x80000000))
      (then
        (global.set $ov (i32.const 1))
        (if (global.get $ovm)
          (then
            (local.set $res
              (select (i32.const 0x7fffffff) (i32.const 0x80000000)
                      (i32.lt_s (local.get $res) (i32.const 0))))))))
    (local.get $res))

  ;; 32-bit subtract; C is set to NOT borrow, OV as for add.
  (func $sub (param $a i32) (param $b i32) (result i32)
    (local $r i64) (local $res i32)
    (local.set $r (i64.sub (i64.extend_i32_u (local.get $a)) (i64.extend_i32_u (local.get $b))))
    (local.set $res (i32.wrap_i64 (local.get $r)))
    (global.set $c (i32.xor
                     (i32.and (i32.wrap_i64 (i64.shr_u (local.get $r) (i64.const 32))) (i32.const 1))
                     (i32.const 1)))
    (if (i32.and
          (i32.and (i32.xor (local.get $a) (local.get $b)) (i32.xor (local.get $a) (local.get $res)))
          (i32.const 0x80000000))
      (then
        (global.set $ov (i32.const 1))
        (if (global.get $ovm)
          (then
            (local.set $res
              (select (i32.const 0x7fffffff) (i32.const 0x80000000)
                      (i32.lt_s (local.get $res) (i32.const 0))))))))
    (local.get $res))

  ;; PREG scaled by PM: 0 = none, 1 = <<1, 2 = <<4, 3 = >>6 (arithmetic).
  (func $pscale (result i32)
    (local $p i32) (local $m i32)
    (local.set $p (global.get $preg))
    (local.set $m (i32.and (global.get $pm) (i32.const 3)))
    (if (result i32) (i32.eqz (local.get $m))
      (then (local.get $p))
      (else
        (if (result i32) (i32.eq (local.get $m) (i32.const 1))
          (then (i32.shl (local.get $p) (i32.const 1)))
          (else
            (if (result i32) (i32.eq (local.get $m) (i32.const 2))
              (then (i32.shl (local.get $p) (i32.const 4)))
              (else (i32.shr_s (local.get $p) (i32.const 6)))))))))

  ;; Load TREG0; unless TRM is set, TREG1/TREG2 mirror its low bits.
  (func $set_t0 (param $d i32)
    (global.set $t0 (local.get $d))
    (if (i32.eqz (global.get $trm))
      (then
        (global.set $t1 (i32.and (local.get $d) (i32.const 0x1f)))
        (global.set $t2 (i32.and (local.get $d) (i32.const 0xf))))))

  (func $supported (param $hi i32) (result i32)
    (i32.or
      (i32.or
        (i32.and (i32.ge_u (local.get $hi) (i32.const 0x10)) (i32.le_u (local.get $hi) (i32.const 0x3f)))
        (i32.and (i32.ge_u (local.get $hi) (i32.const 0x50)) (i32.le_u (local.get $hi) (i32.const 0x55))))
      (i32.or
        (i32.or
          (i32.and (i32.ge_u (local.get $hi) (i32.const 0x40)) (i32.le_u (local.get $hi) (i32.const 0x4f)))
          (i32.and (i32.ge_u (local.get $hi) (i32.const 0x60)) (i32.le_u (local.get $hi) (i32.const 0x6f))))
        (i32.or
          (i32.and (i32.ge_u (local.get $hi) (i32.const 0x70)) (i32.le_u (local.get $hi) (i32.const 0x74)))
          (i32.or
            (i32.or (i32.eq (local.get $hi) (i32.const 0x77))
                    (i32.or (i32.eq (local.get $hi) (i32.const 0x8c)) (i32.eq (local.get $hi) (i32.const 0x8d))))
            (i32.or
              (i32.and (i32.ge_u (local.get $hi) (i32.const 0x79)) (i32.le_u (local.get $hi) (i32.const 0x7c)))
              (i32.or
                (i32.and (i32.ge_u (local.get $hi) (i32.const 0x90)) (i32.le_u (local.get $hi) (i32.const 0x9f)))
                (i32.or
                  (i32.and (i32.ge_u (local.get $hi) (i32.const 0xe0)) (i32.le_u (local.get $hi) (i32.const 0xe3)))
                  (i32.or
                    (i32.and (i32.ge_u (local.get $hi) (i32.const 0xe8)) (i32.le_u (local.get $hi) (i32.const 0xef)))
                    (i32.eq (local.get $hi) (i32.const 0xbe)))))))))))

  ;; Add with carry-in; s16=1 is the 16-bit form (carry sets C, never clears it).
  (func $addx (param $a i32) (param $b i32) (param $cin i32) (param $s16 i32) (result i32)
    (local $r i64) (local $res i32) (local $carry i32)
    (local.set $r (i64.add (i64.add (i64.extend_i32_u (local.get $a))
                                    (i64.extend_i32_u (local.get $b)))
                           (i64.extend_i32_u (local.get $cin))))
    (local.set $res (i32.wrap_i64 (local.get $r)))
    (local.set $carry (i32.and (i32.wrap_i64 (i64.shr_u (local.get $r) (i64.const 32))) (i32.const 1)))
    (if (local.get $s16)
      (then (if (local.get $carry) (then (global.set $c (i32.const 1)))))
      (else (global.set $c (local.get $carry))))
    (if (i32.and
          (i32.and (i32.xor (local.get $a) (local.get $res)) (i32.xor (local.get $b) (local.get $res)))
          (i32.const 0x80000000))
      (then
        (global.set $ov (i32.const 1))
        (if (global.get $ovm)
          (then
            (local.set $res
              (select (i32.const 0x7fffffff) (i32.const 0x80000000)
                      (i32.lt_s (local.get $res) (i32.const 0))))))))
    (local.get $res))

  ;; Subtract with borrow-in; s16=1 is the 16-bit form (borrow clears C).
  (func $subx (param $a i32) (param $b i32) (param $bin i32) (param $s16 i32) (result i32)
    (local $r i64) (local $res i32) (local $borrow i32)
    (local.set $r (i64.sub (i64.sub (i64.extend_i32_u (local.get $a))
                                    (i64.extend_i32_u (local.get $b)))
                           (i64.extend_i32_u (local.get $bin))))
    (local.set $res (i32.wrap_i64 (local.get $r)))
    (local.set $borrow (i32.and (i32.wrap_i64 (i64.shr_u (local.get $r) (i64.const 32))) (i32.const 1)))
    (if (local.get $s16)
      (then (if (local.get $borrow) (then (global.set $c (i32.const 0)))))
      (else (global.set $c (i32.xor (local.get $borrow) (i32.const 1)))))
    (if (i32.and
          (i32.and (i32.xor (local.get $a) (local.get $b)) (i32.xor (local.get $a) (local.get $res)))
          (i32.const 0x80000000))
      (then
        (global.set $ov (i32.const 1))
        (if (global.get $ovm)
          (then
            (local.set $res
              (select (i32.const 0x7fffffff) (i32.const 0x80000000)
                      (i32.lt_s (local.get $res) (i32.const 0))))))))
    (local.get $res))

  ;; Internal data RAM (manual ch. 8): B2 0x00-0x7F, B0/B1 0x100-0x4FF
  ;; (B0 excluded when CNF=1 below 0x300), SARAM 0x800-0xBFF when OVLY=1.
  (func $internal (param $a i32) (result i32)
    (i32.or
      (i32.or
        (i32.lt_u (local.get $a) (i32.const 0x80))
        (i32.and
          (i32.and (i32.ge_u (local.get $a) (i32.const 0x100)) (i32.lt_u (local.get $a) (i32.const 0x500)))
          (i32.eqz (i32.and (global.get $cnf) (i32.lt_u (local.get $a) (i32.const 0x300))))))
      (i32.and (global.get $ovly)
               (i32.and (i32.ge_u (local.get $a) (i32.const 0x800)) (i32.lt_u (local.get $a) (i32.const 0xc00))))))

  ;; AR file: AR0..AR7 as i32 words at byte 262144 (just past program RAM).
  (func $ar_get (param $i i32) (result i32)
    (i32.load (i32.add (i32.const 262144) (i32.shl (local.get $i) (i32.const 2)))))

  (func $ar_set (param $i i32) (param $v i32)
    (i32.store (i32.add (i32.const 262144) (i32.shl (local.get $i) (i32.const 2)))
               (i32.and (local.get $v) (i32.const 0xffff))))

  (func $bitrev16 (param $v i32) (result i32)
    (local $r i32) (local $i i32)
    (block $done
      (loop $next
        (br_if $done (i32.ge_u (local.get $i) (i32.const 16)))
        (if (i32.and (i32.shr_u (local.get $v) (local.get $i)) (i32.const 1))
          (then (local.set $r (i32.or (local.get $r)
                                      (i32.shl (i32.const 1) (i32.sub (i32.const 15) (local.get $i)))))))
        (local.set $i (i32.add (local.get $i) (i32.const 1)))
        (br $next)))
    (local.get $r))

  ;; ARn += step, wrapping to the block start at the block end when
  ;; circular addressing is enabled for that AR (bank 1 wins over bank 2).
  (func $upd_ar (param $ar i32) (param $step i32)
    (local $v i32) (local $cb1 i32) (local $ca1 i32) (local $cb2 i32) (local $ca2 i32)
    (if (i32.eqz (local.get $ar)) (then (global.set $ar0dirty (i32.const 1))))
    (local.set $v (call $ar_get (local.get $ar)))
    (local.set $cb1 (i32.and (i32.shr_u (global.get $cbcr) (i32.const 3)) (i32.const 1)))
    (local.set $ca1 (i32.and (global.get $cbcr) (i32.const 7)))
    (local.set $cb2 (i32.and (i32.shr_u (global.get $cbcr) (i32.const 7)) (i32.const 1)))
    (local.set $ca2 (i32.and (i32.shr_u (global.get $cbcr) (i32.const 4)) (i32.const 7)))
    (if (i32.and (local.get $cb1) (i32.eq (local.get $ar) (local.get $ca1)))
      (then
        (call $ar_set (local.get $ar)
          (if (result i32) (i32.eq (local.get $v) (global.get $cber1))
            (then (global.get $cbsr1))
            (else (i32.add (local.get $v) (local.get $step))))))
      (else
        (if (i32.and (local.get $cb2) (i32.eq (local.get $ar) (local.get $ca2)))
          (then
            (call $ar_set (local.get $ar)
              (if (result i32) (i32.eq (local.get $v) (global.get $cber2))
                (then (global.get $cbsr2))
                (else (i32.add (local.get $v) (local.get $step))))))
          (else
            (call $ar_set (local.get $ar) (i32.add (local.get $v) (local.get $step))))))))

  ;; Circular-buffer end test: block start if ARn has reached its block end, else -1.
  (func $circ_end (param $ar i32) (param $v i32) (result i32)
    (local $cb1 i32) (local $ca1 i32) (local $cb2 i32) (local $ca2 i32)
    (local $c1 i32) (local $c2 i32)
    (local.set $cb1 (i32.and (i32.shr_u (global.get $cbcr) (i32.const 3)) (i32.const 1)))
    (local.set $ca1 (i32.and (global.get $cbcr) (i32.const 7)))
    (local.set $cb2 (i32.and (i32.shr_u (global.get $cbcr) (i32.const 7)) (i32.const 1)))
    (local.set $ca2 (i32.and (i32.shr_u (global.get $cbcr) (i32.const 4)) (i32.const 7)))
    (local.set $c1 (i32.and (local.get $cb1) (i32.eq (local.get $ar) (local.get $ca1))))
    (local.set $c2 (i32.and (local.get $cb2) (i32.eq (local.get $ar) (local.get $ca2))))
    (if (local.get $c1)
      (then (if (i32.eq (local.get $v) (global.get $cber1)) (then (return (global.get $cbsr1))))))
    (if (i32.and (i32.eqz (local.get $c1))
                 (i32.and (local.get $c2) (i32.eq (local.get $v) (global.get $cber2))))
      (then (return (global.get $cbsr2))))
    (i32.const -1))

  ;; Indirect effective address (manual 5.2).  Returns AR[ARP] before the
  ;; modification; applies the modification and the ARP switch (bit 0).
  ;; Caller has already rejected modes 6/7 (see step).
  (func $ea_ind (param $op i32) (result i32)
    (local $arp i32) (local $k i32) (local $a i32) (local $st i32) (local $nv i32)
    (local.set $arp (global.get $arp))
    (local.set $a (call $ar_get (local.get $arp)))
    (local.set $k (i32.and (i32.shr_u (local.get $op) (i32.const 3)) (i32.const 0xe)))
    (if (i32.eq (local.get $k) (i32.const 2)) (then (call $upd_ar (local.get $arp) (i32.const -1))))
    (if (i32.eq (local.get $k) (i32.const 4)) (then (call $upd_ar (local.get $arp) (i32.const 1))))
    (if (i32.eq (local.get $k) (i32.const 0xa))
      (then (call $upd_ar (local.get $arp) (i32.sub (i32.const 0) (i32.extend16_s (global.get $indx))))))
    (if (i32.eq (local.get $k) (i32.const 0xc))
      (then (call $upd_ar (local.get $arp) (i32.extend16_s (global.get $indx)))))
    (if (i32.or (i32.eq (local.get $k) (i32.const 8)) (i32.eq (local.get $k) (i32.const 0xe)))
      (then
        (local.set $st (call $circ_end (local.get $arp) (local.get $a)))
        (call $ar_set (local.get $arp)
          (if (result i32) (i32.ge_s (local.get $st) (i32.const 0))
            (then (local.get $st))
            (else
              (call $bitrev16
                (i32.and
                  (if (result i32) (i32.eq (local.get $k) (i32.const 8))
                    (then (i32.sub (call $bitrev16 (local.get $a)) (call $bitrev16 (global.get $indx))))
                    (else (i32.add (call $bitrev16 (local.get $a)) (call $bitrev16 (global.get $indx)))))
                  (i32.const 0xffff))))))
        (if (i32.eqz (local.get $arp)) (then (global.set $ar0dirty (i32.const 1))))))
    (if (i32.and (i32.shr_u (local.get $op) (i32.const 3)) (i32.const 1))
      (then
        (global.set $arb (local.get $arp))
        (global.set $arp (i32.and (local.get $op) (i32.const 7)))))
    (local.get $a))

  ;; Hardware stack: 8 words at byte 262176 (just past the AR file).
  (func $st_get (param $i i32) (result i32)
    (i32.load (i32.add (i32.const 262176) (i32.shl (local.get $i) (i32.const 2)))))

  (func $st_set (param $i i32) (param $v i32)
    (i32.store (i32.add (i32.const 262176) (i32.shl (local.get $i) (i32.const 2)))
               (i32.and (local.get $v) (i32.const 0xffff))))

  (func $push (param $v i32)
    (global.set $sp (i32.and (i32.sub (global.get $sp) (i32.const 1)) (i32.const 7)))
    (call $st_set (global.get $sp) (local.get $v)))

  ;; Pop with the original's quirk: the vacated slot receives the new
  ;; second-from-top entry (C pop(), orig L219).
  (func $pop (result i32) (local $v i32)
    (local.set $v (call $st_get (global.get $sp)))
    (global.set $sp (i32.and (i32.add (global.get $sp) (i32.const 1)) (i32.const 7)))
    (call $st_set (i32.and (i32.add (global.get $sp) (i32.const 7)) (i32.const 7))
                  (call $st_get (i32.and (i32.add (global.get $sp) (i32.const 6)) (i32.const 7))))
    (local.get $v))

  ;; ZLVC / TP branch condition (C zlvc_cond + tp_cond).
  (func $cond (param $op i32) (result i32)
    (local $zlvc i32) (local $mask i32) (local $k i32) (local $t i32) (local $r i32)
    (local.set $zlvc (i32.and (i32.shr_u (local.get $op) (i32.const 4)) (i32.const 0xf)))
    (local.set $mask (i32.and (local.get $op) (i32.const 0xf)))
    (if (i32.ne (i32.and (local.get $mask) (i32.const 2)) (i32.const 0))
      (then
        (if (i32.ne (i32.and (local.get $zlvc) (i32.const 2)) (i32.const 0))
          (then (if (i32.eqz (global.get $ov)) (then (return (i32.const 0))))))
        (if (i32.eqz (i32.and (local.get $zlvc) (i32.const 2)))
          (then (if (global.get $ov) (then (return (i32.const 0))))))))
    (if (i32.ne (i32.and (local.get $mask) (i32.const 1)) (i32.const 0))
      (then
        (if (i32.ne (i32.and (local.get $zlvc) (i32.const 1)) (i32.const 0))
          (then (if (i32.eqz (global.get $c)) (then (return (i32.const 0))))))
        (if (i32.eqz (i32.and (local.get $zlvc) (i32.const 1)))
          (then (if (global.get $c) (then (return (i32.const 0))))))))
    (local.set $k (i32.or (i32.and (local.get $mask) (i32.const 0xc))
                          (i32.and (i32.shr_u (local.get $zlvc) (i32.const 2)) (i32.const 3))))
    (local.set $r (i32.const 1))
    (if (i32.or (i32.or (i32.eq (local.get $k) (i32.const 4)) (i32.eq (local.get $k) (i32.const 6)))
                (i32.eq (local.get $k) (i32.const 12)))
      (then (local.set $r (i32.gt_s (global.get $acc) (i32.const 0)))))
    (if (i32.or (i32.or (i32.eq (local.get $k) (i32.const 5)) (i32.eq (local.get $k) (i32.const 7)))
                (i32.eq (local.get $k) (i32.const 13)))
      (then (local.set $r (i32.lt_s (global.get $acc) (i32.const 0)))))
    (if (i32.or (i32.eq (local.get $k) (i32.const 8)) (i32.eq (local.get $k) (i32.const 9)))
      (then (local.set $r (i32.ne (global.get $acc) (i32.const 0)))))
    (if (i32.or (i32.eq (local.get $k) (i32.const 10)) (i32.eq (local.get $k) (i32.const 11)))
      (then (local.set $r (i32.eq (global.get $acc) (i32.const 0)))))
    (if (i32.eq (local.get $k) (i32.const 14))
      (then (local.set $r (i32.ge_s (global.get $acc) (i32.const 0)))))
    (if (i32.eq (local.get $k) (i32.const 15))
      (then (local.set $r (i32.le_s (global.get $acc) (i32.const 0)))))
    (local.set $t (i32.and (i32.shr_u (local.get $op) (i32.const 8)) (i32.const 3)))
    (if (i32.eqz (local.get $t))
      (then (local.set $r (i32.and (local.get $r) (i32.eqz (global.get $bio))))))
    (if (i32.eq (local.get $t) (i32.const 1))
      (then (local.set $r (i32.and (local.get $r) (global.get $tc)))))
    (if (i32.eq (local.get $t) (i32.const 2))
      (then (local.set $r (i32.and (local.get $r) (i32.eqz (global.get $tc))))))
    (local.get $r))

  ;; 0xBE single-word control ops (low byte 0x20..0x5B and 0x80..0x83 handled).
  ;; Valid 0xBE low bytes (1 = implemented), at byte 262400.
  (data (i32.const 262400) "\01\01\01\01\01\01\00\00\00\01\01\00\01\01\00\00\01\01\01\01\01\01\01\01\01\01\01\01\01\01\01\01\01\01\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01\00\01\00\00\00\00\00\01\00\01\00\01\01\00\00\01\01\01\01\01\01\01\01\01\01\01\01\01\01\01\01\00\00\00\00\00\00\00\00\01\01\01\01\00\00\00\00\01\01\01\01\01\01\01\01\01\01\01\01\01\01\01\01\01\01\01\01\01\01\01\01\01\01\01\01\01\01\01\01\01\01\01\01\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01\01\01\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00")

  (func $be_ok (param $low i32) (result i32)
    (i32.load8_u (i32.add (i32.const 262400) (i32.and (local.get $low) (i32.const 0xff)))))

  ;; Fetch the word after the opcode (PC already at it); advances PC.
  (func $fetch_imm (result i32) (local $v i32)
    (local.set $v (call $pm_rd (global.get $pc)))
    (global.set $pc (i32.and (i32.add (global.get $pc) (i32.const 1)) (i32.const 0xffff)))
    (local.get $v))

  (func $be_ctrl (param $op i32) (local $low i32) (local $imm i32) (local $t i32)
    (local.set $low (i32.and (local.get $op) (i32.const 0xff)))
    (if (i32.lt_u (local.get $low) (i32.const 0x20))
      (then (call $be_acc (local.get $low)) (return)))
    (if (i32.eq (local.get $low) (i32.const 0xc6))
      (then
        (local.set $imm (call $fetch_imm))
        (global.set $braf (i32.const 1))
        (global.set $pasr (global.get $pc))
        (global.set $paer (local.get $imm))))
    (if (i32.eq (local.get $low) (i32.const 0xc4))
      (then
        (local.set $imm (call $fetch_imm))
        (global.set $rptc (local.get $imm))
        (global.set $rpt_start (global.get $pc))
        (global.set $rpt_end (global.get $pc))))
    (if (i32.eq (local.get $low) (i32.const 0xc5))
      (then
        (local.set $imm (call $fetch_imm))
        (global.set $rptc (local.get $imm))
        (global.set $rpt_start (global.get $pc))
        (global.set $rpt_end (global.get $pc))
        (global.set $acc (i32.const 0))
        (global.set $preg (i32.const 0))))

    (if (i32.eq (local.get $low) (i32.const 0x20))
      (then (global.set $pc (i32.and (global.get $acc) (i32.const 0xffff)))))
    (if (i32.and (i32.ge_u (local.get $low) (i32.const 0x60)) (i32.le_u (local.get $low) (i32.const 0x7f)))
      (then
        ;; INTR k: push PC, INTM=1, vector = IPTR:2k; save context for vectors 2,4,6,18.
        (local.set $t (i32.shl (i32.and (local.get $low) (i32.const 0x1f)) (i32.const 1)))
        (call $push (global.get $pc))
        (global.set $intm (i32.const 1))
        (global.set $pc (i32.and (i32.or (i32.shl (global.get $iptr) (i32.const 11)) (local.get $t)) (i32.const 0xffff)))
        (if (i32.or (i32.or (i32.eq (local.get $t) (i32.const 2)) (i32.eq (local.get $t) (i32.const 4)))
                    (i32.or (i32.eq (local.get $t) (i32.const 6)) (i32.eq (local.get $t) (i32.const 0x12))))
          (then (call $save_ctx)))))
    ;; RETI / RETE: return from interrupt with context restore (RETE also clears INTM).
    (if (i32.eq (local.get $low) (i32.const 0x38))
      (then
        (global.set $pc (call $pop))
        (call $restore_ctx)))
    (if (i32.eq (local.get $low) (i32.const 0x3a))
      (then
        (global.set $pc (call $pop))
        (call $restore_ctx)
        (global.set $intm (i32.const 0))))
    (if (i32.eq (local.get $low) (i32.const 0x21))
      (then
        (local.set $t (i32.and (global.get $acc) (i32.const 0xffff)))
        (call $delay_slot (global.get $pc))
        (global.set $pc (local.get $t))))
    (if (i32.eq (local.get $low) (i32.const 0x3d))
      (then
        (local.set $t (i32.and (global.get $acc) (i32.const 0xffff)))
        (call $push (i32.and (i32.add (global.get $pc) (i32.const 2)) (i32.const 0xffff)))
        (call $delay_slot (global.get $pc))
        (global.set $pc (local.get $t))))
    (if (i32.eq (local.get $low) (i32.const 0x30))
      (then
        (call $push (global.get $pc))
        (global.set $pc (i32.and (global.get $acc) (i32.const 0xffff)))))
    (if (i32.eq (local.get $low) (i32.const 0x32))
      (then (global.set $acc (call $pop))))
    (if (i32.eq (local.get $low) (i32.const 0x3c))
      (then (call $push (global.get $acc))))
    (if (i32.eq (local.get $low) (i32.const 0x40)) (then (global.set $intm (i32.const 0))))
    (if (i32.eq (local.get $low) (i32.const 0x41)) (then (global.set $intm (i32.const 1))))
    (if (i32.eq (local.get $low) (i32.const 0x42)) (then (global.set $ovm (i32.const 0))))
    (if (i32.eq (local.get $low) (i32.const 0x43)) (then (global.set $ovm (i32.const 1))))
    (if (i32.eq (local.get $low) (i32.const 0x44)) (then (global.set $cnf (i32.const 0))))
    (if (i32.eq (local.get $low) (i32.const 0x45)) (then (global.set $cnf (i32.const 1))))
    (if (i32.eq (local.get $low) (i32.const 0x46)) (then (global.set $sxm (i32.const 0))))
    (if (i32.eq (local.get $low) (i32.const 0x47)) (then (global.set $sxm (i32.const 1))))
    (if (i32.eq (local.get $low) (i32.const 0x48)) (then (global.set $hm (i32.const 0))))
    (if (i32.eq (local.get $low) (i32.const 0x49)) (then (global.set $hm (i32.const 1))))
    (if (i32.eq (local.get $low) (i32.const 0x4a)) (then (global.set $tc (i32.const 0))))
    (if (i32.eq (local.get $low) (i32.const 0x4b)) (then (global.set $tc (i32.const 1))))
    (if (i32.eq (local.get $low) (i32.const 0x4c)) (then (global.set $xf (i32.const 0))))
    (if (i32.eq (local.get $low) (i32.const 0x4d)) (then (global.set $xf (i32.const 1))))
    (if (i32.eq (local.get $low) (i32.const 0x4e)) (then (global.set $c (i32.const 0))))
    (if (i32.eq (local.get $low) (i32.const 0x4f)) (then (global.set $c (i32.const 1))))
    (if (i32.eq (local.get $low) (i32.const 0x58)) (then (global.set $preg (i32.const 0))))
    (if (i32.eq (local.get $low) (i32.const 0x59))
      (then (global.set $acc (i32.const 0)) (global.set $preg (i32.const 0))))
    ;; SATH / SATL: arithmetic shift per SXM (logical when SXM=0).
    (if (i32.eq (local.get $low) (i32.const 0x5a))
      (then
        (if (i32.and (global.get $t1) (i32.const 0x10))
          (then
            (global.set $acc
              (if (result i32) (global.get $sxm)
                (then (i32.shr_s (global.get $acc) (i32.const 16)))
                (else (i32.shr_u (global.get $acc) (i32.const 16)))))))))
    (if (i32.eq (local.get $low) (i32.const 0x5b))
      (then
        (local.set $t (i32.and (global.get $t1) (i32.const 0xf)))
        (global.set $acc
          (if (result i32) (global.get $sxm)
            (then (i32.shr_s (global.get $acc) (local.get $t)))
            (else (i32.shr_u (global.get $acc) (local.get $t)))))))
    (if (i32.eq (local.get $low) (i32.const 0x80))
      (then
        (local.set $imm (call $fetch_imm))
        (global.set $preg (i32.mul (i32.extend16_s (global.get $t0)) (i32.extend16_s (local.get $imm))))))
    (if (i32.eq (local.get $low) (i32.const 0x81))
      (then
        (local.set $imm (call $fetch_imm))
        (global.set $acc (i32.and (global.get $acc) (i32.shl (local.get $imm) (i32.const 16))))))
    (if (i32.eq (local.get $low) (i32.const 0x82))
      (then
        (local.set $imm (call $fetch_imm))
        (global.set $acc (i32.or (global.get $acc) (i32.shl (local.get $imm) (i32.const 16))))))
    (if (i32.eq (local.get $low) (i32.const 0x83))
      (then
        (local.set $imm (call $fetch_imm))
        (global.set $acc (i32.xor (global.get $acc) (i32.shl (local.get $imm) (i32.const 16)))))))

  ;; Accumulator-side and memory ops of the 0x00..0x0F and 0x80..0x87 groups.
  (func $supported_e (param $hi i32) (result i32)
    (i32.or
      (i32.or
        (i32.le_u (local.get $hi) (i32.const 0x08))
        (i32.or (i32.or (i32.eq (local.get $hi) (i32.const 0x0a)) (i32.eq (local.get $hi) (i32.const 0x0b)))
                (i32.and (i32.ge_u (local.get $hi) (i32.const 0x0d)) (i32.le_u (local.get $hi) (i32.const 0x0f)))))
      (i32.or
        (i32.and (i32.ge_u (local.get $hi) (i32.const 0x80)) (i32.le_u (local.get $hi) (i32.const 0x87)))
        (i32.or
          (i32.or (i32.eq (local.get $hi) (i32.const 0x88)) (i32.eq (local.get $hi) (i32.const 0xa0)))
          (i32.or (i32.eq (local.get $hi) (i32.const 0x8e)) (i32.eq (local.get $hi) (i32.const 0x8f)))))))

  ;; SUBC: conditional subtract (divide step).  Sets C and OV, never saturates.
  (func $subc (param $d i32)
    (local $a i32) (local $b i32) (local $r i64) (local $res i32)
    (local.set $a (global.get $acc))
    (local.set $b (i32.shl (local.get $d) (i32.const 15)))
    (local.set $r (i64.sub (i64.extend_i32_u (local.get $a)) (i64.extend_i32_u (local.get $b))))
    (local.set $res (i32.wrap_i64 (local.get $r)))
    (global.set $c (i32.eqz (i32.and (i32.wrap_i64 (i64.shr_u (local.get $r) (i64.const 32))) (i32.const 1))))
    (if (i32.and (i32.and (i32.xor (local.get $a) (local.get $b)) (i32.xor (local.get $a) (local.get $res)))
                 (i32.const 0x80000000))
      (then (global.set $ov (i32.const 1))))
    (global.set $acc
      (if (result i32) (i32.ge_s (local.get $res) (i32.const 0))
        (then (i32.add (i32.shl (local.get $res) (i32.const 1)) (i32.const 1)))
        (else (i32.shl (local.get $a) (i32.const 1))))))

  ;; 0xBE accumulator ops (low byte 0x00..0x1F).  ABS/NEG saturate on
  ;; 0x80000000 under OVM and set OV there; the rest follow C be_acc.
  (func $be_acc (param $low i32) (local $t i32) (local $a i32) (local $b i32) (local $cc i32) (local $r i64)
    (local.set $a (global.get $acc))
    (local.set $b (global.get $accb))
    (if (i32.eq (local.get $low) (i32.const 0x00))
      (then
        (if (i32.eq (local.get $a) (i32.const 0x80000000))
          (then
            (global.set $ov (i32.const 1))
            (global.set $c (i32.const 0))
            (global.set $acc (if (result i32) (global.get $ovm)
                               (then (i32.const 0x7fffffff)) (else (i32.const 0x80000000)))))
          (else
            (if (i32.lt_s (local.get $a) (i32.const 0))
              (then (global.set $acc (i32.sub (i32.const 0) (local.get $a)))))
            (global.set $c (i32.const 0))))))
    (if (i32.eq (local.get $low) (i32.const 0x01))
      (then (global.set $acc (i32.xor (local.get $a) (i32.const -1)))))
    (if (i32.eq (local.get $low) (i32.const 0x02))
      (then
        (if (i32.eq (local.get $a) (i32.const 0x80000000))
          (then
            (global.set $ov (i32.const 1))
            (global.set $c (i32.const 0))
            (global.set $acc (if (result i32) (global.get $ovm)
                               (then (i32.const 0x7fffffff)) (else (i32.const 0x80000000)))))
          (else
            (global.set $acc (i32.sub (i32.const 0) (local.get $a)))
            (global.set $c (i32.eqz (global.get $acc)))))))
    (if (i32.eq (local.get $low) (i32.const 0x03))
      (then (global.set $acc (call $pscale))))
    (if (i32.eq (local.get $low) (i32.const 0x04))
      (then (global.set $acc (call $addx (local.get $a) (call $pscale) (i32.const 0) (i32.const 0)))))
    (if (i32.eq (local.get $low) (i32.const 0x05))
      (then (global.set $acc (call $subx (local.get $a) (call $pscale) (i32.const 0) (i32.const 0)))))
    (if (i32.eq (local.get $low) (i32.const 0x09))
      (then
        (global.set $c (i32.shr_u (local.get $a) (i32.const 31)))
        (global.set $acc (i32.shl (local.get $a) (i32.const 1)))))
    (if (i32.eq (local.get $low) (i32.const 0x0a))
      (then
        (global.set $c (i32.and (local.get $a) (i32.const 1)))
        (global.set $acc (if (result i32) (global.get $sxm)
                           (then (i32.shr_s (local.get $a) (i32.const 1)))
                           (else (i32.shr_u (local.get $a) (i32.const 1)))))))
    (if (i32.eq (local.get $low) (i32.const 0x0c))
      (then
        (local.set $t (global.get $c))
        (global.set $c (i32.shr_u (local.get $a) (i32.const 31)))
        (global.set $acc (i32.or (i32.shl (local.get $a) (i32.const 1)) (local.get $t)))))
    (if (i32.eq (local.get $low) (i32.const 0x0d))
      (then
        (local.set $t (global.get $c))
        (global.set $c (i32.and (local.get $a) (i32.const 1)))
        (global.set $acc (i32.or (i32.shr_u (local.get $a) (i32.const 1))
                                 (i32.shl (local.get $t) (i32.const 31))))))
    (if (i32.eq (local.get $low) (i32.const 0x10))
      (then (global.set $acc (call $addx (local.get $a) (local.get $b) (i32.const 0) (i32.const 0)))))
    (if (i32.eq (local.get $low) (i32.const 0x11))
      (then (global.set $acc (call $addx (local.get $a) (local.get $b) (global.get $c) (i32.const 0)))))
    (if (i32.eq (local.get $low) (i32.const 0x12))
      (then (global.set $acc (i32.and (local.get $a) (local.get $b)))))
    (if (i32.eq (local.get $low) (i32.const 0x13))
      (then (global.set $acc (i32.or (local.get $a) (local.get $b)))))
    (if (i32.eq (local.get $low) (i32.const 0x14))
      (then
        (global.set $acc (i32.or (i32.shl (local.get $a) (i32.const 1)) (i32.shr_u (local.get $b) (i32.const 31))))
        (global.set $accb (i32.or (i32.shl (local.get $b) (i32.const 1)) (global.get $c)))
        (global.set $c (i32.shr_u (local.get $a) (i32.const 31)))))
    (if (i32.eq (local.get $low) (i32.const 0x15))
      (then
        (global.set $accb (i32.or (i32.shr_u (local.get $b) (i32.const 1)) (i32.shl (local.get $a) (i32.const 31))))
        (global.set $acc (i32.or (i32.shr_u (local.get $a) (i32.const 1)) (i32.shl (global.get $c) (i32.const 31))))
        (global.set $c (i32.and (local.get $b) (i32.const 1)))))
    (if (i32.eq (local.get $low) (i32.const 0x16))
      (then
        (global.set $acc (i32.or (i32.shl (local.get $a) (i32.const 1)) (i32.shr_u (local.get $b) (i32.const 31))))
        (global.set $accb (i32.shl (local.get $b) (i32.const 1)))
        (global.set $c (i32.shr_u (local.get $a) (i32.const 31)))))
    (if (i32.eq (local.get $low) (i32.const 0x17))
      (then
        (global.set $accb (i32.or (i32.shr_u (local.get $b) (i32.const 1)) (i32.shl (local.get $a) (i32.const 31))))
        (global.set $acc (if (result i32) (global.get $sxm)
                           (then (i32.shr_s (local.get $a) (i32.const 1)))
                           (else (i32.shr_u (local.get $a) (i32.const 1)))))
        (global.set $c (i32.and (local.get $b) (i32.const 1)))))
    (if (i32.eq (local.get $low) (i32.const 0x18))
      (then (global.set $acc (call $subx (local.get $a) (local.get $b) (i32.const 0) (i32.const 0)))))
    (if (i32.eq (local.get $low) (i32.const 0x19))
      (then
        (local.set $cc (i32.eqz (global.get $c)))
        (local.set $r (i64.sub (i64.sub (i64.extend_i32_u (local.get $a))
                                        (i64.extend_i32_u (local.get $b)))
                               (i64.extend_i32_u (local.get $cc))))
        (global.set $c (i32.eqz (i32.and (i32.wrap_i64 (i64.shr_u (local.get $r) (i64.const 32))) (i32.const 1))))
        (global.set $acc (i32.wrap_i64 (local.get $r)))))
    (if (i32.eq (local.get $low) (i32.const 0x1a))
      (then (global.set $acc (i32.xor (local.get $a) (local.get $b)))))
    (if (i32.eq (local.get $low) (i32.const 0x1b))
      (then
        (if (i32.ge_s (local.get $a) (local.get $b))
          (then (global.set $accb (local.get $a)) (global.set $c (i32.const 1)))
          (else (global.set $acc (local.get $b)) (global.set $c (i32.const 0))))))
    (if (i32.eq (local.get $low) (i32.const 0x1c))
      (then
        (if (i32.ge_s (local.get $a) (local.get $b))
          (then (global.set $acc (local.get $b)) (global.set $c (i32.const 0)))
          (else (global.set $accb (local.get $a)) (global.set $c (i32.const 1))))))
    (if (i32.eq (local.get $low) (i32.const 0x1d))
      (then (global.set $acc (local.get $b)) (global.set $accb (local.get $a))))
    (if (i32.eq (local.get $low) (i32.const 0x1e))
      (then (global.set $accb (local.get $a))))
    (if (i32.eq (local.get $low) (i32.const 0x1f))
      (then (global.set $acc (local.get $b)))))

  ;; ST0 / ST1 as the C core packs them (st0_get / st1_get).
  (func $st0_get (result i32)
    (i32.or
      (i32.or
        (i32.or (i32.shl (global.get $arp) (i32.const 13)) (i32.shl (global.get $ov) (i32.const 12)))
        (i32.or (i32.shl (global.get $ovm) (i32.const 11)) (i32.const 0x400)))
      (i32.or (i32.shl (global.get $intm) (i32.const 9)) (i32.shr_u (global.get $dp) (i32.const 7)))))

  (func $st1_get (result i32)
    (i32.or
      (i32.or
        (i32.or (i32.shl (global.get $arb) (i32.const 13)) (i32.shl (global.get $cnf) (i32.const 12)))
        (i32.or (i32.shl (global.get $tc) (i32.const 11)) (i32.shl (global.get $sxm) (i32.const 10))))
      (i32.or
        (i32.or (i32.shl (global.get $c) (i32.const 9)) (i32.const 0x1ac))
        (i32.or
          (i32.or (i32.shl (global.get $hm) (i32.const 6)) (i32.shl (global.get $xf) (i32.const 4)))
          (i32.or (i32.const 0) (global.get $pm))))))

  ;; NORM: shift ACC left unless bits 31/30 differ (or ACC == 0, which sets TC).
  ;; The AR side effect runs only on the non-shifting path (C audit #23).
  (func $norm (param $op i32)
    (local $t i32)
    (local.set $t (i32.and (i32.xor (i32.shr_u (global.get $acc) (i32.const 31))
                                    (i32.shr_u (global.get $acc) (i32.const 30)))
                           (i32.const 1)))
    (if (i32.eqz (global.get $acc)) (then (local.set $t (i32.const 1))))
    (if (i32.eqz (local.get $t))
      (then (if (i32.and (local.get $op) (i32.const 0x80)) (then (drop (call $ea_ind (local.get $op)))))))
    (if (local.get $t)
      (then (global.set $tc (i32.const 1)))
      (else
        (global.set $tc (i32.const 0))
        (global.set $acc (i32.shl (global.get $acc) (i32.const 1))))))

  ;; Effective address for an op whose addressing runs inside its own loop.
  (func $ea_op (param $op i32) (result i32)
    (if (result i32) (i32.and (local.get $op) (i32.const 0x80))
      (then (call $ea_ind (local.get $op)))
      (else (i32.or (global.get $dp) (i32.and (local.get $op) (i32.const 0x7f))))))

  ;; MAC / MACD: repeat-counted multiply-accumulate (C high byte 0xA2/0xA3).
  ;; Loops while RPTC > -1 and leaves RPTC at -1.
  (func $op_mac (param $op i32) (param $dm i32)
    (local $pfc i32) (local $a i32) (local $d i32)
    (local.set $pfc (call $fetch_imm))
    (loop $l
      (local.set $a (call $ea_op (local.get $op)))
      (local.set $d (call $dm_rd (local.get $a)))
      (global.set $acc (call $addx (global.get $acc) (call $pscale) (i32.const 0) (i32.const 0)))
      (call $set_t0 (local.get $d))
      (global.set $preg (i32.mul (i32.extend16_s (local.get $d))
                                 (i32.extend16_s (call $pm_rd (local.get $pfc)))))
      (local.set $pfc (i32.and (i32.add (local.get $pfc) (i32.const 1)) (i32.const 0xffff)))
      (if (local.get $dm) (then (call $dmov (local.get $a) (local.get $d))))
      (if (i32.gt_s (global.get $rptc) (i32.const -1))
        (then (global.set $rptc (i32.sub (global.get $rptc) (i32.const 1)))))
      (br_if $l (i32.gt_s (global.get $rptc) (i32.const -1)))))

  ;; BLPD #pma,dma (C 0xA5): program -> data block move.
  (func $op_blpd (param $op i32) (local $pfc i32)
    (local.set $pfc (call $fetch_imm))
    (block $done
      (loop $l
        (br_if $done (i32.le_s (global.get $rptc) (i32.const -1)))
        (call $dm_wr (call $ea_op (local.get $op)) (call $pm_rd (local.get $pfc)))
        (local.set $pfc (i32.and (i32.add (local.get $pfc) (i32.const 1)) (i32.const 0xffff)))
        (global.set $rptc (i32.sub (global.get $rptc) (i32.const 1)))
        (br $l))))

  ;; BLDD #lk,dma (mode 0, C 0xA8) and BLDD dma,#lk (mode 1, C 0xA9): data -> data.
  (func $op_bldd (param $op i32) (param $mode i32) (local $pfc i32) (local $a i32)
    (local.set $pfc (call $fetch_imm))
    (block $done
      (loop $l
        (br_if $done (i32.le_s (global.get $rptc) (i32.const -1)))
        (local.set $a (call $ea_op (local.get $op)))
        (if (i32.eqz (local.get $mode))
          (then (call $dm_wr (local.get $a) (call $dm_rd (local.get $pfc))))
          (else (call $dm_wr (local.get $pfc) (call $dm_rd (local.get $a)))))
        (local.set $pfc (i32.and (i32.add (local.get $pfc) (i32.const 1)) (i32.const 0xffff)))
        (global.set $rptc (i32.sub (global.get $rptc) (i32.const 1)))
        (br $l))))

  (func $supported_f (param $hi i32) (result i32)
    (i32.or
      (i32.or
        (i32.or (i32.eq (local.get $hi) (i32.const 0xa2)) (i32.eq (local.get $hi) (i32.const 0xa3)))
        (i32.or (i32.eq (local.get $hi) (i32.const 0xa5))
                (i32.or (i32.eq (local.get $hi) (i32.const 0xa8)) (i32.eq (local.get $hi) (i32.const 0xa9)))))
      (i32.or
        (i32.or (i32.eq (local.get $hi) (i32.const 0x09)) (i32.eq (local.get $hi) (i32.const 0x89)))
        (i32.or (i32.eq (local.get $hi) (i32.const 0xa4))
                (i32.or (i32.eq (local.get $hi) (i32.const 0xaa))
                        (i32.or (i32.eq (local.get $hi) (i32.const 0xab))
                                (i32.eq (local.get $hi) (i32.const 0xac))))))))

  ;; SMMR (0x09) / LMMR (0x89): block move between program/data and one fixed
  ;; data address (page 0 for the fixed side, masked by 0x7F).
  (func $op_smmr (param $op i32) (local $pfc i32) (local $a i32)
    (local.set $pfc (call $fetch_imm))
    (local.set $a (i32.and (call $ea_op (local.get $op)) (i32.const 0x7f)))
    (block $done
      (loop $l
        (br_if $done (i32.le_s (global.get $rptc) (i32.const -1)))
        (call $dm_wr (local.get $pfc) (call $dm_rd (local.get $a)))
        (local.set $pfc (i32.and (i32.add (local.get $pfc) (i32.const 1)) (i32.const 0xffff)))
        (global.set $rptc (i32.sub (global.get $rptc) (i32.const 1)))
        (br $l))))

  (func $op_lmmr (param $op i32) (local $pfc i32) (local $a i32)
    (local.set $pfc (call $fetch_imm))
    (local.set $a (i32.and (call $ea_op (local.get $op)) (i32.const 0x7f)))
    (block $done
      (loop $l
        (br_if $done (i32.le_s (global.get $rptc) (i32.const -1)))
        (call $dm_wr (local.get $a) (call $dm_rd (local.get $pfc)))
        (local.set $pfc (i32.and (i32.add (local.get $pfc) (i32.const 1)) (i32.const 0xffff)))
        (global.set $rptc (i32.sub (global.get $rptc) (i32.const 1)))
        (br $l))))

  ;; BLPD bmar,dma (0xA4) and BLDD bmar,dma (0xAC): BMAR is the source, not written back.
  (func $op_blpd_b (param $op i32) (local $pfc i32)
    (local.set $pfc (global.get $bmar))
    (block $done
      (loop $l
        (br_if $done (i32.le_s (global.get $rptc) (i32.const -1)))
        (call $dm_wr (call $ea_op (local.get $op)) (call $pm_rd (local.get $pfc)))
        (local.set $pfc (i32.and (i32.add (local.get $pfc) (i32.const 1)) (i32.const 0xffff)))
        (global.set $rptc (i32.sub (global.get $rptc) (i32.const 1)))
        (br $l))))

  (func $op_bldd_b (param $op i32) (local $pfc i32)
    (local.set $pfc (global.get $bmar))
    (block $done
      (loop $l
        (br_if $done (i32.le_s (global.get $rptc) (i32.const -1)))
        (call $dm_wr (call $ea_op (local.get $op)) (call $dm_rd (local.get $pfc)))
        (local.set $pfc (i32.and (i32.add (local.get $pfc) (i32.const 1)) (i32.const 0xffff)))
        (global.set $rptc (i32.sub (global.get $rptc) (i32.const 1)))
        (br $l))))

  ;; MADS / MADD (0xAA / 0xAB): MAC with the program address from BMAR and TREG0
  ;; written directly (no TRM mirror).
  (func $op_mads (param $op i32) (param $dm i32) (local $pfc i32) (local $a i32) (local $d i32)
    (local.set $pfc (global.get $bmar))
    (loop $l
      (local.set $a (call $ea_op (local.get $op)))
      (local.set $d (call $dm_rd (local.get $a)))
      (global.set $acc (call $addx (global.get $acc) (call $pscale) (i32.const 0) (i32.const 0)))
      (global.set $t0 (local.get $d))
      (global.set $preg (i32.mul (i32.extend16_s (local.get $d))
                                 (i32.extend16_s (call $pm_rd (local.get $pfc)))))
      (local.set $pfc (i32.and (i32.add (local.get $pfc) (i32.const 1)) (i32.const 0xffff)))
      (if (local.get $dm) (then (call $dmov (local.get $a) (local.get $d))))
      (if (i32.gt_s (global.get $rptc) (i32.const -1))
        (then (global.set $rptc (i32.sub (global.get $rptc) (i32.const 1)))))
      (br_if $l (i32.gt_s (global.get $rptc) (i32.const -1)))))

  ;; Interrupt shadow context (C save_ctx / restore_ctx), in memory at byte 262240.
  ;; Slot order: acc accb preg t0 t1 t2 arcr indx arp arb dp ov ovm intm cnf tc
  ;; sxm c hm xf pm iptr avis ovly ram mpmc ndx trm braf.  XF/INTM are not
  ;; restored (audit #9).
  (func $sh_set (param $i i32) (param $v i32)
    (i32.store (i32.add (i32.const 262240) (i32.shl (local.get $i) (i32.const 2))) (local.get $v)))

  (func $sh_get (param $i i32) (result i32)
    (i32.load (i32.add (i32.const 262240) (i32.shl (local.get $i) (i32.const 2)))))

  (func $save_ctx
    (call $sh_set (i32.const 0) (global.get $acc))
    (call $sh_set (i32.const 1) (global.get $accb))
    (call $sh_set (i32.const 2) (global.get $preg))
    (call $sh_set (i32.const 3) (global.get $t0))
    (call $sh_set (i32.const 4) (global.get $t1))
    (call $sh_set (i32.const 5) (global.get $t2))
    (call $sh_set (i32.const 6) (global.get $arcr))
    (call $sh_set (i32.const 7) (global.get $indx))
    (call $sh_set (i32.const 8) (global.get $arp))
    (call $sh_set (i32.const 9) (global.get $arb))
    (call $sh_set (i32.const 10) (global.get $dp))
    (call $sh_set (i32.const 11) (global.get $ov))
    (call $sh_set (i32.const 12) (global.get $ovm))
    (call $sh_set (i32.const 13) (global.get $intm))
    (call $sh_set (i32.const 14) (global.get $cnf))
    (call $sh_set (i32.const 15) (global.get $tc))
    (call $sh_set (i32.const 16) (global.get $sxm))
    (call $sh_set (i32.const 17) (global.get $c))
    (call $sh_set (i32.const 18) (global.get $hm))
    (call $sh_set (i32.const 19) (global.get $xf))
    (call $sh_set (i32.const 20) (global.get $pm))
    (call $sh_set (i32.const 21) (global.get $iptr))
    (call $sh_set (i32.const 22) (global.get $avis))
    (call $sh_set (i32.const 23) (global.get $ovly))
    (call $sh_set (i32.const 24) (global.get $ram))
    (call $sh_set (i32.const 25) (global.get $mpmc))
    (call $sh_set (i32.const 26) (global.get $ndx))
    (call $sh_set (i32.const 27) (global.get $trm))
    (call $sh_set (i32.const 28) (global.get $braf)))

  (func $restore_ctx
    (global.set $acc (call $sh_get (i32.const 0)))
    (global.set $accb (call $sh_get (i32.const 1)))
    (global.set $preg (call $sh_get (i32.const 2)))
    (global.set $t0 (call $sh_get (i32.const 3)))
    (global.set $t1 (call $sh_get (i32.const 4)))
    (global.set $t2 (call $sh_get (i32.const 5)))
    (global.set $arcr (call $sh_get (i32.const 6)))
    (global.set $indx (call $sh_get (i32.const 7)))
    (global.set $arp (call $sh_get (i32.const 8)))
    (global.set $arb (call $sh_get (i32.const 9)))
    (global.set $dp (call $sh_get (i32.const 10)))
    (global.set $ov (call $sh_get (i32.const 11)))
    (global.set $ovm (call $sh_get (i32.const 12)))
    (global.set $cnf (call $sh_get (i32.const 14)))
    (global.set $tc (call $sh_get (i32.const 15)))
    (global.set $sxm (call $sh_get (i32.const 16)))
    (global.set $c (call $sh_get (i32.const 17)))
    (global.set $hm (call $sh_get (i32.const 18)))
    (global.set $pm (call $sh_get (i32.const 20)))
    (global.set $iptr (call $sh_get (i32.const 21)))
    (global.set $avis (call $sh_get (i32.const 22)))
    (global.set $ovly (call $sh_get (i32.const 23)))
    (global.set $ram (call $sh_get (i32.const 24)))
    (global.set $mpmc (call $sh_get (i32.const 25)))
    (global.set $ndx (call $sh_get (i32.const 26)))
    (global.set $trm (call $sh_get (i32.const 27)))
    (global.set $braf (call $sh_get (i32.const 28))))

  ;; Execute the two delay-slot words after a delayed branch (C delay_slot).
  ;; Slot words are assumed to be supported single-word ops.
  (func $delay_slot (param $start i32)
    (loop $l
      (drop (call $step))
      (br_if $l (i32.lt_u (i32.and (i32.sub (global.get $pc) (local.get $start)) (i32.const 0xffff))
                          (i32.const 2)))))

  (func $supported_g (param $hi i32) (result i32)
    (i32.or
      (i32.or (i32.and (i32.ge_u (local.get $hi) (i32.const 0xe4)) (i32.le_u (local.get $hi) (i32.const 0xe7)))
              (i32.and (i32.ge_u (local.get $hi) (i32.const 0xf0)) (i32.le_u (local.get $hi) (i32.const 0xff))))
      (i32.or (i32.eq (local.get $hi) (i32.const 0x7d))
              (i32.or (i32.eq (local.get $hi) (i32.const 0x7e)) (i32.eq (local.get $hi) (i32.const 0x7f))))))

  ;; DMOV: write d to a+1 only when both a and a+1 are on-chip RAM and a >= 0x60.
  (func $dmov (param $a i32) (param $d i32)
    (local $n i32)
    (local.set $n (i32.and (i32.add (local.get $a) (i32.const 1)) (i32.const 0xffff)))
    (if (i32.and
          (i32.and (call $internal (local.get $a)) (i32.ge_u (local.get $a) (i32.const 0x60)))
          (call $internal (local.get $n)))
      (then (call $dm_wr (local.get $n) (local.get $d)))))

  ;; Execute one instruction at PC.  0 = ok, 2 = indirect addressing,
  ;; 3 = unsupported opcode (state unchanged in both error cases).
  (func $step (export "step") (result i32)
    (local $op i32) (local $hi i32) (local $a i32) (local $d i32) (local $s i32)
    (local $ean i32) (local $take i32) (local $imm i32) (local $arsel i32) (local $arb0 i32)
    (local.set $op (call $pm_rd (global.get $pc)))
    (local.set $hi (i32.shr_u (local.get $op) (i32.const 8)))
    (if (i32.eqz (i32.or (i32.or (i32.or (call $supported (local.get $hi)) (call $supported_e (local.get $hi)))
                                 (call $supported_f (local.get $hi)))
                         (call $supported_g (local.get $hi))))
      (then (return (i32.const 3))))
    (if (i32.and (i32.eq (local.get $hi) (i32.const 0xbe))
                 (i32.eqz (call $be_ok (i32.and (local.get $op) (i32.const 0xff)))))
      (then (return (i32.const 3))))
    ;; Ops that run the addressing side effects: everything with bit 7 set,
    ;; except SBRK and the conditional branch/call/return family (no ea()).
    (local.set $ean
      (i32.and (i32.ne (i32.and (local.get $op) (i32.const 0x80)) (i32.const 0))
               (i32.eqz (i32.or (i32.or (i32.eq (local.get $hi) (i32.const 0x7c)) (i32.eq (local.get $hi) (i32.const 0xbe)))
                                (i32.and (i32.ge_u (local.get $hi) (i32.const 0xe0))
                                         (i32.le_u (local.get $hi) (i32.const 0xef)))))))
    (if (i32.eq (local.get $hi) (i32.const 0xa0))
      (then (local.set $ean (i32.const 0))))
    (if (i32.or (i32.or (i32.eq (local.get $hi) (i32.const 0xa2)) (i32.eq (local.get $hi) (i32.const 0xa3)))
                (i32.or (i32.eq (local.get $hi) (i32.const 0xa5))
                        (i32.or (i32.eq (local.get $hi) (i32.const 0xa8)) (i32.eq (local.get $hi) (i32.const 0xa9)))))
      (then (local.set $ean (i32.const 0))))
    (if (i32.or (i32.or (i32.eq (local.get $hi) (i32.const 0x09)) (i32.eq (local.get $hi) (i32.const 0x89)))
                (i32.or (i32.eq (local.get $hi) (i32.const 0xa4))
                        (i32.or (i32.eq (local.get $hi) (i32.const 0xaa))
                                (i32.or (i32.eq (local.get $hi) (i32.const 0xab))
                                        (i32.eq (local.get $hi) (i32.const 0xac)))))
      )
      (then (local.set $ean (i32.const 0))))
    (if (i32.ge_u (local.get $hi) (i32.const 0xf0))
      (then (local.set $ean (i32.const 0))))
    (if (i32.and (local.get $ean)
                 (i32.eq (i32.and (i32.shr_u (local.get $op) (i32.const 3)) (i32.const 0xe)) (i32.const 6)))
      (then (return (i32.const 4))))
    (global.set $pc (i32.and (i32.add (global.get $pc) (i32.const 1)) (i32.const 0xffff)))
    ;; BANZ tests AR[ARP] before the addressing side effects.
    (local.set $take (i32.ne (call $ar_get (global.get $arp)) (i32.const 0)))
    ;; SAR reads AR[hi&7] before addressing; LST0 restores ARB after it.
    (local.set $arsel (call $ar_get (i32.and (local.get $hi) (i32.const 7))))
    (local.set $arb0 (global.get $arb))
    (local.set $a (if (result i32) (local.get $ean)
                    (then (call $ea_ind (local.get $op)))
                    (else (i32.or (global.get $dp) (i32.and (local.get $op) (i32.const 0x7f))))))
    (local.set $d (call $dm_rd (local.get $a)))
    (local.set $s (i32.and (local.get $hi) (i32.const 7)))

    ;; LACC / ADD / SUB with shift: high nibble 1, 2, 3.
    (if (i32.and (i32.ge_u (local.get $hi) (i32.const 0x10)) (i32.le_u (local.get $hi) (i32.const 0x3f)))
      (then
        (local.set $d (call $ext (local.get $d) (i32.and (local.get $hi) (i32.const 0xf))))
        (if (i32.eq (i32.shr_u (local.get $hi) (i32.const 4)) (i32.const 1))
          (then (global.set $acc (local.get $d)))
          (else
            (if (i32.eq (i32.shr_u (local.get $hi) (i32.const 4)) (i32.const 2))
              (then (global.set $acc (call $add (global.get $acc) (local.get $d))))
              (else (global.set $acc (call $sub (global.get $acc) (local.get $d)))))))))

    ;; MPYA: ACC += PREG (scaled); PREG = TREG0 * dma.
    (if (i32.eq (local.get $hi) (i32.const 0x50))
      (then
        (global.set $acc (call $add (global.get $acc) (call $pscale)))
        (global.set $preg (i32.mul (i32.extend16_s (global.get $t0))
                                   (i32.extend16_s (local.get $d))))))

    ;; MPY: PREG = TREG0 * dma.
    (if (i32.eq (local.get $hi) (i32.const 0x54))
      (then
        (global.set $preg (i32.mul (i32.extend16_s (global.get $t0))
                                   (i32.extend16_s (local.get $d))))))

    (if (i32.eq (local.get $hi) (i32.const 0x62))
      (then (global.set $acc (call $add (global.get $acc) (local.get $d)))))
    (if (i32.eq (local.get $hi) (i32.const 0x66))
      (then (global.set $acc (call $sub (global.get $acc) (local.get $d)))))
    (if (i32.eq (local.get $hi) (i32.const 0x69))
      (then (global.set $acc (local.get $d))))
    (if (i32.eq (local.get $hi) (i32.const 0x73))
      (then (call $set_t0 (local.get $d))))

    ;; SACL / SACH: store ACC low / high half, shifted left by hi & 7.
    (if (i32.and (i32.ge_u (local.get $hi) (i32.const 0x90)) (i32.le_u (local.get $hi) (i32.const 0x97)))
      (then (call $dm_wr (local.get $a) (i32.shl (global.get $acc) (local.get $s)))))
    (if (i32.and (i32.ge_u (local.get $hi) (i32.const 0x98)) (i32.le_u (local.get $hi) (i32.const 0x9f)))
      (then (call $dm_wr (local.get $a)
                 (i32.shr_u (i32.shl (global.get $acc) (local.get $s)) (i32.const 16)))))

    ;; ADDC, ADD/SUB 16-bit, ADDT/SUBT, ZALR, LACC 16, LACT, logic ops.
    (if (i32.eq (local.get $hi) (i32.const 0x60))
      (then (global.set $acc (call $addx (global.get $acc) (local.get $d) (global.get $c) (i32.const 0)))))
    (if (i32.eq (local.get $hi) (i32.const 0x61))
      (then (global.set $acc (call $addx (global.get $acc) (i32.shl (local.get $d) (i32.const 16)) (i32.const 0) (i32.const 1)))))
    (if (i32.eq (local.get $hi) (i32.const 0x63))
      (then (global.set $acc (call $addx (global.get $acc)
                                     (call $ext (local.get $d) (i32.and (global.get $t1) (i32.const 0xf)))
                                     (i32.const 0) (i32.const 0)))))
    (if (i32.eq (local.get $hi) (i32.const 0x64))
      (then (global.set $acc (call $subx (global.get $acc) (local.get $d) (i32.eqz (global.get $c)) (i32.const 0)))))
    (if (i32.eq (local.get $hi) (i32.const 0x65))
      (then (global.set $acc (call $subx (global.get $acc) (i32.shl (local.get $d) (i32.const 16)) (i32.const 0) (i32.const 1)))))
    (if (i32.eq (local.get $hi) (i32.const 0x67))
      (then (global.set $acc (call $subx (global.get $acc)
                                     (call $ext (local.get $d) (i32.and (global.get $t1) (i32.const 0xf)))
                                     (i32.const 0) (i32.const 0)))))
    (if (i32.eq (local.get $hi) (i32.const 0x68))
      (then (global.set $acc (i32.or (i32.shl (local.get $d) (i32.const 16)) (i32.const 0x8000)))))
    (if (i32.eq (local.get $hi) (i32.const 0x6a))
      (then (global.set $acc (i32.shl (local.get $d) (i32.const 16)))))
    (if (i32.eq (local.get $hi) (i32.const 0x6b))
      (then (global.set $acc (call $ext (local.get $d) (i32.and (global.get $t1) (i32.const 0xf))))))
    (if (i32.eq (local.get $hi) (i32.const 0x6c))
      (then (global.set $acc (i32.xor (global.get $acc) (local.get $d)))))
    (if (i32.eq (local.get $hi) (i32.const 0x6d))
      (then (global.set $acc (i32.or (global.get $acc) (local.get $d)))))
    (if (i32.eq (local.get $hi) (i32.const 0x6e))
      (then (global.set $acc (i32.and (global.get $acc) (local.get $d)))))

    ;; SQRA/SQRS/MPYS/MPYU and the LT family (LTA/LTP/LTD/LTS).
    (if (i32.eq (local.get $hi) (i32.const 0x51))
      (then
        (global.set $acc (call $subx (global.get $acc) (call $pscale) (i32.const 0) (i32.const 0)))
        (global.set $preg (i32.mul (i32.extend16_s (global.get $t0)) (i32.extend16_s (local.get $d))))))
    (if (i32.eq (local.get $hi) (i32.const 0x52))
      (then
        (global.set $acc (call $addx (global.get $acc) (call $pscale) (i32.const 0) (i32.const 0)))
        (call $set_t0 (local.get $d))
        (global.set $preg (i32.mul (i32.extend16_s (local.get $d)) (i32.extend16_s (local.get $d))))))
    (if (i32.eq (local.get $hi) (i32.const 0x53))
      (then
        (global.set $acc (call $subx (global.get $acc) (call $pscale) (i32.const 0) (i32.const 0)))
        (call $set_t0 (local.get $d))
        (global.set $preg (i32.mul (i32.extend16_s (local.get $d)) (i32.extend16_s (local.get $d))))))
    (if (i32.eq (local.get $hi) (i32.const 0x55))
      (then
        (global.set $preg (i32.mul (i32.and (global.get $t0) (i32.const 0xffff))
                                   (i32.and (local.get $d) (i32.const 0xffff))))))
    (if (i32.eq (local.get $hi) (i32.const 0x70))
      (then
        (global.set $acc (call $addx (global.get $acc) (call $pscale) (i32.const 0) (i32.const 0)))
        (call $set_t0 (local.get $d))))
    (if (i32.eq (local.get $hi) (i32.const 0x71))
      (then
        (global.set $acc (call $pscale))
        (call $set_t0 (local.get $d))))
    (if (i32.eq (local.get $hi) (i32.const 0x72))
      (then
        (global.set $acc (call $addx (global.get $acc) (call $pscale) (i32.const 0) (i32.const 0)))
        (call $set_t0 (local.get $d))
        (call $dmov (local.get $a) (local.get $d))))
    (if (i32.eq (local.get $hi) (i32.const 0x74))
      (then
        (global.set $acc (call $subx (global.get $acc) (call $pscale) (i32.const 0) (i32.const 0)))
        (call $set_t0 (local.get $d))))
    (if (i32.eq (local.get $hi) (i32.const 0x77))
      (then (call $dmov (local.get $a) (local.get $d))))

    ;; SPL / SPH: store PREG low / high half (scaled).
    (if (i32.eq (local.get $hi) (i32.const 0x8c))
      (then (call $dm_wr (local.get $a) (call $pscale))))
    (if (i32.eq (local.get $hi) (i32.const 0x8d))
      (then (call $dm_wr (local.get $a) (i32.shr_u (call $pscale) (i32.const 16)))))

    ;; BIT / BITT: TC = bit (15 - shift) of dma; BITT takes the shift from TREG2.
    (if (i32.and (i32.ge_u (local.get $hi) (i32.const 0x40)) (i32.le_u (local.get $hi) (i32.const 0x4f)))
      (then (global.set $tc (i32.and (i32.shr_u (local.get $d)
                                                (i32.sub (i32.const 15) (i32.and (local.get $hi) (i32.const 0xf))))
                                     (i32.const 1)))))
    (if (i32.eq (local.get $hi) (i32.const 0x6f))
      (then (global.set $tc (i32.and (i32.shr_u (local.get $d)
                                                (i32.and (i32.xor (global.get $t2) (i32.const -1)) (i32.const 0xf)))
                                     (i32.const 1)))))

    ;; B, CALL, BANZ, SBRK, and the non-delayed BCND / CC / RETC.  PC already
    ;; points at the operand word for the two-word forms.
    (if (i32.eq (local.get $hi) (i32.const 0x79))
      (then (global.set $pc (call $pm_rd (global.get $pc)))))
    (if (i32.eq (local.get $hi) (i32.const 0x7a))
      (then
        (local.set $imm (call $pm_rd (global.get $pc)))
        (global.set $pc (i32.and (i32.add (global.get $pc) (i32.const 1)) (i32.const 0xffff)))
        (call $push (global.get $pc))
        (global.set $pc (local.get $imm))))
    (if (i32.eq (local.get $hi) (i32.const 0x7b))
      (then
        (local.set $imm (call $pm_rd (global.get $pc)))
        (global.set $pc (i32.and (i32.add (global.get $pc) (i32.const 1)) (i32.const 0xffff)))
        (if (local.get $take) (then (global.set $pc (local.get $imm))))))
    (if (i32.eq (local.get $hi) (i32.const 0x7c))
      (then (call $upd_ar (global.get $arp) (i32.sub (i32.const 0) (i32.and (local.get $op) (i32.const 0xff))))))
    (if (i32.and (i32.ge_u (local.get $hi) (i32.const 0xe0)) (i32.le_u (local.get $hi) (i32.const 0xe3)))
      (then
        (local.set $imm (call $pm_rd (global.get $pc)))
        (global.set $pc (i32.and (i32.add (global.get $pc) (i32.const 1)) (i32.const 0xffff)))
        (if (call $cond (local.get $op))
          (then
            (global.set $pc (local.get $imm))
            (if (i32.and (local.get $op) (i32.const 2)) (then (global.set $ov (i32.const 0))))))))
    (if (i32.and (i32.ge_u (local.get $hi) (i32.const 0xe8)) (i32.le_u (local.get $hi) (i32.const 0xeb)))
      (then
        (local.set $imm (call $pm_rd (global.get $pc)))
        (global.set $pc (i32.and (i32.add (global.get $pc) (i32.const 1)) (i32.const 0xffff)))
        (if (call $cond (local.get $op))
          (then
            (call $push (global.get $pc))
            (global.set $pc (local.get $imm))
            (if (i32.and (local.get $op) (i32.const 2)) (then (global.set $ov (i32.const 0))))))))
    (if (i32.and (i32.ge_u (local.get $hi) (i32.const 0xec)) (i32.le_u (local.get $hi) (i32.const 0xef)))
      (then
        (if (call $cond (local.get $op))
          (then (global.set $pc (call $pop))))))

    (if (i32.eq (local.get $hi) (i32.const 0xbe))
      (then (call $be_ctrl (local.get $op))))

    ;; LAR, LAMM, SUBC, LDP, LST #0, LST #1, SAR.
    (if (i32.lt_u (local.get $hi) (i32.const 0x08))
      (then
        (call $ar_set (local.get $hi) (local.get $d))
        (if (i32.eqz (local.get $hi)) (then (global.set $ar0dirty (i32.const 1))))))
    (if (i32.eq (local.get $hi) (i32.const 0x08))
      (then (global.set $acc (call $dm_rd (i32.and (local.get $a) (i32.const 0x7f))))))
    (if (i32.eq (local.get $hi) (i32.const 0x0a))
      (then (call $subc (local.get $d))))
    (if (i32.eq (local.get $hi) (i32.const 0x0d))
      (then (global.set $dp (i32.shl (i32.and (local.get $d) (i32.const 0x1ff)) (i32.const 7)))))
    (if (i32.eq (local.get $hi) (i32.const 0x0e))
      (then
        (global.set $arb (local.get $arb0))
        (global.set $arp (i32.shr_u (local.get $d) (i32.const 13)))
        (global.set $ov (i32.and (i32.shr_u (local.get $d) (i32.const 12)) (i32.const 1)))
        (global.set $ovm (i32.and (i32.shr_u (local.get $d) (i32.const 11)) (i32.const 1)))
        (global.set $dp (i32.shl (i32.and (local.get $d) (i32.const 0x1ff)) (i32.const 7)))))
    (if (i32.eq (local.get $hi) (i32.const 0x0f))
      (then
        (global.set $arb (i32.shr_u (local.get $d) (i32.const 13)))
        (global.set $arp (i32.shr_u (local.get $d) (i32.const 13)))
        (global.set $cnf (i32.and (i32.shr_u (local.get $d) (i32.const 12)) (i32.const 1)))
        (global.set $tc (i32.and (i32.shr_u (local.get $d) (i32.const 11)) (i32.const 1)))
        (global.set $sxm (i32.and (i32.shr_u (local.get $d) (i32.const 10)) (i32.const 1)))
        (global.set $c (i32.and (i32.shr_u (local.get $d) (i32.const 9)) (i32.const 1)))
        (global.set $hm (i32.and (i32.shr_u (local.get $d) (i32.const 6)) (i32.const 1)))
        (global.set $xf (i32.and (i32.shr_u (local.get $d) (i32.const 4)) (i32.const 1)))
        (global.set $pm (i32.and (local.get $d) (i32.const 3)))))
    (if (i32.eq (i32.and (local.get $hi) (i32.const 0xf8)) (i32.const 0x80))
      (then (call $dm_wr (local.get $a) (local.get $arsel))))

    ;; SAMM, SST #0 / #1 (direct form addresses page 0 with op&0x7f), NORM.
    (if (i32.eq (local.get $hi) (i32.const 0x88))
      (then (call $dm_wr (i32.and (local.get $a) (i32.const 0x7f)) (global.get $acc))))
    (if (i32.or (i32.eq (local.get $hi) (i32.const 0x8e)) (i32.eq (local.get $hi) (i32.const 0x8f)))
      (then
        (call $dm_wr
          (if (result i32) (i32.and (local.get $op) (i32.const 0x80))
            (then (local.get $a))
            (else (i32.and (local.get $op) (i32.const 0x7f))))
          (if (result i32) (i32.eq (local.get $hi) (i32.const 0x8e))
            (then (call $st0_get))
            (else (call $st1_get))))))
    (if (i32.eq (local.get $hi) (i32.const 0xa0))
      (then (call $norm (local.get $op))))

    ;; RPT dma: repeat the next instruction DMA+1 times (C orig L630).
    (if (i32.eq (local.get $hi) (i32.const 0x0b))
      (then
        (global.set $rptc (local.get $d))
        (global.set $rpt_start (global.get $pc))
        (global.set $rpt_end (global.get $pc))))

    ;; MAC/MACD, BLPD #pma, BLDD #lk,dma / dma,#lk (each runs its own RPTC loop).
    (if (i32.or (i32.eq (local.get $hi) (i32.const 0xa2)) (i32.eq (local.get $hi) (i32.const 0xa3)))
      (then (call $op_mac (local.get $op) (i32.eq (local.get $hi) (i32.const 0xa3)))))
    (if (i32.eq (local.get $hi) (i32.const 0xa5))
      (then (call $op_blpd (local.get $op))))
    (if (i32.eq (local.get $hi) (i32.const 0xa8))
      (then (call $op_bldd (local.get $op) (i32.const 0))))
    (if (i32.eq (local.get $hi) (i32.const 0xa9))
      (then (call $op_bldd (local.get $op) (i32.const 1))))

    ;; SMMR / LMMR / BLPD bmar / BLDD bmar / MADS / MADD.
    (if (i32.eq (local.get $hi) (i32.const 0x09)) (then (call $op_smmr (local.get $op) )))
    (if (i32.eq (local.get $hi) (i32.const 0x89)) (then (call $op_lmmr (local.get $op))))
    (if (i32.eq (local.get $hi) (i32.const 0xa4)) (then (call $op_blpd_b (local.get $op))))
    (if (i32.eq (local.get $hi) (i32.const 0xac)) (then (call $op_bldd_b (local.get $op))))
    (if (i32.eq (local.get $hi) (i32.const 0xaa))
      (then (call $op_mads (local.get $op) (i32.const 0))))
    (if (i32.eq (local.get $hi) (i32.const 0xab))
      (then (call $op_mads (local.get $op) (i32.const 1))))

    ;; XC: skip n words when the condition fails (n = bit 12 + 1).  The
    ;; interrupt-hold state is not modelled (no interrupts in this core yet).
    (if (i32.or (i32.and (i32.ge_u (local.get $hi) (i32.const 0xe4)) (i32.le_u (local.get $hi) (i32.const 0xe7)))
                (i32.and (i32.ge_u (local.get $hi) (i32.const 0xf4)) (i32.le_u (local.get $hi) (i32.const 0xf7))))
      (then
        (if (i32.eqz (call $cond (local.get $op)))
          (then
            (global.set $pc (i32.and (i32.add (global.get $pc)
                                              (i32.add (i32.and (i32.shr_u (local.get $op) (i32.const 12)) (i32.const 1))
                                                       (i32.const 1)))
                                     (i32.const 0xffff)))))))

    ;; Delayed branches / calls / returns: the two slot words run first.
    (if (i32.eq (local.get $hi) (i32.const 0x7d))
      (then
        (local.set $imm (call $fetch_imm))
        (call $delay_slot (global.get $pc))
        (global.set $pc (local.get $imm))))
    (if (i32.eq (local.get $hi) (i32.const 0x7e))
      (then
        (local.set $imm (call $fetch_imm))
        (call $push (i32.and (i32.add (global.get $pc) (i32.const 2)) (i32.const 0xffff)))
        (call $delay_slot (global.get $pc))
        (global.set $pc (local.get $imm))))
    (if (i32.eq (local.get $hi) (i32.const 0x7f))
      (then
        (local.set $imm (call $fetch_imm))
        (call $delay_slot (global.get $pc))
        (if (local.get $take) (then (global.set $pc (local.get $imm))))))
    (if (i32.and (i32.ge_u (local.get $hi) (i32.const 0xf0)) (i32.le_u (local.get $hi) (i32.const 0xf3)))
      (then
        (local.set $imm (call $fetch_imm))
        (if (call $cond (local.get $op))
          (then
            (if (i32.and (local.get $op) (i32.const 2)) (then (global.set $ov (i32.const 0))))
            (call $delay_slot (global.get $pc))
            (global.set $pc (local.get $imm))))))
    (if (i32.and (i32.ge_u (local.get $hi) (i32.const 0xf8)) (i32.le_u (local.get $hi) (i32.const 0xfb)))
      (then
        (local.set $imm (call $fetch_imm))
        (if (call $cond (local.get $op))
          (then
            (call $push (i32.and (i32.add (global.get $pc) (i32.const 2)) (i32.const 0xffff)))
            (if (i32.and (local.get $op) (i32.const 2)) (then (global.set $ov (i32.const 0))))
            (call $delay_slot (global.get $pc))
            (global.set $pc (local.get $imm))))))
    (if (i32.ge_u (local.get $hi) (i32.const 0xfc))
      (then
        (if (call $cond (local.get $op))
          (then
            (call $delay_slot (global.get $pc))
            (global.set $pc (call $pop))))))

    ;; AR0 mirror (C apply_ar0_mirror): with NDX=0, AR0 loads INDX and ARCR.
    (if (global.get $ar0dirty)
      (then
        (if (i32.eqz (global.get $ndx))
          (then
            (global.set $indx (call $ar_get (i32.const 0)))
            (global.set $arcr (call $ar_get (i32.const 0)))))
        (global.set $ar0dirty (i32.const 0))))

    (i32.const 0))

  ;; Run up to BUDGET instructions with the single-instruction repeat logic of
  ;; C c5x_run / handle_rpt.  Returns 0, or the step status on failure.
  (func (export "run") (param $budget i32) (result i32)
    (local $ppc i32) (local $st i32)
    (block $done
      (loop $next
        (br_if $done (i32.eqz (local.get $budget)))
        (local.set $ppc (global.get $pc))
        (local.set $st (call $step))
        (if (local.get $st) (then (return (local.get $st))))
        (if (i32.gt_s (global.get $rptc) (i32.const 0))
          (then
            (if (i32.eq (local.get $ppc) (global.get $rpt_end))
              (then
                (global.set $pc (global.get $rpt_start))
                (global.set $rptc (i32.sub (global.get $rptc) (i32.const 1))))))
          (else (global.set $rptc (i32.const 0))))
        (if (i32.and (global.get $braf)
                     (i32.eq (i32.and (i32.sub (global.get $pc) (i32.const 1)) (i32.const 0xffff))
                             (global.get $paer)))
          (then
            (if (i32.gt_s (global.get $brcr) (i32.const 0))
              (then
                (global.set $pc (global.get $pasr))
                (global.set $brcr (i32.sub (global.get $brcr) (i32.const 1))))
              (else (global.set $braf (i32.const 0))))))
        (local.set $budget (i32.sub (local.get $budget) (i32.const 1)))
        (br $next)))
    (i32.const 0))

  ;; Host accessors for state and memory (used by the differential test).
  (func (export "set") (param $id i32) (param $v i32)
    (if (i32.eq (local.get $id) (i32.const 0))  (then (global.set $acc (local.get $v))))
    (if (i32.eq (local.get $id) (i32.const 1))  (then (global.set $preg (local.get $v))))
    (if (i32.eq (local.get $id) (i32.const 2))  (then (global.set $t0 (local.get $v))))
    (if (i32.eq (local.get $id) (i32.const 3))  (then (global.set $t1 (local.get $v))))
    (if (i32.eq (local.get $id) (i32.const 4))  (then (global.set $t2 (local.get $v))))
    (if (i32.eq (local.get $id) (i32.const 5))  (then (global.set $dp (local.get $v))))
    (if (i32.eq (local.get $id) (i32.const 6))  (then (global.set $sxm (local.get $v))))
    (if (i32.eq (local.get $id) (i32.const 7))  (then (global.set $ovm (local.get $v))))
    (if (i32.eq (local.get $id) (i32.const 8))  (then (global.set $c (local.get $v))))
    (if (i32.eq (local.get $id) (i32.const 9))  (then (global.set $ov (local.get $v))))
    (if (i32.eq (local.get $id) (i32.const 10)) (then (global.set $pm (local.get $v))))
    (if (i32.eq (local.get $id) (i32.const 11)) (then (global.set $trm (local.get $v))))
    (if (i32.eq (local.get $id) (i32.const 12)) (then (global.set $pc (local.get $v))))
    (if (i32.and (i32.ge_u (local.get $id) (i32.const 20)) (i32.le_u (local.get $id) (i32.const 27)))
      (then
        (call $ar_set (i32.sub (local.get $id) (i32.const 20)) (local.get $v))
        (if (i32.eq (local.get $id) (i32.const 20)) (then (global.set $ar0dirty (i32.const 1))))))
    (if (i32.eq (local.get $id) (i32.const 28)) (then (global.set $arp (local.get $v))))
    (if (i32.eq (local.get $id) (i32.const 29)) (then (global.set $indx (i32.and (local.get $v) (i32.const 0xffff)))))
    (if (i32.eq (local.get $id) (i32.const 30)) (then (global.set $arcr (i32.and (local.get $v) (i32.const 0xffff)))))
    (if (i32.eq (local.get $id) (i32.const 31)) (then (global.set $ndx (local.get $v))))
    (if (i32.eq (local.get $id) (i32.const 32)) (then (global.set $cbcr (local.get $v))))
    (if (i32.eq (local.get $id) (i32.const 33)) (then (global.set $cbsr1 (local.get $v))))
    (if (i32.eq (local.get $id) (i32.const 34)) (then (global.set $cber1 (local.get $v))))
    (if (i32.eq (local.get $id) (i32.const 35)) (then (global.set $cbsr2 (local.get $v))))
    (if (i32.eq (local.get $id) (i32.const 36)) (then (global.set $cber2 (local.get $v))))
    (if (i32.eq (local.get $id) (i32.const 37)) (then (global.set $arb (local.get $v))))
    (if (i32.eq (local.get $id) (i32.const 38)) (then (global.set $sp (local.get $v))))
    (if (i32.eq (local.get $id) (i32.const 39)) (then (global.set $tc (local.get $v))))
    (if (i32.eq (local.get $id) (i32.const 40)) (then (global.set $bio (local.get $v))))
    (if (i32.and (i32.ge_u (local.get $id) (i32.const 41)) (i32.le_u (local.get $id) (i32.const 48)))
      (then (call $st_set (i32.sub (local.get $id) (i32.const 41)) (local.get $v))))
    (if (i32.eq (local.get $id) (i32.const 53)) (then (global.set $accb (local.get $v))))
    (if (i32.eq (local.get $id) (i32.const 54)) (then (global.set $intm (local.get $v))))
    (if (i32.eq (local.get $id) (i32.const 55)) (then (global.set $rptc (local.get $v))))
    (if (i32.eq (local.get $id) (i32.const 58)) (then (global.set $bmar (i32.and (local.get $v) (i32.const 0xffff)))))
    (if (i32.eq (local.get $id) (i32.const 59)) (then (global.set $braf (local.get $v))))
    (if (i32.eq (local.get $id) (i32.const 60)) (then (global.set $pasr (local.get $v))))
    (if (i32.eq (local.get $id) (i32.const 61)) (then (global.set $paer (local.get $v))))
    (if (i32.eq (local.get $id) (i32.const 62)) (then (global.set $brcr (local.get $v))))
    (if (i32.eq (local.get $id) (i32.const 50)) (then (global.set $hm (local.get $v))))
    (if (i32.eq (local.get $id) (i32.const 51)) (then (global.set $xf (local.get $v))))
    (if (i32.eq (local.get $id) (i32.const 52)) (then (global.set $cnf (local.get $v)))))

  (func (export "get") (param $id i32) (result i32)
    (local $r i32)
    (if (i32.and (i32.ge_u (local.get $id) (i32.const 20)) (i32.le_u (local.get $id) (i32.const 27)))
      (then (local.set $r (call $ar_get (i32.sub (local.get $id) (i32.const 20))))))
    (if (i32.eq (local.get $id) (i32.const 28)) (then (local.set $r (global.get $arp))))
    (if (i32.eq (local.get $id) (i32.const 29)) (then (local.set $r (global.get $indx))))
    (if (i32.eq (local.get $id) (i32.const 30)) (then (local.set $r (global.get $arcr))))
    (if (i32.eq (local.get $id) (i32.const 37)) (then (local.set $r (global.get $arb))))
    (if (i32.eq (local.get $id) (i32.const 12)) (then (local.set $r (global.get $pc))))
    (if (i32.eq (local.get $id) (i32.const 38)) (then (local.set $r (global.get $sp))))
    (if (i32.eq (local.get $id) (i32.const 39)) (then (local.set $r (global.get $tc))))
    (if (i32.and (i32.ge_u (local.get $id) (i32.const 41)) (i32.le_u (local.get $id) (i32.const 48)))
      (then (local.set $r (call $st_get (i32.sub (local.get $id) (i32.const 41))))))
    (if (i32.eq (local.get $id) (i32.const 0)) (then (local.set $r (global.get $acc))))
    (if (i32.eq (local.get $id) (i32.const 1)) (then (local.set $r (global.get $preg))))
    (if (i32.eq (local.get $id) (i32.const 2)) (then (local.set $r (global.get $t0))))
    (if (i32.eq (local.get $id) (i32.const 3)) (then (local.set $r (global.get $t1))))
    (if (i32.eq (local.get $id) (i32.const 4)) (then (local.set $r (global.get $t2))))
    (if (i32.eq (local.get $id) (i32.const 8)) (then (local.set $r (global.get $c))))
    (if (i32.eq (local.get $id) (i32.const 9)) (then (local.set $r (global.get $ov))))
    (if (i32.eq (local.get $id) (i32.const 6)) (then (local.set $r (global.get $sxm))))
    (if (i32.eq (local.get $id) (i32.const 7)) (then (local.set $r (global.get $ovm))))
    (if (i32.eq (local.get $id) (i32.const 50)) (then (local.set $r (global.get $hm))))
    (if (i32.eq (local.get $id) (i32.const 51)) (then (local.set $r (global.get $xf))))
    (if (i32.eq (local.get $id) (i32.const 52)) (then (local.set $r (global.get $cnf))))
    (if (i32.eq (local.get $id) (i32.const 5)) (then (local.set $r (global.get $dp))))
    (if (i32.eq (local.get $id) (i32.const 10)) (then (local.set $r (global.get $pm))))
    (if (i32.eq (local.get $id) (i32.const 53)) (then (local.set $r (global.get $accb))))
    (if (i32.eq (local.get $id) (i32.const 54)) (then (local.set $r (global.get $intm))))
    (if (i32.eq (local.get $id) (i32.const 55)) (then (local.set $r (global.get $rptc))))
    (if (i32.eq (local.get $id) (i32.const 58)) (then (local.set $r (global.get $bmar))))
    (if (i32.eq (local.get $id) (i32.const 59)) (then (local.set $r (global.get $braf))))
    (if (i32.eq (local.get $id) (i32.const 60)) (then (local.set $r (global.get $pasr))))
    (if (i32.eq (local.get $id) (i32.const 61)) (then (local.set $r (global.get $paer))))
    (if (i32.eq (local.get $id) (i32.const 62)) (then (local.set $r (global.get $brcr))))
    (local.get $r))

  (func (export "dm_rd") (param $a i32) (result i32)
    (call $dm_rd (local.get $a)))

  (func (export "dm_wr") (param $a i32) (param $v i32)
    (call $dm_wr (local.get $a) (local.get $v)))

  (func (export "pm_wr") (param $a i32) (param $v i32)
    (i32.store16 offset=131072 (i32.shl (local.get $a) (i32.const 1)) (local.get $v))))
