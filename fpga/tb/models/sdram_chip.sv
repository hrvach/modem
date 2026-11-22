/* Behavioural SDR SDRAM (4 banks x 8192 rows x 512 columns x 16 bit, sparse), the subset sdram16 uses: ACTIVE, READ, WRITE (A[12:11] = DQM),
   AUTO REFRESH, LOAD MODE. Read data appears CL clocks after READ, then DLY ns of output/pad delay. Tracks the longest gap between refreshes
   once the start-up is done (the first refresh after LOAD MODE starts the clock). */
`timescale 1ns/1ps
module sdram_chip #(parameter integer DLY = 9)
(
    input         clk, nCS, nRAS, nCAS, nWE,
    input  [1:0]  BA,
    input  [12:0] A,
    input  [15:0] DQ_O,
    output [15:0] DQ_I
);
reg [15:0] mem [longint];
reg [12:0] row [0:3];
reg [12:0] mode = 0;
integer refreshes = 0;
real first_ref = 0.0, last_ref = -1.0, max_gap_ns = 0.0, t;
wire [2:0] cmd = {nRAS, nCAS, nWE};
reg [15:0] d0, d1, d2, d3;
reg        v0 = 0, v1 = 0, v2 = 0, v3 = 0;
reg [15:0] dl [0:40];
reg        tick1 = 0;
integer    di;
longint    key;

always #0.5 tick1 = ~tick1;
initial for (di = 0; di <= 40; di = di + 1) dl[di] = 16'h0;
always @(posedge tick1) begin
    dl[0] <= v3 ? d3 : 16'h0;
    for (di = 1; di <= 40; di = di + 1) dl[di] <= dl[di-1];
end
assign DQ_I = dl[DLY];

always @(posedge clk) begin
    v3 <= v2; d3 <= d2; v2 <= v1; d2 <= d1; v1 <= v0; d1 <= d0; v0 <= 0;
    if (!nCS) begin
        key = {BA, row[BA], A[8:0]};
        case (cmd)
            3'b011: row[BA] <= A;
            3'b000: mode <= A;
            3'b001: begin
                t = $realtime;
                if (last_ref >= 0.0 && t - last_ref > max_gap_ns) max_gap_ns = t - last_ref;
                if (last_ref < 0.0) first_ref = t;
                last_ref = t;
                refreshes <= refreshes + 1;
            end
            3'b101: begin
                /* data CL clocks after READ: v1 = CL2 path; CL3 adds one more stage */
                if (mode[6:4] == 3'd2) begin v1 <= 1; d1 <= mem.exists(key) ? mem[key] : 16'hdead; end
                else begin v0 <= 1; d0 <= mem.exists(key) ? mem[key] : 16'hdead; end
            end
            3'b100: begin
                reg [15:0] old;
                old = mem.exists(key) ? mem[key] : 16'h0;
                if (!A[12]) old[15:8] = DQ_O[15:8];
                if (!A[11]) old[7:0]  = DQ_O[7:0];
                mem[key] = old;
            end
            default: ;
        endcase
    end
end
endmodule
