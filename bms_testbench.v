`timescale 1ns / 1ps

module tb_bms;

    // --------------------------------------------------------
    // 1. Declaração de Sinais do Testbench
    // --------------------------------------------------------
    // Entradas (Registradores no TB)
    reg sys_clk;
    reg sys_rst;
    reg CHG_PWR_GD;
    reg I_DIR;
    reg [9:0] V1_dig, V2_dig, V3_dig, V4_dig;
    reg [9:0] I_dig;
    reg [9:0] T_dig;

    // Saídas (Fios no TB para ler do DUT)
    wire CHG_EN;
    wire DSCHG_EN;
    wire OV_FLG;
    wire UV_FLG;
    wire OT_FLG;
    wire LK_FLG;
    wire [3:0] bal_cmd_out; // Pinos de balanceamento
    wire [9:0] SOC_DATA_OUT;
    wire [2:0] Estado_atual; // Para monitorar a FSM na simulação

    // --------------------------------------------------------
    // 2. Instanciação do Módulo Principal (DUT - Device Under Test)
    // --------------------------------------------------------
    // Substitua 'bms_top' pelo nome exato do seu arquivo que une os blocos
    bms_top dut (
        .sys_clk(sys_clk),
        .sys_rst(sys_rst),
        .CHG_PWR_GD(CHG_PWR_GD),
        .I_DIR(I_DIR),
        .V1_dig(V1_dig),
        .V2_dig(V2_dig),
        .V3_dig(V3_dig),
        .V4_dig(V4_dig),
        .I_dig(I_dig),
        .T_dig(T_dig),
        
        .CHG_EN(CHG_EN),
        .DSCHG_EN(DSCHG_EN),
        .OV_FLG(OV_FLG),
        .UV_FLG(UV_FLG),
        .OT_FLG(OT_FLG),
        .LK_FLG(LK_FLG),
        .bal_cmd_out(bal_cmd_out),
        .SOC_DATA_OUT(SOC_DATA_OUT),
        .Estado_atual(Estado_atual)
    );

    // --------------------------------------------------------
    // 3. Geração do Clock (Período de 10ns -> 100MHz)
    // --------------------------------------------------------
    initial begin
        sys_clk = 0;
        forever #5 sys_clk = ~sys_clk;
    end

    // --------------------------------------------------------
    // 4. Estímulos da Simulação
    // --------------------------------------------------------
    initial begin
        // A. Inicialização e Reset do Sistema
        $display("Iniciando Simulação do BMS...");
        sys_rst = 1;
        CHG_PWR_GD = 1; // Simulando carregador conectado
        I_DIR = 1;      // 1 = corrente de carga, 0 = corrente de descarga
        
        // Bateria descarregada inicialmente, tensões seguras (Ex: 3.8V = 380)
        V1_dig = 10'd380; V2_dig = 10'd380;
        V3_dig = 10'd380; V4_dig = 10'd380;
        I_dig  = 10'd50;  // Corrente de carga
        T_dig  = 10'd35;  // 35 graus Celsius
        
        #20 sys_rst = 0; // Libera o Reset
        $display("Reset liberado. Sistema em monitoramento normal.");

        // Deixa o sistema rodar algumas varreduras normais
        #200; 

        $display("Invertendo direcao real da corrente para descarga...");
        I_DIR = 0;
        #80;
        $display("Retornando direcao real da corrente para carga...");
        I_DIR = 1;
        #40;
        
        // B. Teste de Falha: Simular Sobrecarga (Overvoltage) na Célula 1
        // O limite na ROM foi definido como 420 (4.2V). Vamos jogar para 430.
        $display("Aplicando Sobrecarga na Celula 1 (V1 = 4.3V)...");
        V1_dig = 10'd430;
        
        // Espera tempo suficiente para a FSM ler os sensores, comparar na ULA e atuar
        #100;
        
        if (CHG_EN == 0 && OV_FLG == 1)
            $display("SUCESSO: Falha detectada e carregamento interrompido!");
        else
            $display("ERRO: O sistema nao cortou o carregamento na sobrecarga.");

        // C. Simular retorno ao normal (A FSM deve estar travada em ST_FAULT pelo nosso código)
        #50;
        $display("Retornando tensao ao normal (V1 = 3.8V)...");
        V1_dig = 10'd380;
        
        #100;
        // D. Finaliza a simulação
        $display("Simulacao concluida.");
        $finish;
    end

       // Monitoramento no Console
    initial begin
        $monitor("Tempo: %0t | FSM: %b | I_DIR: %b | SOC: %d | V1: %d | V2: %d | V3: %d | V4: %d | OV: %b | CHG: %b | DSCHG: %b",
                 $time, Estado_atual, I_DIR, SOC_DATA_OUT, V1_dig, V2_dig, V3_dig, V4_dig, OV_FLG, CHG_EN, DSCHG_EN);
    end

endmodule
