module bms_top (
    input wire sys_clk,
    input wire sys_rst,
    input wire CHG_PWR_GD,
    input wire I_DIR,

    input wire [9:0] V1_dig,
    input wire [9:0] V2_dig,
    input wire [9:0] V3_dig,
    input wire [9:0] V4_dig,
    input wire [9:0] I_dig,
    input wire [9:0] T_dig,

    output wire CHG_EN,
    output wire DSCHG_EN,

    output wire OV_FLG,
    output wire UV_FLG,
    output wire OT_FLG,
    output wire LK_FLG,

    output wire [3:0] bal_cmd_out,

    output wire [9:0] SOC_DATA_OUT,
    output wire [2:0] Estado_atual
);

    wire [9:0] V1_reg, V2_reg, V3_reg, V4_reg, I_reg, T_reg;

    wire load_V, load_I, load_T, sample_soc;
    wire atualiza_falhas;
    wire [1:0] tipo_falha_sel;
    wire [2:0] mux_A_sel;
    wire [2:0] mux_B_sel;
    wire [2:0] Opcode_ula;
    wire [7:0] Endereco_ROM;
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

    bms_regs_entrada u_regs_in (
        .clk(sys_clk),
        .rst(sys_rst),
        .V1_dig(V1_dig),
        .V2_dig(V2_dig),
        .V3_dig(V3_dig),
        .V4_dig(V4_dig),
        .I_dig(I_dig),
        .T_dig(T_dig),
        .load_V(load_V),
        .load_I(load_I),
        .load_T(load_T),
        .V1_reg(V1_reg),
        .V2_reg(V2_reg),
        .V3_reg(V3_reg),
        .V4_reg(V4_reg),
        .I_reg(I_reg),
        .T_reg(T_reg)
    );

    bms_rom u_rom (
        .clk(sys_clk),
        .read_en(read_en),
        .endereco_ROM(Endereco_ROM),
        .lim_sobrecarga(lim_sobrecarga),
        .lim_sobredescarga(lim_sobredescarga),
        .lim_temp(lim_temp),
        .lim_corrente_fuga(lim_corrente_fuga),
        .capacidade_nom(capacidade_nom),
        .data_out(instrucao_dados)
    );

    bms_mux_A u_mux_A (
        .V1_reg(V1_reg),
        .V2_reg(V2_reg),
        .V3_reg(V3_reg),
        .V4_reg(V4_reg),
        .I_reg(I_reg),
        .T_reg(T_reg),
        .mux_sel(mux_A_sel),
        .dado_A(dado_A)
    );

    bms_mux_B u_mux_B (
        .lim_sobrecarga(lim_sobrecarga),
        .lim_sobredescarga(lim_sobredescarga),
        .lim_temp(lim_temp),
        .lim_corrente_fuga(lim_corrente_fuga),
        .capacidade_nom(capacidade_nom),
        .mux_B_sel(mux_B_sel),
        .dado_B(dado_B)
    );

    bms_ula u_ula (
        .dado_A(dado_A),
        .dado_B(dado_B),
        .Opcode_ula(Opcode_ula),
        .resultado_ula(resultado_ula),
        .cmp_true(cmp_true)
    );

    bms_reg_status u_reg_status (
        .sys_clk(sys_clk),
        .sys_rst(sys_rst),
        .cmp_true(cmp_true),
        .atualiza_falhas(atualiza_falhas),
        .tipo_falha_sel(tipo_falha_sel),
        .OV_FLG(OV_FLG),
        .UV_FLG(UV_FLG),
        .OT_FLG(OT_FLG),
        .LK_FLG(LK_FLG)
    );

    bms_soc_coulomb u_soc (
        .sys_clk(sys_clk),
        .sys_rst(sys_rst),
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
        .Endereco_ROM(Endereco_ROM),
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
