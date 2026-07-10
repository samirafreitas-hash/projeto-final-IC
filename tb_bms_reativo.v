module tb_bms_reativo;

    // ============================================================
    // LIMITES DA ROM (gravados via I2C no início do teste):
    //   lim_sobrecarga    = 420  → OV_FLG se V > 420
    //   lim_sobredescarga = 300  → UV_FLG se V < 300
    //   lim_temp          = 60   → OT_FLG se T > 60
    //   lim_corrente_fuga = 80   → LK_FLG se I > 80
    //
    // FLUXO DA FSM (1 ciclo = 10ns cada estado):
    //   ST_READ_SENSORS → ST_CHECK_OV (x4 células) → ST_CHECK_UV (x4)
    //   → ST_CHECK_OT → ST_CHECK_LK → ST_CALC_BAL_SOC → (repete)
    //   (ST_CALC_BAL_SOC faz o balanceamento E a amostragem do SOC)
    //   Total de uma varredura: ~10 ciclos = 100ns
    //
    // MUDANÇA EM RELAÇÃO À VERSÃO ANTERIOR — SIMULAÇÃO REATIVA:
    //   V1_dig..V4_dig, I_dig, T_dig e I_DIR deixaram de ser regs
    //   atribuídos manualmente pelo testbench. Agora são wires vindos do
    //   módulo bms_battery_model, que reage às saídas de atuação do
    //   próprio BMS (CHG_EN, DSCHG_EN, bal_cmd_out) e evolui a bateria
    //   sozinho a cada varredura da FSM.
    //
    //   Para os testes determinísticos de falha (OV/UV/OT/LK/balanceamento/
    //   SOC), o testbench continua "impondo" exatamente os mesmos valores
    //   de antes — só que agora via um pulso preset_en (task
    //   preset_bateria), em vez de atribuição direta. O comportamento
    //   observável desses testes é idêntico ao da versão anterior.
    //
    //   No final (TESTE 7), a bateria roda sem nenhum preset: o testbench
    //   só "pluga" um carregador ou uma carga (charger_present/
    //   load_present) e observa o sistema reagir sozinho — inclusive
    //   cortando a carga/descarga automaticamente ao violar os limites.
    //
    // ORDEM CRÍTICA DO TESTBENCH:
    //   1. reset (limpa flags, registradores internos e a bateria)
    //   2. libera reset
    //   3. impõe o estímulo de falha via preset_bateria
    //   4. aguarda ST_READ_SENSORS capturar o valor (load_V/I/T pulsa)
    //   5. aguarda a FSM processar e setar a flag
    //   6. verifica
    // ============================================================

    // --------------------------------------------------------
    // 1. Declaração de Sinais
    // --------------------------------------------------------
    reg sys_clk, sys_rst;
    reg CHG_PWR_GD;
    reg I2C_SCL;
    reg i2c_sda_master_drive_low;
    wire I2C_SDA;

    // Auxiliar: guarda o SOC antes de um trecho de carga/descarga
    reg [9:0] soc_antes;

    // Sinais de "mundo externo" controlados pelo testbench para o modelo
    // de bateria
    reg        preset_en;
    reg [9:0]  preset_V1, preset_V2, preset_V3, preset_V4;
    reg [9:0]  preset_I, preset_T;
    reg        preset_I_DIR;
    reg [9:0]  ext_I_bias, ext_T_bias;
    reg        charger_present, load_present;

    // Agora vêm do bms_battery_model, não são mais regs do testbench
    wire [9:0] V1_dig, V2_dig, V3_dig, V4_dig;
    wire [9:0] I_dig;
    wire [9:0] T_dig;
    wire       I_DIR;

    wire CHG_EN, DSCHG_EN;
    // Atividade REAL (mutuamente exclusiva), diferente de CHG_EN/DSCHG_EN
    // que são só permissão do BMS e podem estar os dois em 1 ao mesmo tempo
    wire charging_now, discharging_now;
    wire OV_FLG, UV_FLG, OT_FLG, LK_FLG;
    wire [3:0] bal_cmd_out;
    wire BAL_FLG;
    wire [9:0] SOC_DATA_OUT;
    wire [2:0] Estado_atual;

    assign I2C_SDA = i2c_sda_master_drive_low ? 1'b0 : 1'bz;
    pullup(I2C_SDA);

    // --------------------------------------------------------
    // 2. Instanciação do DUT
    // --------------------------------------------------------
    bms_top dut (
        .sys_clk(sys_clk), .sys_rst(sys_rst),
        .CHG_PWR_GD(CHG_PWR_GD), .I_DIR(I_DIR),
        .V1_dig(V1_dig), .V2_dig(V2_dig),
        .V3_dig(V3_dig), .V4_dig(V4_dig),
        .I_dig(I_dig), .T_dig(T_dig),
        .I2C_SCL(I2C_SCL), .I2C_SDA(I2C_SDA),
        .CHG_EN(CHG_EN), .DSCHG_EN(DSCHG_EN),
        .OV_FLG(OV_FLG), .UV_FLG(UV_FLG),
        .OT_FLG(OT_FLG), .LK_FLG(LK_FLG),
        .bal_cmd_out(bal_cmd_out),
        .BAL_FLG(BAL_FLG),
        .SOC_DATA_OUT(SOC_DATA_OUT),
        .Estado_atual(Estado_atual)
    );

    // --------------------------------------------------------
    // 2b. Instanciação do modelo de bateria reativo
    //     Fecha a malha: consome CHG_EN/DSCHG_EN/bal_cmd_out do dut e
    //     devolve V1..V4_dig/I_dig/T_dig/I_DIR para o dut.
    // --------------------------------------------------------
    bms_battery_model u_bat (
        .sys_clk(sys_clk), .sys_rst(sys_rst),
        .Estado_atual(Estado_atual),
        .CHG_EN(CHG_EN), .DSCHG_EN(DSCHG_EN), .bal_cmd_out(bal_cmd_out),
        .charger_present(charger_present), .load_present(load_present),
        .ext_I_bias(ext_I_bias), .ext_T_bias(ext_T_bias),
        .preset_en(preset_en),
        .preset_V1(preset_V1), .preset_V2(preset_V2),
        .preset_V3(preset_V3), .preset_V4(preset_V4),
        .preset_I(preset_I), .preset_T(preset_T),
        .preset_I_DIR(preset_I_DIR),
        .V1_dig(V1_dig), .V2_dig(V2_dig), .V3_dig(V3_dig), .V4_dig(V4_dig),
        .I_dig(I_dig), .T_dig(T_dig), .I_DIR(I_DIR),
        .charging_now(charging_now), .discharging_now(discharging_now)
    );

    // --------------------------------------------------------
    // 3. Clock: período 10 ns (100 MHz)
    // --------------------------------------------------------
    initial begin
        sys_clk = 0;
        forever #5 sys_clk = ~sys_clk;
    end

    initial begin
        $dumpfile("tb_bms_reativo.vcd");
        $dumpvars(0, tb_bms_reativo);
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

     task i2c_delay;
        begin
            #20;
        end
    endtask

    task i2c_start;
        begin
            i2c_sda_master_drive_low = 1'b0;
            I2C_SCL = 1'b1;
            i2c_delay;
            i2c_sda_master_drive_low = 1'b1;
            i2c_delay;
            I2C_SCL = 1'b0;
            i2c_delay;
        end
    endtask

    task i2c_stop;
        begin
            i2c_sda_master_drive_low = 1'b1;
            I2C_SCL = 1'b0;
            i2c_delay;
            I2C_SCL = 1'b1;
            i2c_delay;
            i2c_sda_master_drive_low = 1'b0;
            i2c_delay;
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
                I2C_SCL = 1'b1;
                i2c_delay;
            end

            I2C_SCL = 1'b0;
            i2c_sda_master_drive_low = 1'b0;
            i2c_delay;
            I2C_SCL = 1'b1;
            i2c_delay;
            I2C_SCL = 1'b0;
            i2c_delay;
        end
    endtask

    task i2c_write_config;
        input [7:0] reg_addr;
        input [9:0] value;
        begin
            i2c_start;
            i2c_write_byte(8'h84); // endereco 7'h42 + escrita
            i2c_write_byte(reg_addr);
            i2c_write_byte({6'd0, value[9:8]});
            i2c_write_byte(value[7:0]);
            i2c_stop;
            #100;
        end
    endtask

    // --------------------------------------------------------
    // 4b. Helper: verifica relação numérica (para o SOC)
    //     modo 0 = espera valor MENOR que ref  (descarga)
    //     modo 1 = espera valor MAIOR  que ref  (carga)
    // --------------------------------------------------------
    task check_relacao;
        input [200:0] nome;
        input [9:0]   valor;
        input [9:0]   ref_val;
        input         modo;      // 0 = menor, 1 = maior
        begin
            if ((modo == 1'b0 && valor < ref_val) ||
                (modo == 1'b1 && valor > ref_val))
                $display("    [OK]    %0s  (ref=%0d  obtido=%0d)", nome, ref_val, valor);
            else
                $display("    [FALHA] %0s  (ref=%0d  obtido=%0d)", nome, ref_val, valor);
        end
    endtask

    // --------------------------------------------------------
    // 4c. Helper: espera N varreduras completas da FSM.
    //     Uma varredura termina em ST_CALC_BAL_SOC (Estado_atual=111),
    //     que é exatamente o instante em que o SOC é amostrado E a
    //     bateria reativa atualiza V/I/T. Aqui esperamos entrar nesse
    //     estado e avançamos mais uma borda para ler os valores já
    //     atualizados.
    // --------------------------------------------------------
    task espera_varreduras;
        input integer n;
        integer k;
        begin
            for (k = 0; k < n; k = k + 1) begin
                while (Estado_atual !== 3'b111) begin
                    @(posedge sys_clk); #1;
                end
                @(posedge sys_clk); #1;
            end
        end
    endtask

    // Mantido por compatibilidade de nome com a versão anterior do TB
    task espera_amostras_soc;
        input integer n;
        begin
            espera_varreduras(n);
        end
    endtask

    // --------------------------------------------------------
    // 4d. Helper: impõe um cenário determinístico na bateria.
    //     Sobrescreve V1..V4/I/T/I_DIR instantaneamente por 1 pulso de
    //     clock — usado pelos testes de falha, balanceamento e SOC, que
    //     precisam de valores exatos e repetíveis.
    // --------------------------------------------------------
    task preset_bateria;
        input [9:0] v1, v2, v3, v4;
        input [9:0] ii, tt;
        input       dir;
        begin
            preset_V1 = v1; preset_V2 = v2; preset_V3 = v3; preset_V4 = v4;
            preset_I  = ii; preset_T  = tt; preset_I_DIR = dir;
            preset_en = 1'b1;
            @(posedge sys_clk); #1;
            preset_en = 1'b0;
        end
    endtask

    // --------------------------------------------------------
    // 5. Helper: limpa o sistema entre testes
    //    IMPORTANTE: o reset agora também zera o modelo de bateria (que
    //    volta ao seu ponto de fábrica levemente desbalanceado). Por
    //    isso, logo depois do reset, impomos a condição segura e
    //    uniforme (380/380/380/380, I=50, T=35) usada como baseline dos
    //    testes determinísticos — exatamente os mesmos valores da
    //    versão anterior do testbench.
    // --------------------------------------------------------
    task limpa_e_aguarda;
        begin
            sys_rst = 1;
            #30;           // segura reset por 3 ciclos (assincrono, garante limpeza)
            sys_rst = 0;
            preset_bateria(10'd380, 10'd380, 10'd380, 10'd380, 10'd50, 10'd35, 1'b1);
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
        CHG_PWR_GD      = 1;
        charger_present = 1'b0;
        load_present    = 1'b0;
        ext_I_bias      = 10'd0;
        ext_T_bias      = 10'd0;
        preset_en       = 1'b0;
        preset_V1 = 10'd0; preset_V2 = 10'd0; preset_V3 = 10'd0; preset_V4 = 10'd0;
        preset_I  = 10'd0; preset_T  = 10'd0; preset_I_DIR = 1'b1;
        I2C_SCL = 1'b1;
        i2c_sda_master_drive_low = 1'b0;

        sys_rst = 1; #30; sys_rst = 0;
        preset_bateria(10'd380, 10'd380, 10'd380, 10'd380, 10'd50, 10'd35, 1'b1);
        $display("[INIT] Reset liberado. Aguardando FSM estabilizar...");
        #300;

         // ====================================================
        // CONFIGURACAO VIA I2C
        //
        // O usuario/microcontrolador IoT grava os limites na ROM
        // configuravel antes da operacao normal do BMS.
        // Mapa:
        //   0x00 sobretensao, 0x01 subtensao, 0x02 corrente maxima,
        //   0x03 corrente minima, 0x04 temperatura maxima, 0x05 capacidade
        // ====================================================
        $display("");
        $display("--- CONFIGURACAO VIA I2C DOS LIMITES DA ROM ---");
        i2c_write_config(8'h00, 10'd420);
        i2c_write_config(8'h01, 10'd300);
        i2c_write_config(8'h02, 10'd80);
        i2c_write_config(8'h03, 10'd5);
        i2c_write_config(8'h04, 10'd60);
        i2c_write_config(8'h05, 10'd500);
        $display("  Limites gravados via I2C: OV=420 UV=300 Imax=80 Imin=5 Tmax=60 Cap=500");
        check("I2C gravou limite de sobretensao",    (dut.u_rom.lim_sobrecarga == 10'd420),    1'b1);
        check("I2C gravou limite de subtensao",      (dut.u_rom.lim_sobredescarga == 10'd300), 1'b1);
        check("I2C gravou corrente maxima",          (dut.u_rom.lim_corrente_max == 10'd80),   1'b1);
        check("I2C gravou corrente minima",          (dut.u_rom.lim_corrente_min == 10'd5),    1'b1);
        check("I2C gravou temperatura maxima",       (dut.u_rom.lim_temp == 10'd60),           1'b1);
        check("I2C gravou capacidade nominal",       (dut.u_rom.capacidade_nom == 10'd500),    1'b1);


        // ====================================================
        // TESTE 1 — SOBRETENSÃO (OV_FLG)
        //   Condição: V > 420  →  OV_FLG=1, CHG_EN=0
        //
        //   A sobretensão é analisada em fms=010
        //
        //   Sequência:
        //     a) Impõe Vx via preset_bateria acima do limite
        //     b) Aguarda FSM: ST_READ_SENSORS captura → ST_CHECK_OV compara → flag sobe
        //     c) Verifica
        //     d) Limpa (reset + preset seguro + aguarda)
        // ====================================================
        $display("");
        $display("--- TESTE 1: SOBRETENSAO (OV_FLG) — limite = 420 ---");

        $display("  [1a] V1=430 (demais=380)");
        preset_bateria(10'd430, 10'd380, 10'd380, 10'd380, 10'd50, 10'd35, 1'b1);
        #300;
        check("OV_FLG ativado",   OV_FLG, 1'b1);
        check("CHG_EN desligado", CHG_EN, 1'b0);
        limpa_e_aguarda;

        $display("  [1b] V2=430 (demais=380)");
        preset_bateria(10'd380, 10'd430, 10'd380, 10'd380, 10'd50, 10'd35, 1'b1);
        #300;
        check("OV_FLG ativado",   OV_FLG, 1'b1);
        check("CHG_EN desligado", CHG_EN, 1'b0);
        limpa_e_aguarda;

        $display("  [1c] V3=430 (demais=380)");
        preset_bateria(10'd380, 10'd380, 10'd430, 10'd380, 10'd50, 10'd35, 1'b1);
        #300;
        check("OV_FLG ativado",   OV_FLG, 1'b1);
        check("CHG_EN desligado", CHG_EN, 1'b0);
        limpa_e_aguarda;

        $display("  [1d] V4=430 (demais=380)");
        preset_bateria(10'd380, 10'd380, 10'd380, 10'd430, 10'd50, 10'd35, 1'b1);
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
        preset_bateria(10'd250, 10'd380, 10'd380, 10'd380, 10'd50, 10'd35, 1'b1);
        #300;
        check("UV_FLG ativado",    UV_FLG,   1'b1);
        check("DSCHG_EN desligado",DSCHG_EN, 1'b0);
        limpa_e_aguarda;

        $display("  [2b] V2=250 (demais=380)");
        preset_bateria(10'd380, 10'd250, 10'd380, 10'd380, 10'd50, 10'd35, 1'b1);
        #300;
        check("UV_FLG ativado",    UV_FLG,   1'b1);
        check("DSCHG_EN desligado",DSCHG_EN, 1'b0);
        limpa_e_aguarda;

        $display("  [2c] V3=250 (demais=380)");
        preset_bateria(10'd380, 10'd380, 10'd250, 10'd380, 10'd50, 10'd35, 1'b1);
        #300;
        check("UV_FLG ativado",    UV_FLG,   1'b1);
        check("DSCHG_EN desligado",DSCHG_EN, 1'b0);
        limpa_e_aguarda;

        $display("  [2d] V4=250 (demais=380)");
        preset_bateria(10'd380, 10'd380, 10'd380, 10'd250, 10'd50, 10'd35, 1'b1);
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
        preset_bateria(10'd380, 10'd380, 10'd380, 10'd380, 10'd50, 10'd75, 1'b1);
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
        preset_bateria(10'd380, 10'd380, 10'd380, 10'd380, 10'd100, 10'd35, 1'b1);
        #300;
        check("LK_FLG ativado",   LK_FLG, 1'b1);
        check("CHG_EN desligado", CHG_EN, 1'b0);
        limpa_e_aguarda;

        // ====================================================
        // TESTE 5 — BALANCEAMENTO (bal_cmd_out / BAL_FLG), fms=111
        //
        //   Cálculo é feito dentro de bms_control_balanceamento:
        //     bal_cmd_calc[x] = (Vx_reg > v_min + BAL_DELTA)   BAL_DELTA = 10
        //     v_min           = menor tensão entre as 4 células
        //
        //   A ULA só sinaliza verifica_bal_flg = 1 enquanto a FSM está
        //   em ST_CALC_BAL (via Opcode_ula = BAL). bms_control_balanceamento
        //   registra o novo bal_cmd_calc no primeiro posedge em que
        //   verifica_bal_flg estiver em 1 — ou seja, na borda em que a
        //   FSM sai de ST_CALC_BAL. Por isso esperamos a FSM ENTRAR em
        //   ST_CALC_BAL e depois aguardamos mais um ciclo de clock para
        //   ler o resultado já registrado em BAL_EN_x / BAL_FLG.
        //
        //   Cenário:
        //     V1 = 380  (menor → v_min = 380, nao balanceia)
        //     V2 = 395  (395 > 380+10=390 → deve balancear)
        //     V3 = 385  (385 > 390? NAO   → nao balanceia)
        //     V4 = 400  (400 > 390? SIM   → deve balancear)
        // ====================================================
        $display("");
        $display("--- TESTE 5: BALANCEAMENTO (bal_cmd_out / BAL_FLG) ---");
        $display("  V1=380 (v_min), V2=395, V3=385, V4=400");
        $display("  Limiar = v_min + BAL_DELTA = 380 + 10 = 390");
        $display("  Esperado: BAL_EN_1=0  BAL_EN_2=1  BAL_EN_3=0  BAL_EN_4=1  BAL_FLG=1");

        preset_bateria(10'd380, 10'd395, 10'd385, 10'd400, 10'd50, 10'd35, 1'b1);

        // Aguarda a FSM passar por ST_READ_SENSORS (recarrega V1_reg..V4_reg
        // com os novos valores de V_dig) e DEPOIS entrar em ST_CALC_BAL.
        //
        // IMPORTANTE: Estado_atual é atualizado dentro da FSM com atribuição
        // não-bloqueante (<=) no mesmo posedge que este testbench espera.
        // Por isso, depois de cada @(posedge sys_clk), aguardamos #1 antes
        // de ler Estado_atual — garante que a atualização NBA já foi
        // aplicada, independente da ordem de escalonamento do simulador
        // (isso evita uma race condition que pode variar entre simuladores).
        begin : wait_read_sensors
            forever begin
                @(posedge sys_clk);
                #1;
                if (Estado_atual == 3'b001) disable wait_read_sensors;
            end
        end
        begin : wait_calc_bal
            forever begin
                @(posedge sys_clk);
                #1;
                if (Estado_atual == 3'b111) disable wait_calc_bal;
            end
        end

        // bms_control_balanceamento registra o resultado na borda em que
        // a FSM sai de ST_CALC_BAL: aguarda mais um ciclo de clock (+ #1
        // pelo mesmo motivo acima, para ler o valor já registrado).
        @(posedge sys_clk);
        #1;
        check("BAL_EN_1=0 (V1=380 e v_min, nao balanceia)", bal_cmd_out[0], 1'b0);
        check("BAL_EN_2=1 (V2=395 > 390, balanceia)",       bal_cmd_out[1], 1'b1);
        check("BAL_EN_3=0 (V3=385 < 390, nao balanceia)",   bal_cmd_out[2], 1'b0);
        check("BAL_EN_4=1 (V4=400 > 390, balanceia)",       bal_cmd_out[3], 1'b1);
        check("BAL_FLG=1 (ao menos uma célula precisa balancear)", BAL_FLG, 1'b1);
        limpa_e_aguarda;

        // ====================================================
        // TESTE 6 — SOC: DESCARGA e CARGA (fms=111 = ST_CALC_BAL_SOC)
        //
        //   O SOC é amostrado no estado ST_CALC_BAL_SOC (uma vez por
        //   varredura da FSM). Com capacidade_nom=500 e SOC_FULL_SCALE=1000:
        //       delta_soc = I_reg * 1 * 1000 / 500 = I_reg * 2
        //
        //   I_DIR = 0  → descarrega (SOC diminui)
        //   I_DIR = 1  → carrega    (SOC aumenta)
        //
        //   Aqui I_DIR é imposto diretamente via preset_bateria — é a
        //   direção usada pelo bms_soc_coulomb para a contagem de
        //   coulombs, independente de haver carregador/carga fisicamente
        //   plugados (charger_present/load_present continuam em 0 neste
        //   teste, propositalmente, para isolar o cálculo do SOC).
        //
        //   No reset o SOC parte de 1000 (100%).
        //   Usamos I = 40  → delta = 80 por amostragem.
        // ====================================================
        $display("");
        $display("--- TESTE 6: SOC (DESCARGA e CARGA) ---");

        // ---- 6a. DESCARGA ----
        // Reset limpo → SOC volta a 1000 e a bateria volta ao ponto de
        // fabrica; em seguida impomos entradas seguras e I_DIR=0.
        sys_rst = 1; #30; sys_rst = 0;
        preset_bateria(10'd380, 10'd380, 10'd380, 10'd380, 10'd40, 10'd35, 1'b0);
        $display("  [6a] DESCARGA: I_DIR=0, I=40 (delta=80/amostra), SOC inicial=1000");
        soc_antes = 10'd1000;

        // Aguarda 3 amostragens de SOC (3 varreduras)
        espera_amostras_soc(3);
        $display("        SOC apos 3 amostras = %0d (esperado ~= 1000 - 3*80 = 760)", SOC_DATA_OUT);
        check_relacao("SOC diminuiu (descarga)", SOC_DATA_OUT, soc_antes, 1'b0);
        check("DSCHG_EN habilitado (sem UV)",   DSCHG_EN, 1'b1);

        // ---- 6b. CARGA ----
        // Sem reset (continua do SOC descarregado), agora I_DIR = 1.
        soc_antes = SOC_DATA_OUT;   // SOC atual antes de carregar
        preset_bateria(10'd380, 10'd380, 10'd380, 10'd380, 10'd40, 10'd35, 1'b1);
        $display("  [6b] CARGA: I_DIR=1, I=40 (delta=+80/amostra), SOC antes=%0d", soc_antes);

        espera_amostras_soc(2);
        $display("        SOC apos 2 amostras = %0d (esperado ~= %0d + 2*80)", SOC_DATA_OUT, soc_antes);
        check_relacao("SOC aumentou (carga)", SOC_DATA_OUT, soc_antes, 1'b1);
        check("CHG_EN habilitado (fonte ok, sem OV)", CHG_EN, 1'b1);

        limpa_e_aguarda;

        // ====================================================
        // TESTE 7 — OPERACAO REATIVA EM MALHA FECHADA (sem preset)
        //
        //   A partir daqui NENHUM valor de V/I/T é imposto. O testbench
        //   só "pluga" um carregador ou uma carga fisicamente
        //   (charger_present/load_present) e deixa o bms_battery_model
        //   reagir sozinho ao que o bms_top decide (CHG_EN/DSCHG_EN/
        //   bal_cmd_out) — inclusive cortando a carga/descarga sozinho
        //   ao violar os limites, e acionando o balanceamento sozinho
        //   por causa do desbalanco natural de fábrica do pack
        //   (V1=380 V2=376 V3=382 V4=370, parâmetros do
        //   bms_battery_model).
        // ====================================================
        $display("");
        $display("--- TESTE 7: OPERACAO REATIVA EM MALHA FECHADA (sem preset) ---");

        sys_rst = 1; #30; sys_rst = 0;
        CHG_PWR_GD = 1'b1;

        $display("  [7a] Conectando um carregador (charger_present=1)...");
        charger_present = 1'b1;
        load_present    = 1'b0;

        // Deixa a bateria carregar sozinha por ~30 varreduras (30*100ns).
        // Dependendo dos parametros do modelo, a tensao e a temperatura
        // sobem juntas — quem estoura o limite primeiro (OV ou OT) pode
        // variar, e isso é o ponto: o BMS reage a QUALQUER uma das duas,
        // sem precisar saber de antemao qual vai disparar.
        //
        // IMPORTANTE: usamos um atraso de TEMPO fixo (#3000), não
        // espera_varreduras — porque ST_FAULT é um estado absorvente
        // (a FSM nunca mais volta a ST_CALC_BAL_SOC depois de entrar
        // nele). Se usássemos espera_varreduras aqui, o testbench
        // travaria esperando para sempre por uma varredura que nunca
        // mais vai se completar assim que uma proteção disparar.
        #3000;
        $display("        Apos ~30 varreduras: V1=%0d V2=%0d V3=%0d V4=%0d T=%0d I=%0d | OV=%b OT=%b | permissao(CHG_EN=%b) atividade_real(chg=%b) | BAL_FLG=%b bal=%b",
                  V1_dig, V2_dig, V3_dig, V4_dig, T_dig, I_dig, OV_FLG, OT_FLG, CHG_EN, charging_now, BAL_FLG, bal_cmd_out);
        check("Alguma protecao ativou sozinha durante a carga reativa (OV ou OT)", (OV_FLG || OT_FLG), 1'b1);
        check("CHG_EN (permissao) cortado automaticamente pela protecao",         CHG_EN, 1'b0);
        check("Atividade real de carga parou junto com a protecao",              charging_now, 1'b0);

        $display("  [7b] Desconectando o carregador e conectando uma carga (descarga reativa)...");
        sys_rst = 1; #30; sys_rst = 0;
        charger_present = 1'b0;
        load_present    = 1'b1;

        #3000; // idem: tempo fixo, nao espera_varreduras (evita travar em FAULT)
        $display("        Apos ~30 varreduras: V1=%0d V2=%0d V3=%0d V4=%0d T=%0d I=%0d | UV=%b OT=%b | permissao(DSCHG_EN=%b) atividade_real(dschg=%b)",
                  V1_dig, V2_dig, V3_dig, V4_dig, T_dig, I_dig, UV_FLG, OT_FLG, DSCHG_EN, discharging_now);
        check("Alguma protecao ativou sozinha durante a descarga reativa (UV ou OT)", (UV_FLG || OT_FLG), 1'b1);
        check("DSCHG_EN (permissao) cortado automaticamente pela protecao",           DSCHG_EN, 1'b0);
        check("Atividade real de descarga parou junto com a protecao",                discharging_now, 1'b0);

        charger_present = 1'b0;
        load_present    = 1'b0;
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
        $monitor("t=%0t | FSM=%b | V1=%0d V2=%0d V3=%0d V4=%0d | T=%0d I=%0d I_DIR=%b | OV=%b UV=%b OT=%b LK=%b | permissao(CHG=%b DSCHG=%b) atividade_real(chg=%b dschg=%b) | BAL_FLG=%b BAL=%b | SOC=%0d",
                 $time, Estado_atual,
                 V1_dig, V2_dig, V3_dig, V4_dig,
                 T_dig, I_dig, I_DIR,
                 OV_FLG, UV_FLG, OT_FLG, LK_FLG,
                 CHG_EN, DSCHG_EN, charging_now, discharging_now,
                 BAL_FLG, bal_cmd_out,
                 SOC_DATA_OUT);
    end

endmodule
