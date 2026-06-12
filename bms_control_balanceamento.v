module bms_control_balanceamento (
    input wire sys_clk,
    input wire sys_rst,
    input wire [3:0] bal_cmd, // Barramento de ativação vindo da Unidade de Controle/FSM
    
    output reg BAL_EN_1,
    output reg BAL_EN_2,
    output reg BAL_EN_3,
    output reg BAL_EN_4
) ;

    always @(posedge sys_clk or posedge sys_rst) begin
        if (sys_rst) begin
            BAL_EN_1 <= 1'b0;
            BAL_EN_2 <= 1'b0;
            BAL_EN_3 <= 1'b0;
            BAL_EN_4 <= 1'b0;
        end else begin
            // Aciona diretamente as chaves externas dos resistores de desvio
            BAL_EN_1 <= bal_cmd[0];
            BAL_EN_2 <= bal_cmd[1];
            BAL_EN_3 <= bal_cmd[2];
            BAL_EN_4 <= bal_cmd[3];
        end
    end
endmodule