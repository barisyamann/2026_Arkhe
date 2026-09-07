// =============================================================================
//  axil_if.sv - AXI4-Lite arayuzu (UVM passive monitor icin)
//  TEKNOFEST 2026 - Takim Arkhe
//
//  Monitor sinyalleri sanal arayuz (virtual interface) uzerinden okur.
//  Boylece UVM ortami tasarim hiyerarsisinden BAGIMSIZ kalir: hangi
//  arayuze baglanacagi testbench tarafinda uvm_config_db ile belirlenir.
//
//  Yalnizca GOZLEM icindir - hicbir sinyal surulmez. Bu yuzden tum
//  sinyaller 'logic' olarak tanimlanir ve modport kullanilmaz; agent
//  passive oldugu icin yon cakismasi olusmaz.
// =============================================================================

interface axil_if (input logic clk, input logic rst_n);

    // Yazma adres kanali
    logic [31:0] awaddr;
    logic        awvalid;
    logic        awready;

    // Yazma veri kanali
    logic [31:0] wdata;
    logic [3:0]  wstrb;
    logic        wvalid;
    logic        wready;

    // Yazma yanit kanali
    logic [1:0]  bresp;
    logic        bvalid;
    logic        bready;

    // Okuma adres kanali
    logic [31:0] araddr;
    logic        arvalid;
    logic        arready;

    // Okuma veri kanali
    logic [31:0] rdata;
    logic [1:0]  rresp;
    logic        rvalid;
    logic        rready;

endinterface
