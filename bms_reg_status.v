module bms_reg_status (
    input wire sys_clk,
    input wire sys_rst,
    input wire cmp_true,

    input wire atualiza_falhas,
    input wire [1:0] tipo_falha_sel,

    output reg OV_FLG,
    output reg UV_FLG,
    output reg OT_FLG,
    output reg LK_FLG
);

    always @(posedge sys_clk or posedge sys_rst) begin
        if (sys_rst) begin
            OV_FLG       <= 1'b0;
            UV_FLG       <= 1'b0;
            OT_FLG       <= 1'b0;
            LK_FLG       <= 1'b0;
        end else begin
            if (atualiza_falhas) begin
                case (tipo_falha_sel)
                    2'b00: OV_FLG <= OV_FLG | cmp_true;
                    2'b01: UV_FLG <= UV_FLG | cmp_true;
                    2'b10: OT_FLG <= OT_FLG | cmp_true;
                    2'b11: LK_FLG <= LK_FLG | cmp_true;
                endcase
            end
        end
    end
endmodule
