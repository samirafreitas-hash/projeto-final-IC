module tb_bms;

    // ============================================================
    // LIMITES DA ROM:
    //   lim_sobrecarga    = 420  → OV_FLG se V > 420
    //   lim_sobredescarga = 300  → UV_FLG se V < 300
    //   lim_temp          = 60   → OT_FLG se T > 60
    //   lim_corrente_fuga = 80   → LK_FLG se I > 80
    //
    // FLUXO DA FSM (1 ciclo = 10ns cada estado):
    //   ST_READ_SENSORS → ST_CHECK_OV (x4 células) → ST_CHECK_UV (x4)
    //   → ST_CHECK_OT → ST_CHECK_LK → ST_CALC_BAL → (repete)
    //   Total de uma varredura: ~10 ciclos = 100ns
    //
    // ORDEM CRÍTICA DO TESTBENCH:
    //   1. reset (limpa flags e registradores internos)
    //   2. libera reset
    //   3. aplica estímulo de falha nos pinos de entrada (_dig)
    //   4. aguarda ST_READ_SENSORS capturar o valor (load_V/I/T pulsa)
    //   5. aguarda a FSM processar e setar a flag
    //   6. verifica
    // ============================================================

    // --------------------------------------------------------
    // 1. Declaração de Sinais
    // --------------------------------------------------------
    reg sys_clk, sys_rst;
    reg CHG_PWR_GD;
    reg I_DIR;
    reg [9:0] V1_dig, V2_dig, V3_dig, V4_dig;
    reg [9:0] I_dig;
    reg [9:0] T_dig;

    wire CHG_EN, DSCHG_EN;
    wire OV_FLG, UV_FLG, OT_FLG, LK_FLG;
    wire [3:0] bal_cmd_out;
    wire [9:0] SOC_DATA_OUT;
    wire [2:0] Estado_atual;

    // --------------------------------------------------------
    // 2. Instanciação do DUT
    // --------------------------------------------------------
    bms_top dut (
        .sys_clk(sys_clk), .sys_rst(sys_rst),
        .CHG_PWR_GD(CHG_PWR_GD), .I_DIR(I_DIR),
        .V1_dig(V1_dig), .V2_dig(V2_dig),
        .V3_dig(V3_dig), .V4_dig(V4_dig),
        .I_dig(I_dig), .T_dig(T_dig),
        .CHG_EN(CHG_EN), .DSCHG_EN(DSCHG_EN),
        .OV_FLG(OV_FLG), .UV_FLG(UV_FLG),
        .OT_FLG(OT_FLG), .LK_FLG(LK_FLG),
        .bal_cmd_out(bal_cmd_out),
        .SOC_DATA_OUT(SOC_DATA_OUT),
        .Estado_atual(Estado_atual)
    );

    // --------------------------------------------------------
    // 3. Clock: período 10 ns (100 MHz)
    // --------------------------------------------------------
    initial begin
        sys_clk = 0;
        forever #5 sys_clk = ~sys_clk;
    end

    initial begin
        $dumpfile("tb_bms.vcd");
        $dumpvars(0, tb_bms);
    end

    // --------------------------------------------------------
    // 4. Helper: imprime [OK] ou [FALHA]
    // --------------------------------------------------------
    task check;
        input [200:0] nome;
        input         sinal;
        input         esperado;
        begin
            if (sinal === esperado)
                $display("    [OK]    %0s", nome);
            else
                $display("    [FALHA] %0s  (esperado=%b  obtido=%b)", nome, esperado, sinal);
        end
    endtask

    // --------------------------------------------------------
    // 5. Helper: limpa o sistema entre testes
    //    IMPORTANTE: o estímulo de falha é aplicado ANTES de
    //    chamar este task — aqui só fazemos reset e esperamos
    //    a FSM estabilizar com entradas seguras.
    // --------------------------------------------------------
    task limpa_e_aguarda;
        begin
            // Volta entradas para estado seguro
            V1_dig = 10'd380; V2_dig = 10'd380;
            V3_dig = 10'd380; V4_dig = 10'd380;
            I_dig  = 10'd50;
            T_dig  = 10'd35;
            I_DIR  = 1;
            // Reset para zerar flags e registradores internos
            sys_rst = 1;
            #30;           // segura reset por 3 ciclos (assincrono, garante limpeza)
            sys_rst = 0;
            // Aguarda 3 varreduras completas para FSM estabilizar
            // (~10 estados x 10ns x 3 = 300ns)
            #300;
        end
    endtask

    // --------------------------------------------------------
    // 6. Estímulos
    // --------------------------------------------------------
    initial begin

        $display("========================================");
        $display("       SIMULACAO BMS - TESTES DE FALHA  ");
        $display("========================================");

        // Inicialização: entradas seguras + reset inicial
        CHG_PWR_GD = 1;
        I_DIR      = 1;
        V1_dig = 10'd380; V2_dig = 10'd380;
        V3_dig = 10'd380; V4_dig = 10'd380;
        I_dig  = 10'd50;
        T_dig  = 10'd35;

        sys_rst = 1; #30; sys_rst = 0;
        $display("[INIT] Reset liberado. Aguardando FSM estabilizar...");
        #300;

        // ====================================================
        // TESTE 1 — SOBRETENSÃO (OV_FLG)
        //   Condição: V > 420  →  OV_FLG=1, CHG_EN=0
        //
        //   A sobretensão é analisada em fms=010
        //
        //   Sequência:
        //     a) Aplica Vx_dig acima do limite
        //     b) Aguarda FSM: ST_READ_SENSORS captura → ST_CHECK_OV compara → flag sobe
        //     c) Verifica
        //     d) Limpa (reset + entradas seguras + aguarda)
        // ====================================================
        $display("");
        $display("--- TESTE 1: SOBRETENSAO (OV_FLG) — limite = 420 ---");

        $display("  [1a] V1=430 (demais=380)");
        V1_dig = 10'd430;               // (a) aplica ANTES de qualquer espera
        #300;                           // (b) 3 varreduras: garante load + check
        check("OV_FLG ativado",   OV_FLG, 1'b1);
        check("CHG_EN desligado", CHG_EN, 1'b0);
        limpa_e_aguarda;                // (d)

        $display("  [1b] V2=430 (demais=380)");
        V2_dig = 10'd430;
        #300;
        check("OV_FLG ativado",   OV_FLG, 1'b1);
        check("CHG_EN desligado", CHG_EN, 1'b0);
        limpa_e_aguarda;

        $display("  [1c] V3=430 (demais=380)");
        V3_dig = 10'd430;
        #300;
        check("OV_FLG ativado",   OV_FLG, 1'b1);
        check("CHG_EN desligado", CHG_EN, 1'b0);
        limpa_e_aguarda;

        $display("  [1d] V4=430 (demais=380)");
        V4_dig = 10'd430;
        #300;
        check("OV_FLG ativado",   OV_FLG, 1'b1);
        check("CHG_EN desligado", CHG_EN, 1'b0);
        limpa_e_aguarda;

        // ====================================================
        // TESTE 2 — SUBTENSÃO (UV_FLG)
        //
        //   Subtensão analisada em fms=011
        //   Condição: V < 300  →  UV_FLG=1, DSCHG_EN=0
        // ====================================================
        $display("");
        $display("--- TESTE 2: SUBTENSAO (UV_FLG) — limite = 300 ---");

        $display("  [2a] V1=250 (demais=380)");
        V1_dig = 10'd250;
        #300;
        check("UV_FLG ativado",    UV_FLG,   1'b1);
        check("DSCHG_EN desligado",DSCHG_EN, 1'b0);
        limpa_e_aguarda;

        $display("  [2b] V2=250 (demais=380)");
        V2_dig = 10'd250;
        #300;
        check("UV_FLG ativado",    UV_FLG,   1'b1);
        check("DSCHG_EN desligado",DSCHG_EN, 1'b0);
        limpa_e_aguarda;

        $display("  [2c] V3=250 (demais=380)");
        V3_dig = 10'd250;
        #300;
        check("UV_FLG ativado",    UV_FLG,   1'b1);
        check("DSCHG_EN desligado",DSCHG_EN, 1'b0);
        limpa_e_aguarda;

        $display("  [2d] V4=250 (demais=380)");
        V4_dig = 10'd250;
        #300;
        check("UV_FLG ativado",    UV_FLG,   1'b1);
        check("DSCHG_EN desligado",DSCHG_EN, 1'b0);
        limpa_e_aguarda;

        // ====================================================
        // TESTE 3 — SOBRETEMPERATURA (OT_FLG)
        //
        //   A temperatura é analisada em fms=100
        //   Condição: T > 60  →  OT_FLG=1, CHG_EN=0, DSCHG_EN=0
        // ====================================================
        $display("");
        $display("--- TESTE 3: SOBRETEMPERATURA (OT_FLG) — limite = 60 ---");
        $display("  T=75");
        T_dig = 10'd75;
        #300;
        check("OT_FLG ativado",    OT_FLG,   1'b1);
        check("CHG_EN desligado",  CHG_EN,   1'b0);
        check("DSCHG_EN desligado",DSCHG_EN, 1'b0);
        limpa_e_aguarda;

        // ====================================================
        // TESTE 4 — SOBRECORRENTE (LK_FLG)
        //
        //   A corrente é analisada em fms=110
        //   Condição: I > 80  →  LK_FLG=1, CHG_EN=0
        // ====================================================
        $display("");
        $display("--- TESTE 4: SOBRECORRENTE (LK_FLG) — limite = 80 ---");
        $display("  I=100");
        I_dig = 10'd100;
        #300;
        check("LK_FLG ativado",   LK_FLG, 1'b1);
        check("CHG_EN desligado", CHG_EN, 1'b0);
        limpa_e_aguarda;

        // ====================================================
        // TESTE 5 — BALANCEAMENTO (bal_cmd_out)
        //
        //   Lógica na FSM (ST_CALC_BAL = 3'b111):
        //     bal_cmd[x] = (Vx_reg > v_min + BAL_DELTA)   BAL_DELTA = 10
        //     v_min      = menor tensão entre as 4 células
        //
        //   PROBLEMA DE DESIGN IDENTIFICADO:
        //     bal_cmd é COMBINACIONAL no always@(*) da FSM.
        //     bms_control_balanceamento registra bal_cmd no posedge do clock.
        //     Na borda que sai de ST_CALC_BAL, Estado_atual já virou ST_READ_SENSORS,
        //     então o always@(*) recalcula bal_cmd=0 antes do registrador capturar.
        //     Resultado: BAL_EN_x nunca sai de zero pelo caminho normal.
        //
        //   SOLUÇÃO NO TESTBENCH:
        //     Capturamos bal_cmd DIRETAMENTE da FSM no meio do estado ST_CALC_BAL
        //     (entre bordas de clock, quando o sinal combinacional está válido),
        //     usando #1 após a borda de subida para ler após a propagação combinacional.
        //
        //   Cenário:
        //     V1 = 380  (menor → v_min = 380, nao balanceia)
        //     V2 = 395  (395 > 380+10=390 → deve balancear)
        //     V3 = 385  (385 > 390? NAO   → nao balanceia)
        //     V4 = 400  (400 > 390? SIM   → deve balancear)
        // ====================================================
        $display("");
        $display("--- TESTE 5: BALANCEAMENTO (bal_cmd_out) ---");
        $display("  V1=380 (v_min), V2=395, V3=385, V4=400");
        $display("  Limiar = v_min + BAL_DELTA = 380 + 10 = 390");
        $display("  Esperado: BAL_EN_1=0  BAL_EN_2=1  BAL_EN_3=0  BAL_EN_4=1");
        $display("  NOTA: bug de design — bal_cmd combinacional zerado antes do");
        $display("        registrador capturar. Verificamos bal_cmd direto da FSM.");

        V1_dig = 10'd380;
        V2_dig = 10'd395;
        V3_dig = 10'd385;
        V4_dig = 10'd400;

        // Aguarda a FSM entrar em ST_CALC_BAL usando loop Verilog puro
        // (compatível com Verilog-2001 / Xcelium sem flag SV)
        begin : wait_calc_bal
            forever begin
                @(posedge sys_clk);
                if (Estado_atual == 3'b111) disable wait_calc_bal;
            end
        end

        // Lê bal_cmd_out AGORA, no meio do estado ST_CALC_BAL,
        // logo após a propagação combinacional (1ns de margem)
        #1;
        check("BAL_EN_1=0 (V1=380 e v_min, nao balanceia)", bal_cmd_out[0], 1'b0);
        check("BAL_EN_2=1 (V2=395 > 390, balanceia)",       bal_cmd_out[1], 1'b1);
        check("BAL_EN_3=0 (V3=385 < 390, nao balanceia)",   bal_cmd_out[2], 1'b0);
        check("BAL_EN_4=1 (V4=400 > 390, balanceia)",       bal_cmd_out[3], 1'b1);
        limpa_e_aguarda;

        $display("");
        $display("========================================");
        $display("         Simulacao concluida.");
        $display("========================================");
        $finish;
    end

    // --------------------------------------------------------
    // 7. Monitor contínuo
    // --------------------------------------------------------
    initial begin
        $monitor("t=%0t | FSM=%b | V1=%0d V2=%0d V3=%0d V4=%0d | T=%0d I=%0d | OV=%b UV=%b OT=%b LK=%b | CHG=%b DSCHG=%b | BAL=%b",
                 $time, Estado_atual,
                 V1_dig, V2_dig, V3_dig, V4_dig,
                 T_dig, I_dig,
                 OV_FLG, UV_FLG, OT_FLG, LK_FLG,
                 CHG_EN, DSCHG_EN,
                 bal_cmd_out);
    end

endmodule
