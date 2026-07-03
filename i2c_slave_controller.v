// Escravo I2C simples para configuracao dos limites do BMS.
// Protocolo de escrita:
//   START -> endereco 7 bits + W(0) -> ACK
//   registrador -> ACK
//   dado[15:8] -> ACK
//   dado[7:0]  -> ACK -> STOP
//
// O valor gravado em cfg_data usa apenas os 10 bits menos significativos.
module bms_i2c_slave_config #(
    parameter I2C_ADDR = 7'h42
) (
    input wire sys_clk,
    input wire sys_rst,
    input wire i2c_scl,
    inout wire i2c_sda,

    output reg cfg_wr_en,
    output reg [7:0] cfg_addr,
    output reg [9:0] cfg_data
);

    localparam ST_IDLE       = 4'd0;
    localparam ST_ADDR       = 4'd1;
    localparam ST_ACK_ADDR   = 4'd2;
    localparam ST_REG        = 4'd3;
    localparam ST_ACK_REG    = 4'd4;
    localparam ST_DATA_H     = 4'd5;
    localparam ST_ACK_DATA_H = 4'd6;
    localparam ST_DATA_L     = 4'd7;
    localparam ST_ACK_DATA_L = 4'd8;
    localparam ST_IGNORE     = 4'd9;

    reg [3:0] state;
    reg [2:0] bit_count;
    reg [7:0] rx_shift;
    reg [7:0] reg_addr_tmp;
    reg [15:0] data_tmp;
    reg sda_drive_low;

    reg scl_d;
    reg sda_d;
    wire sda_in = i2c_sda;
    wire scl_rise = (i2c_scl == 1'b1) && (scl_d == 1'b0);
    wire scl_fall = (i2c_scl == 1'b0) && (scl_d == 1'b1);
    wire start_cond = (sda_in == 1'b0) && (sda_d == 1'b1) && (i2c_scl == 1'b1);
    wire stop_cond  = (sda_in == 1'b1) && (sda_d == 1'b0) && (i2c_scl == 1'b1);

    assign i2c_sda = sda_drive_low ? 1'b0 : 1'bz;

    always @(posedge sys_clk or posedge sys_rst) begin
        if (sys_rst) begin
            state         <= ST_IDLE;
            bit_count     <= 3'd7;
            rx_shift      <= 8'd0;
            reg_addr_tmp  <= 8'd0;
            data_tmp      <= 16'd0;
            sda_drive_low <= 1'b0;
            cfg_wr_en     <= 1'b0;
            cfg_addr      <= 8'd0;
            cfg_data      <= 10'd0;
            scl_d         <= 1'b1;
            sda_d         <= 1'b1;
        end else begin
            scl_d     <= i2c_scl;
            sda_d     <= sda_in;
            cfg_wr_en <= 1'b0;

            if (start_cond) begin
                state         <= ST_ADDR;
                bit_count     <= 3'd7;
                rx_shift      <= 8'd0;
                sda_drive_low <= 1'b0;
            end else if (stop_cond) begin
                state         <= ST_IDLE;
                sda_drive_low <= 1'b0;
            end else begin
                case (state)
                    ST_IDLE: begin
                        sda_drive_low <= 1'b0;
                    end

                    ST_ADDR: begin
                        if (scl_rise) begin
                            rx_shift[bit_count] <= sda_in;
                            if (bit_count == 3'd0) begin
                                state     <= ((rx_shift[7:1] == I2C_ADDR) && (sda_in == 1'b0)) ? ST_ACK_ADDR : ST_IGNORE;
                                bit_count <= 3'd7;
                            end else begin
                                bit_count <= bit_count - 1'b1;
                            end
                        end
                    end

                    ST_ACK_ADDR: begin
                        if (scl_fall) begin
                            if (sda_drive_low) begin
                                sda_drive_low <= 1'b0;
                                state         <= ST_REG;
                            end else begin
                                sda_drive_low <= 1'b1;
                            end
                        end
                    end

                    ST_REG: begin
                        if (scl_rise) begin
                            rx_shift[bit_count] <= sda_in;
                            if (bit_count == 3'd0) begin
                                reg_addr_tmp <= {rx_shift[7:1], sda_in};
                                state        <= ST_ACK_REG;
                                bit_count    <= 3'd7;
                            end else begin
                                bit_count <= bit_count - 1'b1;
                            end
                        end
                    end

                    ST_ACK_REG: begin
                        if (scl_fall) begin
                            if (sda_drive_low) begin
                                sda_drive_low <= 1'b0;
                                state         <= ST_DATA_H;
                            end else begin
                                sda_drive_low <= 1'b1;
                            end
                        end
                    end

                    ST_DATA_H: begin
                        if (scl_rise) begin
                            rx_shift[bit_count] <= sda_in;
                            if (bit_count == 3'd0) begin
                                data_tmp[15:8] <= {rx_shift[7:1], sda_in};
                                state          <= ST_ACK_DATA_H;
                                bit_count      <= 3'd7;
                            end else begin
                                bit_count <= bit_count - 1'b1;
                            end
                        end
                    end

                    ST_ACK_DATA_H: begin
                        if (scl_fall) begin
                            if (sda_drive_low) begin
                                sda_drive_low <= 1'b0;
                                state         <= ST_DATA_L;
                            end else begin
                                sda_drive_low <= 1'b1;
                            end
                        end
                    end

                    ST_DATA_L: begin
                        if (scl_rise) begin
                            rx_shift[bit_count] <= sda_in;
                            if (bit_count == 3'd0) begin
                                data_tmp[7:0] <= {rx_shift[7:1], sda_in};
                                cfg_addr      <= reg_addr_tmp;
                                cfg_data      <= {data_tmp[9:8], rx_shift[7:1], sda_in};
                                cfg_wr_en     <= 1'b1;
                                state         <= ST_ACK_DATA_L;
                                bit_count     <= 3'd7;
                            end else begin
                                bit_count <= bit_count - 1'b1;
                            end
                        end
                    end

                    ST_ACK_DATA_L: begin
                        if (scl_fall) begin
                            if (sda_drive_low) begin
                                sda_drive_low <= 1'b0;
                                state         <= ST_REG;
                            end else begin
                                sda_drive_low <= 1'b1;
                            end
                        end
                    end

                    ST_IGNORE: begin
                        sda_drive_low <= 1'b0;
                    end

                    default: begin
                        state         <= ST_IDLE;
                        sda_drive_low <= 1'b0;
                    end
                endcase
            end
        end
    end
endmodule
