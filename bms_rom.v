// Modulo ROM/configuracao: armazena os limites de operacao do BMS.
// Os valores possuem padrao inicial e podem ser atualizados via I2C.
//
// Mapa de registradores para escrita I2C:
//   0x00: limite de sobretensao
//   0x01: limite de subtensao
//   0x02: corrente maxima
//   0x03: corrente minima
//   0x04: temperatura maxima
//   0x05: capacidade nominal
module bms_rom (
    input wire clk,
    input wire rst,
    input wire read_en,
    input wire cfg_wr_en,
    input wire [7:0] cfg_addr,
    input wire [9:0] cfg_data,

    output reg [9:0] lim_sobrecarga,
    output reg [9:0] lim_sobredescarga,
    output reg [9:0] lim_corrente_max,
    output reg [9:0] lim_corrente_min,
    output reg [9:0] lim_temp,
    output reg [9:0] lim_corrente_fuga,
    output reg [9:0] capacidade_nom
);

    localparam REG_LIM_SOBRECARGA    = 8'h00;
    localparam REG_LIM_SOBREDESCARGA = 8'h01;
    localparam REG_LIM_CORRENTE_MAX  = 8'h02;
    localparam REG_LIM_CORRENTE_MIN  = 8'h03;
    localparam REG_LIM_TEMP          = 8'h04;
    localparam REG_CAPACIDADE_NOM    = 8'h05;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            lim_sobrecarga    <= 10'd420; // 4.20 V por celula, em escala exemplo.
            lim_sobredescarga <= 10'd300; // 3.00 V por celula, em escala exemplo.
            lim_corrente_max  <= 10'd80;  // Corrente maxima permitida.
            lim_corrente_min  <= 10'd0;   // Corrente minima esperada.
            lim_temp          <= 10'd60;  // Temperatura maxima em graus Celsius.
            lim_corrente_fuga <= 10'd80;  // Mantido para compatibilidade com a logica atual.
            capacidade_nom    <= 10'd500; // Valor didatico de capacidade/SOC.
        end else if (read_en && cfg_wr_en) begin
            case (cfg_addr)
                REG_LIM_SOBRECARGA: begin
                    lim_sobrecarga <= cfg_data;
                end

                REG_LIM_SOBREDESCARGA: begin
                    lim_sobredescarga <= cfg_data;
                end

                REG_LIM_CORRENTE_MAX: begin
                    lim_corrente_max  <= cfg_data;
                    lim_corrente_fuga <= cfg_data;
                end

                REG_LIM_CORRENTE_MIN: begin
                    lim_corrente_min <= cfg_data;
                end

                REG_LIM_TEMP: begin
                    lim_temp <= cfg_data;
                end

                REG_CAPACIDADE_NOM: begin
                    capacidade_nom <= cfg_data;
                end
            endcase
        end
    end

endmodule
