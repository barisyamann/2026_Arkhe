`timescale 1ns / 1ps


module timer_peripheral # (
    parameter integer S_AXI_ADDR_WIDTH = 12,
    parameter integer S_AXI_DATA_WIDTH = 32
)(
    // --- AXI4-Lite Standart Portları ---
    input  logic                          s_axi_aclk,
    input  logic                          s_axi_aresetn,

    input  logic [S_AXI_ADDR_WIDTH-1:0]   s_axi_awaddr,
    input  logic [2:0]                    s_axi_awprot,
    input  logic                          s_axi_awvalid,
    output logic                          s_axi_awready,

    input  logic [S_AXI_DATA_WIDTH-1:0]   s_axi_wdata,
    input  logic [(S_AXI_DATA_WIDTH/8)-1:0] s_axi_wstrb,
    input  logic                          s_axi_wvalid,
    output logic                          s_axi_wready,

    output logic [1:0]                    s_axi_bresp,
    output logic                          s_axi_bvalid,
    input  logic                          s_axi_bready,

    input  logic [S_AXI_ADDR_WIDTH-1:0]   s_axi_araddr,
    input  logic [2:0]                    s_axi_arprot,
    input  logic                          s_axi_arvalid,
    output logic                          s_axi_arready,

    output logic [S_AXI_DATA_WIDTH-1:0]   s_axi_rdata,
    output logic [1:0]                    s_axi_rresp,
    output logic                          s_axi_rvalid,
    input  logic                          s_axi_rready,

    // =========================================================================
    // --- DONANIMSAL KESME (INTERRUPT) ÇIKIŞI ---
    // =========================================================================
    output logic                          timer_irq
);

    // Yazmaç Offsetleri 
    localparam logic [11:0] ADDR_TIM_PRE = 12'h000;
    localparam logic [11:0] ADDR_TIM_ARE = 12'h004;
    localparam logic [11:0] ADDR_TIM_CLR = 12'h008;
    localparam logic [11:0] ADDR_TIM_ENA = 12'h00C;
    localparam logic [11:0] ADDR_TIM_MOD = 12'h010;
    localparam logic [11:0] ADDR_TIM_CNT = 12'h014;
    localparam logic [11:0] ADDR_TIM_EVN = 12'h018;
    localparam logic [11:0] ADDR_TIM_EVC = 12'h01C;

    // Dahili Yazmaçlar
    logic [31:0] reg_tim_pre;
    logic [31:0] reg_tim_are;
    logic        reg_tim_ena;
    logic        reg_tim_mod;
    logic [31:0] reg_tim_cnt;
    logic [31:0] reg_tim_evn;

    logic [31:0] prescaler_counter;
    logic        timer_tick;

    // --- Interrupt Sinyali Ataması (Kombinatoryal) ---
    // Event Counter 0'dan büyük olduğu sürece Interrupt hattı HIGH kalır.
    // Yazılım (İşlemci) ADDR_TIM_EVC yazmacına 1 yazana kadar kesme düşmez.
    assign timer_irq = (reg_tim_evn != 0) ? 1'b1 : 1'b0;

    // --- Prescaler Motoru ---
    always_ff @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            prescaler_counter <= '0;
            timer_tick        <= 1'b0;
        end else begin
            timer_tick <= 1'b0;
            if (reg_tim_ena) begin
                if (prescaler_counter >= reg_tim_pre) begin
                    prescaler_counter <= '0;
                    timer_tick        <= 1'b1;
                end else begin
                    prescaler_counter <= prescaler_counter + 1'b1;
                end
            end else begin
                prescaler_counter <= '0;
            end
        end
    end

    // --- Ana Sayaç ve Event Lojiki ---
    always_ff @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            reg_tim_cnt <= '0;
            reg_tim_evn <= '0;
        end else begin
            // Sayaç Temizleme
            if (s_axi_awvalid && s_axi_awready && s_axi_wvalid && s_axi_wready && (s_axi_awaddr[11:0] == ADDR_TIM_CLR) && s_axi_wdata[0]) begin
                reg_tim_cnt <= '0;
            end else if (timer_tick) begin
                if (reg_tim_mod) begin // Yukarı
                    if (reg_tim_cnt == reg_tim_are) begin
                        reg_tim_cnt <= '0;
                        reg_tim_evn <= reg_tim_evn + 1'b1; // Event arttır, IRQ tetiklenir!
                    end else begin
                        reg_tim_cnt <= reg_tim_cnt + 1'b1;
                    end
                end else begin         // Aşağı
                    if (reg_tim_cnt == '0) begin
                        reg_tim_cnt <= reg_tim_are;
                        reg_tim_evn <= reg_tim_evn + 1'b1; // Event arttır, IRQ tetiklenir!
                    end else begin
                        reg_tim_cnt <= reg_tim_cnt - 1'b1;
                    end
                end
            end

            // Event ve Interrupt Temizleme
            if (s_axi_awvalid && s_axi_awready && s_axi_wvalid && s_axi_wready && (s_axi_awaddr[11:0] == ADDR_TIM_EVC) && s_axi_wdata[0]) begin
                reg_tim_evn <= '0; // Event sıfırlanınca timer_irq anında LOW olur
            end
        end
    end

    // --- AXI4-Lite Kombinatoryal El Sıkışma ---
    assign s_axi_awready = s_axi_awvalid && s_axi_wvalid && !s_axi_bvalid;
    assign s_axi_wready  = s_axi_awvalid && s_axi_wvalid && !s_axi_bvalid;

    // --- AXI4-Lite Write Kanalı ---
    always_ff @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            s_axi_bvalid   <= 1'b0;
            s_axi_bresp    <= 2'b00;
            reg_tim_pre    <= '0;
            reg_tim_are    <= 32'hFFFFFFFF;
            reg_tim_ena    <= 1'b0;
            reg_tim_mod    <= 1'b1;
        end else begin
            if (s_axi_awvalid && s_axi_awready && s_axi_wvalid && s_axi_wready) begin
                s_axi_bvalid <= 1'b1;
                s_axi_bresp  <= 2'b00;
                case (s_axi_awaddr[11:0])
                    ADDR_TIM_PRE: reg_tim_pre <= s_axi_wdata;
                    ADDR_TIM_ARE: reg_tim_are <= s_axi_wdata;
                    ADDR_TIM_ENA: reg_tim_ena <= s_axi_wdata[0];
                    ADDR_TIM_MOD: reg_tim_mod <= s_axi_wdata[0];
                    default:      s_axi_bresp <= 2'b10; // SLVERR
                endcase
            end else if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end
        end
    end

    // --- AXI4-Lite Read Kanalı ---
    always_ff @(posedge s_axi_aclk or negedge s_axi_aresetn) begin
        if (!s_axi_aresetn) begin
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rdata   <= '0;
            s_axi_rresp   <= 2'b00;
        end else begin
            if (s_axi_arvalid && !s_axi_rvalid) begin
                s_axi_arready <= 1'b1;
                s_axi_rvalid  <= 1'b1;
                s_axi_rresp   <= 2'b00;
                case (s_axi_araddr[11:0])
                    ADDR_TIM_PRE: s_axi_rdata <= reg_tim_pre;
                    ADDR_TIM_ARE: s_axi_rdata <= reg_tim_are;
                    ADDR_TIM_CLR: s_axi_rdata <= '0;
                    ADDR_TIM_ENA: s_axi_rdata <= {31'b0, reg_tim_ena};
                    ADDR_TIM_MOD: s_axi_rdata <= {31'b0, reg_tim_mod};
                    ADDR_TIM_CNT: s_axi_rdata <= reg_tim_cnt;
                    ADDR_TIM_EVN: s_axi_rdata <= reg_tim_evn;
                    ADDR_TIM_EVC: s_axi_rdata <= '0;
                    default: begin
                        s_axi_rdata <= '0;
                        s_axi_rresp <= 2'b10;
                    end
                endcase
            end else begin
                s_axi_arready <= 1'b0;
            end

            if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

endmodule