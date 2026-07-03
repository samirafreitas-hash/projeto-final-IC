module bms_fsm (
    input wire sys_clk,
    input wire sys_rst,
    input wire I_DIR,

    input wire OV_FLG,
    input wire UV_FLG,
    input wire OT_FLG,
    input wire LK_FLG,

   // output reg [7:0] Endereco_ROM,
    output reg load_V,
    output reg load_I,
    output reg load_T,
    output reg sample_soc,
    output reg atualiza_falhas,
    output reg [1:0] tipo_falha_sel,

    output reg [2:0] mux_A_sel,
    output reg [2:0] mux_B_sel,
    output reg [2:0] Opcode_ula,

    output reg [2:0] Estado_atual
);

    localparam ST_INIT         = 3'b000;
    localparam ST_READ_SENSORS = 3'b001;
    localparam ST_CHECK_OV     = 3'b010;
    localparam ST_CHECK_UV     = 3'b011;
    localparam ST_CHECK_OT     = 3'b100;
    localparam ST_FAULT        = 3'b101;
    localparam ST_CHECK_LK     = 3'b110;
    localparam ST_CALC_BAL_SOC    = 3'b111;

    //localparam ADD = 3'b000;
    //localparam SUB = 3'b001;
    localparam CMP = 3'b010;
    //localparam PAS = 3'b011;
    localparam CLT = 3'b100;
    localparam BAL = 3'b101; // pede pra ULA sinalizar "hora de verificar balanceamento"

    reg [2:0] state_next;
    reg [1:0] cell_index;
    reg [1:0] cell_index_next;

    always @(posedge sys_clk or posedge sys_rst) begin
        if (sys_rst) begin
            Estado_atual <= ST_INIT;
            cell_index   <= 2'd0;
        end else begin
            Estado_atual <= state_next;
            cell_index   <= cell_index_next;
        end
    end

    always @(*) begin
        state_next      = Estado_atual;
        cell_index_next = cell_index;

        if (OT_FLG || LK_FLG || OV_FLG || UV_FLG) begin
            state_next = ST_FAULT;
        end else begin
            case (Estado_atual)
                ST_INIT: begin
                    state_next = ST_READ_SENSORS;
                end

                ST_READ_SENSORS: begin
                    state_next      = ST_CHECK_OV;
                    cell_index_next = 2'd0;
                end

                ST_CHECK_OV: begin
                    if (cell_index == 2'd3) begin
                        state_next      = ST_CHECK_UV;
                        cell_index_next = 2'd0;
                    end else begin
                        cell_index_next = cell_index + 1'b1;
                    end
                end

                ST_CHECK_UV: begin
                    if (cell_index == 2'd3) begin
                        state_next = ST_CHECK_OT;
                    end else begin
                        cell_index_next = cell_index + 1'b1;
                    end
                end

                ST_CHECK_OT: begin
                    state_next = ST_CHECK_LK;
                end

                ST_CHECK_LK: begin
                    state_next = ST_CALC_BAL_SOC;
                end

                ST_CALC_BAL_SOC: begin
                    state_next = ST_READ_SENSORS;
                end

                ST_FAULT: begin
                    state_next = ST_FAULT;
                end

                default: begin
                    state_next = ST_INIT;
                end
            endcase
        end
    end

    always @(*) begin
        //Endereco_ROM    = 8'h00;
        load_V          = 1'b0;
        load_I          = 1'b0;
        load_T          = 1'b0;
        sample_soc      = 1'b0;
        atualiza_falhas = 1'b0;
        tipo_falha_sel  = 2'b00;
        mux_A_sel       = 3'b000;
        mux_B_sel       = 3'b000;
        Opcode_ula      = CMP;

        case (Estado_atual)
            ST_READ_SENSORS: begin
              //  Endereco_ROM = 8'h01;
                load_V = 1'b1;
                load_I = 1'b1;
                load_T = 1'b1;
            end

            ST_CHECK_OV: begin
              //  Endereco_ROM    = {6'd0, cell_index};
                mux_A_sel       = {1'b0, cell_index};
                mux_B_sel       = 3'b000;
                Opcode_ula      = CMP;
                atualiza_falhas = 1'b1;
                tipo_falha_sel  = 2'b00;
            end

            ST_CHECK_UV: begin
                mux_A_sel       = {1'b0, cell_index};
                mux_B_sel       = 3'b001;
                Opcode_ula      = CLT;
                atualiza_falhas = 1'b1;
                tipo_falha_sel  = 2'b01;
            end

            ST_CHECK_OT: begin
                mux_A_sel       = 3'b101;
                mux_B_sel       = 3'b010;
                Opcode_ula      = CMP;
                atualiza_falhas = 1'b1;
                tipo_falha_sel  = 2'b10;
            end

            ST_CHECK_LK: begin
                mux_A_sel       = 3'b100;
                mux_B_sel       = 3'b100;
                Opcode_ula      = CMP;
                atualiza_falhas = 1'b1;
                tipo_falha_sel  = 2'b11;
            end

            ST_CALC_BAL_SOC: begin
                // Este estado faz DUAS coisas:
                //  1) Amostra o SOC (sample_soc = 1) → bms_soc_coulomb
                //     atualiza a carga com base na corrente e direção.
                //  2) Pede pra ULA sinalizar (Opcode_ula = BAL) que é o
                //     momento de verificar o balanceamento. O cálculo
                //     (v_min, comparação com BAL_DELTA, decisão de quais
                //     células balancear) fica em bms_control_balanceamento.
                sample_soc = 1'b1;
                Opcode_ula = BAL;
            end

            ST_FAULT: begin
                // Em falha não há nada a fazer aqui; o módulo de
                // balanceamento mantém o último estado registrado
                // (não recebe verifica_bal_flg = 1 nesse estado).
            end
        endcase
    end
endmodule