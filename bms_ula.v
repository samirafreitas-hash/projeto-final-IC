//Módulo ULA: Unidade Lógica e Aritmética
//Ela é responsável por executar operações matemáticas e lógicas sobre os dados.

//Pega os dados do mux A e B e faz operações como comparação
module bms_ula (
    input wire [9:0] dado_A,
    input wire [9:0] dado_B,
    input wire [2:0] Opcode_ula,

    output reg [9:0] resultado_ula,
    output reg cmp_true,

    // Flag que apenas indica que a FSM está no momento de verificar
    // o balanceamento das células. Não faz nenhum cálculo de
    // balanceamento aqui — isso é responsabilidade do módulo
    // bms_control_balanceamento.
    output reg verify_bal_flg
);

    localparam ADD = 3'b000;
    localparam SUB = 3'b001;
    localparam CMP = 3'b010; // cmp_true = A > B
    localparam PAS = 3'b011;
    localparam CLT = 3'b100; // cmp_true = A < B
    localparam BAL = 3'b101; // apenas sinaliza verifica_bal_flg = 1

    reg [10:0] temp_result;

    always @(*) begin
        resultado_ula    = 10'd0;
        cmp_true         = 1'b0;
        verify_bal_flg = 1'b0;
        temp_result      = 11'd0;

        case (Opcode_ula)
            ADD: begin
                temp_result   = {1'b0, dado_A} + {1'b0, dado_B};
                resultado_ula = temp_result[9:0];
            end

            SUB: begin
                if (dado_A < dado_B) begin
                    resultado_ula = 10'd0;
                end else begin
                    resultado_ula = dado_A - dado_B;
                end
            end

            CMP: begin
                cmp_true = (dado_A > dado_B);
            end

            PAS: begin
                resultado_ula = dado_A;
            end

            CLT: begin
                cmp_true = (dado_A < dado_B);
            end

            BAL: begin
                // Apenas sinaliza pra fora que é hora de verificar o
                // balanceamento. O cálculo em si (v_min, comparação com
                // BAL_DELTA, etc.) é feito dentro de bms_control_balanceamento.
                verify_bal_flg = 1'b1;
            end

            default: begin
                resultado_ula = 10'd0;
            end
        endcase
    end
endmodule