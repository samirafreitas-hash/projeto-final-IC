// Módulo: bms_soc_coulomb

// Estimador de Estado de Carga (SOC - State of Charge) utilizando Contagem de Coulombs (Coulomb Counting).

// O módulo calcula a variação do SOC a partir da corrente medida e da capacidade nominal da bateria.
//
// Funcionamento:
// - Quando I_DIR = 1, considera que a bateria está carregando e o SOC aumenta.
// - Quando I_DIR = 0, considera que a bateria está descarregando e o SOC diminui.
// - O SOC é limitado entre 0 e SOC_FULL_SCALE.
// - A atualização ocorre apenas quando sample_tick é ativado.
// - Em reset, o SOC inicia em 100% (SOC_FULL_SCALE).

module bms_soc_coulomb #(
    // Valor correspondente a 100% de carga
    parameter SOC_FULL_SCALE = 10'd1000,

    // Intervalo de amostragem utilizado no cálculo
    parameter SAMPLE_TIME = 10'd1
) (
    // Clock principal do sistema
    input wire sys_clk,

    // Reset assíncrono
    input wire sys_rst,

    // Pulso que indica o momento de atualizar o SOC
    input wire sample_tick,

    // Direção da corrente
    // 1 = carregando
    // 0 = descarregando
    input wire I_DIR,

    // Corrente medida da bateria
    input wire [9:0] I_reg,

    // Capacidade nominal da bateria
    input wire [9:0] capacidade_nom,

    // Saída com o valor atual do SOC
    output reg [9:0] SOC_DATA_OUT,

    // Registrador interno contendo o SOC atual
    output reg [9:0] SOC_atual
);

    // Variação calculada do SOC
    reg [31:0] delta_soc;

    // Próximo valor de SOC após atualização
    reg [31:0] next_soc;

    // -------------------------------------------------------------------------
    // Lógica combinacional
    // Calcula a variação do SOC e determina o próximo valor.
    // -------------------------------------------------------------------------
    always @(*) begin

        // Evita divisão por zero
        if (capacidade_nom == 10'd0) begin
            delta_soc = 32'd0;

        end else begin
            // Fórmula simplificada de Coulomb Counting:
            //
            // ΔSOC = (Corrente × Tempo de Amostragem × Escala SOC)
            //        / Capacidade Nominal
            //
            delta_soc =
                (I_reg * SAMPLE_TIME * SOC_FULL_SCALE) / capacidade_nom;
        end

        // Caso a bateria esteja carregando
        if (I_DIR) begin
            next_soc = SOC_atual + delta_soc;

        // Caso esteja descarregando
        end else if (SOC_atual > delta_soc[9:0]) begin
            next_soc = SOC_atual - delta_soc;

        // Impede valores negativos
        end else begin
            next_soc = 32'd0;
        end
    end

    // -------------------------------------------------------------------------
    // Lógica sequencial
    // Atualiza o valor do SOC somente quando ocorre sample_tick.
    // -------------------------------------------------------------------------
    always @(posedge sys_clk or posedge sys_rst) begin

        // Inicializa o SOC em 100% durante o reset
        if (sys_rst) begin
            SOC_atual    <= SOC_FULL_SCALE;
            SOC_DATA_OUT <= SOC_FULL_SCALE;

        // Atualiza o SOC quando chegar um pulso de amostragem
        end else if (sample_tick) begin

            // Limita o valor máximo ao SOC_FULL_SCALE
            if (next_soc > SOC_FULL_SCALE) begin
                SOC_atual    <= SOC_FULL_SCALE;
                SOC_DATA_OUT <= SOC_FULL_SCALE;

            end else begin
                // Armazena o novo valor calculado
                SOC_atual    <= next_soc[9:0];
                SOC_DATA_OUT <= next_soc[9:0];
            end
        end
    end

endmodule