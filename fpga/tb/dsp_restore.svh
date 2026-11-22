/* generated from cosim.cpp rtl_load_snapshot (C5x snapshot -> RTL registers); snv[] = snapshot scalar words */
u_dsp.u_alu.acc_q = snv[0]; u_dsp.u_alu.accb_q = snv[1]; u_dsp.u_alu.preg_q = snv[2];
u_dsp.u_alu.treg0_q = snv[3]; u_dsp.u_alu.treg1_q = snv[4] & 'h1F; u_dsp.u_alu.treg2_q = snv[5] & 'hF;
for (i = 0; i < 8; i = i + 1) begin u_dsp.u_addr.ar_q[i] = snv[109 + i]; u_dsp.u_addr.stack_q[i] = snv[117 + i]; end
u_dsp.u_addr.arp_q = snv[6] & 7; u_dsp.u_addr.arb_q = snv[7] & 7; u_dsp.u_addr.ov_q = snv[9] & 1; u_dsp.u_alu.ov_q = snv[9] & 1; u_dsp.u_addr.ovm_q = snv[10] & 1; u_dsp.u_addr.intm_q = snv[11] & 1;
u_dsp.u_addr.dp_q = snv[8] & 'hFFFF; u_dsp.u_addr.cnf_q = snv[12] & 1; u_dsp.u_addr.tc_q = snv[13] & 1; u_dsp.u_addr.sxm_q = snv[14] & 1; u_dsp.u_addr.c_q = snv[15] & 1; u_dsp.u_alu.c_q = snv[15] & 1;
u_dsp.u_addr.hm_q = snv[16] & 1; u_dsp.u_addr.xf_q = snv[17] & 1; u_dsp.u_addr.pm_q = snv[18] & 3; u_dsp.u_addr.iptr_q = snv[19] & 'h1F; u_dsp.u_addr.avis_q = snv[20] & 1; u_dsp.u_addr.ovly_q = snv[21] & 1;
u_dsp.u_addr.ram_q = snv[22] & 1; u_dsp.u_addr.mpmc_q = snv[23] & 1; u_dsp.u_addr.ndx_q = snv[24] & 1; u_dsp.u_addr.trm_q = snv[25] & 1; u_dsp.u_addr.braf_q = snv[26] & 1;
u_dsp.u_addr.sp_q = snv[29] & 7; u_dsp.u_addr.rptc_q = snv[30]; u_dsp.u_addr.rpt_start_q = snv[31]; u_dsp.u_addr.rpt_end_q = snv[32];
u_dsp.u_addr.ifr_q = snv[33]; u_dsp.u_addr.imr_q = snv[34]; u_dsp.u_addr.indx_q = snv[35]; u_dsp.u_addr.arcr_q = snv[36];
u_dsp.u_addr.cbsr1_q = snv[37]; u_dsp.u_addr.cber1_q = snv[38]; u_dsp.u_addr.cbsr2_q = snv[39]; u_dsp.u_addr.cber2_q = snv[40]; u_dsp.u_addr.cbcr_q = snv[41] & 'hFF;
u_dsp.u_addr.bmar_q = snv[42]; u_dsp.u_addr.dbmr_q = snv[43]; u_dsp.u_addr.pasr_q = snv[44]; u_dsp.u_addr.paer_q = snv[45]; u_dsp.u_addr.brcr_q = snv[46];
u_dsp.u_mem.prd_q = snv[55]; u_dsp.u_mem.tim_q = snv[54]; u_dsp.u_mem.psc_q = snv[60] & 'hF; u_dsp.u_mem.tss_q = snv[61] & 1; u_dsp.u_mem.tcr_tddr_q = snv[56] & 'hF;
u_dsp.u_mem.greg_q = snv[50]; u_dsp.u_mem.drr_q = snv[51]; u_dsp.u_mem.dxr_q = snv[52]; u_dsp.u_mem.spc_q = snv[53]; u_dsp.u_mem.pdwsr_q = snv[57]; u_dsp.u_mem.iowsr_q = snv[58]; u_dsp.u_mem.cwsr_q = snv[59];
u_dsp.u_mem.xrdy_q = snv[68] & 1; u_dsp.u_mem.rrdy_q = snv[69] & 1; u_dsp.u_mem.xsrempty_q = snv[62] & 1; u_dsp.u_mem.rsrfull_q = snv[63] & 1; u_dsp.u_mem.xint_mode_q = snv[70] & 1; u_dsp.u_mem.xint_first_q = snv[71] & 1;
u_dsp.u_ctrl.fetch_pc_q = snv[64] ? (snv[27] - 1) : snv[27]; u_dsp.u_ctrl.idle_q = 0;    u_dsp.u_ctrl.int_inh_q = snv[77] & 1; u_dsp.u_ctrl.xc_left_q = snv[48] & 7; u_dsp.u_ctrl.xc_new_q = snv[49] & 1;
u_dsp.u_ctrl.sh_acc_q = snv[80]; u_dsp.u_ctrl.sh_accb_q = snv[81]; u_dsp.u_ctrl.sh_preg_q = snv[82]; u_dsp.u_ctrl.sh_treg0_q = snv[83]; u_dsp.u_ctrl.sh_treg1_q = snv[84] & 'h1F; u_dsp.u_ctrl.sh_treg2_q = snv[85] & 'hF;
u_dsp.u_ctrl.sh_arcr_q = snv[86]; u_dsp.u_ctrl.sh_indx_q = snv[87]; u_dsp.u_ctrl.sh_arp_q = snv[88] & 7; u_dsp.u_ctrl.sh_arb_q = snv[89] & 7; u_dsp.u_ctrl.sh_dp_q = snv[90] & 'hFFFF;
u_dsp.u_ctrl.sh_ov_q = snv[91] & 1; u_dsp.u_ctrl.sh_ovm_q = snv[92] & 1; u_dsp.u_ctrl.sh_intm_q = snv[93] & 1; u_dsp.u_ctrl.sh_cnf_q = snv[94] & 1; u_dsp.u_ctrl.sh_tc_q = snv[95] & 1; u_dsp.u_ctrl.sh_sxm_q = snv[96] & 1;
u_dsp.u_ctrl.sh_c_q = snv[97] & 1; u_dsp.u_ctrl.sh_hm_q = snv[98] & 1; u_dsp.u_ctrl.sh_xf_q = snv[99] & 1; u_dsp.u_ctrl.sh_pm_q = snv[100] & 3; u_dsp.u_ctrl.sh_iptr_q = snv[101] & 'h1F;
u_dsp.u_ctrl.sh_avis_q = snv[102] & 1; u_dsp.u_ctrl.sh_ovly_q = snv[103] & 1; u_dsp.u_ctrl.sh_ram_q = snv[104] & 1; u_dsp.u_ctrl.sh_mpmc_q = snv[105] & 1; u_dsp.u_ctrl.sh_ndx_q = snv[106] & 1; u_dsp.u_ctrl.sh_trm_q = snv[107] & 1; u_dsp.u_ctrl.sh_braf_q = snv[108] & 1;
