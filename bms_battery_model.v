// Modelo comportamental de um pack de 4 células, criado para tornar a
// simulação do BMS REATIVA em vez de passiva: em vez do testbench "empurrar"
// valores fixos de tensão/corrente/temperatura para dentro do bms_top, este
// módulo consome as saídas de atuação do próprio BMS (CHG_EN, DSCHG_EN,
// bal_cmd_out) e atualiza os valores digitais (_dig) de volta para a entrada
// do bms_top — fechando o laço:
//
//        bms_top --CHG_EN / DSCHG_EN / bal_cmd_out--> bms_battery_model
//        bms_battery_model --V1..V4_dig / I_dig / T_dig--> bms_top
//
// O testbench ainda pode impor condições específicas a qualquer momento
// (por exemplo, para reproduzir um caso de falha determinístico) usando o
// pulso preset_en, que sobrescreve os registradores internos instantanea-
// mente. Fora dos pulsos de preset, o modelo evolui sozinho a cada rodada de
// varredura da FSM — no mesmo instante em que o SOC é amostrado
// (Estado_atual == ST_CALC_BAL_SOC) — reagindo ao que o BMS decidiu fazer no
// ciclo anterior.
// ============================================================================

module bms_battery_model #(
    // ---- Condição inicial das 4 células (propositalmente desbalanceada,
    //      para dar trabalho ao bms_control_balanceamento desde o início) ----
    parameter [9:0] V1_INIT = 10'd380,
    parameter [9:0] V2_INIT = 10'd376,
    parameter [9:0] V3_INIT = 10'd382,
    parameter [9:0] V4_INIT = 10'd370,

    // ---- Autodescarga natural de cada célula (mismatch de fabricação) ----
    parameter [9:0] LEAK_1 = 10'd0,
    parameter [9:0] LEAK_2 = 10'd1,
    parameter [9:0] LEAK_3 = 10'd0,
    parameter [9:0] LEAK_4 = 10'd2,

    // ---- Passo de tensão por amostragem ----
    parameter [9:0] CHG_STEP       = 10'd6,  // subida de tensão ao carregar
    parameter [9:0] DSCHG_STEP     = 10'd6,  // queda de tensão ao descarregar
    parameter [9:0] BAL_DRAIN_STEP = 10'd4,  // dreno extra da célula em bypass

    // ---- Corrente simulada (valores propositalmente diferentes para
    //      deixar claro no monitor quando está carregando vs descarregando) ----
    parameter [9:0] I_CHG_BASE   = 10'd80,   // corrente de carga (alta)
    parameter [9:0] I_DSCHG_BASE = 10'd30,   // corrente de descarga (baixa)
    parameter [9:0] I_IDLE       = 10'd2,    // corrente residual (repouso)

    // ---- Modelo térmico simplificado ----
    parameter [9:0] T_AMBIENT   = 10'd25,
    parameter [9:0] T_HEAT_STEP = 10'd4,     // aquece ao carregar/descarregar
    parameter [9:0] T_COOL_STEP = 10'd1,     // esfria quando ocioso

    // ---- Limites de saturação (10 bits) ----
    parameter [9:0] V_MIN = 10'd0,
    parameter [9:0] V_MAX = 10'd1023,
    parameter [9:0] T_MAX = 10'd1023,
    parameter [9:0] I_MAX = 10'd1023
)(
    input  wire        sys_clk,
    input  wire        sys_rst,

    // Estado da FSM do bms_top: usado só para saber quando a FSM está no
    // estado de amostragem (ST_CALC_BAL_SOC = 3'b111), e assim atualizar a
    // bateria exatamente no mesmo ritmo em que o SOC é amostrado
    input  wire [2:0]  Estado_atual,

    // Realimentação vinda do bms_top: o que o BMS PERMITE fazer
    // (CHG_EN/DSCHG_EN são sinais de permissão, não de comando — um BMS
    // real habilita a carga, mas só carrega de fato se houver uma fonte
    // fisicamente conectada)
    input  wire        CHG_EN,
    input  wire        DSCHG_EN,
    input  wire [3:0]  bal_cmd_out,

    // O que está fisicamente plugado no pack agora — só o testbench sabe
    // disso, é o "mundo externo" que ele controla
    input  wire        charger_present,
    input  wire        load_present,

    // Perturbações externas opcionais, somadas à corrente/temperatura
    // "naturais" do modelo — o testbench pode usar isso para simular uma
    // carga externa inesperada ou um evento térmico sem quebrar o laço
    // reativo (ex.: ext_I_bias = 40 simula uma fuga extra de corrente)
    input  wire [9:0]  ext_I_bias,
    input  wire [9:0]  ext_T_bias,

    // Sobrescrita manual e instantânea (uso do testbench para montar um
    // cenário determinístico de teste). Ativa por 1 pulso de clock
    input  wire        preset_en,
    input  wire [9:0]  preset_V1, preset_V2, preset_V3, preset_V4,
    input  wire [9:0]  preset_I,
    input  wire [9:0]  preset_T,
    input  wire        preset_I_DIR,

    // Saídas prontas para alimentar os pinos _dig do bms_top
    output reg [9:0]   V1_dig, V2_dig, V3_dig, V4_dig,
    output reg [9:0]   I_dig,
    output reg [9:0]   T_dig,

    // Direção da corrente já coerente com o que está fisicamente
    // acontecendo (1 = carregando, 0 = descarregando/parado) — ligar
    // direto no I_DIR do bms_top
    output reg         I_DIR,

    // Saídas de depuração: o que está DE FATO acontecendo agora (sempre
    // mutuamente exclusivos, ao contrário de CHG_EN/DSCHG_EN, que são só
    // permissão do BMS e podem estar os dois em 1 simultaneamente).
    // Úteis para o testbench monitorar sem confundir permissão com
    // atividade real.
    output wire        charging_now,
    output wire        discharging_now
);

    localparam [2:0] ST_CALC_BAL_SOC = 3'b111;

    wire tick = (Estado_atual == ST_CALC_BAL_SOC);

    // Carga/descarga só acontecem de verdade se o BMS permite E existe
    // fisicamente uma fonte/carga conectada agora (sempre mutuamente
    // exclusivos, por construção)
    assign charging_now    = CHG_EN   && charger_present;
    assign discharging_now = DSCHG_EN && load_present && !charging_now;

    // Variáveis de trabalho com folga de bits para evitar estouro/underflow
    // antes da saturação final em 10 bits
    integer v1_next, v2_next, v3_next, v4_next;
    integer i_next, t_next;

    function [9:0] clamp10;
        input integer valor;
        input [9:0] minimo;
        input [9:0] maximo;
        begin
            if (valor < $signed({1'b0, minimo}))
                clamp10 = minimo;
            else if (valor > $signed({1'b0, maximo}))
                clamp10 = maximo;
            else
                clamp10 = valor[9:0];
        end
    endfunction

    always @(posedge sys_clk or posedge sys_rst) begin
        if (sys_rst) begin
            V1_dig <= V1_INIT;
            V2_dig <= V2_INIT;
            V3_dig <= V3_INIT;
            V4_dig <= V4_INIT;
            I_dig  <= I_IDLE;
            T_dig  <= T_AMBIENT;
            I_DIR  <= 1'b0;

        end else if (preset_en) begin
            // O testbench está impondo um cenário específico agora
            V1_dig <= preset_V1;
            V2_dig <= preset_V2;
            V3_dig <= preset_V3;
            V4_dig <= preset_V4;
            I_dig  <= preset_I;
            T_dig  <= preset_T;
            I_DIR  <= preset_I_DIR;

        end else if (tick) begin
            // ---- Evolução reativa: reage ao que o bms_top decidiu ----

            // Tensão de cada célula: sobe ao carregar, desce ao descarregar,
            // sempre subtraindo a autodescarga própria da célula, e com
            // dreno extra se aquela célula está em bypass de balanceamento
            v1_next = V1_dig;
            v2_next = V2_dig;
            v3_next = V3_dig;
            v4_next = V4_dig;

            if (charging_now) begin
                v1_next = v1_next + CHG_STEP - LEAK_1;
                v2_next = v2_next + CHG_STEP - LEAK_2;
                v3_next = v3_next + CHG_STEP - LEAK_3;
                v4_next = v4_next + CHG_STEP - LEAK_4;
            end else if (discharging_now) begin
                v1_next = v1_next - DSCHG_STEP - LEAK_1;
                v2_next = v2_next - DSCHG_STEP - LEAK_2;
                v3_next = v3_next - DSCHG_STEP - LEAK_3;
                v4_next = v4_next - DSCHG_STEP - LEAK_4;
            end else begin
                // Ocioso: só a autodescarga natural age
                v1_next = v1_next - LEAK_1;
                v2_next = v2_next - LEAK_2;
                v3_next = v3_next - LEAK_3;
                v4_next = v4_next - LEAK_4;
            end

            // Bypass de balanceamento: dreno adicional na célula sinalizada
            if (bal_cmd_out[0]) v1_next = v1_next - BAL_DRAIN_STEP;
            if (bal_cmd_out[1]) v2_next = v2_next - BAL_DRAIN_STEP;
            if (bal_cmd_out[2]) v3_next = v3_next - BAL_DRAIN_STEP;
            if (bal_cmd_out[3]) v4_next = v4_next - BAL_DRAIN_STEP;

            V1_dig <= clamp10(v1_next, V_MIN, V_MAX);
            V2_dig <= clamp10(v2_next, V_MIN, V_MAX);
            V3_dig <= clamp10(v3_next, V_MIN, V_MAX);
            V4_dig <= clamp10(v4_next, V_MIN, V_MAX);

            // Corrente: reflete o que está de fato acontecendo agora
            if (charging_now)
                i_next = I_CHG_BASE + ext_I_bias;
            else if (discharging_now)
                i_next = I_DSCHG_BASE + ext_I_bias;
            else
                i_next = I_IDLE + ext_I_bias;

            I_dig <= clamp10(i_next, V_MIN, I_MAX);

            // Temperatura: aquece sob carga/descarga, esfria em repouso,
            // sempre tendendo à ambiente + perturbação externa
            if (charging_now || discharging_now)
                t_next = T_dig + T_HEAT_STEP + ext_T_bias;
            else if (T_dig > T_AMBIENT)
                t_next = T_dig - T_COOL_STEP;
            else
                t_next = T_AMBIENT + ext_T_bias;

            T_dig <= clamp10(t_next, V_MIN, T_MAX);

            // I_DIR sempre coerente com o que está fisicamente acontecendo
            I_DIR <= charging_now;
        end
    end

endmodule
