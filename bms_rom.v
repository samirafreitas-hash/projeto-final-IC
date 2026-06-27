// Módulo ROM: para armazenar os limites de operação do BMS (DADOS FIXOS)

// ROM (Read-Only Memory) é uma memória de "somente leitura". 
// Ela guarda informações permanentes que não são apagadas quando o dispositivo é desligado.

module bms_rom (
    input wire clk,
    input wire read_en,
   // input wire [7:0] endereco_ROM,

    output reg [9:0] lim_sobrecarga,
    output reg [9:0] lim_sobredescarga,
    output reg [9:0] lim_temp,
    output reg [9:0] lim_corrente_fuga,
    output reg [9:0] capacidade_nom

   // output reg [15:0] data_out
);

    initial begin
        lim_sobrecarga    = 10'd420; // 4.20 V por celula, em escala exemplo.
        lim_sobredescarga = 10'd300; // 3.00 V por celula, em escala exemplo.
        lim_temp          = 10'd60;  // 60 graus Celsius.
        lim_corrente_fuga = 10'd80;  // Limite exemplo para corrente anomala/fuga.
        capacidade_nom    = 10'd500; // Valor didatico de capacidade/SOC.
       // data_out          = 16'h0000;
    end

    //always @(posedge clk) begin
       // if (read_en) begin
         //   case (endereco_ROM)
            //   8'h00: data_out <= 16'h0001;
            //   8'h01: data_out <= 16'h0010;
            //  8'h02: data_out <= 16'h0020;
            //     8'h03: data_out <= 16'h0030;
            //    8'h04: data_out <= 16'h0040;
            //    8'h05: data_out <= 16'h0100;
            //    8'h06: data_out <= 16'h0200;
            //    default: data_out <= 16'h0000;
         //   endcase
    //    end
   // end

endmodule
