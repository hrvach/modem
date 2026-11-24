/*
   c5x_opcodes.h -- instruction names for the TMS320C5x core (c5x_core.c)

   A C5x instruction is one 16-bit word, optionally followed by a second word
   (an immediate or an address).  The core decodes on the high byte of the
   first word; the high byte alone names most instructions.  Where a single
   high byte stands for a family (LAR AR0..AR7, ADD with shifts 0..15, ...),
   the family is named by its first and last high byte and the low bits of the
   word select the member.

   Two high bytes, 0xBE and 0xBF, are further decoded on the low byte of the
   word; their sub-opcodes are named separately below.

   Mnemonics follow the TI C5x User's Guide (SPRU056D).  Names here are the
   mnemonic, plus a suffix when the same mnemonic has several encodings:
     _DMA   data-memory operand (direct or indirect addressing)
     _K8    8-bit immediate in the low byte
     _K9    9-bit immediate in the low 9 bits
     _K13   13-bit immediate in the low 13 bits
     _LK    16-bit immediate in the second word
     _DBMR  the operand is combined with the DBMR register
*/
#ifndef C5X_OPCODES_H
#define C5X_OPCODES_H

/* ------------------------------------------------------------------
   Fields inside the instruction word
   ------------------------------------------------------------------ */

/* Data-memory operand (dma), the low byte of the first word.
     bit 7 = 0   direct: data page pointer DP (9 bits) followed by a 7-bit offset
     bit 7 = 1   indirect: through the auxiliary register ARP, with an addressing
                 mode (bits 6-3) and the next ARP value (bits 2-0) */
#define C5X_DMA_INDIRECT_BIT 0x80
#define C5X_DMA_DIRECT_OFFSET_MASK 0x7F
#define C5X_DMA_NEXT_ARP_MASK 0x07
#define C5X_DMA_MODE_SHIFT 3
#define C5X_DMA_MODE_MASK 0x0F

/* Bit 0 of the indirect mode field: also load ARP with the next-ARP field. */
#define C5X_DMA_MODE_LOAD_ARP_BIT 0x1

/* Indirect addressing modes (the mode field with the load-ARP bit cleared). */
enum c5x_indirect_mode {
    C5X_AM_NONE = 0x0,    /* *       use ARn as is */
    C5X_AM_DEC = 0x2,     /* *-      use ARn, then decrement it */
    C5X_AM_INC = 0x4,     /* *+      use ARn, then increment it */
    C5X_AM_BR0_DEC = 0x8, /* *BR0-   use ARn, then subtract INDX with reversed carry propagation */
    C5X_AM_INDX_DEC = 0xA, /* *0-    use ARn, then subtract INDX */
    C5X_AM_INDX_INC = 0xC, /* *0+    use ARn, then add INDX */
    C5X_AM_BR0_INC = 0xE   /* *BR0+  use ARn, then add INDX with reversed carry propagation */
};

/* Fields of the high byte shared by instruction families. */
#define C5X_OP_AR_MASK 0x07    /* LAR, SAR, LAR #k8: the auxiliary register number */
#define C5X_OP_SHIFT_MASK 0x0F /* LACC/ADD/SUB/BIT with a shift: the shift or bit number */
#define C5X_OP_SACX_SHIFT_MASK 0x07 /* SACL/SACH: the left shift, 0-7 */

/* Low byte of the word used as an 8-bit immediate (ADDK, LACK, SUBK, RPT #k8, ADRK, SBRK, LAR #k8). */
#define C5X_K8_MASK 0xFF

/* CMPR compares AR[ARP] with ARCR; the mode is the low 2 bits of the word. */
#define C5X_BF_CMPR_MODE_MASK 0x03
enum c5x_cmpr_mode { C5X_CMPR_EQUAL = 0, C5X_CMPR_LESS = 1, C5X_CMPR_GREATER = 2, C5X_CMPR_NOT_EQUAL = 3 };

/* SPM: the new product shift mode is the low 2 bits of the word. */
#define C5X_BF_SPM_MASK 0x03

/* BF long-immediate ALU row: the low nibble is the shift count. */
#define C5X_BF_SHIFT_MASK 0x0F

/* ------------------------------------------------------------------
   High byte of the first instruction word
   ------------------------------------------------------------------ */
enum c5x_opcode {
    /* 0x00-0x0F: loads and special register moves. */
    C5X_OP_LAR_DMA_FIRST = 0x00, /* LAR ARn, dma: n is the low 3 bits of the high byte */
    C5X_OP_LAR_DMA_LAST = 0x07,
    C5X_OP_LAMM = 0x08,    /* ACC = memory-mapped register */
    C5X_OP_SMMR = 0x09,    /* store an MMR to successive program addresses */
    C5X_OP_SUBC = 0x0A,    /* conditional subtract: one step of a divide */
    C5X_OP_RPT_DMA = 0x0B, /* repeat the next instruction, count from data memory */
    C5X_OP_OUT = 0x0C,     /* write a data word to an I/O port (two words) */
    C5X_OP_LDP_DMA = 0x0D, /* load the data page pointer from data memory */
    C5X_OP_LST0 = 0x0E,    /* load status register ST0 */
    C5X_OP_LST1 = 0x0F,    /* load status register ST1 */

    /* 0x10-0x4F: accumulator operations with a shift (0-15) in the low nibble of the high byte. */
    C5X_OP_LACC_SHIFT_FIRST = 0x10, /* ACC = dma << shift */
    C5X_OP_LACC_SHIFT_LAST = 0x1F,
    C5X_OP_ADD_SHIFT_FIRST = 0x20, /* ACC += dma << shift */
    C5X_OP_ADD_SHIFT_LAST = 0x2F,
    C5X_OP_SUB_SHIFT_FIRST = 0x30, /* ACC -= dma << shift */
    C5X_OP_SUB_SHIFT_LAST = 0x3F,
    C5X_OP_BIT_FIRST = 0x40, /* TC = one bit of dma; the bit number is in the low nibble */
    C5X_OP_BIT_LAST = 0x4F,

    /* 0x50-0x5F: multiplies and logic on data memory. */
    C5X_OP_MPYA = 0x50,   /* ACC += PREG, PREG = TREG0 * dma */
    C5X_OP_MPYS = 0x51,   /* ACC -= PREG, PREG = TREG0 * dma */
    C5X_OP_SQRA = 0x52,   /* ACC += PREG, TREG0 = dma, PREG = dma * dma */
    C5X_OP_SQRS = 0x53,   /* ACC -= PREG, TREG0 = dma, PREG = dma * dma */
    C5X_OP_MPY_DMA = 0x54, /* PREG = TREG0 * dma, signed */
    C5X_OP_MPYU = 0x55,   /* PREG = TREG0 * dma, unsigned */
    C5X_OP_UNDEFINED_56 = 0x56,
    C5X_OP_BLDP = 0x57,     /* block move data -> program, BMAR as the data address */
    C5X_OP_XPL_DBMR = 0x58, /* dma ^= DBMR */
    C5X_OP_OPL_DBMR = 0x59, /* dma |= DBMR */
    C5X_OP_APL_DBMR = 0x5A, /* dma &= DBMR */
    C5X_OP_CPL_DBMR = 0x5B, /* compare dma with DBMR, sets TC */
    C5X_OP_XPL_LK = 0x5C,   /* dma ^= immediate (two words) */
    C5X_OP_OPL_LK = 0x5D,
    C5X_OP_APL_LK = 0x5E,
    C5X_OP_CPL_LK = 0x5F,

    /* 0x60-0x7F: add/subtract variants, loads, logic, branches. */
    C5X_OP_ADDC = 0x60,   /* ACC += dma + C */
    C5X_OP_ADD_16 = 0x61, /* ACC += dma << 16 */
    C5X_OP_ADDS = 0x62,   /* ACC += dma, zero-extended */
    C5X_OP_ADDT = 0x63,   /* ACC += dma << TREG1 */
    C5X_OP_SUBB = 0x64,   /* ACC -= dma + !C */
    C5X_OP_SUB_16 = 0x65,
    C5X_OP_SUBS = 0x66,
    C5X_OP_SUBT = 0x67,
    C5X_OP_ZALR = 0x68,   /* ACC = (dma << 16) + 0x8000, a rounding load */
    C5X_OP_LACL = 0x69,   /* ACC = dma, zero-extended */
    C5X_OP_LACC_16 = 0x6A, /* ACC = dma << 16 */
    C5X_OP_LACT = 0x6B,   /* ACC = dma << TREG1 */
    C5X_OP_XOR = 0x6C,
    C5X_OP_OR = 0x6D,
    C5X_OP_AND = 0x6E,
    C5X_OP_BITT = 0x6F, /* TC = bit (15 - TREG2) of dma */
    C5X_OP_LTA = 0x70,  /* ACC += PREG, TREG0 = dma */
    C5X_OP_LTP = 0x71,  /* ACC = PREG, TREG0 = dma */
    C5X_OP_LTD = 0x72,  /* ACC += PREG, TREG0 = dma, then DMOV */
    C5X_OP_LT = 0x73,   /* TREG0 = dma */
    C5X_OP_LTS = 0x74,  /* ACC -= PREG, TREG0 = dma */
    C5X_OP_LPH = 0x75,  /* high half of PREG = dma */
    C5X_OP_PSHD = 0x76, /* push dma onto the hardware stack */
    C5X_OP_DMOV = 0x77, /* copy dma to the next address (on-chip RAM only) */
    C5X_OP_ADRK = 0x78, /* AR[ARP] += K8 */
    C5X_OP_B = 0x79,
    C5X_OP_CALL = 0x7A,
    C5X_OP_BANZ = 0x7B, /* branch if AR[ARP] != 0 */
    C5X_OP_SBRK = 0x7C, /* AR[ARP] -= K8 */
    C5X_OP_BD = 0x7D,    /* delayed branch */
    C5X_OP_CALLD = 0x7E, /* delayed call */
    C5X_OP_BANZD = 0x7F, /* delayed BANZ */

    /* 0x80-0x9F: stores. */
    C5X_OP_SAR_FIRST = 0x80, /* store ARn: n is the low 3 bits of the high byte */
    C5X_OP_SAR_LAST = 0x87,
    C5X_OP_SAMM = 0x88, /* store ACC low half to a memory-mapped register */
    C5X_OP_LMMR = 0x89, /* load memory-mapped registers from program memory (two words) */
    C5X_OP_POPD = 0x8A, /* pop the stack into dma */
    C5X_OP_MAR = 0x8B,  /* modify the auxiliary register, no data access */
    C5X_OP_SPL = 0x8C,  /* store the low half of PREG */
    C5X_OP_SPH = 0x8D,  /* store the high half of PREG */
    C5X_OP_SST0 = 0x8E, /* store ST0 */
    C5X_OP_SST1 = 0x8F, /* store ST1 */
    C5X_OP_SACL_FIRST = 0x90, /* store ACC low half << shift; the shift is the low 3 bits */
    C5X_OP_SACL_LAST = 0x97,
    C5X_OP_SACH_FIRST = 0x98, /* store ACC high half << shift */
    C5X_OP_SACH_LAST = 0x9F,

    /* 0xA0-0xAF: block moves, table access, multiply-accumulate, I/O. */
    C5X_OP_NORM = 0xA0,
    C5X_OP_UNDEFINED_A1 = 0xA1,
    C5X_OP_MAC = 0xA2,  /* multiply-accumulate with a program-memory operand (two words) */
    C5X_OP_MACD = 0xA3, /* MAC with data move */
    C5X_OP_BLPD_BMAR = 0xA4, /* block move program -> data, BMAR as the program address */
    C5X_OP_BLPD_PMA = 0xA5,  /* block move program -> data, address in the second word */
    C5X_OP_TBLR = 0xA6,      /* table read: program (ACC) -> data */
    C5X_OP_TBLW = 0xA7,      /* table write: data -> program (ACC) */
    C5X_OP_BLDD_LK_DMA = 0xA8, /* block move data -> data, source in the second word */
    C5X_OP_BLDD_DMA_LK = 0xA9, /* block move data -> data, destination in the second word */
    C5X_OP_MADS = 0xAA,        /* MAC with the program address in BMAR */
    C5X_OP_MADD = 0xAB,        /* MADS with data move */
    C5X_OP_BLDD_BMAR_DMA = 0xAC,
    C5X_OP_BLDD_DMA_BMAR = 0xAD,
    C5X_OP_SPLK = 0xAE, /* store the second word to data memory */
    C5X_OP_IN = 0xAF,   /* read a data word from an I/O port (two words) */

    /* 0xB0-0xBF: 8-bit immediates, and the two sub-decoded groups. */
    C5X_OP_LAR_K8_FIRST = 0xB0, /* ARn = K8: n is the low 3 bits of the high byte */
    C5X_OP_LAR_K8_LAST = 0xB7,
    C5X_OP_ADDK = 0xB8,
    C5X_OP_LACK = 0xB9,
    C5X_OP_SUBK = 0xBA,
    C5X_OP_RPT_K8 = 0xBB,
    C5X_OP_LDP_K9_FIRST = 0xBC, /* the 9-bit value spills into the low bit of the high byte */
    C5X_OP_LDP_K9_LAST = 0xBD,
    C5X_OP_GROUP_BE = 0xBE, /* accumulator, control and status instructions; see enum c5x_be below */
    C5X_OP_GROUP_BF = 0xBF, /* SPM, LAR, CMPR, long immediates; see enum c5x_bf below */

    /* 0xC0-0xDF: MPY with a 13-bit immediate. */
    C5X_OP_MPY_K13_FIRST = 0xC0,
    C5X_OP_MPY_K13_LAST = 0xDF,

    /* 0xE0-0xFF: conditional branches, calls, returns and XC. */
    C5X_OP_BCND_FIRST = 0xE0, /* conditional branch (two words) */
    C5X_OP_BCND_LAST = 0xE3,
    C5X_OP_XC_1_FIRST = 0xE4, /* execute the next 1 word if the condition holds */
    C5X_OP_XC_1_LAST = 0xE7,
    C5X_OP_CC_FIRST = 0xE8, /* conditional call (two words) */
    C5X_OP_CC_LAST = 0xEB,
    C5X_OP_RETC_FIRST = 0xEC, /* conditional return */
    C5X_OP_RETC_LAST = 0xEF,
    C5X_OP_BCNDD_FIRST = 0xF0, /* delayed conditional branch */
    C5X_OP_BCNDD_LAST = 0xF3,
    C5X_OP_XC_2_FIRST = 0xF4, /* execute the next 2 words if the condition holds */
    C5X_OP_XC_2_LAST = 0xF7,
    C5X_OP_CCD_FIRST = 0xF8, /* delayed conditional call */
    C5X_OP_CCD_LAST = 0xFB,
    C5X_OP_RETCD_FIRST = 0xFC, /* delayed conditional return */
    C5X_OP_RETCD_LAST = 0xFF
};

/* Bit 1 of the conditional branch/call words: also clear OV when the branch is taken. */
#define C5X_COND_CLEAR_OV_BIT 0x0002u

/* Bit 12 of an XC word: 0 = skip/execute 1 word, 1 = 2 words. */
#define C5X_XC_TWO_WORDS_BIT 12

/* ------------------------------------------------------------------
   Low byte of the 0xBE group
   ------------------------------------------------------------------ */
enum c5x_be {
    /* 0x00-0x1F: operations on ACC and ACCB. */
    C5X_BE_ABS = 0x00,  /* ACC = |ACC| */
    C5X_BE_CMPL = 0x01, /* ACC = ~ACC */
    C5X_BE_NEG = 0x02,  /* ACC = -ACC */
    C5X_BE_PAC = 0x03,  /* ACC = PREG */
    C5X_BE_APAC = 0x04, /* ACC += PREG */
    C5X_BE_SPAC = 0x05, /* ACC -= PREG */
    C5X_BE_SFL = 0x09,  /* shift ACC left one bit */
    C5X_BE_SFR = 0x0A,  /* shift ACC right one bit */
    C5X_BE_ROL = 0x0C,  /* rotate ACC left through carry */
    C5X_BE_ROR = 0x0D,  /* rotate ACC right through carry */
    C5X_BE_ADDB = 0x10, /* ACC += ACCB */
    C5X_BE_ADCB = 0x11, /* ACC += ACCB + C */
    C5X_BE_ANDB = 0x12,
    C5X_BE_ORB = 0x13,
    C5X_BE_ROLB = 0x14, /* rotate ACCB:ACC left through carry */
    C5X_BE_RORB = 0x15,
    C5X_BE_SFLB = 0x16, /* shift ACCB:ACC left one bit */
    C5X_BE_SFRB = 0x17,
    C5X_BE_SUBB = 0x18, /* ACC -= ACCB */
    C5X_BE_SBBB = 0x19, /* ACC -= ACCB + !C */
    C5X_BE_XORB = 0x1A,
    C5X_BE_CRGT = 0x1B, /* ACCB = max(ACC, ACCB) */
    C5X_BE_CRLT = 0x1C, /* ACC = min(ACC, ACCB) */
    C5X_BE_EXAR = 0x1D, /* exchange ACC and ACCB */
    C5X_BE_SACB = 0x1E, /* ACCB = ACC */
    C5X_BE_LACB = 0x1F, /* ACC = ACCB */

    /* 0x20-0xFF: control, status and immediate operations. */
    C5X_BE_BACC = 0x20,  /* branch to ACC */
    C5X_BE_BACCD = 0x21, /* delayed branch to ACC */
    C5X_BE_IDLE = 0x22,
    C5X_BE_IDLE2 = 0x23,
    C5X_BE_CALA = 0x30, /* call ACC */
    C5X_BE_POP = 0x32,  /* ACC = pop the stack */
    C5X_BE_RETI = 0x38, /* return from interrupt */
    C5X_BE_RETE = 0x3A, /* return from interrupt and enable interrupts */
    C5X_BE_PSHA = 0x3C, /* push ACC low half */
    C5X_BE_CALAD = 0x3D, /* delayed call ACC */
    C5X_BE_EINT = 0x40, /* enable interrupts */
    C5X_BE_DINT = 0x41, /* disable interrupts */
    C5X_BE_ROVM = 0x42, /* reset the overflow mode bit */
    C5X_BE_SOVM = 0x43,
    C5X_BE_RCNF = 0x44, /* reset the RAM configuration bit */
    C5X_BE_SCNF = 0x45,
    C5X_BE_RSXM = 0x46, /* reset the sign-extension mode bit */
    C5X_BE_SSXM = 0x47,
    C5X_BE_RHM = 0x48, /* reset the hold mode bit */
    C5X_BE_SHM = 0x49,
    C5X_BE_RTC = 0x4A, /* reset TC */
    C5X_BE_STC = 0x4B,
    C5X_BE_RXF = 0x4C, /* reset the external flag XF */
    C5X_BE_SXF = 0x4D,
    C5X_BE_RCB = 0x4E, /* reset the carry bit */
    C5X_BE_SCB = 0x4F,
    C5X_BE_TRAP = 0x51, /* software interrupt through vector 0x22 */
    C5X_BE_NMI = 0x52,  /* software NMI */
    C5X_BE_ZPR = 0x58,  /* PREG = 0 */
    C5X_BE_ZAP = 0x59,  /* ACC = PREG = 0 */
    C5X_BE_SATH = 0x5A, /* ACC >>= 16 when TREG1 bit 4 is set */
    C5X_BE_SATL = 0x5B, /* ACC >>= TREG1 & 0xF */
    C5X_BE_MPY_LK = 0x80,      /* PREG = TREG0 * second word */
    C5X_BE_AND_LK_16 = 0x81,   /* ACC &= second word << 16 */
    C5X_BE_OR_LK_16 = 0x82,
    C5X_BE_XOR_LK_16 = 0x83,
    C5X_BE_RPT_LK = 0xC4,  /* repeat the next instruction, count in the second word */
    C5X_BE_RPTZ_LK = 0xC5, /* RPT with ACC = PREG = 0 */
    C5X_BE_RPTB = 0xC6     /* repeat a block; the block end is in the second word */
};

/* INTR k, also in the 0xBE group: low byte 0x60-0x7F, the vector number k in the low 5 bits. */
#define C5X_BE_INTR_MASK 0xE0
#define C5X_BE_INTR_BASE 0x60
#define C5X_BE_INTR_VECTOR_MASK 0x1F

/* The boundary between the two halves of the 0xBE group's decoder. */
#define C5X_BE_CONTROL_FIRST 0x20

/* ------------------------------------------------------------------
   Low byte of the 0xBF group
   ------------------------------------------------------------------ */
enum c5x_bf {
    C5X_BF_SPM_FIRST = 0x00, /* set the product shift mode PM to the low 2 bits */
    C5X_BF_SPM_LAST = 0x03,
    C5X_BF_LAR_LK_FIRST = 0x08, /* ARn = second word: n is the low 3 bits */
    C5X_BF_LAR_LK_LAST = 0x0F,
    C5X_BF_CMPR_FIRST = 0x44, /* compare AR[ARP] with ARCR, sets TC; the mode is the low 2 bits */
    C5X_BF_CMPR_LAST = 0x47
};

/* The other 0xBF opcodes are selected by the high nibble of the low byte; the low nibble is a
   shift count.  Each takes a second word, except SFTA. */
enum c5x_bf_row {
    C5X_BF_ROW_MASK = 0xF0,
    C5X_BF_ROW_LACC_LK = 0x80, /* ACC = LK << shift */
    C5X_BF_ROW_ADD_LK = 0x90,
    C5X_BF_ROW_SUB_LK = 0xA0,
    C5X_BF_ROW_AND_LK = 0xB0,
    C5X_BF_ROW_OR_LK = 0xC0,
    C5X_BF_ROW_XOR_LK = 0xD0,
    C5X_BF_ROW_SFTA = 0xE0, /* ACC >>= shift + 1, arithmetic if SXM */
    C5X_BF_ROW_LK_FIRST = C5X_BF_ROW_LACC_LK,
    C5X_BF_ROW_LK_LAST = C5X_BF_ROW_XOR_LK
};

#endif /* C5X_OPCODES_H */
