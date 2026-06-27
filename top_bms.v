module bms_top (

    // Entradas

    //Clock e reset
    input wire sys_clk,
    input wire sys_rst,

    //CHG_PWR_GD: indica que a fonte/carga está pronta/ok para carregar
    input wire CHG_PWR_GD,

    // Controla a variação do SOC
    // se 1 -> diminui o soc, se 0 -> aumenta o soc
    input wire I_DIR,

    //Voltagem das 4 células, corrente, temperatura (todas em formato digital, 10 bits)
    input wire [9:0] V1_dig,
    input wire [9:0] V2_dig,
    input wire [9:0] V3_dig,
    input wire [9:0] V4_dig,
    input wire [9:0] I_dig,
    input wire [9:0] T_dig,

    // Saídas

    //Sinal de habilitação para carga e descarga
    output wire CHG_EN, //habilita carga
    output wire DSCHG_EN, //habilita descarga

    // Flags de falhas: sobrecarga, sobredescarga, sobretemperatura e sobrecorrente
    output wire OV_FLG,
    output wire UV_FLG,
    output wire OT_FLG,
    output wire LK_FLG,

    // Comando de balanceamento para cada célula (4 bits, um para cada célula)
    output wire [3:0] bal_cmd_out,

    // Valor do SOC em formato digital (10 bits)
    output wire [9:0] SOC_DATA_OUT, 

    // Estado atual da FSM (3 bits)
    output wire [2:0] Estado_atual 
);

    //Fios Internos 

    wire [9:0] V1_reg, V2_reg, V3_reg, V4_reg, I_reg, T_reg;

    wire load_V, load_I, load_T, sample_soc;
    wire atualiza_falhas;
    wire [1:0] tipo_falha_sel;
    wire [2:0] mux_A_sel;
    wire [2:0] mux_B_sel;
    wire [2:0] Opcode_ula;
   // wire [7:0] Endereco_ROM;
    wire [3:0] bal_cmd;

    wire [9:0] SOC_atual;
    wire [9:0] dado_A, dado_B;
    wire [9:0] resultado_ula;
    wire [15:0] instrucao_dados;

    wire [9:0] lim_sobrecarga;
    wire [9:0] lim_sobredescarga;
    wire [9:0] lim_temp;
    wire [9:0] lim_corrente_fuga;
    wire [9:0] capacidade_nom;
    wire read_en = 1'b1;

    wire cmp_true;

    wire BAL_EN_1, BAL_EN_2, BAL_EN_3, BAL_EN_4;
    assign bal_cmd_out = {BAL_EN_4, BAL_EN_3, BAL_EN_2, BAL_EN_1};

    //Módulo Registradores de Entrada:

    //É responsável por armazenar as leituras digitais dos sensores de tensão, corrente e temperatura em registradores internos, 
    //controlados por sinais de uma FSM.
    //É o primeiro mod do sistema
    bms_regs_entrada u_regs_in (
        //clock e rst
        .clk(sys_clk), .rst(sys_rst),
        //Entradas: tensão das células, corrente e temperatura
        .V1_dig(V1_dig), .V2_dig(V2_dig), .V3_dig(V3_dig),
        .V4_dig(V4_dig), .I_dig(I_dig), .T_dig(T_dig),
        //Saídas: sinais de controle para carregar os registradores e os próprios registradores
        .load_V(load_V),.load_I(load_I),.load_T(load_T),
        .V1_reg(V1_reg),.V2_reg(V2_reg),.V3_reg(V3_reg),.V4_reg(V4_reg),
        .I_reg(I_reg),.T_reg(T_reg)
    );

    //Módulo ROM: 
    //para armazenar os limites de operação do BMS (DADOS FIXOS)
    bms_rom u_rom (
        .clk(sys_clk),.read_en(read_en),
       // .endereco_ROM(Endereco_ROM),
        .lim_sobrecarga(lim_sobrecarga), .lim_sobredescarga(lim_sobredescarga),.lim_temp(lim_temp),
        .lim_corrente_fuga(lim_corrente_fuga),.capacidade_nom(capacidade_nom)
       // .data_out(instrucao_dados)
    );

    //Módulo Mutiplexador A:
    //Seleciona qual dado vai para a ULA (tensão, corrente ou temperatura)
    bms_mux_A u_mux_A (
        //Tensões vindas dos registradores de entrada
        .V1_reg(V1_reg),.V2_reg(V2_reg),.V3_reg(V3_reg),.V4_reg(V4_reg),
        //Corrente e temperatura vindas dos registradores de entrada
        .I_reg(I_reg),.T_reg(T_reg),
        //Seleção do dado
        .mux_sel(mux_A_sel),
        //Dado de saída
        .dado_A(dado_A)
    );

    //Módulo Mutiplexador B:
    //Seleciona qual dado vai para a ULA (limites de operação do BMS)
    bms_mux_B u_mux_B (
        //Dados fixos
        .lim_sobrecarga(lim_sobrecarga),.lim_sobredescarga(lim_sobredescarga),
        .lim_temp(lim_temp),.lim_corrente_fuga(lim_corrente_fuga),.capacidade_nom(capacidade_nom),
        //Seleção do dado
        .mux_B_sel(mux_B_sel),
        //Dado de saída
        .dado_B(dado_B)
    );

    //Módulo ULA: Unidade Lógica e Aritmética
    //Faz a operação com os dados selecionados pelo mux A e B
    bms_ula u_ula (
        //Dado selecionado do Mux A
        .dado_A(dado_A),
        //Dado selecionado do Mux B
        .dado_B(dado_B),
        //Seleciona qual operação deve ser feita com os dois dados
        .Opcode_ula(Opcode_ula),
        //Resultado da saída
        .resultado_ula(resultado_ula),
        //Diz se a comparação entre os dois dados é verdadeira ou falsa (A > B ou A < B)
        .cmp_true(cmp_true)
    );

    //Módulo de registro de status do BMS
    //Armazena o status do BMS, incluindo flags de falha e atualiza o status com base nas comparações feitas pela ULA
    bms_reg_status u_reg_status (
        //clock e rst
        .sys_clk(sys_clk), .sys_rst(sys_rst),
        //saída da ULA
        .cmp_true(cmp_true),
        //Para habilitar se pode atualizar as falhas
        .atualiza_falhas(atualiza_falhas),
        //Diz qual falha vai ser atualizada
        .tipo_falha_sel(tipo_falha_sel),
        //Flags de falha armazenadas
        .OV_FLG(OV_FLG), //sobrecarga
        .UV_FLG(UV_FLG), //sobredescarga
        .OT_FLG(OT_FLG), //sobretemperatura
        .LK_FLG(LK_FLG)  //sobrecorrente
    );

    //Módulo de Calculo do SOC (State of Charge) do BMS
    bms_soc_coulomb u_soc (
        .sys_clk(sys_clk),.sys_rst(sys_rst),
        .sample_tick(sample_soc),
        .I_DIR(I_DIR),
        .I_reg(I_reg),
        .capacidade_nom(capacidade_nom),
        .SOC_DATA_OUT(SOC_DATA_OUT),
        .SOC_atual(SOC_atual)
    );

    bms_control_potencia u_ctrl_pot (
        .Estado_atual(Estado_atual),
        .CHG_PWR_GD(CHG_PWR_GD),
        .OV_FLG(OV_FLG),
        .UV_FLG(UV_FLG),
        .OT_FLG(OT_FLG),
        .LK_FLG(LK_FLG),
        .CHG_EN(CHG_EN),
        .DSCHG_EN(DSCHG_EN)
    );

    bms_control_balanceamento u_ctrl_bal (
        .sys_clk(sys_clk),
        .sys_rst(sys_rst),
        .bal_cmd(bal_cmd),
        .BAL_EN_1(BAL_EN_1),
        .BAL_EN_2(BAL_EN_2),
        .BAL_EN_3(BAL_EN_3),
        .BAL_EN_4(BAL_EN_4)
    );

    bms_fsm u_fsm (
        .sys_clk(sys_clk),
        .sys_rst(sys_rst),
        .I_DIR(I_DIR),
        .OV_FLG(OV_FLG),
        .UV_FLG(UV_FLG),
        .OT_FLG(OT_FLG),
        .LK_FLG(LK_FLG),
        .V1_reg(V1_reg),
        .V2_reg(V2_reg),
        .V3_reg(V3_reg),
        .V4_reg(V4_reg),
        //.Endereco_ROM(Endereco_ROM),
        .load_V(load_V),
        .load_I(load_I),
        .load_T(load_T),
        .sample_soc(sample_soc),
        .atualiza_falhas(atualiza_falhas),
        .tipo_falha_sel(tipo_falha_sel),
        .mux_A_sel(mux_A_sel),
        .mux_B_sel(mux_B_sel),
        .Opcode_ula(Opcode_ula),
        .bal_cmd(bal_cmd),
        .Estado_atual(Estado_atual)
    );
endmodule
