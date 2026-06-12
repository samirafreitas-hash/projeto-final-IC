module bms_soc_coulomb #(
    parameter SOC_FULL_SCALE = 10'd1000,
    parameter SAMPLE_TIME = 10'd1
) (
    input wire sys_clk,
    input wire sys_rst,
    input wire sample_tick,
    input wire I_DIR,
    input wire [9:0] I_reg,
    input wire [9:0] capacidade_nom,

    output reg [9:0] SOC_DATA_OUT,
    output reg [9:0] SOC_atual
);

    reg [31:0] delta_soc;
    reg [31:0] next_soc;

    always @(*) begin
        if (capacidade_nom == 10'd0) begin
            delta_soc = 32'd0;
        end else begin
            delta_soc = (I_reg * SAMPLE_TIME * SOC_FULL_SCALE) / capacidade_nom;
        end

        if (I_DIR) begin
            next_soc = SOC_atual + delta_soc;
        end else if (SOC_atual > delta_soc[9:0]) begin
            next_soc = SOC_atual - delta_soc;
        end else begin
            next_soc = 32'd0;
        end
    end

    always @(posedge sys_clk or posedge sys_rst) begin
        if (sys_rst) begin
            SOC_atual    <= SOC_FULL_SCALE;
            SOC_DATA_OUT <= SOC_FULL_SCALE;
        end else if (sample_tick) begin
            if (next_soc > SOC_FULL_SCALE) begin
                SOC_atual    <= SOC_FULL_SCALE;
                SOC_DATA_OUT <= SOC_FULL_SCALE;
            end else begin
                SOC_atual    <= next_soc[9:0];
                SOC_DATA_OUT <= next_soc[9:0];
            end
        end
    end
endmodule
