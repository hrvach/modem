/*
dbg_status.sv -- bring-up heartbeat: a status line on the DTE serial pin, independent of the PLL, the core reset and the cores.

FPGA-only plumbing. Runs on the raw 50 MHz board clock (nothing else has to work for it to talk): twice a second it sends
  "[P1 X0 R1 S1 L0 D0 B0 A=FFFF0 Q=8000 N=0000 W=0000 K0 M1 T1 J=00000>00000 I=0000000 O=0000 E=0000 F=0000]\r\n"
      P = PLL locked, X = reset requested (OSD / button / HPS), R = core reset released, S = SDRAM controller up, L = a file download is active,
      D = the DSP is running, B = the 186 hit an undefined opcode, A = the 186's physical program counter, Q = the DSP's program counter
      N = SDRAM words the loader wrote for the flash image (0x8000..0xFFFF*; the full image is 0x40000 words), W = the word the SDRAM returns at 186 physical FFFF0 (the reset
      vector area: the image's JMP, 0000 or garbage if the SDRAM or the load is broken), K = the calibrated read-capture edge (x = no setting worked), M = mask of capture settings that passed the 64-word calibration (bit n = setting n), T = SDRAM write/read test passed,
      J = first time the 186 left valid code: last valid PC > first invalid PC ('=' once latched, '-' while none yet)
      (A and Q are sampled from the 120.96 MHz domain without synchronisation, so a value can be torn while the core is running: look at where it sits)
at 115200 8N1 (50 MHz / 434). The inputs come from other clock domains and are only observed, so a two-flop synchroniser each is enough.
tx_o idles high; the top ANDs it with the core's own TX (both idle high, so a core byte can only be garbled by overlapping a status line).
*/
`default_nettype none

module dbg_status #(
    parameter integer CLKS_PER_BIT = 434,           /* 50 MHz / 115200 */
    parameter integer PERIOD_CLKS  = 25_000_000     /* 0.5 s */
) (
    input  logic        clk,
    input  logic [6:0]  flags_i,                    /* {P, X, R, S, L, D, B} */
    input  logic [19:0] pc186_i,
    input  logic [15:0] pcdsp_i,
    input  logic [15:0] words_i,                    /* loader: SDRAM words written for the flash image */
    input  logic [15:0] vec_i,                      /* SDRAM probe: the word at 186 physical 0xFFFF0 */
    input  logic        test_ok_i,                  /* SDRAM probe: write / read-back test */
    input  logic [1:0]  cap_i,                      /* calibrated capture edge */
    input  logic        cal_ok_i,                   /* calibration found a working setting */
    input  logic [2:0]  mask_i,                     /* capture settings that passed */
    input  logic        jlat_i,                     /* first jump out of valid code latched */
    input  logic [19:0] jfrom_i,
    input  logic [19:0] jto_i,
    output logic [1:0]  tr_sel_o,                   /* which frozen ring: 0 host commands '#', 1 DSP messages '$', 2 DSP instruction history '!' */
    input  logic        trap_i,                     /* the trap froze the rings: print all three */
    output logic [5:0]  tr_idx_o,                   /* bus_trace read index (a frozen ring: the data is static) */
    input  logic [24:0] icu_i,                      /* interrupt controller: requests / in-service / mask */
    input  logic [15:0] int0_i,                     /* INT0 requests raised by the glue */
    input  logic [15:0] texp_i,                     /* DSP timer expiries (low 16 bits) */
    input  logic [15:0] frames_i,
    input  logic [15:0] rxc_i,                      /* bytes the DTE UART received */
    input  logic [15:0] txc_i,                      /* bytes the 186 sent to the DTE */
    input  logic [15:0] duty_i,
    input  logic [15:0] dxrc_i,                     /* DXR writes of the DSP */
    input  logic [15:0] dacc_i,                     /* DAC samples produced */
    input  logic [63:0] dspg_i,                     /* DSP interrupt state: {ST0, IMR, PMST, rptc[7:0], halted, idle, sp} */
    input  logic [15:0] peak_i,                     /* peak |DAC sample| of the last window */                     /* 186 enabled share of clk_cpu (0xFFFF = 100 %) */                   /* codec frames */
    input  logic [37:0] tr_data_i,                  /* {wr, word, addr[19:0], data[15:0]} */
    output logic        tx_o
);
    localparam integer LEN = 168;                    /* the status line plus CR LF: 76 characters, indexes 0..75 */

    logic [6:0]  s1_q, s2_q;
    logic [19:0] a_q;
    logic [15:0] q_q;
    logic [15:0] w_q, v_q;
    logic [3:0]  t_q;
    logic [27:0] icu_q;
    logic [15:0] i0_q, te_q, fr_q, rx_q, tx_q, du_q, dx_q, dc_q, pk_q;
    logic [63:0] g_q;
    logic        dump_q;
    logic [4:0]  didx_q;
    logic [7:0]  dch;
    logic [2:0]  m_q;
    logic        jl_q;
    logic [19:0] jf_q, jt_q;
    logic [31:0] period_q;
    logic [7:0]  idx_q;
    logic        busy_q;
    logic        active_q;
    logic [9:0]  shift_q;
    logic [15:0] cnt_q;
    logic [3:0]  bit_q;
    logic [7:0]  ch;

    function automatic logic [7:0] d(input logic v);
        d = v ? "1" : "0";
    endfunction

    function automatic logic [7:0] hx(input logic [3:0] v);
        hx = (v < 4'd10) ? (8'h30 + {4'd0, v}) : (8'h37 + {4'd0, v});
    endfunction

    always_comb begin
        case (idx_q)
            8'd0:    ch = "[";
            8'd1:    ch = "P";
            8'd2:    ch = d(s2_q[6]);
            8'd3:    ch = " ";
            8'd4:    ch = "X";
            8'd5:    ch = d(s2_q[5]);
            8'd6:    ch = " ";
            8'd7:    ch = "R";
            8'd8:    ch = d(s2_q[4]);
            8'd9:    ch = " ";
            8'd10:   ch = "S";
            8'd11:   ch = d(s2_q[3]);
            8'd12:   ch = " ";
            8'd13:   ch = "L";
            8'd14:   ch = d(s2_q[2]);
            8'd15:   ch = " ";
            8'd16:   ch = "D";
            8'd17:   ch = d(s2_q[1]);
            8'd18:   ch = " ";
            8'd19:   ch = "B";
            8'd20:   ch = d(s2_q[0]);
            8'd21:   ch = " ";
            8'd22:   ch = "A";
            8'd23:   ch = "=";
            8'd24:   ch = hx(a_q[19:16]);
            8'd25:   ch = hx(a_q[15:12]);
            8'd26:   ch = hx(a_q[11:8]);
            8'd27:   ch = hx(a_q[7:4]);
            8'd28:   ch = hx(a_q[3:0]);
            8'd29:   ch = " ";
            8'd30:   ch = "Q";
            8'd31:   ch = "=";
            8'd32:   ch = hx(q_q[15:12]);
            8'd33:   ch = hx(q_q[11:8]);
            8'd34:   ch = hx(q_q[7:4]);
            8'd35:   ch = hx(q_q[3:0]);
            8'd36:   ch = " ";
            8'd37:   ch = "N";
            8'd38:   ch = "=";
            8'd39:   ch = hx(w_q[15:12]);
            8'd40:   ch = hx(w_q[11:8]);
            8'd41:   ch = hx(w_q[7:4]);
            8'd42:   ch = hx(w_q[3:0]);
            8'd43:   ch = " ";
            8'd44:   ch = "W";
            8'd45:   ch = "=";
            8'd46:   ch = hx(v_q[15:12]);
            8'd47:   ch = hx(v_q[11:8]);
            8'd48:   ch = hx(v_q[7:4]);
            8'd49:   ch = hx(v_q[3:0]);
            8'd50:   ch = " ";
            8'd51:   ch = "K";
            8'd52:   ch = t_q[3] ? (8'h30 + {6'd0, t_q[1:0]}) : "x";
            8'd53:   ch = " ";
            8'd54:   ch = "M";
            8'd55:   ch = hx({1'b0, m_q});
            8'd56:   ch = " ";
            8'd57:   ch = "T";
            8'd58:   ch = d(t_q[2]);
            8'd59:   ch = " ";
            8'd60:   ch = "J";
            8'd61:   ch = jl_q ? "=" : "-";
            8'd62:   ch = hx(jf_q[19:16]);
            8'd63:   ch = hx(jf_q[15:12]);
            8'd64:   ch = hx(jf_q[11:8]);
            8'd65:   ch = hx(jf_q[7:4]);
            8'd66:   ch = hx(jf_q[3:0]);
            8'd67:   ch = ">";
            8'd68:   ch = hx(jt_q[19:16]);
            8'd69:   ch = hx(jt_q[15:12]);
            8'd70:   ch = hx(jt_q[11:8]);
            8'd71:   ch = hx(jt_q[7:4]);
            8'd72:   ch = hx(jt_q[3:0]);
            8'd73:   ch = " ";
            8'd74:   ch = "I";
            8'd75:   ch = "=";
            8'd76:   ch = hx(icu_q[27:24]);
            8'd77:   ch = hx(icu_q[23:20]);
            8'd78:   ch = hx(icu_q[19:16]);
            8'd79:   ch = hx(icu_q[15:12]);
            8'd80:   ch = hx(icu_q[11:8]);
            8'd81:   ch = hx(icu_q[7:4]);
            8'd82:   ch = hx(icu_q[3:0]);
            8'd83:   ch = " ";
            8'd84:   ch = "O";
            8'd85:   ch = "=";
            8'd86:   ch = hx(i0_q[15:12]);
            8'd87:   ch = hx(i0_q[11:8]);
            8'd88:   ch = hx(i0_q[7:4]);
            8'd89:   ch = hx(i0_q[3:0]);
            8'd90:   ch = " ";
            8'd91:   ch = "E";
            8'd92:   ch = "=";
            8'd93:   ch = hx(te_q[15:12]);
            8'd94:   ch = hx(te_q[11:8]);
            8'd95:   ch = hx(te_q[7:4]);
            8'd96:   ch = hx(te_q[3:0]);
            8'd97:   ch = " ";
            8'd98:   ch = "F";
            8'd99:   ch = "=";
            8'd100:  ch = hx(fr_q[15:12]);
            8'd101:  ch = hx(fr_q[11:8]);
            8'd102:  ch = hx(fr_q[7:4]);
            8'd103:  ch = hx(fr_q[3:0]);
            8'd104:  ch = " ";
            8'd105:  ch = "R";
            8'd106:  ch = "=";
            8'd107:  ch = hx(rx_q[15:12]);
            8'd108:  ch = hx(rx_q[11:8]);
            8'd109:  ch = hx(rx_q[7:4]);
            8'd110:  ch = hx(rx_q[3:0]);
            8'd111:  ch = " ";
            8'd112:  ch = "X";
            8'd113:  ch = "=";
            8'd114:  ch = hx(tx_q[15:12]);
            8'd115:  ch = hx(tx_q[11:8]);
            8'd116:  ch = hx(tx_q[7:4]);
            8'd117:  ch = hx(tx_q[3:0]);
            8'd118:  ch = " ";
            8'd119:  ch = "D";
            8'd120:  ch = "=";
            8'd121:  ch = hx(du_q[15:12]);
            8'd122:  ch = hx(du_q[11:8]);
            8'd123:  ch = hx(du_q[7:4]);
            8'd124:  ch = hx(du_q[3:0]);
            8'd125:  ch = " ";
            8'd126:  ch = "C";
            8'd127:  ch = "=";
            8'd128:  ch = hx(dx_q[15:12]);
            8'd129:  ch = hx(dx_q[11:8]);
            8'd130:  ch = hx(dx_q[7:4]);
            8'd131:  ch = hx(dx_q[3:0]);
            8'd132:  ch = " ";
            8'd133:  ch = "Y";
            8'd134:  ch = "=";
            8'd135:  ch = hx(dc_q[15:12]);
            8'd136:  ch = hx(dc_q[11:8]);
            8'd137:  ch = hx(dc_q[7:4]);
            8'd138:  ch = hx(dc_q[3:0]);
            8'd139:  ch = " ";
            8'd140:  ch = "Z";
            8'd141:  ch = "=";
            8'd142:  ch = hx(pk_q[15:12]);
            8'd143:  ch = hx(pk_q[11:8]);
            8'd144:  ch = hx(pk_q[7:4]);
            8'd145:  ch = hx(pk_q[3:0]);
            8'd146:  ch = " ";
            8'd147:  ch = "G";
            8'd148:  ch = "=";
            8'd149:  ch = hx(g_q[63:60]);
            8'd150:  ch = hx(g_q[59:56]);
            8'd151:  ch = hx(g_q[55:52]);
            8'd152:  ch = hx(g_q[51:48]);
            8'd153:  ch = hx(g_q[47:44]);
            8'd154:  ch = hx(g_q[43:40]);
            8'd155:  ch = hx(g_q[39:36]);
            8'd156:  ch = hx(g_q[35:32]);
            8'd157:  ch = hx(g_q[31:28]);
            8'd158:  ch = hx(g_q[27:24]);
            8'd159:  ch = hx(g_q[23:20]);
            8'd160:  ch = hx(g_q[19:16]);
            8'd161:  ch = hx(g_q[15:12]);
            8'd162:  ch = hx(g_q[11:8]);
            8'd163:  ch = hx(g_q[7:4]);
            8'd164:  ch = hx(g_q[3:0]);
            8'd165:  ch = "]";
            8'd166:  ch = 8'h0D;
            default: ch = 8'h0A;
        endcase
    end

    /* after a heartbeat line, once the first bad jump is latched: the 64 frozen bus accesses, oldest first, "#nn Rw AAAAA DDDD" */
    always_comb begin
        case (didx_q)
            5'd0:    dch = (tr_sel_o == 2'd1) ? "$" : (tr_sel_o == 2'd2) ? "!" : (tr_sel_o == 2'd3) ? "%" : "#";
            5'd1:    dch = hx({2'b00, tr_idx_o[5:4]});
            5'd2:    dch = hx(tr_idx_o[3:0]);
            5'd3:    dch = " ";
            5'd4:    dch = tr_data_i[37] ? "W" : "R";
            5'd5:    dch = tr_data_i[36] ? "w" : "b";
            5'd6:    dch = " ";
            5'd7:    dch = hx(tr_data_i[35:32]);
            5'd8:    dch = hx(tr_data_i[31:28]);
            5'd9:    dch = hx(tr_data_i[27:24]);
            5'd10:   dch = hx(tr_data_i[23:20]);
            5'd11:   dch = hx(tr_data_i[19:16]);
            5'd12:   dch = " ";
            5'd13:   dch = hx(tr_data_i[15:12]);
            5'd14:   dch = hx(tr_data_i[11:8]);
            5'd15:   dch = hx(tr_data_i[7:4]);
            5'd16:   dch = hx(tr_data_i[3:0]);
            5'd17:   dch = 8'h0D;
            default: dch = 8'h0A;
        endcase
    end

    always_ff @(posedge clk) begin
        s1_q <= flags_i;
        s2_q <= s1_q;
        if (!active_q && !busy_q) begin
            a_q <= pc186_i;
            q_q <= pcdsp_i;
            w_q <= words_i;
            v_q <= vec_i;
            t_q <= {cal_ok_i, test_ok_i, cap_i};
            m_q <= mask_i;
            icu_q <= {3'b000, icu_i};
            i0_q <= int0_i;
            te_q <= texp_i;
            fr_q <= frames_i;
            rx_q <= rxc_i;
            tx_q <= txc_i;
            du_q <= duty_i;
            dx_q <= dxrc_i;
            dc_q <= dacc_i;
            pk_q <= peak_i;
            g_q  <= dspg_i;
            jl_q <= jlat_i;
            jf_q <= jfrom_i;
            jt_q <= jto_i;
        end
        if (busy_q) begin
            if (cnt_q == CLKS_PER_BIT[15:0] - 16'd1) begin
                cnt_q <= 16'd0;
                if (bit_q == 4'd9) begin
                    busy_q <= 1'b0;
                    tx_o   <= 1'b1;
                end else begin
                    bit_q   <= bit_q + 4'd1;
                    shift_q <= {1'b1, shift_q[9:1]};
                    tx_o    <= shift_q[1];
                end
            end else begin
                cnt_q <= cnt_q + 16'd1;
            end
        end else if (active_q && dump_q) begin
            if (didx_q == 5'd19) begin
                didx_q <= 5'd0;
                if (tr_idx_o == 6'd63) begin
                    if (trap_i && tr_sel_o != 2'd3) begin
                        tr_sel_o <= tr_sel_o + 2'd1;
                        tr_idx_o <= 6'd0;
                    end else begin
                        dump_q   <= 1'b0;
                        active_q <= 1'b0;
                    end
                end else begin
                    tr_idx_o <= tr_idx_o + 6'd1;
                end
            end else begin
                shift_q <= {1'b1, dch, 1'b0};
                tx_o    <= 1'b0;
                busy_q  <= 1'b1;
                cnt_q   <= 16'd0;
                bit_q   <= 4'd0;
                didx_q  <= didx_q + 5'd1;
            end
        end else if (active_q) begin
            if (idx_q == LEN[7:0]) begin
                idx_q <= 7'd0;
                if (jl_q) begin
                    dump_q   <= 1'b1;
                    didx_q   <= 5'd0;
                    tr_idx_o <= 6'd0;
                    tr_sel_o <= 2'd0;
                end else begin
                    active_q <= 1'b0;
                end
            end else begin
                shift_q <= {1'b1, ch, 1'b0};
                tx_o    <= 1'b0;
                busy_q  <= 1'b1;
                cnt_q   <= 16'd0;
                bit_q   <= 4'd0;
                idx_q   <= idx_q + 8'd1;
            end
        end else if (period_q >= PERIOD_CLKS - 1) begin
            period_q <= 32'd0;
            active_q <= 1'b1;
        end else begin
            period_q <= period_q + 32'd1;
        end
    end

    initial begin
        tx_o     = 1'b1;
        busy_q   = 1'b0;
        active_q = 1'b0;
        idx_q    = 8'd0;
        period_q = 32'd0;
        cnt_q    = 16'd0;
        bit_q    = 4'd0;
        shift_q  = 10'h3FF;
        s1_q     = 7'd0;
        s2_q     = 7'd0;
        a_q      = 20'd0;
        q_q      = 16'd0;
        w_q      = 16'd0;
        v_q      = 16'd0;
        t_q      = 4'd0;
        icu_q    = 28'd0;
        i0_q     = 16'd0;
        te_q     = 16'd0;
        fr_q     = 16'd0;
        rx_q     = 16'd0;
        tx_q     = 16'd0;
        du_q     = 16'd0;
        dx_q     = 16'd0;
        dc_q     = 16'd0;
        pk_q     = 16'd0;
        g_q      = 64'd0;
        dump_q   = 1'b0;
        didx_q   = 5'd0;
        tr_idx_o = 6'd0;
        tr_sel_o = 2'd0;
        m_q      = 3'd0;
        jl_q     = 1'b0;
        jf_q     = 20'd0;
        jt_q     = 20'd0;
    end
endmodule
