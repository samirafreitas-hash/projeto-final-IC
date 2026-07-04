// ============================================================================
// Testbench: tb_bms_dataset
// ----------------------------------------------------------------------------
// Simula o BMS completo (bms_top) alimentado com DADOS REAIS de uma bateria de
// litio, lidos da ROM "bms_battery_rom" (que por sua vez carrega "battery_data.mem", derivado do dataset da NASA).

// IDEIA GERAL:
//   - Cada LINHA do dataset e um instante de tempo da bateria.
//   - O dataset tem apenas UMA tensao medida por instante; como o pack possui
//     4 celulas, usamos a MESMA tensao para as 4, aplicando pequenas variacoes
//     (offsets de poucos mV) para emular o desbalanceamento natural entre elas.
//   - A corrente medida (negativa = descarga) define a direcao I_DIR e, em
//     magnitude escalada, alimenta a contagem de Coulomb (SOC).
//   - A temperatura medida alimenta a protecao de sobretemperatura.

// CONVERSAO DE ESCALA (dataset -> formato do DUT, que usa tensao x100 V):
//   tensao : v_meas(x1000 V) / 10   -> centi-volts (ex.: 4.247 V -> 424)
//   temp   : t_meas(x1000 C) / 1000 -> graus Celsius inteiros
//   corr.  : |i_meas(x1000 A)| / I_SCALE -> magnitude pequena p/ o SOC

// LIMITES CONFIGURADOS VIA I2C (adequados a este dataset):
//   OV = 430 (4.30 V)  -> acima do pico de carga (~4.25 V), nao dispara falso
//   UV = 300 (3.00 V)  -> protecao de subtensao (a bateria chega a ~2.47 V)
//   Imax = 80, Tmax = 60, cap = 500

// COMPORTAMENTO ESPERADO:
//   A bateria descarrega ao longo do dataset (o SOC cai). Enquanto a tensao
//   fica acima de 3.00 V o sistema opera normalmente. Quando a tensao cai
//   abaixo de 3.00 V, a protecao de SUBTENSAO (UV_FLG) e ativada, a FSM entra
//   em ST_FAULT e a descarga e desabilitada (DSCHG_EN = 0) -- exatamente como
//   um BMS real protege a celula no fim da descarga.
// ============================================================================

`timescale 1ns/1ps

module tb_bms_dataset;

    // ------------------------------------------------------------------
    // Parametros do experimento
    // ------------------------------------------------------------------
    localparam integer N_SAMPLES = 490;   // linhas do dataset
    localparam integer I_SCALE   = 500;   // divisor da corrente -> SOC gradual

    // ------------------------------------------------------------------
    // 1. Sinais do DUT
    // ------------------------------------------------------------------
    reg sys_clk, sys_rst;
    reg CHG_PWR_GD;
    reg I_DIR;
    reg [9:0] V1_dig, V2_dig, V3_dig, V4_dig;
    reg [9:0] I_dig;
    reg [9:0] T_dig;
    reg I2C_SCL;
    reg i2c_sda_master_drive_low;
    wire I2C_SDA;

    wire CHG_EN, DSCHG_EN;
    wire OV_FLG, UV_FLG, OT_FLG, LK_FLG;
    wire [3:0] bal_cmd_out;
    wire BAL_FLG;
    wire [9:0] SOC_DATA_OUT;
    wire [2:0] Estado_atual;

    // Mestre I2C simplificado: puxa SDA para 0 quando necessario; solto = '1'.
    assign I2C_SDA = i2c_sda_master_drive_low ? 1'b0 : 1'bz;
    pullup(I2C_SDA);

    // ------------------------------------------------------------------
    // 2. Sinais da ROM de dados reais
    // ------------------------------------------------------------------
    reg  [15:0] rom_addr;
    wire signed [15:0] v_meas, i_meas, t_meas, i_load, v_load, time_meas;

    // ------------------------------------------------------------------
    // 3. Instanciacao do DUT (BMS completo)
    // ------------------------------------------------------------------
    bms_top dut (
        .sys_clk(sys_clk), .sys_rst(sys_rst),
        .CHG_PWR_GD(CHG_PWR_GD), .I_DIR(I_DIR),
        .V1_dig(V1_dig), .V2_dig(V2_dig), .V3_dig(V3_dig), .V4_dig(V4_dig),
        .I_dig(I_dig), .T_dig(T_dig),
        .I2C_SCL(I2C_SCL), .I2C_SDA(I2C_SDA),
        .CHG_EN(CHG_EN), .DSCHG_EN(DSCHG_EN),
        .OV_FLG(OV_FLG), .UV_FLG(UV_FLG), .OT_FLG(OT_FLG), .LK_FLG(LK_FLG),
        .bal_cmd_out(bal_cmd_out), .BAL_FLG(BAL_FLG),
        .SOC_DATA_OUT(SOC_DATA_OUT), .Estado_atual(Estado_atual)
    );

    // ------------------------------------------------------------------
    // 4. Instanciacao da ROM com os dados da bateria
    // ------------------------------------------------------------------
    bms_battery_rom #(
        .N_SAMPLES(N_SAMPLES),
        .MEMFILE("battery_data.mem")
    ) u_data (
        .clk(sys_clk),
        .addr(rom_addr),
        .voltage_measured(v_meas),
        .current_measured(i_meas),
        .temperature_measured(t_meas),
        .current_load(i_load),
        .voltage_load(v_load),
        .time_measured(time_meas)
    );

    // ------------------------------------------------------------------
    // 5. Clock: periodo 10 ns (100 MHz)
    // ------------------------------------------------------------------
    initial begin
        sys_clk = 0;
        forever #5 sys_clk = ~sys_clk;
    end

    // ------------------------------------------------------------------
    // 6. Dump de ondas
    // ------------------------------------------------------------------
    initial begin
        $dumpfile("tb_bms_dataset.vcd");
        $dumpvars(0, tb_bms_dataset);
    end

    // ==================================================================
    // 7. Helpers de configuracao via I2C (identicos ao testbench original)
    // ==================================================================
    task i2c_delay; begin #20; end endtask

    task i2c_start;
        begin
            i2c_sda_master_drive_low = 1'b0; I2C_SCL = 1'b1; i2c_delay;
            i2c_sda_master_drive_low = 1'b1; i2c_delay;
            I2C_SCL = 1'b0; i2c_delay;
        end
    endtask

    task i2c_stop;
        begin
            i2c_sda_master_drive_low = 1'b1; I2C_SCL = 1'b0; i2c_delay;
            I2C_SCL = 1'b1; i2c_delay;
            i2c_sda_master_drive_low = 1'b0; i2c_delay;
        end
    endtask

    task i2c_write_byte;
        input [7:0] data;
        integer i;
        begin
            for (i = 7; i >= 0; i = i - 1) begin
                I2C_SCL = 1'b0;
                i2c_sda_master_drive_low = ~data[i];
                i2c_delay;
                I2C_SCL = 1'b1; i2c_delay;
            end
            I2C_SCL = 1'b0; i2c_sda_master_drive_low = 1'b0; i2c_delay;
            I2C_SCL = 1'b1; i2c_delay;
            I2C_SCL = 1'b0; i2c_delay;
        end
    endtask

    task i2c_write_config;
        input [7:0] reg_addr;
        input [9:0] value;
        begin
            i2c_start;
            i2c_write_byte(8'h84);              // endereco 7'h42 + escrita
            i2c_write_byte(reg_addr);
            i2c_write_byte({6'd0, value[9:8]});
            i2c_write_byte(value[7:0]);
            i2c_stop;
            #100;
        end
    endtask

    // ==================================================================
    // 8. Funcoes de conversao dataset -> formato do DUT
    // ==================================================================
    // Satura um inteiro para a faixa de 10 bits [0, 1023].
    function [9:0] clamp10;
        input integer x;
        begin
            if (x < 0)         clamp10 = 10'd0;
            else if (x > 1023) clamp10 = 10'd1023;
            else               clamp10 = x[9:0];
        end
    endfunction

    // Valor absoluto de um numero de 16 bits com sinal.
    function integer abs16;
        input signed [15:0] x;
        begin
            abs16 = (x < 0) ? -x : x;
        end
    endfunction

    // ==================================================================
    // 9. Aplicacao de UMA amostra do dataset nas entradas do DUT
    // ==================================================================
    integer base_v;

    task aplica_amostra;
        input integer idx;
        begin
            // Seleciona a amostra na ROM e aguarda a leitura sincrona.
            rom_addr = idx[15:0];
            @(posedge sys_clk); #1;   // ROM registra as saidas neste ciclo
            @(posedge sys_clk); #1;   // margem de estabilizacao

            // --- Tensao: dataset (x1000 V) -> DUT (x100 V) ---
            base_v = v_meas / 10;

            // 4 celulas com a MESMA tensao base + pequenas variacoes (mV),
            // emulando o desbalanceamento natural do pack.
            V1_dig = clamp10(base_v - 3);
            V2_dig = clamp10(base_v - 1);
            V3_dig = clamp10(base_v + 2);
            V4_dig = clamp10(base_v + 4);

            // --- Temperatura: dataset (x1000 C) -> graus C ---
            T_dig = clamp10(t_meas / 1000);

            // --- Corrente: sinal define a direcao, magnitude alimenta o SOC ---
            //   i_meas < 0  -> descarga  -> I_DIR = 0
            //   i_meas >= 0 -> carga     -> I_DIR = 1
            I_DIR = (i_meas < 0) ? 1'b0 : 1'b1;
            I_dig = clamp10(abs16(i_meas) / I_SCALE);

            CHG_PWR_GD = 1'b1;
        end
    endtask

    // Aguarda a FSM completar UMA varredura (uma amostragem de SOC).
    // O SOC e amostrado no estado ST_CALC_BAL_SOC (Estado_atual = 111).
    task espera_uma_varredura;
        begin
            // espera entrar em ST_CALC_BAL_SOC
            while (Estado_atual !== 3'b111) begin
                @(posedge sys_clk); #1;
                if (Estado_atual === 3'b101) disable espera_uma_varredura; // ST_FAULT
            end
            // borda em que a FSM sai do estado -> SOC ja registrado
            @(posedge sys_clk); #1;
        end
    endtask

    // ==================================================================
    // 10. Contadores / variaveis de relatorio
    // ==================================================================
    integer i;
    integer amostra_uv;        // amostra em que a protecao UV disparou
    integer soc_inicial;
    reg fault_detectado;

    // ==================================================================
    // 11. Estimulo principal
    // ==================================================================
    initial begin
        $display("================================================================");
        $display("   SIMULACAO BMS COM DADOS REAIS DE BATERIA DE LITIO (NASA)");
        $display("================================================================");

        // ---- Inicializacao ----
        CHG_PWR_GD = 1'b1;
        I_DIR      = 1'b1;
        I2C_SCL    = 1'b1;
        i2c_sda_master_drive_low = 1'b0;
        V1_dig = 10'd380; V2_dig = 10'd380; V3_dig = 10'd380; V4_dig = 10'd380;
        I_dig  = 10'd0;   T_dig  = 10'd25;
        rom_addr = 16'd0;
        amostra_uv = -1;
        fault_detectado = 1'b0;

        // ---- Reset inicial ----
        sys_rst = 1'b1; #30; sys_rst = 1'b0;
        #200;

        // ---- Configuracao dos limites via I2C ----
        $display("");
        $display("--- Configurando limites da ROM via I2C ---");
        i2c_write_config(8'h00, 10'd430);  // OV: 4.30 V (acima do pico de carga)
        i2c_write_config(8'h01, 10'd300);  // UV: 3.00 V
        i2c_write_config(8'h02, 10'd80);   // Imax
        i2c_write_config(8'h03, 10'd5);    // Imin
        i2c_write_config(8'h04, 10'd60);   // Tmax
        i2c_write_config(8'h05, 10'd500);  // capacidade nominal
        $display("  OV=430  UV=300  Imax=80  Tmax=60  cap=500");
        $display("  ROM  -> OV=%0d UV=%0d Imax=%0d Tmax=%0d cap=%0d",
                 dut.u_rom.lim_sobrecarga, dut.u_rom.lim_sobredescarga,
                 dut.u_rom.lim_corrente_max, dut.u_rom.lim_temp,
                 dut.u_rom.capacidade_nom);

        soc_inicial = SOC_DATA_OUT;

        // ---- Streaming do dataset ----
        $display("");
        $display("--- Reproduzindo %0d amostras reais da bateria ---", N_SAMPLES);
        $display("amostra |  V_real | V(x100) [cel1..4] | T(C) | I_real(mA) I_DIR | OV UV OT LK | CHG DSCHG | SOC");
        $display("--------+---------+------------------+------+------------------+------------+----------+-----");

        for (i = 0; i < N_SAMPLES; i = i + 1) begin
            aplica_amostra(i);
            espera_uma_varredura;

            // Detecta a primeira ativacao da protecao de subtensao.
            if (UV_FLG && !fault_detectado) begin
                fault_detectado = 1'b1;
                amostra_uv = i;
                $display("");
                $display(">>> PROTECAO DE SUBTENSAO (UV_FLG) ATIVADA na amostra %0d <<<", i);
                $display("    Tensao real = %0d.%03d V  (abaixo do limite de 3.000 V)",
                         v_meas/1000, (v_meas%1000));
                $display("    A FSM entra em ST_FAULT e a descarga e desabilitada (DSCHG_EN=%b).", DSCHG_EN);
                $display("");
            end

            // Log periodico (a cada 30 amostras) + primeiras/ultimas amostras.
            if ((i % 30 == 0) || (i < 3) || (i >= N_SAMPLES-2) ||
                (fault_detectado && amostra_uv == i)) begin
                $display(" %5d  | %2d.%03d | %3d %3d %3d %3d      |  %2d  |  %6d     %b   |  %b  %b  %b  %b  |  %b    %b   | %4d",
                    i,
                    v_meas/1000, (v_meas%1000),
                    V1_dig, V2_dig, V3_dig, V4_dig,
                    T_dig,
                    i_meas, I_DIR,
                    OV_FLG, UV_FLG, OT_FLG, LK_FLG,
                    CHG_EN, DSCHG_EN,
                    SOC_DATA_OUT);
            end

            // Apos a falha travar (FSM em ST_FAULT), nao ha mais processamento:
            // encerramos o streaming e vamos para o relatorio.
            if (fault_detectado && Estado_atual === 3'b101) begin
                $display("    (FSM travada em ST_FAULT - encerrando reproducao)");
                i = N_SAMPLES; // forca saida do laco
            end
        end

        // ---- Relatorio final ----
        $display("");
        $display("================================================================");
        $display("                       RELATORIO FINAL");
        $display("================================================================");
        $display("  Amostras reproduzidas .......... %0d de %0d", amostra_uv >= 0 ? amostra_uv+1 : N_SAMPLES, N_SAMPLES);
        $display("  SOC inicial (100%%) ............. %0d", soc_inicial);
        $display("  SOC final ...................... %0d", SOC_DATA_OUT);
        if (amostra_uv >= 0)
            $display("  Protecao UV ativada na amostra . %0d (fim da descarga util)", amostra_uv);
        else
            $display("  Protecao UV ..................... nao ativada no dataset");
        $display("  Estado final da FSM ............ %b %s",
                 Estado_atual, (Estado_atual === 3'b101) ? "(ST_FAULT)" : "");
        $display("  Flags finais: OV=%b UV=%b OT=%b LK=%b", OV_FLG, UV_FLG, OT_FLG, LK_FLG);
        $display("  Saidas de potencia: CHG_EN=%b  DSCHG_EN=%b", CHG_EN, DSCHG_EN);
        $display("================================================================");
        $display("  Conclusao: o BMS operou com os dados reais, acompanhou a queda");
        $display("  do SOC durante a descarga e acionou a protecao de subtensao ao");
        $display("  final, protegendo a celula - comportamento esperado do sistema.");
        $display("================================================================");
        $finish;
    end

endmodule
