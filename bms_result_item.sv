// -----------------------------------------------------------------------------
// bms_result_item
// Transação TLM com as saídas observadas do DUT (bms_top), usada pelo monitor
// e pelo scoreboard para comparar com o modelo de referência.
// -----------------------------------------------------------------------------
`ifndef BMS_RESULT_ITEM_SV
`define BMS_RESULT_ITEM_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

class bms_result_item extends uvm_sequence_item;

    // ---------------- Saídas do DUT -------------------------------------
    bit         chg_en;
    bit         dschg_en;
    bit         ov_flg;
    bit         uv_flg;
    bit         ot_flg;
    bit         lk_flg;
    bit [3:0]   bal_cmd_out;
    bit         bal_flg;
    bit [9:0]   soc_data_out;
    bit [2:0]   estado_atual;

    // ---------------- Registro na UVM Factory ----------------------------
    `uvm_object_utils_begin(bms_result_item)
        `uvm_field_int(chg_en,       UVM_ALL_ON | UVM_BIN)
        `uvm_field_int(dschg_en,     UVM_ALL_ON | UVM_BIN)
        `uvm_field_int(ov_flg,       UVM_ALL_ON | UVM_BIN)
        `uvm_field_int(uv_flg,       UVM_ALL_ON | UVM_BIN)
        `uvm_field_int(ot_flg,       UVM_ALL_ON | UVM_BIN)
        `uvm_field_int(lk_flg,       UVM_ALL_ON | UVM_BIN)
        `uvm_field_int(bal_cmd_out,  UVM_ALL_ON | UVM_BIN)
        `uvm_field_int(bal_flg,      UVM_ALL_ON | UVM_BIN)
        `uvm_field_int(soc_data_out, UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(estado_atual, UVM_ALL_ON | UVM_BIN)
    `uvm_object_utils_end

    function new(string name = "bms_result_item");
        super.new(name);
    endfunction

    // Há alguma falha ativa?
    function bit tem_falha();
        return (ov_flg | uv_flg | ot_flg | lk_flg);
    endfunction

    function string convert2string();
        return $sformatf("estado=%0b CHG=%0b DSCHG=%0b OV/UV/OT/LK=%0b%0b%0b%0b BAL=%04b BAL_FLG=%0b SOC=%0d",
                         estado_atual, chg_en, dschg_en, ov_flg, uv_flg, ot_flg, lk_flg,
                         bal_cmd_out, bal_flg, soc_data_out);
    endfunction

endclass

`endif
