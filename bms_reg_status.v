// Módulo bms_reg_status
// Registrador de status do BMS responsável por armazenar as falhas detectadas.

// Cada flag representa uma condição de falha:
// OV_FLG = Over Voltage (Sobretensão)
// UV_FLG = Under Voltage (Subtensão)
// OT_FLG = Over Temperature (Sobretemperatura)
// LK_FLG = Falha de balanceamento/Link (dependendo da definição do projeto)

// Quando uma comparação realizada pela ULA resulta em verdadeira
// (cmp_true = 1), a flag correspondente é ativada e permanece ativa
// até que ocorra um reset do sistema.

module bms_reg_status (
    // Clock principal do sistema
    input wire sys_clk,

    // Reset assíncrono
    input wire sys_rst,

    // Resultado da comparação realizada pela ULA
    input wire cmp_true,

    // Sinal que habilita a atualização das flags de falha
    input wire atualiza_falhas,

    // Seleciona qual flag será atualizada
    // 00 = OV_FLG
    // 01 = UV_FLG
    // 10 = OT_FLG
    // 11 = LK_FLG
    input wire [1:0] tipo_falha_sel,

    // Flags de falha armazenadas
    output reg OV_FLG,
    output reg UV_FLG,
    output reg OT_FLG,
    output reg LK_FLG
);

    // Processo sequencial acionado na borda de subida do clock
    // ou quando ocorre reset.
    always @(posedge sys_clk or posedge sys_rst) begin

        // Reset: limpa todas as flags de falha
        if (sys_rst) begin
            OV_FLG <= 1'b0;
            UV_FLG <= 1'b0;
            OT_FLG <= 1'b0;
            LK_FLG <= 1'b0;

        end else begin

            // Atualiza as flags somente quando habilitado
            if (atualiza_falhas) begin

                // Seleciona qual flag será modificada
                case (tipo_falha_sel)

                    // Sobretensão (Over Voltage)
                    // A flag permanece ativa após ser detectada
                    2'b00: OV_FLG <= OV_FLG | cmp_true;

                    // Subtensão (Under Voltage)
                    2'b01: UV_FLG <= UV_FLG | cmp_true;

                    // Sobretemperatura (Over Temperature)
                    2'b10: OT_FLG <= OT_FLG | cmp_true;

                    // Falha de balanceamento/Link
                    2'b11: LK_FLG <= LK_FLG | cmp_true;

                endcase
            end
        end
    end

endmodule