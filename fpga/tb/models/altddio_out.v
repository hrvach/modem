// Simulation stub of the Altera DDR output cell used by rtl/ram/sdram2.sv (SDRAM_CLK): high-data on the high clock phase,
// low-data on the low phase (datain_h = 0, datain_l = 1 gives the inverted clock).
module altddio_out #(parameter extend_oe_disable = "OFF", intended_device_family = "", invert_output = "OFF", lpm_hint = "", lpm_type = "",
                     oe_reg = "", power_up_high = "OFF", width = 1)
(
    input  [width-1:0] datain_h, datain_l,
    input              outclock, outclocken, aclr, aset, sclr, sset, oe,
    output [width-1:0] dataout
);
assign dataout = outclock ? datain_h : datain_l;
endmodule
