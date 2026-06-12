module bms_mux_B (
    input wire [9:0] lim_sobrecarga,
    input wire [9:0] lim_sobredescarga,
    input wire [9:0] lim_temp,
    input wire [9:0] lim_corrente_fuga,
    input wire [9:0] capacidade_nom,
    input wire [2:0] mux_B_sel,

    output reg [9:0] dado_B
);

    always @(*) begin
        case (mux_B_sel)
            3'b000: dado_B = lim_sobrecarga;
            3'b001: dado_B = lim_sobredescarga;
            3'b010: dado_B = lim_temp;
            3'b011: dado_B = capacidade_nom;
            3'b100: dado_B = lim_corrente_fuga;
            default: dado_B = 10'd0;
        endcase
    end
endmodule
