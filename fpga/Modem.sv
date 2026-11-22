//============================================================================
//
//  USRobotics Courier V.Everything modem for the MiSTer: 80C186EB supervisor + TMS320C5x DSP, firmware SV25.
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//============================================================================

module emu
(
	`include "sys/emu_ports.vh"
);

///////// Default values for ports not used in this core /////////

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;

assign VGA_SL = 0;
assign VGA_F1 = 0;
assign VGA_SCALER  = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;
assign HDMI_BOB_DEINT = 0;

assign AUDIO_MIX = 0;
assign LED_POWER = 0;
assign BUTTONS = 0;
assign {UART_RTS, UART_DTR} = 0;

//////////////////////////////////////////////////////////////////

wire [1:0] ar = status[122:121];

assign VIDEO_ARX = (!ar) ? 12'd4 : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? 12'd3 : 12'd0;

`include "build_id.v"
localparam CONF_STR = {
	"Modem;UART115200;",
	"-;",
	"F0,BIN,Load SV25 flash image;",
	"F1,BIN,Load NVRAM image;",
	"F2,BIN,Load DSP ROM image;",
	"-;",
	"O[4],Debug text on UART,Off,On;",
	"O[122:121],Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"-;",
	"T[0],Reset;",
	"R[0],Reset and close OSD;",
	"v,0;",
	"V,v",`BUILD_DATE
};

wire        forced_scandoubler;
wire  [1:0] buttons;
wire [127:0] status;
wire [10:0] ps2_key;
wire        ioctl_download;
wire [15:0] ioctl_index;
wire        ioctl_wr;
wire        ioctl_wait;
wire [26:0] ioctl_addr;
wire  [7:0] ioctl_dout;

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(),

	.forced_scandoubler(forced_scandoubler),

	.buttons(buttons),
	.status(status),
	.status_menumask(16'd0),

	.ps2_key(ps2_key),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(ioctl_wait)
);

///////////////////////   CLOCKS   ///////////////////////////////

wire clk_sys;      // 80.64 MHz: SDRAM, loader, hps_io
wire clk_cpu;      // 20.16 MHz = clk_sys / 4: the 186, the glue, the DTE UART (see rtl/modem_core.sv)
wire clk_dsp;      // 40.32 MHz = clk_sys / 2: the DSP, its program RAM and the codec model
wire pll_locked;
assign DDRAM_CLK = clk_cpu;   // the phone line rings (rtl/line_ddr.sv) live in the HPS DDR memory
pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_sys),
	.outclk_1(clk_dsp),
	.outclk_2(clk_cpu),
	.locked(pll_locked)
);

///////////////////////   MODEM   ////////////////////////////////

wire        dsp_run, loading, sdram_up, core_running, badop186;
wire [19:0] pc186;
wire [15:0] pcdsp;
wire [15:0] dbg_words, dbg_vec, dbg_ifr, dbg_spc;
wire        dbg_test_ok, dbg_cal_ok, dbg_jlat;
wire  [2:0] dbg_cal_mask;
wire [19:0] dbg_jfrom, dbg_jto;
wire  [5:0] dbg_tr_idx;
wire  [1:0] dbg_tr_sel;
wire        dbg_trap;
wire [24:0] dbg_icu;
wire [63:0] dbg_dspg;
wire [15:0] dbg_int0, dbg_texp, dbg_frames, dbg_rxc, dbg_txc, dbg_duty, dbg_idle, dbg_dxrc, dbg_dacc, dbg_peak;
wire [37:0] dbg_tr_data;
wire  [1:0] dbg_cap;
wire [15:0] sd_dq_i = SDRAM_DQ;
wire [15:0] sd_dq_o;
wire        sd_dq_oe;
assign SDRAM_DQ = sd_dq_oe ? sd_dq_o : 16'hZZZZ;

wire        core_txd;
wire        dbg_txd;
wire        dbg_text;
wire        dte_tx_valid;
wire  [7:0] dte_tx_byte;
wire        dac_valid;
wire signed [15:0] dac_sample;
wire signed [15:0] line_rx;
wire        speaker_on;

modem_core modem
(
	.clk(clk_sys),
	.clk_cpu(clk_cpu),
	.clk_dsp(clk_dsp),
	.reset_i(reset_req),
	.pll_locked_i(pll_locked),

	.SDRAM_CLK(SDRAM_CLK),
	.SDRAM_CKE(SDRAM_CKE),
	.SDRAM_A(SDRAM_A),
	.SDRAM_BA(SDRAM_BA),
	.SDRAM_DQ_I(sd_dq_i),
	.SDRAM_DQ_O(sd_dq_o),
	.SDRAM_DQ_OE(sd_dq_oe),
	.SDRAM_DQML(SDRAM_DQML),
	.SDRAM_DQMH(SDRAM_DQMH),
	.SDRAM_nCS(SDRAM_nCS),
	.SDRAM_nCAS(SDRAM_nCAS),
	.SDRAM_nRAS(SDRAM_nRAS),
	.SDRAM_nWE(SDRAM_nWE),

	.ioctl_download_i(ioctl_download),
	.ioctl_index_i(ioctl_index),
	.ioctl_wait_o(ioctl_wait),
	.ioctl_wr_i(ioctl_wr),
	.ioctl_addr_i(ioctl_addr),
	.ioctl_dout_i(ioctl_dout),

	.dbg_markers_i(status[4]),
	.uart_rxd_i(UART_RXD),
	.uart_txd_o(core_txd),
	.term_rx_valid_i(term_rx_valid),
	.term_rx_byte_i(term_rx_byte),
	.dte_tx_valid_o(dte_tx_valid),
	.dte_tx_byte_o(dte_tx_byte),

	.dac_valid_o(dac_valid),
	.dac_sample_o(dac_sample),
	.ddr_addr_o(DDRAM_ADDR),
	.ddr_burstcnt_o(DDRAM_BURSTCNT),
	.ddr_busy_i(DDRAM_BUSY),
	.ddr_dout_i(DDRAM_DOUT),
	.ddr_dout_ready_i(DDRAM_DOUT_READY),
	.ddr_rd_o(DDRAM_RD),
	.ddr_din_o(DDRAM_DIN),
	.ddr_be_o(DDRAM_BE),
	.ddr_we_o(DDRAM_WE),
	.line_connected_o(),
	.line_rx_o(line_rx),
	.speaker_on_o(speaker_on),

	.dsp_run_o(dsp_run),
	.loading_o(loading),
	.sdram_ready_o(sdram_up),
	.core_running_o(core_running),
	.pc186_o(pc186),
	.badop186_o(badop186),
	.pcdsp_o(pcdsp),
	.dbg_words_o(dbg_words),
	.dbg_vec_o(dbg_vec),
	.dbg_ifr_o(dbg_ifr),
	.dbg_spc_o(dbg_spc),
	.dbg_test_ok_o(dbg_test_ok),
	.dbg_cap_o(dbg_cap),
	.dbg_cal_ok_o(dbg_cal_ok),
	.dbg_cal_mask_o(dbg_cal_mask),
	.dbg_jfrom_o(dbg_jfrom),
	.dbg_jto_o(dbg_jto),
	.dbg_jlat_o(dbg_jlat),
	.dbg_text_o(dbg_text),
	.dbg_tr_sel_i(dbg_tr_sel),
	.dbg_trap_o(dbg_trap),
	.dbg_tr_idx_i(dbg_tr_idx),
	.dbg_tr_data_o(dbg_tr_data),
	.dbg_icu_o(dbg_icu),
	.dbg_int0_o(dbg_int0),
	.dbg_texp_o(dbg_texp),
	.dbg_frames_o(dbg_frames),
	.dbg_rxc_o(dbg_rxc),
	.dbg_txc_o(dbg_txc),
	.dbg_duty_o(dbg_duty),
	.dbg_idle_o(dbg_idle),
	.dbg_dxrc_o(dbg_dxrc),
	.dbg_dacc_o(dbg_dacc),
	.dbg_peak_o(dbg_peak),
	.dbg_dspg_o(dbg_dspg)
);

// bring-up heartbeat on the raw 50 MHz clock: nothing else has to work for it to talk; ANDed with the core's TX (both idle high)
wire reset_req = RESET | status[0] | buttons[1];
dbg_status dbg
(
	.clk(CLK_50M),
	.flags_i({pll_locked, reset_req, core_running, sdram_up, ioctl_download, dsp_run, badop186}),
	.pc186_i(pc186),
	.pcdsp_i(pcdsp),
	.words_i(dbg_ifr),
	.vec_i(dbg_spc),
	.test_ok_i(dbg_test_ok),
	.cap_i(dbg_cap),
	.cal_ok_i(dbg_cal_ok),
	.mask_i(dbg_cal_mask),
	.jlat_i(dbg_jlat),
	.jfrom_i(dbg_jfrom),
	.jto_i(dbg_jto),
	.tr_sel_o(dbg_tr_sel),
	.trap_i(dbg_trap),
	.tr_idx_o(dbg_tr_idx),
	.tr_data_i(dbg_tr_data),
	.icu_i(dbg_icu),
	.int0_i(dbg_int0),
	.texp_i(dbg_texp),
	.frames_i(dbg_frames),
	.rxc_i(dbg_rxc),
	.txc_i(dbg_txc),
	.duty_i(dbg_idle),
	.dxrc_i(dbg_dxrc),
	.dacc_i(dbg_dacc),
	.peak_i(dbg_peak),
	.dspg_i(dbg_dspg),
	.tx_o(dbg_txd)
);
/* the debug heartbeat / trace text shares the DTE pin only when the OSD option is on (default off): the pin carries just the modem */
/* the heartbeat text shares the DTE pin only when asked for: the OSD option, or Ctrl-A Ctrl-A Ctrl-A D on the serial port (toggle); off after reset */
assign UART_TXD = (status[4] || dbg_text) ? (core_txd & dbg_txd) : core_txd;

///////////////////////   AUDIO   ////////////////////////////////

// line output of the modem (the DAC samples at the codec rate, 4..16 kHz): held, the framework resamples
reg signed [15:0] audio_hold;
always @(posedge clk_sys) if (dac_valid) audio_hold <= dac_sample;

// the modem's speaker: what the modem sends, plus what comes in from the line while the firmware has its speaker latch on (ATM / ATL: port 0x12 bit 4, active low); saturating sum
reg signed [15:0] line_hold;
always @(posedge clk_sys) line_hold <= line_rx;
wire signed [16:0] spk_sum = audio_hold + (speaker_on ? line_hold : 17'sd0);
wire signed [15:0] spk = (spk_sum > 17'sd32767) ? 16'sh7FFF : (spk_sum < -17'sd32768) ? 16'sh8000 : spk_sum[15:0];

assign AUDIO_S = 1;
assign AUDIO_L = spk;
assign AUDIO_R = spk;

///////////////////////   TERMINAL / VIDEO   /////////////////////

wire       term_rx_valid = 1'b0;
wire [7:0] term_rx_byte  = 8'h00;

`ifdef NO_VIDEO
// first builds: no picture, no terminal (faster compile); H/V sync stay off
assign CLK_VIDEO = clk_sys;
assign CE_PIXEL  = 1'b1;
assign VGA_DE    = 1'b0;
assign VGA_HS    = 1'b0;
assign VGA_VS    = 1'b0;
assign {VGA_R, VGA_G, VGA_B} = '0;
`else
// placeholder until rtl/video/term.sv lands: blank picture
assign CLK_VIDEO = clk_sys;
assign CE_PIXEL  = 1'b1;
assign VGA_DE    = 1'b0;
assign VGA_HS    = 1'b0;
assign VGA_VS    = 1'b0;
assign {VGA_R, VGA_G, VGA_B} = '0;
`endif

reg [27:0] act_cnt;
always @(posedge clk_sys) act_cnt <= act_cnt + 1'd1;
assign LED_USER = dsp_run ? act_cnt[25] : act_cnt[27];
assign LED_DISK = {1'b0, loading};

endmodule
