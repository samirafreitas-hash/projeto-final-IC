// -----------------------------------------------------------------------------
// bms_sensor_item
// Transação TLM dos estímulos aplicados ao DUT (bms_top):
//   V1..V4_dig, I_dig, T_dig (10 bits), I_DIR, CHG_PWR_GD e pulso de reset.
//
// Rastreabilidade com o Plano de Verificação (VP v1.0):
//   F1  Reset              -> aplica_reset
//   F2  Sequência da FSM   -> CEN_NORMAL + hold_cycles >= 1 varredura
//   F3  OV  (430/421/420/419) -> CEN_SOBRETENSAO e CEN_BORDA (grandeza 0)
//   F4  UV  (250/299/300/301) -> CEN_SUBTENSAO   e CEN_BORDA (grandeza 1)
//   F5  OT  (75/61/60/59)     -> CEN_SOBRETEMP   e CEN_BORDA (grandeza 2)
//   F6  LK  (100/81/80/79)    -> CEN_SOBRECORRENTE e CEN_BORDA (grandeza 3)
//   F7  Duas falhas ao mesmo tempo -> CEN_MULTIPLA_FALHA
//   F8  Controle de potência   -> chg_pwr_gd combinado com cada cenário
//   F9  Balanceamento (dif. 9/10/11, nenhuma/todas) -> CEN_BALANCEAMENTO
//   F10 SOC (carga/descarga, saturação) -> i_dir, i_dig, hold_cycles longo
//   Ponto de atenção: célula em 0 (latch em bal_cmd_calc) -> CEN_CELULA_ZERO
// Os limites default seguem a ROM (OV=420, UV=300, Imax=80, Tmax=60, DELTA=10)
// e podem ser atualizados pela sequence após uma escrita I2C (F11).
// -----------------------------------------------------------------------------
`ifndef BMS_SENSOR_ITEM_SV
`define BMS_SENSOR_ITEM_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

typedef enum bit [3:0] {
    CEN_NORMAL         = 4'd0,
    CEN_BALANCEAMENTO  = 4'd1,
    CEN_SOBRETENSAO    = 4'd2,
    CEN_SUBTENSAO      = 4'd3,
    CEN_SOBRETEMP      = 4'd4,
    CEN_SOBRECORRENTE  = 4'd5,
    CEN_BORDA          = 4'd6,  // valores em limite-1, limite, limite+1
    CEN_MULTIPLA_FALHA = 4'd7,  // 2 ou mais falhas simultâneas
    CEN_CELULA_ZERO    = 4'd8   // uma célula em 0 (v_min = 0)
} bms_cenario_e;

class bms_sensor_item extends uvm_sequence_item;

    // ---------------- Campos de protocolo (estímulos) ----------------
    rand bit [9:0]       v_dig [4];     // V1..V4_dig (índice 0 = célula 1)
    rand bit [9:0]       i_dig;         // corrente
    rand bit [9:0]       t_dig;         // temperatura
    rand bit             i_dir;         // 1 = carregando (SOC sobe), 0 = descarregando
    rand bit             chg_pwr_gd;    // fonte de carga OK
    rand bit             aplica_reset;  // pulso de sys_rst antes do estímulo (F1)

    // ---------------- Controle da geração ------------------------------
    rand bms_cenario_e   cenario;
    rand bit [1:0]       cell_alvo;     // célula principal do cenário
    rand bit [1:0]       cell_alvo2;    // 2ª célula (falha dupla OV+UV)
    rand bit [9:0]       v_base;        // menor tensão "normal" de referência
    rand bit [15:0]      hold_cycles;   // ciclos mantendo o estímulo
    rand bit [1:0]       grandeza_borda;// 0=OV 1=UV 2=OT 3=LK (CEN_BORDA)
    rand int             delta_borda;   // -1, 0 ou +1 em relação ao limite
    rand bit [3:0]       mascara_falhas;// bit0=OV bit1=UV bit2=OT bit3=LK

    // Limites vigentes no DUT (não randomizados; a sequence atualiza após I2C)
    bit [9:0] lim_ov = 10'd420;
    bit [9:0] lim_uv = 10'd300;
    bit [9:0] lim_ot = 10'd60;
    bit [9:0] lim_lk = 10'd80;

    // ---------------- Registro na UVM Factory --------------------------
    `uvm_object_utils_begin(bms_sensor_item)
        `uvm_field_sarray_int(v_dig,          UVM_ALL_ON | UVM_DEC)
        `uvm_field_int       (i_dig,          UVM_ALL_ON | UVM_DEC)
        `uvm_field_int       (t_dig,          UVM_ALL_ON | UVM_DEC)
        `uvm_field_int       (i_dir,          UVM_ALL_ON | UVM_BIN)
        `uvm_field_int       (chg_pwr_gd,     UVM_ALL_ON | UVM_BIN)
        `uvm_field_int       (aplica_reset,   UVM_ALL_ON | UVM_BIN)
        `uvm_field_enum      (bms_cenario_e, cenario, UVM_ALL_ON)
        `uvm_field_int       (cell_alvo,      UVM_ALL_ON | UVM_DEC)
        `uvm_field_int       (cell_alvo2,     UVM_ALL_ON | UVM_DEC)
        `uvm_field_int       (v_base,         UVM_ALL_ON | UVM_DEC)
        `uvm_field_int       (hold_cycles,    UVM_ALL_ON | UVM_DEC)
        `uvm_field_int       (grandeza_borda, UVM_ALL_ON | UVM_DEC)
        `uvm_field_int       (delta_borda,    UVM_ALL_ON | UVM_DEC)
        `uvm_field_int       (mascara_falhas, UVM_ALL_ON | UVM_BIN)
        `uvm_field_int       (lim_ov,         UVM_ALL_ON | UVM_DEC | UVM_NOCOMPARE)
        `uvm_field_int       (lim_uv,         UVM_ALL_ON | UVM_DEC | UVM_NOCOMPARE)
        `uvm_field_int       (lim_ot,         UVM_ALL_ON | UVM_DEC | UVM_NOCOMPARE)
        `uvm_field_int       (lim_lk,         UVM_ALL_ON | UVM_DEC | UVM_NOCOMPARE)
    `uvm_object_utils_end

    // ---------------- Constraints -------------------------------------
    constraint c_cenario_dist {
        cenario dist {
            CEN_NORMAL         := 25,
            CEN_BALANCEAMENTO  := 20,
            CEN_SOBRETENSAO    := 8,
            CEN_SUBTENSAO      := 8,
            CEN_SOBRETEMP      := 8,
            CEN_SOBRECORRENTE  := 8,
            CEN_BORDA          := 15,
            CEN_MULTIPLA_FALHA := 6,
            CEN_CELULA_ZERO    := 2
        };
    }

    constraint c_chg_pwr { chg_pwr_gd dist {1 := 70, 0 := 30}; }
    constraint c_reset   { aplica_reset dist {0 := 90, 1 := 10}; }

    // Uma varredura completa leva ~13 ciclos: esperar >= 14 antes de checar
    // flags. Valores longos servem para saturar o SOC em 0 / 1000 (F10).
    constraint c_hold {
        hold_cycles dist { [14:40] :/ 80, [41:200] :/ 15, [1000:3000] :/ 5 };
    }

    constraint c_borda {
        delta_borda inside {-1, 0, 1};
        mascara_falhas inside {4'b0011, 4'b0101, 4'b0110, 4'b1001, 4'b1010,
                               4'b1100, 4'b0111, 4'b1011, 4'b1101, 4'b1110, 4'b1111};
        cell_alvo2 != cell_alvo;
    }

    // Faixa "segura" para as demais células
    constraint c_vbase { v_base inside {[int'(lim_uv) + 5 : int'(lim_ov) - 25]}; }

    // --- Tensões -----------------------------------------------------------
    // NORMAL, OT e LK: spread <= 10 (<= BAL_DELTA, nenhuma célula balanceia),
    // sem falha de tensão. Cobre as diferenças 9 e 10 do VP (F9).
    constraint c_v_normal {
        (cenario inside {CEN_NORMAL, CEN_SOBRETEMP, CEN_SOBRECORRENTE}) ->
            foreach (v_dig[k]) v_dig[k] inside {[v_base : v_base + 10]};
    }

    // BALANCEAMENTO: cell_alvo2 fica em v_min (varia a célula v_min) e cell_alvo
    // fica >= v_min + 11 (BAL_EN = 1). As demais ficam entre v_min e v_min + 20,
    // o que gera as células balanceando, uma a uma. Diferenças de 9 e
    // 10 (BAL_EN = 0) vêm de CEN_NORMAL, cujo spread vai de 0 a 10.
    constraint c_v_bal {
        (cenario == CEN_BALANCEAMENTO) -> foreach (v_dig[k]) {
            if (k == cell_alvo)       v_dig[k] inside {[v_base + 11 : v_base + 20]};
            else if (k == cell_alvo2) v_dig[k] == v_base;
            else                      v_dig[k] inside {[v_base : v_base + 20]};
        }
    }

    // SOBRETENSÃO / SUBTENSÃO: valor claramente fora do limite (ex.: 430, 250)
    constraint c_v_ov {
        (cenario == CEN_SOBRETENSAO) -> foreach (v_dig[k]) {
            if (k == cell_alvo) v_dig[k] inside {[int'(lim_ov) + 1 : int'(lim_ov) + 60]};
            else                v_dig[k] inside {[v_base : v_base + 9]};
        }
    }
    constraint c_v_uv {
        (cenario == CEN_SUBTENSAO) -> foreach (v_dig[k]) {
            if (k == cell_alvo) v_dig[k] inside {[int'(lim_uv) - 100 : int'(lim_uv) - 1]};
            else                v_dig[k] inside {[v_base : v_base + 9]};
        }
    }

    // BORDA: limite-1 / limite / limite+1 (419,420,421; 299,300,301)
    constraint c_v_borda {
        (cenario == CEN_BORDA) -> foreach (v_dig[k]) {
            if (k == cell_alvo && grandeza_borda == 0) v_dig[k] == int'(lim_ov) + delta_borda;
            else if (k == cell_alvo && grandeza_borda == 1) v_dig[k] == int'(lim_uv) + delta_borda;
            else v_dig[k] inside {[v_base : v_base + 9]};
        }
    }

    // MÚLTIPLA FALHA: OV na cell_alvo e/ou UV na cell_alvo2 conforme a máscara
    constraint c_v_multi {
        (cenario == CEN_MULTIPLA_FALHA) -> foreach (v_dig[k]) {
            if (k == cell_alvo && mascara_falhas[0])
                v_dig[k] inside {[int'(lim_ov) + 1 : int'(lim_ov) + 60]};
            else if (k == cell_alvo2 && mascara_falhas[1])
                v_dig[k] inside {[int'(lim_uv) - 100 : int'(lim_uv) - 1]};
            else
                v_dig[k] inside {[v_base : v_base + 9]};
        }
    }

    // CÉLULA ZERO: v_min = 0 (ponto de atenção do VP: latch no balanceamento)
    constraint c_v_zero {
        (cenario == CEN_CELULA_ZERO) -> foreach (v_dig[k]) {
            if (k == cell_alvo) v_dig[k] == 0;
            else                v_dig[k] inside {[v_base : v_base + 9]};
        }
    }

    // --- Temperatura (F5) --------------------------------------------------
    constraint c_temp {
        if (cenario == CEN_SOBRETEMP ||
            (cenario == CEN_MULTIPLA_FALHA && mascara_falhas[2]))
            t_dig inside {[int'(lim_ot) + 1 : int'(lim_ot) + 40]};   // ex.: 61, 75
        else if (cenario == CEN_BORDA && grandeza_borda == 2)
            t_dig == int'(lim_ot) + delta_borda;                     // 59, 60, 61
        else
            t_dig inside {[0 : int'(lim_ot) - 1]};
    }

    // --- Corrente (F6 / F10) -------------------------------------------------
    constraint c_corrente {
        if (cenario == CEN_SOBRECORRENTE ||
            (cenario == CEN_MULTIPLA_FALHA && mascara_falhas[3]))
            i_dig inside {[int'(lim_lk) + 1 : int'(lim_lk) + 120]};  // ex.: 81, 100
        else if (cenario == CEN_BORDA && grandeza_borda == 3)
            i_dig == int'(lim_lk) + delta_borda;                     // 79, 80, 81
        else
            i_dig inside {[0 : int'(lim_lk) - 1]};
    }

    // ---------------- Construtor --------------------------------------
    function new(string name = "bms_sensor_item");
        super.new(name);
    endfunction

    // Valor mínimo entre as 4 tensões (útil para o modelo de referência)
    function bit [9:0] v_min();
        bit [9:0] m = v_dig[0];
        foreach (v_dig[k]) if (v_dig[k] < m) m = v_dig[k];
        return m;
    endfunction

    function string convert2string();
        return $sformatf("[%s] V=%0d/%0d/%0d/%0d I=%0d T=%0d DIR=%0b PWR_GD=%0b RST=%0b hold=%0d",
                         cenario.name(), v_dig[0], v_dig[1], v_dig[2], v_dig[3],
                         i_dig, t_dig, i_dir, chg_pwr_gd, aplica_reset, hold_cycles);
    endfunction

endclass

`endif
