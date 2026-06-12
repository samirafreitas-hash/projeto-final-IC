module bms_control_potencia (
    input wire [2:0] Estado_atual,
    input wire CHG_PWR_GD,
    input wire OV_FLG,
    input wire UV_FLG,
    input wire OT_FLG,
    input wire LK_FLG,

    output reg CHG_EN,
    output reg DSCHG_EN
);

    localparam ST_INIT  = 3'b000;
    localparam ST_FAULT = 3'b101;

    always @(*) begin
        CHG_EN   = 1'b0;
        DSCHG_EN = 1'b0;

        if ((Estado_atual == ST_INIT) || (Estado_atual == ST_FAULT)) begin
            CHG_EN   = 1'b0;
            DSCHG_EN = 1'b0;
        end else if (OT_FLG || LK_FLG) begin
            CHG_EN   = 1'b0;
            DSCHG_EN = 1'b0;
        end else begin
            // OV bloqueia carga; UV bloqueia descarga profunda.
            CHG_EN   = CHG_PWR_GD && !OV_FLG;
            DSCHG_EN = !UV_FLG;
        end
    end
endmodule
