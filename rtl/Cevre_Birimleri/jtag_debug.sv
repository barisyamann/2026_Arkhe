`timescale 1ns / 1ps
// Description: Simplified JTAG Debug Bridge for the Arkhe SoC.
//              Provides external debug access via JTAG TAP pins.
//              Features:
//              - Memory read/write through AXI4-Lite Master port
//              - CPU halt/resume control via debug_req_o signal
//              - AXI4-Lite Slave CSR for internal debug register access
//              Ref: ÖTR Bölüm 3.2.7

module jtag_debug (
    input  logic        clk,
    input  logic        rst_n,

    // --- JTAG Fiziksel Pinler ---
    input  logic        jtag_tms,       // Test Mode Select
    input  logic        jtag_tck,       // Test Clock
    input  logic        jtag_tdi,       // Test Data Input
    output logic        jtag_tdo,       // Test Data Output
    input  logic        jtag_trst_n,    // Test Reset (aktif düşük)

    // --- CPU Debug Kontrol ---
    output logic        debug_req_o,    // CPU halt isteği

    // -------------------------------------------------------------------------
    // Veri yolu hata yakalama (OBI -> AXI koprulerinden)
    //
    // Bir AXI kolesi OKAY disinda yanit dondurdugunde ilgili kopru bir
    // cevrimlik darbe uretir. Burada yakalanip yapiskan hale getiriliyor
    // ve kesme olarak sunuluyor; yazilim hangi adresin ve hangi koprunun
    // hata verdigini okuyabiliyor.
    //
    // Hata teshis kapsamina girdigi icin debug bloguna yerlestirildi -
    // ayri bir AXI kolesi eklemek 13 koleli ara baglantida ~60 noktaya
    // dokunmayi gerektirirdi.
    // -------------------------------------------------------------------------
    input  logic        instr_bus_err_i,
    input  logic [31:0] instr_bus_err_addr_i,
    input  logic        data_bus_err_i,
    input  logic [31:0] data_bus_err_addr_i,
    output logic        bus_fault_irq_o,

    // --- AXI4-Lite Slave - CSR (0x4008_0000) ---
    input  logic [31:0] s_axi_awaddr,
    input  logic        s_axi_awvalid,
    output logic        s_axi_awready,
    input  logic [31:0] s_axi_wdata,
    input  logic [3:0]  s_axi_wstrb,
    input  logic        s_axi_wvalid,
    output logic        s_axi_wready,
    output logic [1:0]  s_axi_bresp,
    output logic        s_axi_bvalid,
    input  logic        s_axi_bready,
    input  logic [31:0] s_axi_araddr,
    input  logic        s_axi_arvalid,
    output logic        s_axi_arready,
    output logic [31:0] s_axi_rdata,
    output logic [1:0]  s_axi_rresp,
    output logic        s_axi_rvalid,
    input  logic        s_axi_rready,

    // --- AXI4-Lite Master - Bellek Erişim Portu ---
    output logic [31:0] m_axi_awaddr,
    output logic        m_axi_awvalid,
    input  logic        m_axi_awready,
    output logic [31:0] m_axi_wdata,
    output logic [3:0]  m_axi_wstrb,
    output logic        m_axi_wvalid,
    input  logic        m_axi_wready,
    input  logic [1:0]  m_axi_bresp,
    input  logic        m_axi_bvalid,
    output logic        m_axi_bready,
    output logic [31:0] m_axi_araddr,
    output logic        m_axi_arvalid,
    input  logic        m_axi_arready,
    input  logic [31:0] m_axi_rdata,
    input  logic [1:0]  m_axi_rresp,
    input  logic        m_axi_rvalid,
    output logic        m_axi_rready
);

    // =========================================================================
    // CSR Yazmaç Ofsetleri
    // =========================================================================
    localparam logic [4:0] REG_DBG_CTRL   = 5'h00; // [0] CPU Halt, [1] CPU Resume
    localparam logic [4:0] REG_DBG_STATUS = 5'h04; // [0] Halted, [1] Running, [2] Bus Busy
    localparam logic [4:0] REG_DBG_ADDR   = 5'h08; // Hedef bellek adresi
    localparam logic [4:0] REG_DBG_DATA   = 5'h0C; // Okuma/yazma verisi
    localparam logic [4:0] REG_DBG_CMD    = 5'h10; // [0] Read, [1] Write

    // Veri yolu hata yazmaclari
    localparam logic [4:0] REG_FAULT_ST   = 5'h14; // [0] Hata var, [1] Buyruk kopru,
                                                   // [2] Veri kopru (RO)
    localparam logic [4:0] REG_FAULT_ADDR = 5'h18; // Hatayi doguran adres (RO)
    localparam logic [4:0] REG_FAULT_CLR  = 5'h1C; // 1 yazilinca temizlenir (WO)

    // =========================================================================
    // İç Yazmaçlar
    // =========================================================================
    logic [31:0] reg_ctrl;
    logic [31:0] reg_addr;
    logic [31:0] reg_data;
    logic [31:0] reg_cmd;
    
    logic        dbg_halted;
    logic        bus_busy;
    logic        bus_done;

    // CPU Debug kontrol
    assign debug_req_o = dbg_halted;

    // =========================================================================
    // JTAG TAP - Standard IEEE 1149.1 TAP Controller
    // =========================================================================
    typedef enum logic [3:0] {
        TEST_LOGIC_RESET = 4'h0,
        RUN_TEST_IDLE    = 4'h1,
        SELECT_DR_SCAN   = 4'h2,
        CAPTURE_DR       = 4'h3,
        SHIFT_DR         = 4'h4,
        EXIT1_DR         = 4'h5,
        PAUSE_DR         = 4'h6,
        EXIT2_DR         = 4'h7,
        UPDATE_DR        = 4'h8,
        SELECT_IR_SCAN   = 4'h9,
        CAPTURE_IR       = 4'hA,
        SHIFT_IR         = 4'hB,
        EXIT1_IR         = 4'hC,
        PAUSE_IR         = 4'hD,
        EXIT2_IR         = 4'hE,
        UPDATE_IR        = 4'hF
    } tap_state_t;

    tap_state_t tap_state;

    // JTAG TCK domain shift register (72 bit = 8-bit IR + 64-bit DR)
    logic [3:0]  ir_reg;         // Instruction register (4-bit)
    logic [63:0] dr_reg;         // Data register (addr + data)
    logic [5:0]  shift_cnt;      // Shift counter

    // AXI master okuma sonucu. Bildirimi buraya alindi: asagidaki TAP
    // blogu (CAPTURE_DR) bu sinyali kullaniyor ve eskiden bildiriminden
    // once geciyordu - Vivado [Synth 8-6901] uyariyordu.
    logic [31:0] bus_rdata_result;

    // JTAG Instruction Codes
    localparam IR_BYPASS   = 4'hF;
    localparam IR_IDCODE   = 4'h1;
    localparam IR_MEM_READ = 4'h2;
    localparam IR_MEM_WRITE= 4'h3;
    localparam IR_DBG_CTRL = 4'h4;

    // TCK domain ile CLK domain arası senkronizasyon
    logic        jtag_cmd_valid;
    logic        jtag_cmd_valid_sync1, jtag_cmd_valid_sync2;
    logic [3:0]  jtag_ir_latched;
    logic [63:0] jtag_dr_latched;

    // TCK Domain - TAP State Machine (IEEE 1149.1 Compliant)
    always_ff @(posedge jtag_tck or negedge jtag_trst_n) begin
        if (!jtag_trst_n) begin
            tap_state      <= TEST_LOGIC_RESET;
            ir_reg         <= IR_BYPASS;
            dr_reg         <= 64'b0;
            shift_cnt      <= 6'b0;
            jtag_cmd_valid <= 1'b0;
            jtag_ir_latched<= IR_BYPASS;
            jtag_dr_latched<= 64'b0;
            jtag_tdo       <= 1'b0;
        end else begin
            case (tap_state)
                TEST_LOGIC_RESET: begin
                    ir_reg         <= IR_BYPASS;
                    jtag_cmd_valid <= 1'b0;
                    tap_state      <= jtag_tms ? TEST_LOGIC_RESET : RUN_TEST_IDLE;
                end
                RUN_TEST_IDLE: begin
                    jtag_cmd_valid <= 1'b0;
                    tap_state      <= jtag_tms ? SELECT_DR_SCAN : RUN_TEST_IDLE;
                end
                SELECT_DR_SCAN: begin
                    tap_state      <= jtag_tms ? SELECT_IR_SCAN : CAPTURE_DR;
                end
                CAPTURE_DR: begin
                    shift_cnt      <= 6'd0;
                    // IR koduna göre DR'ye ID veya okunan veriyi yükle
                    if (ir_reg == IR_IDCODE) begin
                        dr_reg     <= {32'h0, 32'h41524B48}; // "ARKH" identifier
                    end else if (ir_reg == IR_MEM_READ) begin
                        dr_reg     <= {bus_rdata_result, 32'h0}; // Hafızadan okunan veri
                    end
                    tap_state      <= jtag_tms ? EXIT1_DR : SHIFT_DR;
                end
                SHIFT_DR: begin
                    jtag_tdo       <= dr_reg[0];
                    dr_reg         <= {jtag_tdi, dr_reg[63:1]};
                    shift_cnt      <= shift_cnt + 6'd1;
                    tap_state      <= jtag_tms ? EXIT1_DR : SHIFT_DR;
                end
                EXIT1_DR: begin
                    tap_state      <= jtag_tms ? UPDATE_DR : PAUSE_DR;
                end
                PAUSE_DR: begin
                    tap_state      <= jtag_tms ? EXIT2_DR : PAUSE_DR;
                end
                EXIT2_DR: begin
                    tap_state      <= jtag_tms ? UPDATE_DR : SHIFT_DR;
                end
                UPDATE_DR: begin
                    jtag_dr_latched <= dr_reg;
                    jtag_ir_latched <= ir_reg;
                    jtag_cmd_valid  <= 1'b1;
                    tap_state       <= jtag_tms ? SELECT_DR_SCAN : RUN_TEST_IDLE;
                end
                SELECT_IR_SCAN: begin
                    tap_state      <= jtag_tms ? TEST_LOGIC_RESET : CAPTURE_IR;
                end
                CAPTURE_IR: begin
                    shift_cnt      <= 6'd0;
                    tap_state      <= jtag_tms ? EXIT1_IR : SHIFT_IR;
                end
                SHIFT_IR: begin
                    jtag_tdo       <= ir_reg[0];
                    ir_reg         <= {jtag_tdi, ir_reg[3:1]};
                    shift_cnt      <= shift_cnt + 6'd1;
                    tap_state      <= jtag_tms ? EXIT1_IR : SHIFT_IR;
                end
                EXIT1_IR: begin
                    tap_state      <= jtag_tms ? UPDATE_IR : PAUSE_IR;
                end
                PAUSE_IR: begin
                    tap_state      <= jtag_tms ? EXIT2_IR : PAUSE_IR;
                end
                EXIT2_IR: begin
                    tap_state      <= jtag_tms ? UPDATE_IR : SHIFT_IR;
                end
                UPDATE_IR: begin
                    jtag_ir_latched <= ir_reg;
                    tap_state      <= jtag_tms ? SELECT_DR_SCAN : RUN_TEST_IDLE;
                end
                default: tap_state <= TEST_LOGIC_RESET;
            endcase
        end
    end

    // CLK domain senkronizasyon (2 flip-flop CDC)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            jtag_cmd_valid_sync1 <= 1'b0;
            jtag_cmd_valid_sync2 <= 1'b0;
        end else begin
            jtag_cmd_valid_sync1 <= jtag_cmd_valid;
            jtag_cmd_valid_sync2 <= jtag_cmd_valid_sync1;
        end
    end

    // Rising edge detect
    logic jtag_cmd_valid_prev;
    logic jtag_cmd_pulse;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            jtag_cmd_valid_prev <= 1'b0;
        else
            jtag_cmd_valid_prev <= jtag_cmd_valid_sync2;
    end
    assign jtag_cmd_pulse = jtag_cmd_valid_sync2 && !jtag_cmd_valid_prev;

    // =========================================================================
    // Bus Access FSM (CLK Domain)
    // =========================================================================
    typedef enum logic [2:0] {
        BUS_IDLE,
        BUS_READ_ADDR,
        BUS_READ_DATA,
        BUS_WRITE_ADDR,
        BUS_WRITE_WAIT,
        BUS_COMPLETE
    } bus_state_t;

    bus_state_t bus_state;
    logic [31:0] bus_addr;
    logic [31:0] bus_wdata;
    logic        bus_is_write;
    // bus_rdata_result yukarida, TAP bloklarindan once bildirildi

    // AXI Master Kontrol
    always_comb begin
        m_axi_awaddr  = bus_addr;
        m_axi_awvalid = 1'b0;
        m_axi_wdata   = bus_wdata;
        m_axi_wstrb   = 4'hF;
        m_axi_wvalid  = 1'b0;
        m_axi_bready  = 1'b0;
        m_axi_araddr  = bus_addr;
        m_axi_arvalid = 1'b0;
        m_axi_rready  = 1'b0;

        case (bus_state)
            BUS_READ_ADDR: begin
                m_axi_arvalid = 1'b1;
            end
            BUS_READ_DATA: begin
                m_axi_rready = 1'b1;
            end
            BUS_WRITE_ADDR: begin
                m_axi_awvalid = 1'b1;
                m_axi_wvalid  = 1'b1;
            end
            BUS_WRITE_WAIT: begin
                m_axi_bready = 1'b1;
            end
            default: ;
        endcase
    end

    // Bus Access FSM - Sıralı Mantık
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bus_state       <= BUS_IDLE;
            bus_busy        <= 1'b0;
            bus_done        <= 1'b0;
            bus_addr        <= 32'b0;
            bus_wdata       <= 32'b0;
            bus_is_write    <= 1'b0;
            bus_rdata_result<= 32'b0;
        end else begin
            case (bus_state)
                BUS_IDLE: begin
                    bus_busy <= 1'b0;
                    
                    // JTAG TAP'dan gelen komut
                    if (jtag_cmd_pulse) begin
                        case (jtag_ir_latched)
                            IR_MEM_READ: begin
                                bus_addr     <= jtag_dr_latched[31:0];
                                bus_is_write <= 1'b0;
                                bus_busy     <= 1'b1;
                                bus_done     <= 1'b0;
                                bus_state    <= BUS_READ_ADDR;
                            end
                            IR_MEM_WRITE: begin
                                bus_addr     <= jtag_dr_latched[31:0];
                                bus_wdata    <= jtag_dr_latched[63:32];
                                bus_is_write <= 1'b1;
                                bus_busy     <= 1'b1;
                                bus_done     <= 1'b0;
                                bus_state    <= BUS_WRITE_ADDR;
                            end
                            IR_DBG_CTRL: begin
                                // dbg_halted is updated in a separate dedicated block to avoid multi-driver conflicts
                            end
                            default: ;
                        endcase
                    end
                    
                    // CSR üzerinden CPU kontrol komutu
                    if (reg_cmd[0]) begin
                        // Read komutu
                        bus_addr     <= reg_addr;
                        bus_is_write <= 1'b0;
                        bus_busy     <= 1'b1;
                        bus_done     <= 1'b0;
                        bus_state    <= BUS_READ_ADDR;
                    end else if (reg_cmd[1]) begin
                        // Write komutu
                        bus_addr     <= reg_addr;
                        bus_wdata    <= reg_data;
                        bus_is_write <= 1'b1;
                        bus_busy     <= 1'b1;
                        bus_done     <= 1'b0;
                        bus_state    <= BUS_WRITE_ADDR;
                    end
                end

                BUS_READ_ADDR: begin
                    if (m_axi_arready) begin
                        bus_state <= BUS_READ_DATA;
                    end
                end

                BUS_READ_DATA: begin
                    if (m_axi_rvalid) begin
                        bus_rdata_result <= m_axi_rdata;
                        bus_state        <= BUS_COMPLETE;
                    end
                end

                BUS_WRITE_ADDR: begin
                    if (m_axi_awready && m_axi_wready) begin
                        bus_state <= BUS_WRITE_WAIT;
                    end
                end

                BUS_WRITE_WAIT: begin
                    if (m_axi_bvalid) begin
                        bus_state <= BUS_COMPLETE;
                    end
                end

                BUS_COMPLETE: begin
                    bus_busy  <= 1'b0;
                    bus_done  <= 1'b1;
                    bus_state <= BUS_IDLE;
                end

                default: bus_state <= BUS_IDLE;
            endcase
        end
    end

    // =========================================================================
    // AXI4-Lite Slave - CSR Yazma Kanalı
    // =========================================================================
    logic [31:0] csr_aw_addr_lat;
    logic        csr_aw_valid_lat;
    logic [31:0] csr_w_data_lat;
    logic        csr_w_valid_lat;
    logic        csr_do_write;

    // AXI4-Lite WSTRB: yazma verisiyle birlikte bayt strobe'u da mandallanir
    logic [31:0] csr_w_mask_lat;

    assign csr_do_write = csr_aw_valid_lat && csr_w_valid_lat;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_awready   <= 1'b0;
            s_axi_wready    <= 1'b0;
            s_axi_bvalid    <= 1'b0;
            s_axi_bresp     <= 2'b00;
            csr_aw_valid_lat<= 1'b0;
            csr_w_valid_lat <= 1'b0;
            csr_aw_addr_lat <= '0;
            csr_w_data_lat  <= '0;
            csr_w_mask_lat  <= '0;
            reg_ctrl        <= 32'b0;
            reg_addr        <= 32'b0;
            reg_data        <= 32'b0;
            reg_cmd         <= 32'b0;
        end else begin
            // Cmd darbesini otomatik sıfırla
            if (reg_cmd[0] || reg_cmd[1]) reg_cmd <= 32'b0;

            // AW Handshake
            if (s_axi_awvalid && !csr_aw_valid_lat) begin
                s_axi_awready   <= 1'b1;
                csr_aw_addr_lat <= s_axi_awaddr;
                csr_aw_valid_lat<= 1'b1;
            end else begin
                s_axi_awready   <= 1'b0;
            end

            // W Handshake
            if (s_axi_wvalid && !csr_w_valid_lat) begin
                s_axi_wready    <= 1'b1;
                csr_w_data_lat  <= s_axi_wdata;
                csr_w_mask_lat  <= {{8{s_axi_wstrb[3]}}, {8{s_axi_wstrb[2]}},
                                    {8{s_axi_wstrb[1]}}, {8{s_axi_wstrb[0]}}};
                csr_w_valid_lat <= 1'b1;
            end else begin
                s_axi_wready    <= 1'b0;
            end

            // B Channel
            if (csr_do_write) begin
                csr_aw_valid_lat <= 1'b0;
                csr_w_valid_lat  <= 1'b0;
                s_axi_bvalid     <= 1'b1;
                s_axi_bresp      <= 2'b00;

                case (csr_aw_addr_lat[4:0])
                    REG_DBG_CTRL: begin
                        // dbg_halted is updated in a separate dedicated block to avoid multi-driver conflicts
                    end
                    REG_DBG_ADDR: reg_addr <= (reg_addr & ~csr_w_mask_lat) | (csr_w_data_lat & csr_w_mask_lat);
                    REG_DBG_DATA: reg_data <= (reg_data & ~csr_w_mask_lat) | (csr_w_data_lat & csr_w_mask_lat);
                    REG_DBG_CMD:  reg_cmd  <= (reg_cmd  & ~csr_w_mask_lat) | (csr_w_data_lat & csr_w_mask_lat);
                    default: ;
                endcase
            end

            if (s_axi_bvalid && s_axi_bready) begin
                s_axi_bvalid <= 1'b0;
            end
        end
    end

    // =========================================================================
    // Veri Yolu Hata Yakalama
    //
    // Kopruler bir cevrimlik DARBE uretir; burada yapiskan hale getirilir.
    // Kaynak darbe oldugu icin yazilim bayragi temizledikten sonra bayrak
    // kendiliginden geri gelmez - npu_csr'da yasadigimiz sonsuz kesme
    // dongusu burada yapisal olarak imkansiz.
    //
    // ILK hata saklanir; temizlenene kadar sonrakiler uzerine yazilmaz.
    // Bir hatanin ardindan gelen ikincil hatalar genellikle birincinin
    // sonucudur, asil bilgi ilk adrestir.
    // =========================================================================
    logic        fault_valid_r;
    logic        fault_instr_r;
    logic        fault_data_r;
    logic [31:0] fault_addr_r;
    logic        fault_clr_w;

    assign fault_clr_w = csr_do_write &&
                         (csr_aw_addr_lat[4:0] == REG_FAULT_CLR) &&
                         csr_w_data_lat[0] && csr_w_mask_lat[0];

    assign bus_fault_irq_o = fault_valid_r;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fault_valid_r <= 1'b0;
            fault_instr_r <= 1'b0;
            fault_data_r  <= 1'b0;
            fault_addr_r  <= 32'b0;
        end else if (!fault_valid_r && (instr_bus_err_i || data_bus_err_i)) begin
            // Yeni hata - temizleme ile ayni cevrimde gelirse hata kazanir,
            // boylece hicbir hata kaybolmaz.
            fault_valid_r <= 1'b1;
            fault_instr_r <= instr_bus_err_i;
            fault_data_r  <= data_bus_err_i && !instr_bus_err_i;
            fault_addr_r  <= instr_bus_err_i ? instr_bus_err_addr_i
                                             : data_bus_err_addr_i;
        end else if (fault_clr_w) begin
            fault_valid_r <= 1'b0;
            fault_instr_r <= 1'b0;
            fault_data_r  <= 1'b0;
        end
    end

    // =========================================================================
    // AXI4-Lite Slave - CSR Okuma Kanalı
    // =========================================================================
    logic [31:0] csr_ar_addr_lat;
    logic        csr_ar_valid_lat;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_arready   <= 1'b0;
            s_axi_rvalid    <= 1'b0;
            s_axi_rresp     <= 2'b00;
            s_axi_rdata     <= '0;
            csr_ar_valid_lat<= 1'b0;
            csr_ar_addr_lat <= '0;
        end else begin
            // AR Handshake
            if (s_axi_arvalid && !csr_ar_valid_lat) begin
                s_axi_arready   <= 1'b1;
                csr_ar_addr_lat <= s_axi_araddr;
                csr_ar_valid_lat<= 1'b1;
            end else begin
                s_axi_arready   <= 1'b0;
            end

            // R Channel
            if (csr_ar_valid_lat && !s_axi_rvalid) begin
                csr_ar_valid_lat <= 1'b0;
                s_axi_rvalid     <= 1'b1;
                s_axi_rresp      <= 2'b00;

                case (csr_ar_addr_lat[4:0])
                    REG_DBG_CTRL:   s_axi_rdata <= {31'b0, dbg_halted};
                    REG_DBG_STATUS: s_axi_rdata <= {29'b0, bus_busy, ~dbg_halted, dbg_halted};
                    REG_DBG_ADDR:   s_axi_rdata <= reg_addr;
                    REG_DBG_DATA:   s_axi_rdata <= bus_done ? bus_rdata_result : reg_data;
                    REG_DBG_CMD:    s_axi_rdata <= reg_cmd;
                    REG_FAULT_ST:   s_axi_rdata <= {29'b0, fault_data_r,
                                                    fault_instr_r, fault_valid_r};
                    REG_FAULT_ADDR: s_axi_rdata <= fault_addr_r;
                    default:        s_axi_rdata <= 32'b0;
                endcase
            end

            if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end
        end
    end

    // Dedicated always_ff for dbg_halted to avoid multi-driver conflicts
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dbg_halted <= 1'b0;
        end else begin
            if (csr_do_write && (csr_aw_addr_lat[4:0] == REG_DBG_CTRL)) begin
                if (csr_w_data_lat[0]) dbg_halted <= 1'b1;
                else if (csr_w_data_lat[1]) dbg_halted <= 1'b0;
            end else if (bus_state == BUS_IDLE && jtag_cmd_pulse && (jtag_ir_latched == IR_DBG_CTRL)) begin
                dbg_halted <= jtag_dr_latched[0];
            end
        end
    end

endmodule
