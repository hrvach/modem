/*
dte_uart.sv -- 8N1 serial port of the DTE side (the HPS UART pins of the MiSTer), byte level towards i186_sys.

FPGA-only plumbing. Receiver: rxd_i (async, synchronised here) -> rx_valid_o pulse with rx_byte_o in the middle of the stop bit; line_o is the synchronised
rxd level for i186_sys' DTE TXD input (its T1 gating and INT1 on the start edge). Transmitter: tx_valid_i / tx_byte_i (pulse) into a 16-byte FIFO,
sent back to back at BAUD (115200, the C model's dte_baud); txd_o idles high. A byte pushed into a full FIFO is dropped and counted in dropped_o.
Not modelled: parity, framing error reporting (a bad stop bit still delivers the byte), flow control (CTS / RTS are not used by the modem model).
*/
`default_nettype none

module dte_uart #(
    parameter integer CLKS_PER_BIT = 1050     /* 120.96 MHz / 115200 */
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        rxd_i,
    output logic        txd_o,
    output logic        line_o,
    output logic        rx_valid_o,
    output logic [7:0]  rx_byte_o,
    input  logic        tx_valid_i,
    input  logic [7:0]  tx_byte_i,
    output logic [7:0]  dropped_o
);
    localparam integer HALF = CLKS_PER_BIT / 2;

    logic [2:0]  sync_q;
    logic        rxd;
    localparam integer CW = $clog2(CLKS_PER_BIT + 1);
    logic [CW-1:0] rx_cnt_q;
    logic [3:0]  rx_bit_q;
    logic        rx_busy_q;
    logic [7:0]  rx_shift_q;

    always_comb begin
        rxd    = sync_q[2];
        line_o = sync_q[2];
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            sync_q     <= 3'b111;
            rx_cnt_q   <= {CW{1'b0}};
            rx_bit_q   <= 4'd0;
            rx_busy_q  <= 1'b0;
            rx_shift_q <= 8'h00;
            rx_valid_o <= 1'b0;
            rx_byte_o  <= 8'h00;
        end else begin
            sync_q     <= {sync_q[1:0], rxd_i};
            rx_valid_o <= 1'b0;
            if (!rx_busy_q) begin
                if (!rxd) begin
                    rx_busy_q <= 1'b1;
                    rx_cnt_q  <= {{(CW-1){1'b0}}, 1'b1};
                    rx_bit_q  <= 4'd0;
                end
            end else begin
                rx_cnt_q <= rx_cnt_q + {{(CW-1){1'b0}}, 1'b1};
                /* first sample in the middle of the start bit, then one per bit time */
                if (rx_bit_q == 4'd0) begin
                    if (rx_cnt_q == HALF[CW-1:0]) begin
                        if (rxd) begin
                            rx_busy_q <= 1'b0;                /* glitch, not a start bit */
                        end else begin
                            rx_bit_q <= 4'd1;
                            rx_cnt_q <= {{(CW-1){1'b0}}, 1'b1};
                        end
                    end
                end else if (rx_cnt_q == CLKS_PER_BIT[CW-1:0]) begin
                    rx_cnt_q <= {{(CW-1){1'b0}}, 1'b1};
                    if (rx_bit_q <= 4'd8) begin
                        rx_shift_q <= {rxd, rx_shift_q[7:1]};
                        rx_bit_q   <= rx_bit_q + 4'd1;
                    end else begin
                        rx_valid_o <= 1'b1;
                        rx_byte_o  <= rx_shift_q;
                        rx_busy_q  <= 1'b0;
                    end
                end
            end
        end
    end

    /* ---- transmitter */
    logic [7:0]  fifo_q [0:15];
    logic [4:0]  wr_q, rd_q;
    logic        empty, full;
    logic [CW-1:0] tx_cnt_q;
    logic [3:0]  tx_bit_q;
    logic        tx_busy_q;
    logic [9:0]  tx_shift_q;

    always_comb begin
        empty = (wr_q == rd_q);
        full  = (wr_q[3:0] == rd_q[3:0]) && (wr_q[4] != rd_q[4]);
    end

    always_ff @(posedge clk) begin
        if (!rst_n) begin
            wr_q       <= 5'd0;
            rd_q       <= 5'd0;
            tx_cnt_q   <= {CW{1'b0}};
            tx_bit_q   <= 4'd0;
            tx_busy_q  <= 1'b0;
            tx_shift_q <= 10'h3FF;
            txd_o      <= 1'b1;
            dropped_o  <= 8'd0;
        end else begin
            if (tx_valid_i) begin
                if (full) begin
                    if (dropped_o != 8'hFF)
                        dropped_o <= dropped_o + 8'd1;
                end else begin
                    fifo_q[wr_q[3:0]] <= tx_byte_i;
                    wr_q <= wr_q + 5'd1;
                end
            end
            if (!tx_busy_q) begin
                if (!empty) begin
                    tx_shift_q <= {1'b1, fifo_q[rd_q[3:0]], 1'b0};
                    rd_q       <= rd_q + 5'd1;
                    tx_busy_q  <= 1'b1;
                    tx_cnt_q   <= {{(CW-1){1'b0}}, 1'b1};
                    tx_bit_q   <= 4'd0;
                    txd_o      <= 1'b0;
                end
            end else if (tx_cnt_q == CLKS_PER_BIT[CW-1:0]) begin
                tx_cnt_q <= {{(CW-1){1'b0}}, 1'b1};
                if (tx_bit_q == 4'd9) begin
                    tx_busy_q <= 1'b0;
                    txd_o     <= 1'b1;
                end else begin
                    tx_bit_q   <= tx_bit_q + 4'd1;
                    tx_shift_q <= {1'b1, tx_shift_q[9:1]};
                    txd_o      <= tx_shift_q[1];
                end
            end else begin
                tx_cnt_q <= tx_cnt_q + {{(CW-1){1'b0}}, 1'b1};
            end
        end
    end
endmodule
