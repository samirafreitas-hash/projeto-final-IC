module bms_mux_A (
    input wire [9:0] V1_reg,
    input wire [9:0] V2_reg,
    input wire [9:0] V3_reg,
    input wire [9:0] V4_reg,
    input wire [9:0] I_reg,
    input wire [9:0] T_reg,
    input wire [2:0] mux_sel,

    output reg [9:0] dado_A
);

    always @(*) begin
        case (mux_sel)
            3'b000: dado_A = V1_reg;
            3'b001: dado_A = V2_reg;
            3'b010: dado_A = V3_reg;
            3'b011: dado_A = V4_reg;
            3'b100: dado_A = I_reg;
            3'b101: dado_A = T_reg;
            default: dado_A = 10'd0;
        endcase
    end
endmodule
