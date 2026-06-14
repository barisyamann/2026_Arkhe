`timescale 1ns / 1ps
// =============================================================================
// Modül: gpio_peripheral
// Açıklama: Vivado loop variable slicing (genvar) hatası düzeltilmiş,
//            şartnameye uygun 16 Giriş / 16 Çıkış Sabit AXI4-Lite modülü.
// =============================================================================

module gpio_peripheral #(
    parameter int AXI_ADDR_W = 8,
    parameter int AXI_DATA_W = 32
)(
    input  logic                    clk,
    input  logic                    rst_n,

    // --- Fiziksel Sabit GPIO Pinleri ---
    input  logic [15:0]             gpio_i,             // 16 Giriş Pin (Pad -> SoC)
    output logic [15:0]             gpio_o,             // 16 Çıkış Pin (SoC -> Pad)
    output logic [15:0]             gpio_tx_en_o,       // Pad Yön Kontrolü (0: RX, 1: TX)
    output logic                    global_interrupt_o, // Global Kesme Hattı

    // --- AXI4-Lite Slave Arayüzü ---
    input  logic [AXI_ADDR_W-1:0]   s_axil_awaddr,
    input  logic                    s_axil_awvalid,
    output logic                    s_axil_awready,
    input  logic [AXI_DATA_W-1:0]   s_axil_wdata,
    input  logic [3:0]              s_axil_wstrb,
    input  logic                    s_axil_wvalid,
    output logic                    s_axil_wready,
    output logic [1:0]              s_axil_bresp,
    output logic                    s_axil_bvalid,
    input  logic                    s_axil_bready,
    input  logic [AXI_ADDR_W-1:0]   s_axil_araddr,
    input  logic                    s_axil_arvalid,
    output logic                    s_axil_arready,
    output logic [AXI_DATA_W-1:0]   s_axil_rdata,
    output logic [1:0]              s_axil_rresp,
    output logic                    s_axil_rvalid,
    input  logic                    s_axil_rready
);

    // --- Yazmaç Adres Tanımlamaları ---
    localparam logic [7:0] ADDR_GPIO_IDR             = 8'h00;
    localparam logic [7:0] ADDR_GPIO_ODR             = 8'h04;
    localparam logic [7:0] ADDR_GPIO_MODE            = 8'h08;
    localparam logic [7:0] ADDR_GPIO_SET             = 8'h0C;
    localparam logic [7:0] ADDR_GPIO_CLEAR           = 8'h10;
    localparam logic [7:0] ADDR_GPIO_TOGGLE          = 8'h14;
    localparam logic [7:0] ADDR_INTRPT_RISE_EN       = 8'h18;
    localparam logic [7:0] ADDR_INTRPT_FALL_EN       = 8'h1C;
    localparam logic [7:0] ADDR_INTRPT_LVL_HIGH_EN   = 8'h20;
    localparam logic [7:0] ADDR_INTRPT_LVL_LOW_EN    = 8'h24;
    localparam logic [7:0] ADDR_INTRPT_STATUS        = 8'h28;

    localparam logic [1:0] RESP_OKAY   = 2'b00;
    localparam logic [1:0] RESP_SLVERR = 2'b10;

    // --- Durum ve Konfigürasyon Yazmaçları ---
    logic [15:0] reg_odr;
    logic [31:0] reg_mode_expanded; 
    logic [15:0] reg_intrpt_rise_en;
    logic [15:0] reg_intrpt_fall_en;
    logic [15:0] reg_intrpt_lvl_high_en;
    logic [15:0] reg_intrpt_lvl_low_en;
    
    logic [15:0] status_rise;
    logic [15:0] status_fall;
    logic [15:0] status_lvl_high;
    logic [15:0] status_lvl_low;

    // --- Giriş Senkronizasyon Katmanı (2-Stage) ---
    logic [15:0] gpio_in_q1, gpio_in_q2, gpio_in_q3;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gpio_in_q1 <= '0;
            gpio_in_q2 <= '0;
            gpio_in_q3 <= '0;
        end else begin
            gpio_in_q1 <= gpio_i;
            gpio_in_q2 <= gpio_in_q1;
            gpio_in_q3 <= gpio_in_q2;
        end
    end

    // Kenar Algılayıcılar
    logic [15:0] s_gpio_rise_edge, s_gpio_fall_edge;
    assign s_gpio_rise_edge = gpio_in_q2 & ~gpio_in_q3;
    assign s_gpio_fall_edge = ~gpio_in_q2 & gpio_in_q3;

    // Kesme Giriş Sinyalleri
    logic [15:0] s_gpio_rise_intrpt, s_gpio_fall_intrpt, s_gpio_high_intrpt, s_gpio_low_intrpt;
    assign s_gpio_rise_intrpt = s_gpio_rise_edge & reg_intrpt_rise_en;
    assign s_gpio_fall_intrpt = s_gpio_fall_edge & reg_intrpt_fall_en;
    assign s_gpio_high_intrpt = gpio_in_q2        & reg_intrpt_lvl_high_en;
    assign s_gpio_low_intrpt  = ~gpio_in_q2       & reg_intrpt_lvl_low_en;

    logic [15:0] interrupts_pending;
    assign interrupts_pending = status_rise | status_fall | status_lvl_high | status_lvl_low;
    assign global_interrupt_o = |interrupts_pending;

    // --- AXI4-Lite Yazma Kanalı Lojiki ---
    logic [AXI_ADDR_W-1:0] write_addr;

    assign s_axil_awready = ~s_axil_bvalid && s_axil_awvalid && s_axil_wvalid;
    assign s_axil_wready  = ~s_axil_bvalid && s_axil_awvalid && s_axil_wvalid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axil_bvalid          <= 1'b0;
            s_axil_bresp           <= RESP_OKAY;
            reg_odr                <= '0;
            reg_mode_expanded      <= '0;
            reg_intrpt_rise_en     <= '0;
            reg_intrpt_fall_en     <= '0;
            reg_intrpt_lvl_high_en <= '0;
            reg_intrpt_lvl_low_en  <= '0;
            status_rise            <= '0;
            status_fall            <= '0;
            status_lvl_high        <= '0;
            status_lvl_low         <= '0;
        end else begin
            status_rise     <= status_rise     | s_gpio_rise_intrpt;
            status_fall     <= status_fall     | s_gpio_fall_intrpt;
            status_lvl_high <= status_lvl_high | s_gpio_high_intrpt;
            status_lvl_low  <= status_lvl_low  | s_gpio_low_intrpt;

            if (s_axil_awvalid && s_axil_wvalid && !s_axil_bvalid) begin
                s_axil_bvalid <= 1'b1;
                s_axil_bresp  <= RESP_OKAY;
                write_addr    = s_axil_awaddr;

                unique case (write_addr[7:0])
                    ADDR_GPIO_ODR:           reg_odr                <= s_axil_wdata[15:0];
                    ADDR_GPIO_MODE:          reg_mode_expanded      <= s_axil_wdata;
                    ADDR_GPIO_SET:           reg_odr                <= reg_odr | s_axil_wdata[15:0];
                    ADDR_GPIO_CLEAR:         reg_odr                <= reg_odr & ~s_axil_wdata[15:0];
                    ADDR_GPIO_TOGGLE:        reg_odr                <= reg_odr ^ s_axil_wdata[15:0];
                    ADDR_INTRPT_RISE_EN:     reg_intrpt_rise_en     <= s_axil_wdata[15:0];
                    ADDR_INTRPT_FALL_EN:     reg_intrpt_fall_en     <= s_axil_wdata[15:0];
                    ADDR_INTRPT_LVL_HIGH_EN: reg_intrpt_lvl_high_en <= s_axil_wdata[15:0];
                    ADDR_INTRPT_LVL_LOW_EN:  reg_intrpt_lvl_low_en  <= s_axil_wdata[15:0];
                    ADDR_INTRPT_STATUS: begin
                        status_rise     <= (status_rise     | s_gpio_rise_intrpt)     & ~s_axil_wdata[15:0];
                        status_fall     <= (status_fall     | s_gpio_fall_intrpt)     & ~s_axil_wdata[15:0];
                        status_lvl_high <= (status_lvl_high | s_gpio_high_intrpt)     & ~s_axil_wdata[15:0];
                        status_lvl_low  <= (status_lvl_low  | s_gpio_low_intrpt)      & ~s_axil_wdata[15:0];
                    end
                    default: s_axil_bresp <= RESP_SLVERR;
                endcase
            end

            if (s_axil_bvalid && s_axil_bready) begin
                s_axil_bvalid <= 1'b0;
            end
        end
    end

    assign gpio_o = reg_odr;

    // --- Dinamik Çıkış Buffer Mod Çözücü (Genvar ile Çözülen Kısım) ---
    // Sentezleyicinin 'i' değişkenini sabit görmesi için generate döngüsüne geçildi.
    generate
        for (genvar i = 0; i < 16; i++) begin : gen_mode_control
            always_comb begin
                logic [1:0] pin_mode;
                pin_mode = reg_mode_expanded[(2*i)+1 : 2*i];
                
                case (pin_mode)
                    2'b00:   gpio_tx_en_o[i] = 1'b0;          // INPUT ONLY
                    2'b01:   gpio_tx_en_o[i] = 1'b1;          // OUTPUT ACTIVE
                    2'b10:   gpio_tx_en_o[i] = reg_odr[i];    // OPEN DRAIN 0
                    2'b11:   gpio_tx_en_o[i] = ~reg_odr[i];   // OPEN DRAIN 1
                    default: gpio_tx_en_o[i] = 1'b0;
                endcase
            end
        end
    endgenerate

    // --- AXI4-Lite Okuma Kanalı Lojiki ---
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axil_arready <= 1'b0;
            s_axil_rvalid  <= 1'b0;
            s_axil_rdata   <= '0;
            s_axil_rresp   <= RESP_OKAY;
        end else begin
            if (s_axil_arvalid && !s_axil_rvalid) begin
                s_axil_arready <= 1'b1;
                s_axil_rvalid  <= 1'b1;
                s_axil_rresp   <= RESP_OKAY;

                unique case (s_axil_araddr[7:0])
                    ADDR_GPIO_IDR:           s_axil_rdata <= {16'h0000, gpio_in_q2};
                    ADDR_GPIO_ODR:           s_axil_rdata <= {16'h0000, reg_odr};
                    ADDR_GPIO_MODE:          s_axil_rdata <= reg_mode_expanded;
                    ADDR_INTRPT_RISE_EN:     s_axil_rdata <= {16'h0000, reg_intrpt_rise_en};
                    ADDR_INTRPT_FALL_EN:     s_axil_rdata <= {16'h0000, reg_intrpt_fall_en};
                    ADDR_INTRPT_LVL_HIGH_EN: s_axil_rdata <= {16'h0000, reg_intrpt_lvl_high_en};
                    ADDR_INTRPT_LVL_LOW_EN:  s_axil_rdata <= {16'h0000, reg_intrpt_lvl_low_en};
                    ADDR_INTRPT_STATUS:      s_axil_rdata <= {16'h0000, interrupts_pending};
                    default: begin
                        s_axil_rdata <= '0;
                        s_axil_rresp <= RESP_SLVERR;
                    end
                endcase
            end else begin
                s_axil_arready <= 1'b0;
            end

            if (s_axil_rvalid && s_axil_rready) begin
                s_axil_rvalid <= 1'b0;
            end
        end
    end

endmodule