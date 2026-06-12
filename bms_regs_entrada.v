// Módulo de registro de entrada para o BMS

// Este módulo armazena as leituras digitais dos sensores de tensão, corrente e temperatura em registradores internos, 
// controlados por sinais de uma FSM.

// Para esse projeto estamos considerando um pack de 4 células de lítio em série, 
// portanto temos 4 entradas de tensão (V1 a V4), uma entrada de corrente (I) e uma entrada de temperatura (T)

// Para os dados, estamos considerando que as leituras digitais já estão escaladas para um formato de 10 bits

module bms_regs_entrada (
    input wire clk,
    input wire rst,
    
    // Entradas digitais dos sensores (10 bits)
    input wire [9:0] V1_dig,
    input wire [9:0] V2_dig,
    input wire [9:0] V3_dig,
    input wire [9:0] V4_dig,
    input wire [9:0] I_dig,
    input wire [9:0] T_dig,
    
    // Sinais de controle da FSM
    input wire load_V,
    input wire load_I,
    input wire load_T,
    
    // Saídas registradas
    output reg [9:0] V1_reg,
    output reg [9:0] V2_reg,
    output reg [9:0] V3_reg,
    output reg [9:0] V4_reg,
    output reg [9:0] I_reg,
    output reg [9:0] T_reg
);

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            // Reset assíncrono zera todos os registradores
            V1_reg <= 10'd0;
            V2_reg <= 10'd0;
            V3_reg <= 10'd0;
            V4_reg <= 10'd0;
            I_reg  <= 10'd0;
            T_reg  <= 10'd0;
        end else begin
            // Atualiza as tensões se load_V estiver alto
            if (load_V) begin
                V1_reg <= V1_dig;
                V2_reg <= V2_dig;
                V3_reg <= V3_dig;
                V4_reg <= V4_dig;
            end
            
            // Atualiza a corrente se load_I estiver alto
            if (load_I) begin
                I_reg <= I_dig;
            end
            
            // Atualiza a temperatura se load_T estiver alto
            if (load_T) begin
                T_reg <= T_dig;
            end
        end
    end
endmodule