// ============================================================================
// Modulo: bms_battery_rom
// ----------------------------------------------------------------------------
// ROM que armazena o dataset REAL de uma bateria de litio (NASA) e o
// disponibiliza amostra a amostra para o testbench.
//
// Os dados vem de "battery_data.mem", gerado por gerarDados.py a partir de
// "nasa_dataset_battery.csv". Cada LINHA do arquivo representa um instante de
// tempo da bateria e contem 6 grandezas. Cada grandeza foi escalada por 1000 e
// gravada como hexadecimal de 16 bits em complemento de dois:
//
//   coluna 0 : Voltage_measured      -> tensao da celula      (x1000 V)
//   coluna 1 : Current_measured      -> corrente da bateria   (x1000 A, negativa na descarga)
//   coluna 2 : Temperature_measured  -> temperatura           (x1000 C)
//   coluna 3 : Current_load          -> corrente de carga     (x1000 A)
//   coluna 4 : Voltage_load          -> tensao de carga       (x1000 V)
//   coluna 5 : Time                  -> instante da amostra   (x1000 s)
//
// Observacao: a coluna Time pode transbordar 16 bits (tempos > 32 s), por isso
// e apenas informativa. As grandezas usadas pelo BMS (tensao, corrente e
// temperatura) estao dentro da faixa de 16 bits com sinal.
//
// O $readmemh carrega TODOS os tokens do arquivo em uma memoria linear, na
// ordem em que aparecem. Assim, a amostra de indice "addr" ocupa as posicoes
// addr*N_COLS .. addr*N_COLS + 5.
// ============================================================================

module bms_battery_rom #(
    parameter N_SAMPLES = 490,               // numero de linhas (instantes) do dataset
    parameter N_COLS    = 6,                 // grandezas por linha
    parameter MEMFILE   = "battery_data.mem" // arquivo de dados
)(
    input  wire        clk,
    input  wire [15:0] addr,                 // indice da amostra (0 .. N_SAMPLES-1)

    output reg signed [15:0] voltage_measured,     // x1000 V
    output reg signed [15:0] current_measured,     // x1000 A (negativa na descarga)
    output reg signed [15:0] temperature_measured, // x1000 C
    output reg signed [15:0] current_load,         // x1000 A
    output reg signed [15:0] voltage_load,         // x1000 V
    output reg signed [15:0] time_measured         // x1000 s (informativo)
);

    // Memoria linear: N_SAMPLES * N_COLS palavras de 16 bits.
    reg [15:0] mem [0:N_SAMPLES*N_COLS-1];

    // Carrega o dataset uma unica vez, no inicio da simulacao.
    initial begin
        $readmemh(MEMFILE, mem);
    end

    // Leitura sincrona: na borda de clock entrega as 6 grandezas da amostra
    // apontada por "addr".
    integer base;
    always @(posedge clk) begin
        base                 = addr * N_COLS;
        voltage_measured     <= mem[base + 0];
        current_measured     <= mem[base + 1];
        temperature_measured <= mem[base + 2];
        current_load         <= mem[base + 3];
        voltage_load         <= mem[base + 4];
        time_measured        <= mem[base + 5];
    end

endmodule
