// =============================================================================
//  axil_uvm_pkg.sv - AXI4-Lite passive UVM agent
//  TEKNOFEST 2026 - Takim Arkhe
//
//  NEDEN VAR
//
//    Sartname §4.2.2:
//      "...cevre birimlerinin ve YZ hizlandiricinin {AXI veya AXI-Lite}
//       arayuzlerinin SystemVerilog HDL ve Universal Verification
//       Methodology (UVM) kullanilarak dogrulanmasi BEKLENECEKTIR."
//
//    EK-3:
//      "Tam tesekkullu bir UVM tabanli sistem dogrulama ortamina sahip
//       olunmasi BEKLENMEMEKTEDIR. Ancak protokol kontrolu amaciyla tum AXI
//       arayuzlerine entegre edilmis agent'lar halihazirda butun veri akisini
//       PAKETLERE BOLECEGINDEN oturu yarismacilarin, isterlerse UVM-tabanli
//       olasi scoreboarding faaliyetleri gerceklemeleri cok daha kolay
//       olacaktir."
//
//    §5.2 (odul esigi):
//      "...AXI arayuzlerinin EN AZINDAN PROTOCOL CHECK duzeyinde AXI
//       agent'lariyla dogrulanmasi."
//
//  KAPSAM - NEDEN "PASSIVE"
//
//    Bu agent SURUCU ICERMEZ; yalnizca dinler (passive monitor). Sebebi:
//    tasarim zaten gercek trafikle (CPU, DMA, NPU) suruluyor ve o trafik
//    self-checking sistem testleriyle dogrulaniyor. Buraya bir surucu
//    eklemek mevcut testleri tekrar etmek olurdu.
//
//    Agent'in kattigi sey: ham sinyalleri ISLEM (transaction) nesnelerine
//    cevirmek, protokol kurallarini islem duzeyinde denetlemek ve kosum
//    sonunda sayisal ozet vermek.
//
//  MEVCUT SVA ILE ILISKI
//
//    rtl/Memory/axil_protocol_checker.sv KORUNUR ve calismaya devam eder.
//    Ikisi FARKLI seviyede denetler:
//        SVA   - sinyal/cevrim duzeyi (valid dusmemeli, adres degismemeli)
//        UVM   - islem duzeyi (her adrese bir yanit, yanit kodu gecerli,
//                yarim kalmis islem yok)
//    EK-3 de tam bunu oneriyor.
// =============================================================================

package axil_uvm_pkg;

    import uvm_pkg::*;
`include "uvm_macros.svh"

    // -------------------------------------------------------------------------
    // ISLEM NESNESI
    // -------------------------------------------------------------------------
    typedef enum { AXIL_OKUMA, AXIL_YAZMA } axil_tur_e;

    class axil_islem extends uvm_sequence_item;
        rand axil_tur_e   tur;
        rand bit [31:0]   adres;
        rand bit [31:0]   veri;
        rand bit [3:0]    strb;
        rand bit [1:0]    yanit;
        time              baslangic;
        time              bitis;

        `uvm_object_utils_begin(axil_islem)
            `uvm_field_enum(axil_tur_e, tur, UVM_ALL_ON)
            `uvm_field_int(adres, UVM_ALL_ON | UVM_HEX)
            `uvm_field_int(veri,  UVM_ALL_ON | UVM_HEX)
            `uvm_field_int(strb,  UVM_ALL_ON | UVM_HEX)
            `uvm_field_int(yanit, UVM_ALL_ON)
        `uvm_object_utils_end

        function new(string name = "axil_islem");
            super.new(name);
        endfunction

        function string ozet();
            return $sformatf("%s adres=0x%08h veri=0x%08h yanit=%0d",
                             tur.name(), adres, veri, yanit);
        endfunction
    endclass

    // -------------------------------------------------------------------------
    // SANAL ARAYUZ
    //
    // Monitor sinyalleri buradan okur. Baglanti tb tarafinda
    // uvm_config_db ile yapilir.
    // -------------------------------------------------------------------------
    typedef virtual axil_if axil_vif;

    // -------------------------------------------------------------------------
    // MONITOR - ham sinyalleri islemlere cevirir
    // -------------------------------------------------------------------------
    class axil_monitor extends uvm_monitor;
        `uvm_component_utils(axil_monitor)

        axil_vif vif;
        uvm_analysis_port #(axil_islem) ap;

        // Sayaclar - kosum sonunda raporlanir.
        //
        // NEDEN 'static': testbench kendi $finish'ini cagirir ve UVM'in
        // report_phase'i O ZAMAN HIC KOSMAZ - ozet kayboluyordu. static
        // olunca sayaclar sinif kapsamindan (axil_monitor::okuma_sayisi)
        // okunabilir ve testbench'teki 'final' blogu ozeti basabilir.
        // Agent tek ornekli oldugu icin static olmasi anlam kaybettirmez.
        static int unsigned okuma_sayisi;
        static int unsigned yazma_sayisi;
        static int unsigned hatali_yanit;

        function new(string name, uvm_component parent);
            super.new(name, parent);
            ap = new("ap", this);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(axil_vif)::get(this, "", "vif", vif))
                `uvm_fatal(get_type_name(), "sanal arayuz bulunamadi (vif)")
        endfunction

        task run_phase(uvm_phase phase);
            fork
                okuma_izle();
                yazma_izle();
            join
        endtask

        // --- Okuma kanali: AR el sikismasi -> R el sikismasi ---
        //
        // KUYRUK GEREKLI - tek slotlu bayrak YETMEZ.
        //
        // Ilk yazimda tek bir 'bekliyor' bayragi vardi. Bizim AXI4-Lite
        // slave'imiz arready'yi HER cevrim yuksek tutar ve okuma verisi bir
        // cevrim sonra doner; yani AR(n+1) ile R(n) AYNI cevrimde el sikisir.
        // Tek slot bu durumda yeni adresi eskinin uzerine yazip R(n)'i YENI
        // adresle esliyordu ve islem sayisi da eksik cikiyordu:
        //     ham AR el sikismasi 81024  ->  monitor 78344  (2680 kayip)
        // Kuyruk hem sayimi hem adres-veri eslemesini dogru yapar.
        task okuma_izle();
            axil_islem it;
            bit [31:0] adres_kuyruk[$];
            time       zaman_kuyruk[$];
            bit [31:0] adres;
            time       t0;

            forever begin
                @(posedge vif.clk);
                if (!vif.rst_n) begin
                    adres_kuyruk.delete();
                    zaman_kuyruk.delete();
                    continue;
                end

                // SIRA ONEMLI: once R (o cevrimde biten islem), sonra AR.
                // Tersi olursa ayni cevrimde gelen yeni adres, biten islemin
                // adresi sanilir.
                if (vif.rvalid && vif.rready) begin
                    if (adres_kuyruk.size() == 0) begin
                        `uvm_error(get_type_name(),
                            "AR olmadan R yaniti geldi - eslesmeyen okuma")
                    end else begin
                        adres = adres_kuyruk.pop_front();
                        t0    = zaman_kuyruk.pop_front();
                        it            = axil_islem::type_id::create("okuma");
                        it.tur        = AXIL_OKUMA;
                        it.adres      = adres;
                        it.veri       = vif.rdata;
                        it.yanit      = vif.rresp;
                        it.baslangic  = t0;
                        it.bitis      = $time;
                        okuma_sayisi++;
                        if (vif.rresp != 2'b00) hatali_yanit++;
                        ap.write(it);
                    end
                end

                if (vif.arvalid && vif.arready) begin
                    adres_kuyruk.push_back(vif.araddr);
                    zaman_kuyruk.push_back($time);
                end
            end
        endtask

        // --- Yazma kanali: AW+W el sikismasi -> B el sikismasi ---
        //
        // AW ve W AYRI cevrimlerde gelebilir - AXI4-Lite'ta kanallar
        // bagimsizdir. Bu, veriyolu incelemesinde bulunan V1 hatasinin
        // (DMA ikisini ayni cevrimde varsayiyordu) izlem karsiligidir.
        // Okuma kanalindaki gerekce ile burada da AYRI kuyruklar kullanilir.
        task yazma_izle();
            axil_islem it;
            bit [31:0] aw_kuyruk[$];
            time       aw_zaman[$];
            bit [31:0] w_kuyruk[$];
            bit [3:0]  strb_kuyruk[$];
            time       w_zaman[$];
            time       t0;

            forever begin
                @(posedge vif.clk);
                if (!vif.rst_n) begin
                    aw_kuyruk.delete();  aw_zaman.delete();
                    w_kuyruk.delete();   strb_kuyruk.delete();  w_zaman.delete();
                    continue;
                end

                // Once B (biten islem), sonra AW/W - okuma ile ayni gerekce
                if (vif.bvalid && vif.bready) begin
                    if (aw_kuyruk.size() == 0 || w_kuyruk.size() == 0) begin
                        `uvm_error(get_type_name(),
                            "AW/W tamamlanmadan B yaniti geldi - eslesmeyen yazma")
                    end else begin
                        it            = axil_islem::type_id::create("yazma");
                        it.tur        = AXIL_YAZMA;
                        it.adres      = aw_kuyruk.pop_front();
                        it.veri       = w_kuyruk.pop_front();
                        it.strb       = strb_kuyruk.pop_front();
                        it.yanit      = vif.bresp;
                        // Islem, AW ve W'den HANGISI ONCE geldiyse orada baslar
                        t0            = aw_zaman.pop_front();
                        if (w_zaman[0] < t0) t0 = w_zaman[0];
                        void'(w_zaman.pop_front());
                        it.baslangic  = t0;
                        it.bitis      = $time;
                        yazma_sayisi++;
                        if (vif.bresp != 2'b00) hatali_yanit++;
                        ap.write(it);
                    end
                end

                if (vif.awvalid && vif.awready) begin
                    aw_kuyruk.push_back(vif.awaddr);
                    aw_zaman.push_back($time);
                end
                if (vif.wvalid && vif.wready) begin
                    w_kuyruk.push_back(vif.wdata);
                    strb_kuyruk.push_back(vif.wstrb);
                    w_zaman.push_back($time);
                end
            end
        endtask

        function void report_phase(uvm_phase phase);
            `uvm_info(get_type_name(),
                $sformatf("islem ozeti: okuma=%0d yazma=%0d hatali_yanit=%0d",
                          okuma_sayisi, yazma_sayisi, hatali_yanit), UVM_LOW)
        endfunction
    endclass

    // -------------------------------------------------------------------------
    // SCOREBOARD - islem duzeyi denetimler
    //
    // SVA sinyal duzeyinde denetler; burasi ISLEM duzeyinde:
    //   - yanit kodu gecerli mi (OKAY/SLVERR/DECERR disinda deger olmamali)
    //   - islem suresi makul mu (asili kalmis islem var mi)
    // -------------------------------------------------------------------------
    class axil_scoreboard extends uvm_scoreboard;
        `uvm_component_utils(axil_scoreboard)

        uvm_analysis_imp #(axil_islem, axil_scoreboard) analiz;

        // static - gerekcesi axil_monitor'daki ile ayni
        static int unsigned toplam;
        static int unsigned gecersiz_yanit;
        static int unsigned uzun_islem;

        // AXI4-Lite'ta RESP[1:0] yalnizca 00/10/11 olabilir; 01 (EXOKAY)
        // yalnizca AXI4 exclusive erisimde gecerlidir ve Lite'ta YOKTUR.
        localparam time UZUN_ESIK = 10000;   // 10 us

        function new(string name, uvm_component parent);
            super.new(name, parent);
            analiz = new("analiz", this);
        endfunction

        function void write(axil_islem it);
            toplam++;
            if (it.yanit == 2'b01) begin
                gecersiz_yanit++;
                `uvm_error(get_type_name(),
                    $sformatf("AXI4-Lite'ta gecersiz yanit EXOKAY: %s", it.ozet()))
            end
            if ((it.bitis - it.baslangic) > UZUN_ESIK) begin
                uzun_islem++;
                `uvm_warning(get_type_name(),
                    $sformatf("islem %0t surdu: %s", it.bitis - it.baslangic, it.ozet()))
            end
        endfunction

        function void report_phase(uvm_phase phase);
            `uvm_info(get_type_name(),
                $sformatf("scoreboard: toplam=%0d gecersiz_yanit=%0d uzun=%0d",
                          toplam, gecersiz_yanit, uzun_islem), UVM_LOW)
        endfunction
    endclass

    // -------------------------------------------------------------------------
    // AGENT (passive)
    // -------------------------------------------------------------------------
    class axil_agent extends uvm_agent;
        `uvm_component_utils(axil_agent)

        axil_monitor mon;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            // PASSIVE: surucu ve sequencer olusturulmaz.
            set_int_local("is_active", UVM_PASSIVE);
            mon = axil_monitor::type_id::create("mon", this);
        endfunction
    endclass

    // -------------------------------------------------------------------------
    // ENV
    // -------------------------------------------------------------------------
    class axil_env extends uvm_env;
        `uvm_component_utils(axil_env)

        axil_agent      agent;
        axil_scoreboard sb;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            agent = axil_agent::type_id::create("agent", this);
            sb    = axil_scoreboard::type_id::create("sb", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            agent.mon.ap.connect(sb.analiz);
        endfunction
    endclass

    // -------------------------------------------------------------------------
    // TEST
    //
    // Surucu yok; test yalnizca ortami kurar ve simulasyonun bitmesini
    // bekler. Gercek trafik CPU/DMA/NPU tarafindan uretilir.
    // -------------------------------------------------------------------------
    class axil_passive_test extends uvm_test;
        `uvm_component_utils(axil_passive_test)

        axil_env env;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            env = axil_env::type_id::create("env", this);
        endfunction

        // ---------------------------------------------------------------------
        // OBJECTION - UVM'i simulasyon boyunca AYAKTA TUTAR
        //
        // Ilk yazimda run_phase yoktu ve UVM ZAMAN 0'DA bitiyordu: hicbir
        // faz objection tutmadigi icin run_test() hemen $finish cagiriyor,
        // tasarim hic kosmadan simulasyon kapaniyordu.
        //   "islem ozeti: okuma=0 yazma=0"  <-- belirti buydu
        //
        // Passive agent surucu icermez, yani kendi basina bitis kosulu da
        // yoktur. Objection burada alinir ve BIRAKILMAZ; simulasyonu
        // testbench'in kendi $finish'i sonlandirir. Bu, passive/monitor-only
        // ortamlarda standart yaklasimdir.
        // ---------------------------------------------------------------------
        task run_phase(uvm_phase phase);
            phase.raise_objection(this, "passive izleme suruyor");
            // Testbench $finish cagirana kadar bekle
            wait (0);
        endtask
    endclass

    // -------------------------------------------------------------------------
    // OZET YAZDIRMA - testbench'in 'final' blogundan cagrilir
    //
    // report_phase'e guvenemeyiz: testbench $finish'i UVM disindan cagirir,
    // o yuzden UVM fazlari tamamlanmadan simulasyon biter. 'final' blogu ise
    // $finish'te MUTLAKA kosar. Ozet ve gecme/kalma karari buraya tasindi.
    //
    // Donus: 0 = temiz, >0 = protokol ihlali sayisi
    // -------------------------------------------------------------------------
    function automatic int axil_ozet_yaz();
        int ihlal;
        ihlal = axil_scoreboard::gecersiz_yanit + axil_monitor::hatali_yanit;
        $display("");
        $display("================= UVM AXI4-Lite PASSIVE AGENT =================");
        $display("  izlenen arayuz     : NPU motoru -> TCM (AXI4-Lite master)");
        $display("  okuma islemi       : %0d", axil_monitor::okuma_sayisi);
        $display("  yazma islemi       : %0d", axil_monitor::yazma_sayisi);
        $display("  toplam islem       : %0d", axil_scoreboard::toplam);
        $display("  hatali yanit       : %0d  (SLVERR/DECERR)",
                 axil_monitor::hatali_yanit);
        $display("  gecersiz yanit kodu: %0d  (AXI4-Lite'ta EXOKAY olamaz)",
                 axil_scoreboard::gecersiz_yanit);
        $display("  asili kalmis islem : %0d  (>10us)", axil_scoreboard::uzun_islem);
        // Denetim isaretleri: regresyon betigi [OK]/[HATA] sayar.
        // Isaretsiz $display satirlari "DENETIM YOK" olarak gorunuyordu.
        if (axil_scoreboard::toplam == 0)
            $display("  [HATA] hic islem yakalanmadi - agent bagli degil mi?");
        else
            $display("  [OK]   %0d AXI4-Lite islemi yakalandi ve paketlendi",
                     axil_scoreboard::toplam);

        if (ihlal == 0)
            $display("  [OK]   tum yanit kodlari gecerli (OKAY), protokol ihlali yok");
        else
            $display("  [HATA] %0d protokol ihlali", ihlal);

        if (axil_scoreboard::uzun_islem == 0)
            $display("  [OK]   asili kalmis islem yok (hepsi <10us tamamlandi)");
        else
            $display("  [HATA] %0d islem asili kaldi", axil_scoreboard::uzun_islem);

        $display("==============================================================");
        return ihlal;
    endfunction

endpackage
