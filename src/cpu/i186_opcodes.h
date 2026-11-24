/*
   i186_opcodes.h -- instruction names for the 80C186EB core (i186.c)

   Every primary opcode byte the core knows by name, the prefix bytes, and
   the values of the ModR/M reg field that pick an instruction inside the
   group opcodes.  Opcodes come in byte/word pairs: the word form is the
   byte form + 1 (bit 0 is the operand width).  Families that cover a whole
   run of opcodes are named by their first and last member.
*/
#ifndef I186_OPCODES_H
#define I186_OPCODES_H

/* ------------------------------------------------------------------
   Prefix bytes
   ------------------------------------------------------------------ */
#define PREFIX_ES 0x26u
#define PREFIX_CS 0x2Eu
#define PREFIX_SS 0x36u
#define PREFIX_DS 0x3Eu
#define PREFIX_LOCK 0xF0u
#define PREFIX_REPNE 0xF2u /* REPNE / REPNZ */
#define PREFIX_REP 0xF3u   /* REP / REPE / REPZ */

/* Bit 0 of most opcodes: 1 = word form, 0 = byte form. */
#define OP_WIDTH_BIT 0x01u

/* ------------------------------------------------------------------
   The ALU block, opcodes 0x00-0x3F.
   Eight operations (ADD, OR, ADC, SBB, AND, SUB, XOR, CMP) with six forms
   each; the operation is opcode >> 3 and the form is opcode & 7.  The two
   remaining slots of each row hold PUSH/POP of a segment register, the
   decimal adjusts and the segment prefixes.
   ------------------------------------------------------------------ */
#define OP_ALU_END 0x40u /* first opcode after the ALU block */
#define ALU_OP_SHIFT 3
#define ALU_FORM_MASK 7
#define ALU_FORM_COUNT 6

enum alu_form {
    ALU_FORM_RM_REG_BYTE = 0, /* r/m8, reg8 */
    ALU_FORM_RM_REG_WORD = 1, /* r/m16, reg16 */
    ALU_FORM_REG_RM_BYTE = 2, /* reg8, r/m8 */
    ALU_FORM_REG_RM_WORD = 3, /* reg16, r/m16 */
    ALU_FORM_AL_IMM = 4,      /* AL, imm8 */
    ALU_FORM_AX_IMM = 5       /* AX, imm16 */
};

/* ALU operation codes: the reg field of the 0x80-0x83 group, and opcode >> 3
   in the ALU block. */
enum alu_op { ALU_ADD = 0, ALU_OR = 1, ALU_ADC = 2, ALU_SBB = 3, ALU_AND = 4, ALU_SUB = 5, ALU_XOR = 6, ALU_CMP = 7 };

/* ------------------------------------------------------------------
   Opcodes
   ------------------------------------------------------------------ */
enum i186_opcode {
    /* Segment registers on the stack. */
    OP_PUSH_ES = 0x06,
    OP_POP_ES = 0x07,
    OP_PUSH_CS = 0x0E, /* there is no POP CS */
    OP_PUSH_SS = 0x16,
    OP_POP_SS = 0x17,
    OP_PUSH_DS = 0x1E,
    OP_POP_DS = 0x1F,

    /* Decimal adjusts. */
    OP_DAA = 0x27,
    OP_DAS = 0x2F,
    OP_AAA = 0x37,
    OP_AAS = 0x3F,
    OP_AAM = 0xD4,
    OP_AAD = 0xD5,

    /* INC/DEC and PUSH/POP of a 16-bit register; the register is opcode & 7. */
    OP_INC_REG_FIRST = 0x40, /* 0x40-0x47 INC, 0x48-0x4F DEC */
    OP_INC_REG_LAST = 0x47,
    OP_DEC_REG_FIRST = 0x48,
    OP_DEC_REG_LAST = 0x4F,
    OP_PUSH_REG_FIRST = 0x50,
    OP_PUSH_SP = 0x54, /* pushes SP as it was before the instruction */
    OP_PUSH_REG_LAST = 0x57,
    OP_POP_REG_FIRST = 0x58,
    OP_POP_SP = 0x5C,
    OP_POP_REG_LAST = 0x5F,

    /* 80186 additions. */
    OP_PUSHA = 0x60,
    OP_POPA = 0x61,
    OP_BOUND = 0x62,
    OP_PUSH_IMM16 = 0x68,
    OP_IMUL_IMM16 = 0x69,
    OP_PUSH_IMM8 = 0x6A, /* sign-extended */
    OP_IMUL_IMM8 = 0x6B,
    OP_INS_BYTE = 0x6C,
    OP_INS_WORD = 0x6D,
    OP_OUTS_BYTE = 0x6E,
    OP_OUTS_WORD = 0x6F,

    /* Conditional jumps; the condition is opcode & 0xF. */
    OP_JCC_FIRST = 0x70,
    OP_JCC_LAST = 0x7F,

    /* ALU with an immediate: reg field selects the ALU operation. */
    OP_ALU_IMM_BYTE = 0x80,
    OP_ALU_IMM_WORD = 0x81,
    OP_ALU_IMM_BYTE_ALIAS = 0x82, /* same as 0x80 */
    OP_ALU_IMM_SIGNED = 0x83,     /* imm8 sign-extended to 16 bits */

    /* TEST, XCHG and MOV with a ModR/M operand. */
    OP_TEST_RM_REG_BYTE = 0x84,
    OP_TEST_RM_REG_WORD = 0x85,
    OP_XCHG_RM_REG_BYTE = 0x86,
    OP_XCHG_RM_REG_WORD = 0x87,
    OP_MOV_RM_REG_BYTE = 0x88,
    OP_MOV_RM_REG_WORD = 0x89,
    OP_MOV_REG_RM_BYTE = 0x8A,
    OP_MOV_REG_RM_WORD = 0x8B,
    OP_MOV_RM_SREG = 0x8C,
    OP_LEA = 0x8D,
    OP_MOV_SREG_RM = 0x8E,
    OP_POP_RM = 0x8F,

    OP_NOP = 0x90, /* really XCHG AX, AX */
    OP_XCHG_AX_FIRST = 0x91,
    OP_XCHG_AX_LAST = 0x97,
    OP_CBW = 0x98,
    OP_CWD = 0x99,
    OP_CALL_FAR = 0x9A,
    OP_WAIT = 0x9B,
    OP_PUSHF = 0x9C,
    OP_POPF = 0x9D,
    OP_SAHF = 0x9E,
    OP_LAHF = 0x9F,

    /* MOV between the accumulator and a direct address. */
    OP_MOV_AL_MOFFS = 0xA0,
    OP_MOV_AX_MOFFS = 0xA1,
    OP_MOV_MOFFS_AL = 0xA2,
    OP_MOV_MOFFS_AX = 0xA3,

    /* String instructions. */
    OP_MOVS_BYTE = 0xA4,
    OP_MOVS_WORD = 0xA5,
    OP_CMPS_BYTE = 0xA6,
    OP_CMPS_WORD = 0xA7,
    OP_STOS_BYTE = 0xAA,
    OP_STOS_WORD = 0xAB,
    OP_LODS_BYTE = 0xAC,
    OP_LODS_WORD = 0xAD,
    OP_SCAS_BYTE = 0xAE,
    OP_SCAS_WORD = 0xAF,

    OP_TEST_AL_IMM = 0xA8,
    OP_TEST_AX_IMM = 0xA9,

    /* MOV reg, imm: 0xB0-0xB7 take an 8-bit register, 0xB8-0xBF a 16-bit one. */
    OP_MOV_REG_IMM_FIRST = 0xB0,
    OP_MOV_REG16_IMM_FIRST = 0xB8,
    OP_MOV_REG_IMM_LAST = 0xBF,

    OP_SHIFT_IMM_BYTE = 0xC0,
    OP_SHIFT_IMM_WORD = 0xC1,
    OP_RET_NEAR_POP = 0xC2, /* RET imm16 */
    OP_RET_NEAR = 0xC3,
    OP_LES = 0xC4,
    OP_LDS = 0xC5,
    OP_MOV_RM_IMM_BYTE = 0xC6,
    OP_MOV_RM_IMM_WORD = 0xC7,
    OP_ENTER = 0xC8,
    OP_LEAVE = 0xC9,
    OP_RET_FAR_POP = 0xCA, /* RETF imm16 */
    OP_RET_FAR = 0xCB,
    OP_INT3 = 0xCC,
    OP_INT_IMM = 0xCD,
    OP_INTO = 0xCE,
    OP_IRET = 0xCF,

    OP_SHIFT_1_BYTE = 0xD0, /* shift or rotate by 1 */
    OP_SHIFT_1_WORD = 0xD1,
    OP_SHIFT_CL_BYTE = 0xD2, /* shift or rotate by CL */
    OP_SHIFT_CL_WORD = 0xD3,
    OP_XLAT = 0xD7,
    OP_ESC_FIRST = 0xD8, /* coprocessor escape: decoded and ignored */
    OP_ESC_LAST = 0xDF,

    OP_LOOPNE = 0xE0,
    OP_LOOPE = 0xE1,
    OP_LOOP = 0xE2,
    OP_JCXZ = 0xE3,
    OP_IN_AL_IMM = 0xE4,
    OP_IN_AX_IMM = 0xE5,
    OP_OUT_IMM_AL = 0xE6,
    OP_OUT_IMM_AX = 0xE7,
    OP_CALL_NEAR = 0xE8,
    OP_JMP_NEAR = 0xE9,
    OP_JMP_FAR = 0xEA,
    OP_JMP_SHORT = 0xEB,
    OP_IN_AL_DX = 0xEC,
    OP_IN_AX_DX = 0xED,
    OP_OUT_DX_AL = 0xEE,
    OP_OUT_DX_AX = 0xEF,

    OP_HLT = 0xF4,
    OP_CMC = 0xF5,
    OP_GROUP_F6 = 0xF6, /* TEST/NOT/NEG/MUL/IMUL/DIV/IDIV r/m8 */
    OP_GROUP_F7 = 0xF7, /* the same on r/m16 */
    OP_CLC = 0xF8,
    OP_STC = 0xF9,
    OP_CLI = 0xFA,
    OP_STI = 0xFB,
    OP_CLD = 0xFC,
    OP_STD = 0xFD,
    OP_GROUP_FE = 0xFE, /* INC/DEC r/m8 */
    OP_GROUP_FF = 0xFF  /* INC/DEC/CALL/JMP/PUSH r/m16 */
};

/* ------------------------------------------------------------------
   ModR/M reg field values inside the group opcodes
   ------------------------------------------------------------------ */

/* Shifts and rotates (opcodes 0xC0, 0xC1, 0xD0-0xD3). */
enum shift_op {
    SHIFT_ROL = 0,
    SHIFT_ROR = 1,
    SHIFT_RCL = 2,
    SHIFT_RCR = 3,
    SHIFT_SHL = 4,
    SHIFT_SHR = 5,
    SHIFT_SHL_ALIAS = 6, /* a second encoding of SHL; the opcode handlers reject it as undefined */
    SHIFT_SAR = 7
};

/* Group 0xF6 / 0xF7. */
enum group_f6f7_reg {
    F6F7_REG_TEST = 0,
    F6F7_REG_TEST_ALIAS = 1, /* undefined: the handler rejects it */
    F6F7_REG_NOT = 2,
    F6F7_REG_NEG = 3,
    F6F7_REG_MUL = 4,
    F6F7_REG_IMUL = 5,
    F6F7_REG_DIV = 6,
    F6F7_REG_IDIV = 7
};

/* Groups 0xFE / 0xFF (0xFE only has INC and DEC). */
enum group_ff_reg {
    FF_REG_INC = 0,
    FF_REG_DEC = 1,
    FF_REG_CALL_NEAR = 2,
    FF_REG_CALL_FAR = 3,
    FF_REG_JMP_NEAR = 4,
    FF_REG_JMP_FAR = 5,
    FF_REG_PUSH = 6
};

/* ------------------------------------------------------------------
   ModR/M byte
   ------------------------------------------------------------------ */

/* The mod field. */
enum modrm_mod {
    MODRM_MOD_NO_DISPLACEMENT = 0, /* memory operand (r/m 6: a 16-bit direct address) */
    MODRM_MOD_DISPLACEMENT_8 = 1,  /* memory operand + sign-extended 8-bit displacement */
    MODRM_MOD_DISPLACEMENT_16 = 2, /* memory operand + 16-bit displacement */
    MODRM_MOD_REGISTER = 3         /* the operand is a register */
};

/* The r/m field of a memory operand: which registers form the address. */
enum modrm_rm {
    MODRM_RM_BX_SI = 0,
    MODRM_RM_BX_DI = 1,
    MODRM_RM_BP_SI = 2, /* BP-based forms default to the stack segment */
    MODRM_RM_BP_DI = 3,
    MODRM_RM_SI = 4,
    MODRM_RM_DI = 5,
    MODRM_RM_BP_OR_DIRECT = 6, /* mod 0: direct address; otherwise BP + displacement */
    MODRM_RM_BX = 7
};

/* MOV r/m, imm and POP r/m only exist with this reg field. */
#define MODRM_REG_ONLY_FORM 0

/* ------------------------------------------------------------------
   Conditions of the Jcc opcodes 0x70-0x7F
   ------------------------------------------------------------------ */

/* The condition is (opcode & 0xF) >> 1; bit 0 of the opcode inverts it. */
enum condition {
    COND_OVERFLOW = 0,
    COND_BELOW = 1, /* carry */
    COND_EQUAL = 2, /* zero */
    COND_BELOW_OR_EQUAL = 3,
    COND_SIGN = 4,
    COND_PARITY = 5,
    COND_LESS = 6,
    COND_LESS_OR_EQUAL = 7
};

#endif /* I186_OPCODES_H */
