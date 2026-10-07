// -----------------------------------------------------------------------------
// bms_i2c_cfg_item
// Transação TLM de escrita I2C para configurar os limites da ROM do BMS.
// Protocolo (bms_i2c_slave_config):
//   START -> {dev_addr[6:0], W} -> ACK -> reg_addr -> ACK
//         -> data[15:8] -> ACK -> data[7:0] -> ACK -> STOP
// Apenas os 10 bits menos significativos do dado são usados.
// Rastreabilidade (VP v1.0, F11): os 6 registradores 0x00..0x05 são escritos;
// Após cada escrita válida a sequence deve atualizar os limites (lim_*) do bms_sensor_item para os novos valores.
// -----------------------------------------------------------------------------
`ifndef BMS_I2C_CFG_ITEM_SV
`define BMS_I2C_CFG_ITEM_SV

`include "uvm_macros.svh"
import uvm_pkg::*;

typedef enum bit [7:0] {
    REG_LIM_SOBRECARGA    = 8'h00,
    REG_LIM_SOBREDESCARGA = 8'h01,
    REG_LIM_CORRENTE_MAX  = 8'h02,
    REG_LIM_CORRENTE_MIN  = 8'h03,
    REG_LIM_TEMP          = 8'h04,
    REG_CAPACIDADE_NOM    = 8'h05
} bms_cfg_reg_e;

class bms_i2c_cfg_item extends uvm_sequence_item;

    // ---------------- Campos de protocolo ------------------------------
    rand bit [6:0]        dev_addr;   // endereço I2C do escravo (padrão 0x42)
    rand bit [7:0]        reg_addr;   // registrador de destino (0x00..0x05 válidos)
    rand bit [15:0]       data;       // dado de 16 bits (somente [9:0] é usado)

    // ---------------- Controle da geração ------------------------------
    rand bit              reg_valido; // 1 = reg_addr dentro do mapa da ROM
    rand bit              dev_valido; // 1 = endereço correto do escravo

    // ---------------- Registro na UVM Factory --------------------------
    `uvm_object_utils_begin(bms_i2c_cfg_item)
        `uvm_field_int(dev_addr,   UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(reg_addr,   UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(data,       UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(reg_valido, UVM_ALL_ON | UVM_BIN)
        `uvm_field_int(dev_valido, UVM_ALL_ON | UVM_BIN)
    `uvm_object_utils_end

    // ---------------- Constraints --------------------------------------
    // Maioria das transações endereça o escravo correto;
    constraint c_dev_valido { dev_valido dist {1 := 90, 0 := 10}; }
    constraint c_dev_addr {
        if (dev_valido) dev_addr == 7'h42;
        else            dev_addr != 7'h42;
    }

    // Maioria dos acessos em registradores válidos
    constraint c_reg_valido { reg_valido dist {1 := 90, 0 := 10}; }
    constraint c_reg_addr {
        if (reg_valido) reg_addr inside {[8'h00:8'h05]};
        else            reg_addr inside {[8'h06:8'hFF]};
    }

    // Valores coerentes com cada registrador (escala de 10 bits do projeto)
    constraint c_data_por_reg {
        if (reg_valido) {
            (reg_addr == REG_LIM_SOBRECARGA)    -> data[9:0] inside {[350:450]};
            (reg_addr == REG_LIM_SOBREDESCARGA) -> data[9:0] inside {[250:330]};
            (reg_addr == REG_LIM_CORRENTE_MAX)  -> data[9:0] inside {[50:150]};
            (reg_addr == REG_LIM_CORRENTE_MIN)  -> data[9:0] inside {[0:20]};
            (reg_addr == REG_LIM_TEMP)          -> data[9:0] inside {[40:90]};
            (reg_addr == REG_CAPACIDADE_NOM)    -> data[9:0] dist {10'd0 := 10, [100:1000] :/ 90};  // cap = 0 (F10)
        }
    }

    // Bits [15:10] são ignorados pelo DUT: mantidos em zero para facilitar a checagem
    constraint c_data_upper { data[15:10] == 6'd0; }

    // ---------------- Construtor ----------------------------------------
    function new(string name = "bms_i2c_cfg_item");
        super.new(name);
    endfunction

    // Valor efetivamente armazenado na ROM (10 LSBs)
    function bit [9:0] get_cfg_data();
        return data[9:0];
    endfunction

    function string convert2string();
        return $sformatf("I2C WR dev=0x%02h reg=0x%02h data=0x%03h (%0d)",
                         dev_addr, reg_addr, data[9:0], data[9:0]);
    endfunction

endclass

`endif
