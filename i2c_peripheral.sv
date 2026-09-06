// ============================================================================
//  i2c_peripheral.sv - I2C Master Peripheral with AXI4-Lite Slave Interface
// ============================================================================
//  TEKNOFEST 2026 Chip Design Competition
// ============================================================================

module i2c_peripheral #(
    parameter int SYS_CLK_FREQ = 48_000_000,   // System clock in Hz
    parameter int I2C_FREQ     = 400_000        // I2C SCL frequency in Hz
) (
    // ----------------------------------------------------------------
    // System
    // ----------------------------------------------------------------
    input  logic        clk,
    input  logic        rst_n,

    // ----------------------------------------------------------------
    // AXI4-Lite Slave - Write Address Channel
    // ----------------------------------------------------------------
    input  logic [7:0]  s_axi_awaddr,
    input  logic [2:0]  s_axi_awprot,
    input  logic        s_axi_awvalid,
    output logic        s_axi_awready,

    // ----------------------------------------------------------------
    // AXI4-Lite Slave - Write Data Channel
    // ----------------------------------------------------------------
    input  logic [31:0] s_axi_wdata,
    input  logic [3:0]  s_axi_wstrb,
    input  logic        s_axi_wvalid,
    output logic        s_axi_wready,

    // ----------------------------------------------------------------
    // AXI4-Lite Slave - Write Response Channel
    // ----------------------------------------------------------------
    output logic [1:0]  s_axi_bresp,
    output logic        s_axi_bvalid,
    input  logic        s_axi_bready,

    // ----------------------------------------------------------------
    // AXI4-Lite Slave - Read Address Channel
    // ----------------------------------------------------------------
    input  logic [7:0]  s_axi_araddr,
    input  logic [2:0]  s_axi_arprot,
    input  logic        s_axi_arvalid,
    output logic        s_axi_arready,

    // ----------------------------------------------------------------
    // AXI4-Lite Slave - Read Data Channel
    // ----------------------------------------------------------------
    output logic [31:0] s_axi_rdata,
    output logic [1:0]  s_axi_rresp,
    output logic        s_axi_rvalid,
    input  logic        s_axi_rready,

    // ----------------------------------------------------------------
    // I2C Physical Interface (active-low open-drain)
    // ----------------------------------------------------------------
    output logic        sda_o,
    output logic        sda_oe,
    input  wire         sda_i,
    output logic        scl_o,
    output logic        scl_oe,
    input  wire         scl_i,

    // ----------------------------------------------------------------
    // Interrupt Output
    // ----------------------------------------------------------------
    output logic        i2c_irq
);

    // ================================================================
    //  Local Parameters
    // ================================================================
    localparam int QUARTER = SYS_CLK_FREQ / (4 * I2C_FREQ);
    localparam int CW      = $clog2(QUARTER) > 0 ? $clog2(QUARTER) : 1;

    // ================================================================
    //  Lint İzolasyonu: Kullanılmayan sinyaller
    // ================================================================
    logic unused_ok;
    assign unused_ok = &{1'b0,
                         s_axi_awprot,
                         s_axi_arprot,
                         s_axi_awaddr[7:5], s_axi_awaddr[1:0],
                         s_axi_araddr[7:5], s_axi_araddr[1:0],
                         scl_i,
                         cfg_wr_full[31:4],
                         1'b0};

    // ================================================================
    //  I2C FSM States
    // ================================================================
    typedef enum logic [3:0] {
        ST_IDLE     = 4'd0,
        ST_START    = 4'd1,
        ST_ADDR_BIT = 4'd2,
        ST_ADDR_ACK = 4'd3,
        ST_WR_BIT   = 4'd4,
        ST_WR_ACK   = 4'd5,
        ST_RD_BIT   = 4'd6,
        ST_RD_ACK   = 4'd7,
        ST_STOP     = 4'd8
    } state_t;

    // ================================================================
    //  Internal Signals
    // ================================================================
    logic [31:0] reg_nby;
    logic [31:0] wr_mask;

    assign wr_mask = {{8{s_axi_wstrb[3]}}, {8{s_axi_wstrb[2]}},
                      {8{s_axi_wstrb[1]}}, {8{s_axi_wstrb[0]}}};

    function automatic logic [31:0] wr_val(input logic [31:0] old_v);
        wr_val = (old_v & ~wr_mask) | (s_axi_wdata & wr_mask);
    endfunction

    logic [31:0] reg_adr;
    logic [31:0] reg_rdr;
    logic [31:0] reg_tdr;
    logic [3:0]  reg_cfg;

    logic [31:0] cfg_wr_full;
    logic [3:0]  cfg_wr;
    assign cfg_wr_full = ({28'd0, reg_cfg} & ~wr_mask) | (s_axi_wdata & wr_mask);
    assign cfg_wr      = cfg_wr_full[3:0];

    // -- I2C FSM --
    state_t      state;
    logic [2:0]  bit_cnt;
    logic [2:0]  byte_cnt;
    logic [7:0]  shift_out;
    logic [7:0]  shift_in;
    logic        op_rw;
    logic [2:0]  op_nby;
    logic [6:0]  op_addr;
    logic [31:0] op_tdr;
    logic [31:0] rx_data;
    logic        sda_sampled;

    // -- I2C timing --
    logic [CW-1:0] tick_cnt;
    logic [1:0]    phase;
    logic          i2c_active;
    logic          bit_done;
    logic          sample;

    logic          sda_in;
    logic          axi_wr_en;
    logic          axi_rd_en;
    logic [31:0]   rd_mux;

    // ================================================================
    //  Open-Drain Bus Assignments
    // ================================================================
    assign sda_o   = 1'b0;
    assign scl_o   = 1'b0;
    assign sda_in  = sda_i;
    assign i2c_irq = reg_cfg[1] | reg_cfg[3];

    // ================================================================
    //  I2C Timing Generator (WIDTHEXPAND çözüldü)
    // ================================================================
    assign i2c_active = (state != ST_IDLE);
    assign bit_done   = i2c_active &&
                        (phase    == 2'd3) &&
                        (tick_cnt == CW'(QUARTER - 1));
    assign sample     = i2c_active &&
                        (phase    == 2'd2) &&
                        (tick_cnt == '0);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tick_cnt <= '0;
            phase    <= 2'd0;
        end else if (!i2c_active) begin
            tick_cnt <= '0;
            phase    <= 2'd0;
        end else begin
            if (tick_cnt == CW'(QUARTER - 1)) begin
                tick_cnt <= '0;
                phase    <= phase + 2'd1;
            end else begin
                tick_cnt <= tick_cnt + 1'b1;
            end
        end
    end

    // ================================================================
    //  SCL / SDA Combinational Output Logic
    // ================================================================
    always_comb begin
        sda_oe = 1'b0;
        scl_oe = 1'b0;

        case (state)
            ST_IDLE: begin
                sda_oe = 1'b0;
                scl_oe = 1'b0;
            end

            ST_START: begin
                case (phase)
                    2'd0: begin sda_oe = 1'b0; scl_oe = 1'b0; end
                    2'd1: begin sda_oe = 1'b1; scl_oe = 1'b0; end
                    2'd2: begin sda_oe = 1'b1; scl_oe = 1'b1; end
                    2'd3: begin sda_oe = 1'b1; scl_oe = 1'b1; end
                endcase
            end

            ST_ADDR_BIT,
            ST_WR_BIT: begin
                sda_oe = ~shift_out[7];
                case (phase)
                    2'd0: scl_oe = 1'b1;
                    2'd1: scl_oe = 1'b0;
                    2'd2: scl_oe = 1'b0;
                    2'd3: scl_oe = 1'b1;
                endcase
            end

            ST_ADDR_ACK,
            ST_WR_ACK: begin
                sda_oe = 1'b0;
                case (phase)
                    2'd0: scl_oe = 1'b1;
                    2'd1: scl_oe = 1'b0;
                    2'd2: scl_oe = 1'b0;
                    2'd3: scl_oe = 1'b1;
                endcase
            end

            ST_RD_BIT: begin
                sda_oe = 1'b0;
                case (phase)
                    2'd0: scl_oe = 1'b1;
                    2'd1: scl_oe = 1'b0;
                    2'd2: scl_oe = 1'b0;
                    2'd3: scl_oe = 1'b1;
                endcase
            end

            ST_RD_ACK: begin
                sda_oe = ((byte_cnt + 3'd1) < op_nby) ? 1'b1 : 1'b0;
                case (phase)
                    2'd0: scl_oe = 1'b1;
                    2'd1: scl_oe = 1'b0;
                    2'd2: scl_oe = 1'b0;
                    2'd3: scl_oe = 1'b1;
                endcase
            end

            ST_STOP: begin
                case (phase)
                    2'd0: begin sda_oe = 1'b1; scl_oe = 1'b1; end
                    2'd1: begin sda_oe = 1'b1; scl_oe = 1'b0; end
                    2'd2: begin sda_oe = 1'b0; scl_oe = 1'b0; end
                    2'd3: begin sda_oe = 1'b0; scl_oe = 1'b0; end
                endcase
            end

            default: begin
                sda_oe = 1'b0;
                scl_oe = 1'b0;
            end
        endcase
    end

    // ================================================================
    //  AXI4-Lite Slave - Write Channel
    // ================================================================
    assign axi_wr_en     = s_axi_awvalid && s_axi_wvalid && !s_axi_bvalid;
    assign s_axi_awready = axi_wr_en;
    assign s_axi_wready  = axi_wr_en;
    assign s_axi_bresp   = 2'b00;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            s_axi_bvalid <= 1'b0;
        else if (axi_wr_en)
            s_axi_bvalid <= 1'b1;
        else if (s_axi_bvalid && s_axi_bready)
            s_axi_bvalid <= 1'b0;
    end

    // ================================================================
    //  AXI4-Lite Slave - Read Channel
    // ================================================================
    assign axi_rd_en     = s_axi_arvalid && !s_axi_rvalid;
    assign s_axi_arready = axi_rd_en;
    assign s_axi_rresp   = 2'b00;

    always_comb begin
        case (s_axi_araddr[4:2])
            3'd0:    rd_mux = reg_nby;
            3'd1:    rd_mux = reg_adr;
            3'd2:    rd_mux = reg_rdr;
            3'd3:    rd_mux = reg_tdr;
            3'd4:    rd_mux = {28'd0, reg_cfg};
            default: rd_mux = 32'd0;
        endcase
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axi_rvalid <= 1'b0;
            s_axi_rdata  <= 32'd0;
        end else if (axi_rd_en) begin
            s_axi_rvalid <= 1'b1;
            s_axi_rdata  <= rd_mux;
        end else if (s_axi_rvalid && s_axi_rready) begin
            s_axi_rvalid <= 1'b0;
        end
    end

    // ================================================================
    //  Register File + I2C Master FSM
    // ================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_nby     <= 32'd1;
            reg_adr     <= 32'd0;
            reg_rdr     <= 32'd0;
            reg_tdr     <= 32'd0;
            reg_cfg     <= 4'd0;
            state       <= ST_IDLE;
            bit_cnt     <= 3'd0;
            byte_cnt    <= 3'd0;
            shift_out   <= 8'd0;
            shift_in    <= 8'd0;
            op_rw       <= 1'b0;
            op_nby      <= 3'd1;
            op_addr     <= 7'd0;
            op_tdr      <= 32'd0;
            rx_data     <= 32'd0;
            sda_sampled <= 1'b1;
        end else begin

            if (axi_wr_en) begin
                case (s_axi_awaddr[4:2])
                    3'd0: begin
                        if (wr_val(reg_nby) == 32'd0)
                            reg_nby <= 32'd1;
                        else if (wr_val(reg_nby) > 32'd4)
                            reg_nby <= 32'd4;
                        else
                            reg_nby <= wr_val(reg_nby);
                    end

                    3'd1: if (s_axi_wstrb[0]) reg_adr <= {25'd0, s_axi_wdata[6:0]};

                    3'd2: ;

                    3'd3: reg_tdr <= wr_val(reg_tdr);

                    3'd4: begin
                        if (cfg_wr[0] && cfg_wr[2]) begin
                            reg_cfg[0] <= 1'b1;
                            reg_cfg[2] <= 1'b0;
                        end else begin
                            reg_cfg[0] <= cfg_wr[0];
                            reg_cfg[2] <= cfg_wr[2];
                        end
                        if (!cfg_wr[1]) reg_cfg[1] <= 1'b0;
                        if (!cfg_wr[3]) reg_cfg[3] <= 1'b0;
                    end

                    default: ;
                endcase
            end

            if (sample) begin
                sda_sampled <= sda_in;
            end

            case (state)
                ST_IDLE: begin
                    if (reg_cfg[0]) begin
                        op_rw     <= 1'b0;
                        op_addr   <= reg_adr[6:0];
                        op_nby    <= (reg_nby[2:0] == 3'd0) ? 3'd1 :
                                     (reg_nby > 32'd4)      ? 3'd4 :
                                                               reg_nby[2:0];
                        op_tdr    <= reg_tdr;
                        byte_cnt  <= 3'd0;
                        state     <= ST_START;
                    end else if (reg_cfg[2]) begin
                        op_rw     <= 1'b1;
                        op_addr   <= reg_adr[6:0];
                        op_nby    <= (reg_nby[2:0] == 3'd0) ? 3'd1 :
                                     (reg_nby > 32'd4)      ? 3'd4 :
                                                               reg_nby[2:0];
                        byte_cnt  <= 3'd0;
                        rx_data   <= 32'd0;
                        state     <= ST_START;
                    end
                end

                ST_START: begin
                    if (bit_done) begin
                        shift_out <= {op_addr, op_rw};
                        bit_cnt   <= 3'd0;
                        state     <= ST_ADDR_BIT;
                    end
                end

                ST_ADDR_BIT: begin
                    if (bit_done) begin
                        if (bit_cnt == 3'd7) begin
                            state <= ST_ADDR_ACK;
                        end else begin
                            shift_out <= {shift_out[6:0], 1'b0};
                            bit_cnt   <= bit_cnt + 3'd1;
                        end
                    end
                end

                ST_ADDR_ACK: begin
                    if (bit_done) begin
                        if (sda_sampled) begin
                            state <= ST_STOP;
                        end else begin
                            bit_cnt <= 3'd0;
                            if (!op_rw) begin
                                case (byte_cnt[1:0])
                                    2'd0: shift_out <= op_tdr[7:0];
                                    2'd1: shift_out <= op_tdr[15:8];
                                    2'd2: shift_out <= op_tdr[23:16];
                                    2'd3: shift_out <= op_tdr[31:24];
                                endcase
                                state <= ST_WR_BIT;
                            end else begin
                                shift_in <= 8'd0;
                                state    <= ST_RD_BIT;
                            end
                        end
                    end
                end

                ST_WR_BIT: begin
                    if (bit_done) begin
                        if (bit_cnt == 3'd7) begin
                            state <= ST_WR_ACK;
                        end else begin
                            shift_out <= {shift_out[6:0], 1'b0};
                            bit_cnt   <= bit_cnt + 3'd1;
                        end
                    end
                end

                ST_WR_ACK: begin
                    if (bit_done) begin
                        if (sda_sampled) begin
                            state <= ST_STOP;
                        end else if ((byte_cnt + 3'd1) < op_nby) begin
                            byte_cnt <= byte_cnt + 3'd1;
                            bit_cnt  <= 3'd0;
                            case (byte_cnt[1:0] + 2'd1)
                                2'd1: shift_out <= op_tdr[15:8];
                                2'd2: shift_out <= op_tdr[23:16];
                                2'd3: shift_out <= op_tdr[31:24];
                                default: shift_out <= 8'd0;
                            endcase
                            state <= ST_WR_BIT;
                        end else begin
                            state <= ST_STOP;
                        end
                    end
                end

                ST_RD_BIT: begin
                    if (sample) begin
                        shift_in <= {shift_in[6:0], sda_in};
                    end
                    if (bit_done) begin
                        if (bit_cnt == 3'd7) begin
                            case (byte_cnt[1:0])
                                2'd0: rx_data[7:0]   <= shift_in;
                                2'd1: rx_data[15:8]  <= shift_in;
                                2'd2: rx_data[23:16] <= shift_in;
                                2'd3: rx_data[31:24] <= shift_in;
                            endcase
                            state <= ST_RD_ACK;
                        end else begin
                            bit_cnt <= bit_cnt + 3'd1;
                        end
                    end
                end

                ST_RD_ACK: begin
                    if (bit_done) begin
                        if ((byte_cnt + 3'd1) < op_nby) begin
                            byte_cnt <= byte_cnt + 3'd1;
                            shift_in <= 8'd0;
                            bit_cnt  <= 3'd0;
                            state    <= ST_RD_BIT;
                        end else begin
                            state <= ST_STOP;
                        end
                    end
                end

                ST_STOP: begin
                    if (bit_done) begin
                        if (!op_rw) begin
                            reg_cfg[0] <= 1'b0;
                            reg_cfg[1] <= 1'b1;
                        end else begin
                            reg_cfg[2] <= 1'b0;
                            reg_cfg[3] <= 1'b1;
                            reg_rdr    <= rx_data;
                        end
                        state <= ST_IDLE;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
