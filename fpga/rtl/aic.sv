/*
aic.sv -- TLC320AC01 codec model and codec-frame scheduler of the Courier modem's DSP.

Where it sits: beside c5x_core. It takes the DXR stream (dxr_wr / dxr_wdata, sampled on the DSP's ce_i) and the DSP's charged-cycle counter (cycles_o), and it
drives the core's single-step input (step_o), the serial tick (ser_tick_o / ser_rx_o) and the INT3 request (int3_o). It also turns the DXR words into DAC
samples (dac_valid_o / dac_sample_o) and feeds the ADC side from a line source (rx_sample_i, advanced by rx_next_o).

Reference: ../courier/src/glue/machine.c, machine_sample (frame sequence), aic_feed (AC01 register protocol), aic_row_rate / aic_update (sample rate from
port 0x6B N and AC01 registers 1 (A) and 2 (B)), machine_take_tx (DAC: low two bits dropped, gain from register 4), aic_gain_in (ADC gain, register 4).
Fixed to the call.conf defaults: ac01_model = 1, sec_frame = 1, int23 = 1, ac01_filt = 0, ac01_lat = 0, noise_amp = 8 (line noise floor, LCG seed 12345).

Frame sequence (the C glue runs the DSP a budget of dsp_cps charged cycles per codec sample, to the first instruction boundary at or past it):
  budget = dsp_cps; if a control word is pending (a primary word with D1 D0 = 11 was written) the frame is split: half = dsp_cps / 2 cycles, then the secondary
  frame (INT3, serial tick with 0, the DXR words written in the half are control words: register write, no DAC sample, no ADC consumption), then
  dsp_cps - half cycles, then the primary frame (ADC word, serial tick, INT3, frame_tick_o for the glue).
  step_o = 0 parks the control FSM at the instruction boundary; the actions run while parked (or while the core is in IDLE, which cannot park).
dsp_cps: the 40.32 MHz DSP clock divided by the sample rate: 20 * T for the six symbol-rate table rows (A = 10), otherwise floor(3360 A B / N); clamped to the
4000..16000 Hz range (cps 10080 .. 2520). Initial 5600 (7200 Hz).

Not modelled: the AC01 reconstruction / anti-alias filters (ac01_filt = 0 in the reference), extra ADC latency, the A/D secondary-channel result.
*/
`default_nettype none

module aic (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        ce_i,            /* the DSP clock enable: dxr_wr_i, ser_tick_o and int3_o are exchanged on its edges */

    /* DSP core */
    input  logic [31:0] cycles_i,        /* low half of the DSP's charged cycles */
    input  logic        parked_i,        /* the core is in DONE (instr_done) */
    input  logic        idle_i,          /* the core is in IDLE / IDLE2 */
    input  logic        run_i,           /* the DSP is out of reset: the first frame starts one period after this goes high */
    output logic        step_o,
    output logic        ser_tick_o,      /* level until the next ce_i edge */
    output logic [15:0] ser_rx_o,
    output logic        int3_o,          /* level until the next ce_i edge */
    input  logic        dxr_wr_i,
    input  logic [15:0] dxr_wdata_i,
    input  logic [15:0] mclk_n_i,

    /* line side */
    output logic        dac_valid_o,     /* pulse: one DAC sample */
    output logic signed [15:0] dac_sample_o,
    output logic        rx_next_o,       /* pulse: the source advances to its next sample */
    input  logic signed [15:0] rx_sample_i,

    /* glue */
    output logic        frame_tick_o,    /* pulse: end of a primary frame */
    output logic [15:0] rate_cps_o,      /* current DSP cycles per codec frame (observation) */
    output logic [15:0] dbg_o            /* {frame state, reached, split, req, run_i, div state, cps[6:0]} */
);
    localparam [15:0] CPS_INIT    = 16'd5600;     /* 40.32 MHz / 7200 Hz */
    localparam [15:0] CPS_MAX     = 16'd10080;    /* 4000 Hz */
    localparam [15:0] CPS_MIN     = 16'd2520;     /* 16000 Hz */
    localparam [31:0] CPS_NUM     = 32'd3360;     /* 40.32e6 / 12000 */
    localparam [7:0]  NOISE_AMP   = 8'd8;         /* call.conf noise_amp */
    localparam [30:0] NOISE_SEED  = 31'd12345;

    /* the six symbol-rate rows (aic_row_rate): N, B, T */
    function automatic logic [8:0] row_t(input logic [15:0] n, input logic [7:0] b);
        begin
            row_t = 9'd0;
            if (n == 16'd120 && b == 8'd20) row_t = 9'd280;
            if (n == 16'd130 && b == 8'd19) row_t = 9'd245;
            if (n == 16'd133 && b == 8'd19) row_t = 9'd240;
            if (n == 16'd142 && b == 8'd19) row_t = 9'd224;
            if (n == 16'd144 && b == 8'd18) row_t = 9'd210;
            if (n == 16'd154 && b == 8'd18) row_t = 9'd196;
        end
    endfunction

    /* ---- AC01 registers 1..6 (reg 0 unused) */
    logic [7:0]  aic_q [1:6];
    logic        req_q;                 /* a control word follows */
    logic [15:0] cps_q;
    logic [15:0] half_q;

    /* ---- divider for floor(3360 A B / N) */
    typedef enum logic [1:0] { D_IDLE = 2'd0, D_RUN = 2'd1 } div_t;
    div_t        div_q;
    logic [31:0] div_num_q;
    logic [15:0] div_den_q;
    logic [31:0] div_quo_q;
    logic [31:0] div_rem_q;
    logic [5:0]  div_cnt_q;
    logic        upd_q;                 /* a recalculation is wanted (set by a register or N change) */
    logic [15:0] n_prev_q;

    /* ---- frame FSM */
    typedef enum logic [2:0] {
        F_RUN1  = 3'd0,     /* toward the first target: half of the frame (split) or the whole frame */
        F_SEC   = 3'd1,     /* secondary frame actions */
        F_RUN2  = 3'd2,     /* the rest of a split frame */
        F_WAIT  = 3'd3      /* wait until the core has taken the primary tick, then start the next budget */
    } frame_t;
    frame_t      frame_q;
    logic [31:0] target_q;
    logic        split_q;               /* this frame is split */

    logic        reached;
    logic        can_act;
    logic [31:0] diff;

    always_comb begin
        diff    = cycles_i - target_q;
        reached = !diff[31];
        can_act = parked_i || idle_i;
        step_o  = ((frame_q == F_RUN1) || (frame_q == F_RUN2)) && !reached;
    end

    /* ---- ADC path: line sample with noise, register-4 gain, low two bits dropped, 16-bit clamp (machine_sample, aic_gain_in) */
    logic [30:0]        seed_q;
    logic [30:0]        seed_n;
    logic [30:0]        seed_n_q;
    logic signed [31:0] noise_q;
    logic signed [15:0] adc_q;
    logic signed [31:0] noise;
    logic signed [31:0] adc_base;
    logic signed [31:0] adc_gain;
    logic signed [31:0] adc_val;
    logic [1:0]         gain_in_sel;
    logic [1:0]         gain_out_sel;

    always_comb begin
        seed_n      = seed_n_q;
        noise       = noise_q;
        gain_in_sel = aic_q[4][3:2];
        gain_out_sel = aic_q[4][1:0];
        adc_base    = $signed({{16{rx_sample_i[15]}}, rx_sample_i}) + noise;
        case (gain_in_sel)
            2'd0:    adc_gain = 32'sd0;
            2'd1:    adc_gain = adc_base;
            2'd2:    adc_gain = adc_base <<< 1;
            default: adc_gain = adc_base <<< 2;
        endcase
        adc_val = adc_gain & ~32'sd3;
        if (adc_val > 32'sd32767)
            adc_val = 32'sd32767;
        else if (adc_val < -32'sd32768)
            adc_val = -32'sd32768;
    end

    /* The ADC value is needed once per frame, thousands of clocks after its inputs (the line sample, register 4, the seed) last changed: three register
       stages make the multiply / modulo / gain / clamp chain a few ns each instead of one 34 ns path. adc_q is valid 3 clocks after the last change. */
    /* (seed >> 16) mod 17, one bit per clock (a combinational divider by 17 is a 25 ns path): restarts whenever the value changes */
    logic [14:0] mv_q = 15'h7FFF, mcur_q = 15'd0;   /* power-up values, no reset: free-running helper */
    logic [3:0]  mi_q = 4'd0;
    logic [4:0]  mr_q = 5'd0;
    logic        mbusy_q = 1'b0;
    logic [5:0]  mt;
    always_comb begin
        mt = {mr_q, mcur_q[mi_q]};
        if (mt >= 6'd17)
            mt = mt - 6'd17;
    end
    always_ff @(posedge clk) begin
        seed_n_q <= seed_q * 31'd1103515245 + 31'd12345;
        adc_q    <= adc_val[15:0];
        if (!mbusy_q) begin
            if (seed_n_q[30:16] != mv_q) begin
                mv_q    <= seed_n_q[30:16];
                mcur_q  <= seed_n_q[30:16];
                mr_q    <= 5'd0;
                mi_q    <= 4'd14;
                mbusy_q <= 1'b1;
            end
        end else begin
            mr_q <= mt[4:0];
            if (mi_q == 4'd0) begin
                mbusy_q <= 1'b0;
                noise_q <= $signed({27'd0, mt[4:0]}) - $signed({24'd0, NOISE_AMP});
            end else begin
                mi_q <= mi_q - 4'd1;
            end
        end
    end

    /* ---- DAC path: word with the two control bits dropped, analog gain from register 4 */
    logic signed [15:0] dac_hold;
    logic signed [15:0] dac_val;
    always_comb begin
        dac_hold = $signed(dxr_wdata_i & 16'hFFFC);
        case (gain_out_sel)
            2'd0:    dac_val = 16'sd0;
            2'd1:    dac_val = dac_hold;
            2'd2:    dac_val = dac_hold >>> 1;
            default: dac_val = dac_hold >>> 2;
        endcase
    end

    logic        tick_q, int3_q;
    logic        ctl_reg_ok;
    logic [4:0]  ctl_reg;
    always_comb begin
        ctl_reg    = dxr_wdata_i[12:8];
        ctl_reg_ok = !dxr_wdata_i[13] && (ctl_reg >= 5'd1) && (ctl_reg <= 5'd6);
    end

    assign ser_tick_o = tick_q;
    assign int3_o     = int3_q;
    assign rate_cps_o = cps_q;

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            for (int i = 1; i <= 6; i++) aic_q[i] <= 8'h00;
            req_q        <= 1'b0;
            cps_q        <= CPS_INIT;
            half_q       <= CPS_INIT >> 1;
            div_q        <= D_IDLE;
            div_num_q    <= 32'd0;
            div_den_q    <= 16'd1;
            div_quo_q    <= 32'd0;
            div_rem_q    <= 32'd0;
            div_cnt_q    <= 6'd0;
            upd_q        <= 1'b0;
            n_prev_q     <= 16'h0000;
            frame_q      <= F_RUN1;
            target_q     <= 32'd0;
            split_q      <= 1'b0;
            seed_q       <= NOISE_SEED;
            ser_rx_o     <= 16'h0000;
            tick_q       <= 1'b0;
            int3_q       <= 1'b0;
            dac_valid_o  <= 1'b0;
            dac_sample_o <= 16'sd0;
            rx_next_o    <= 1'b0;
            frame_tick_o <= 1'b0;
        end else begin
            dac_valid_o  <= 1'b0;
            rx_next_o    <= 1'b0;
            frame_tick_o <= 1'b0;

            /* the core consumes the tick and the interrupt at its ce_i edge */
            if (ce_i) begin
                tick_q <= 1'b0;
                int3_q <= 1'b0;
            end

            /* ---- DXR words (sampled with ce_i): control word, register write, DAC sample */
            if (ce_i && dxr_wr_i) begin
                if (req_q) begin
                    req_q <= 1'b0;
                    if (ctl_reg_ok) begin
                        aic_q[ctl_reg[2:0]] <= dxr_wdata_i[7:0];
                        upd_q <= 1'b1;
                    end
                end else begin
                    if (dxr_wdata_i[1:0] == 2'b11)
                        req_q <= 1'b1;
                end
                /* an ordinary word (not the control word that followed a DD = 11 word): one DAC sample, one line sample consumed */
                if (!req_q) begin
                    dac_valid_o  <= 1'b1;
                    dac_sample_o <= dac_val;
                    rx_next_o    <= 1'b1;
                end
            end
            if (mclk_n_i != n_prev_q) begin
                n_prev_q <= mclk_n_i;
                upd_q    <= 1'b1;
            end

            /* ---- sample rate: recalculate when N, A or B changed and all three are known */
            case (div_q)
                D_IDLE: begin
                    if (upd_q && div_q == D_IDLE) begin
                        upd_q <= 1'b0;
                        if (n_prev_q != 16'd0 && aic_q[1] != 8'd0 && aic_q[2] != 8'd0) begin
                            if (aic_q[1] == 8'd10 && row_t(n_prev_q, aic_q[2]) != 9'd0) begin
                                cps_q  <= {7'd0, row_t(n_prev_q, aic_q[2])} * 16'd20;
                                half_q <= ({7'd0, row_t(n_prev_q, aic_q[2])} * 16'd20) >> 1;
                            end else begin
                                div_num_q <= CPS_NUM * {24'd0, aic_q[1]} * {24'd0, aic_q[2]};
                                div_den_q <= n_prev_q;
                                div_quo_q <= 32'd0;
                                div_rem_q <= 32'd0;
                                div_cnt_q <= 6'd32;
                                div_q     <= D_RUN;
                            end
                        end
                    end
                end
                D_RUN: begin
                    /* restoring division, one numerator bit per clock */
                    if (div_cnt_q != 6'd0) begin
                        div_cnt_q <= div_cnt_q - 6'd1;
                        if ({div_rem_q[30:0], div_num_q[31]} >= {16'd0, div_den_q}) begin
                            div_rem_q <= {div_rem_q[30:0], div_num_q[31]} - {16'd0, div_den_q};
                            div_quo_q <= {div_quo_q[30:0], 1'b1};
                        end else begin
                            div_rem_q <= {div_rem_q[30:0], div_num_q[31]};
                            div_quo_q <= {div_quo_q[30:0], 1'b0};
                        end
                        div_num_q <= {div_num_q[30:0], 1'b0};
                    end else begin
                        div_q <= D_IDLE;
                        if (div_quo_q > {16'd0, CPS_MAX}) begin
                            cps_q  <= CPS_MAX;
                            half_q <= CPS_MAX >> 1;
                        end else if (div_quo_q < {16'd0, CPS_MIN}) begin
                            cps_q  <= CPS_MIN;
                            half_q <= CPS_MIN >> 1;
                        end else begin
                            cps_q  <= div_quo_q[15:0];
                            half_q <= {1'b0, div_quo_q[15:1]};
                        end
                    end
                end
                default: div_q <= D_IDLE;
            endcase

            /* ---- frame sequence */
            if (!run_i) begin
                frame_q     <= F_RUN1;
                split_q     <= 1'b0;
                target_q    <= cycles_i + {16'd0, cps_q};
            end else case (frame_q)
                F_RUN1: begin
                    if (reached && can_act) begin
                        if (split_q) begin
                            tick_q      <= 1'b1;
                            int3_q      <= 1'b1;
                            ser_rx_o    <= 16'h0000;
                            frame_q     <= F_SEC;
                        end else begin
                            ser_rx_o    <= adc_q;
                            seed_q      <= seed_n;
                            tick_q      <= 1'b1;
                            int3_q      <= 1'b1;
                            frame_tick_o <= 1'b1;
                            frame_q     <= F_WAIT;
                        end
                    end
                end
                F_SEC: begin
                    /* the secondary tick and INT3 stay up until the core takes them at a ce_i edge */
                    if (!tick_q && !int3_q) begin
                                split_q     <= 1'b0;
                        target_q    <= cycles_i + {16'd0, cps_q - half_q};
                        frame_q     <= F_RUN2;
                    end
                end
                F_RUN2: begin
                    if (reached && can_act) begin
                        ser_rx_o     <= adc_q;
                        seed_q       <= seed_n;
                        tick_q       <= 1'b1;
                        int3_q       <= 1'b1;
                        frame_tick_o <= 1'b1;
                        frame_q      <= F_WAIT;
                    end
                end
                F_WAIT: begin
                    if (!tick_q && !int3_q) begin
                        /* next frame: split when a control word is pending */
                        split_q     <= req_q;
                        target_q    <= cycles_i + {16'd0, req_q ? half_q : cps_q};
                        frame_q     <= F_RUN1;
                    end
                end
                default: frame_q <= F_RUN1;
            endcase
        end
    end
    assign dbg_o = {frame_q, reached, split_q, req_q, run_i, div_q, cps_q[6:0]};
endmodule
