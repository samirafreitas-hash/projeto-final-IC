// Módulo bms_control_balanceamento
// Responsável por TODO o cálculo do balanceamento das células:
//   - encontrar a tensão mínima entre as 4 células (v_min)
//   - decidir quais células estão "acima" de v_min + BAL_DELTA
//   - acionar as chaves externas dos resistores de desvio (BAL_EN_x)
//   - informar, através de PRECISA_BAL_FLG, se alguma célula precisa
//     ser balanceada (flag de informação, NÃO é flag de falha)
//
// A ULA não participa do cálculo: ela só sinaliza, através de
// verifica_bal_flg, que é o momento (definido pela FSM) de recalcular
// e atualizar o estado do balanceamento.

module bms_control_balanceamento (
    input wire sys_clk,
    input wire sys_rst,

    // Tensões das 4 células, vindas dos registradores de entrada
    input wire [9:0] V1_reg,
    input wire [9:0] V2_reg,
    input wire [9:0] V3_reg,
    input wire [9:0] V4_reg,

    // Vindo da ULA: indica que é o momento de verificar/recalcular
    // o balanceamento (pulsado pela FSM durante o estado ST_CALC_BAL)
    input wire verifica_bal_flg,

    // Aciona diretamente as chaves externas dos resistores de desvio
    output reg BAL_EN_1,
    output reg BAL_EN_2,
    output reg BAL_EN_3,
    output reg BAL_EN_4,

    // Flag de informação (NÃO é falha): indica se alguma célula
    // precisa ser balanceada no momento
    output reg BAL_FLG
);

    // Margem tolerada acima da menor tensão antes de acionar o desvio
    localparam BAL_DELTA = 10'd10;

    reg [9:0] v_min;
    reg [3:0] bal_cmd_calc;

    // Encontra a menor tensão entre as 4 células
    always @(*) begin
        if ((V1_reg <= V2_reg) && (V1_reg <= V3_reg) && (V1_reg <= V4_reg)) begin
            v_min = V1_reg;
        end else if ((V2_reg <= V1_reg) && (V2_reg <= V3_reg) && (V2_reg <= V4_reg)) begin
            v_min = V2_reg;
        end else if ((V3_reg <= V1_reg) && (V3_reg <= V2_reg) && (V3_reg <= V4_reg)) begin
            v_min = V3_reg;
        end else begin
            v_min = V4_reg;
        end
    end

    // Decide quais células estão acima de v_min + BAL_DELTA
    always @(*) begin
        if(v_min > 1'b0) begin
            bal_cmd_calc[0] = (V1_reg > (v_min + BAL_DELTA));
            bal_cmd_calc[1] = (V2_reg > (v_min + BAL_DELTA));
            bal_cmd_calc[2] = (V3_reg > (v_min + BAL_DELTA));
            bal_cmd_calc[3] = (V4_reg > (v_min + BAL_DELTA));
        end
    end

    // Só atualiza (e mantém) o estado do balanceamento quando a ULA
    // sinaliza que é o momento certo (verifica_bal_flg = 1). Fora
    // disso, os registradores mantêm o último valor calculado.
    always @(posedge sys_clk or posedge sys_rst) begin
        if (sys_rst) begin
            BAL_EN_1        <= 1'b0;
            BAL_EN_2        <= 1'b0;
            BAL_EN_3        <= 1'b0;
            BAL_EN_4        <= 1'b0;
            BAL_FLG         <= 1'b0;
        end else if (verifica_bal_flg) begin
            BAL_EN_1        <= bal_cmd_calc[0];
            BAL_EN_2        <= bal_cmd_calc[1];
            BAL_EN_3        <= bal_cmd_calc[2];
            BAL_EN_4        <= bal_cmd_calc[3];
            BAL_FLG         <= |bal_cmd_calc;
        end
    end
endmodule