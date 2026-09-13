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

        // -------------------------------------------------------------------
        // SINYAL DUZEYI KARARLILIK SAYACLARI (8 Eylul 2026'da eklendi)
        //
        // Islem duzeyi denetimi yalnizca TAMAMLANMIS islemlere bakar; bir
        // islem tamamlanirken protokolu ihlal etse bile orada gorunmez.
        // AXI4-Lite spesifikasyonu (ARM IHI0022, A3.2.1) sunu sart kosar:
        //
        //   "Once VALID yukseldiginde, READY gelene kadar dusurulemez ve
        //    bilgi sinyalleri (ADDR/DATA/STRB) degistirilemez."
        //
        // Bu sayaclar el sikisma oncesi geri cekilme ve adres/veri kaymasi
        // hatalarini yakalar. Ikisi de islem SAYISINI bozmadan VERIYI bozan
        // hatalardir, dolayisiyla mevcut denetimlerin koru noktasidir.
        // -------------------------------------------------------------------
        static int unsigned ar_kararsiz;
        static int unsigned aw_kararsiz;
        static int unsigned w_kararsiz;
        static int unsigned r_kararsiz;
        static int unsigned b_kararsiz;
        static int unsigned x_bilinmeyen;
        // 12 Eylul 2026: okuma verisindeki X ayri sayilir.
        //   rdata_x_baslatilmamis : Data RAM'in yazilmamis kelimeleri
        //       (simulasyon artefakti - gercek SRAM X uretmez)
        //   rdata_x_diger         : baska kaynaklardan X -> GERCEK ihlal
        static int unsigned rdata_x_baslatilmamis;
        static int unsigned rdata_x_diger;

        // --- 12 Eylul 2026'da eklenen denetimler ---
        static int unsigned rst_valid_hata;    // reset'te VALID yuksekti
        static int unsigned fazlalik_yanit;    // istenmeden gelen B/R
        static int unsigned exokay_hata;       // AXI4-Lite'ta RRESP=01 yasak
        static int unsigned aw_w_gecikme;      // AW ile W arasi >16 cevrim
        static int unsigned en_uzun_aw_w;      // en buyuk AW-W araligi

        // -------------------------------------------------------------------
        // FONKSIYONEL KAPSAM (8 Eylul 2026'da eklendi)
        //
        // Sartname EK-3 "UVM-tabanli olasi scoreboarding" diyor; kapsam
        // olcumu bunun dogal parcasidir. Sayilar tek basina bir sey
        // KANITLAMAZ ama neyin HIC uyarilmadigini gosterir - dogrulamanin
        // kor noktalari boyle bulunur.
        //
        // Burada olculen: hangi WSTRB desenleri gorundu, adres hangi
        // araliklara dagildi, ardisik okuma serisi ne kadar uzadi.
        // -------------------------------------------------------------------
        static int unsigned strb_deseni [16];      // WSTRB 0..15 gorulme sayisi
        static int unsigned ardisik_okuma;         // en uzun okuma serisi
        static int unsigned mevcut_seri;
        static bit          onceki_okumaydi;
        static int unsigned adres_min;
        static int unsigned adres_max;
        static bit          adres_ilk;

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
                kararlilik_izle();
            join
        endtask

        // -------------------------------------------------------------------
        // AXI4-Lite el sikisma kararliligi (ARM IHI0022 A3.2.1)
        //
        // Her kanal icin kural: VALID yuksek ve READY dusukken, BIR SONRAKI
        // cevrimde VALID hala yuksek olmali ve bilgi sinyalleri AYNI
        // kalmalidir. Ayrica el sikisan cevrimde hicbir bilgi sinyali X/Z
        // olmamalidir - sentez sonrasi netlistte veya eksik reset'te
        // bilinmeyen deger tasinabilir ve islem duzeyi bunu gormez.
        // -------------------------------------------------------------------
        task kararlilik_izle();
            bit        ar_bekle, aw_bekle, w_bekle, r_bekle, b_bekle;
            bit [31:0] ar_adr, aw_adr, w_veri, r_veri;
            bit [3:0]  w_strb;
            bit [1:0]  r_yanit, b_yanit;

            ar_bekle = 1'b0; aw_bekle = 1'b0; w_bekle = 1'b0;
            r_bekle  = 1'b0; b_bekle  = 1'b0;

            forever begin
                @(posedge vif.clk);
                if (!vif.rst_n) begin
                    // -------------------------------------------------------
                    // RESET DENETIMI (ARM IHI0022 A3.1.2)
                    //
                    // Reset aktifken hicbir kanalda VALID yuksek olmamalidir.
                    // Sentez sonrasi netlistte reset agi eksikse veya bir
                    // yazmac reset'siz kalmissa burada yakalanir.
                    // -------------------------------------------------------
                    if (vif.arvalid || vif.awvalid || vif.wvalid) begin
                        rst_valid_hata++;
                        `uvm_error(get_type_name(), $sformatf(
                            "reset aktifken VALID yuksek (ar=%0b aw=%0b w=%0b)",
                            vif.arvalid, vif.awvalid, vif.wvalid))
                    end
                    ar_bekle = 1'b0; aw_bekle = 1'b0; w_bekle = 1'b0;
                    r_bekle  = 1'b0; b_bekle  = 1'b0;
                    continue;
                end

                // --- AR kanali ---
                if (ar_bekle) begin
                    if (!vif.arvalid) begin
                        ar_kararsiz++;
                        `uvm_error(get_type_name(),
                            "AR: arready gelmeden arvalid dusuruldu")
                    end
                    else if (vif.araddr !== ar_adr) begin
                        ar_kararsiz++;
                        `uvm_error(get_type_name(), $sformatf(
                            "AR: el sikismadan once araddr degisti 0x%08h -> 0x%08h",
                            ar_adr, vif.araddr))
                    end
                end
                ar_bekle = vif.arvalid && !vif.arready;
                if (ar_bekle) ar_adr = vif.araddr;

                // --- AW kanali ---
                if (aw_bekle) begin
                    if (!vif.awvalid) begin
                        aw_kararsiz++;
                        `uvm_error(get_type_name(),
                            "AW: awready gelmeden awvalid dusuruldu")
                    end
                    else if (vif.awaddr !== aw_adr) begin
                        aw_kararsiz++;
                        `uvm_error(get_type_name(), $sformatf(
                            "AW: el sikismadan once awaddr degisti 0x%08h -> 0x%08h",
                            aw_adr, vif.awaddr))
                    end
                end
                aw_bekle = vif.awvalid && !vif.awready;
                if (aw_bekle) aw_adr = vif.awaddr;

                // --- W kanali ---
                if (w_bekle) begin
                    if (!vif.wvalid) begin
                        w_kararsiz++;
                        `uvm_error(get_type_name(),
                            "W: wready gelmeden wvalid dusuruldu")
                    end
                    else if (vif.wdata !== w_veri || vif.wstrb !== w_strb) begin
                        w_kararsiz++;
                        `uvm_error(get_type_name(),
                            "W: el sikismadan once wdata/wstrb degisti")
                    end
                end
                w_bekle = vif.wvalid && !vif.wready;
                if (w_bekle) begin
                    w_veri = vif.wdata;
                    w_strb = vif.wstrb;
                end

                // --- R kanali (slave -> master) ---
                if (r_bekle) begin
                    if (!vif.rvalid) begin
                        r_kararsiz++;
                        `uvm_error(get_type_name(),
                            "R: rready gelmeden rvalid dusuruldu")
                    end
                    // EL SIKISMA CEVRIMI DENETIMDEN MUAFTIR
                    //
                    // 12 Eylul 2026: ikinci agent (SoC ana yolu) eklendikten
                    // sonra 239.665 islemde 3 "R kararsiz" ihlali cikti:
                    //     0x00000033 -> 0xXXXXXX33   (rvalid=1 rready=1)
                    //
                    // Tanilandi ve BU DENETIMIN HATASI oldugu bulundu.
                    // ARM IHI0022 A3.2.1 sunu der: VALID yuksek ve READY
                    // DUSUKKEN bilgi sinyalleri degismemelidir. READY
                    // yukseldiginde EL SIKISMA TAMAMLANIR ve slave bir
                    // sonraki cevrim icin sinyallerini serbest birakabilir.
                    //
                    // Onceki surum `!vif.rready` kosulunu koymadigi icin
                    // el sikismanin GERCEKLESTIGI cevrimde de karsilastirma
                    // yapiyordu. O cevrimde veri zaten teslim edilmistir;
                    // degismesi ihlal DEGILDIR.
                    //
                    // Bu ihlaller ilk agent'ta (NPU motoru) hic gorulmedi
                    // cunku o slave RVALID'i RREADY gelene kadar sabit
                    // tutuyor; SoC yolundaki cevre birimleri ise el
                    // sikisma cevriminde birakiyor - ikisi de GECERLIDIR.
                    else if (!vif.rready &&
                             (vif.rdata !== r_veri || vif.rresp !== r_yanit)) begin
                        r_kararsiz++;
                        `uvm_error(get_type_name(), $sformatf(
                            "R kararsiz: 0x%08h/%0d -> 0x%08h/%0d (rready dusukken degisti)",
                            r_veri, r_yanit, vif.rdata, vif.rresp))
                    end
                end
                r_bekle = vif.rvalid && !vif.rready;
                if (r_bekle) begin
                    r_veri  = vif.rdata;
                    r_yanit = vif.rresp;
                end

                // --- B kanali ---
                if (b_bekle) begin
                    if (!vif.bvalid) begin
                        b_kararsiz++;
                        `uvm_error(get_type_name(),
                            "B: bready gelmeden bvalid dusuruldu")
                    end
                    else if (vif.bresp !== b_yanit) begin
                        b_kararsiz++;
                        `uvm_error(get_type_name(),
                            "B: el sikismadan once bresp degisti")
                    end
                end
                b_bekle = vif.bvalid && !vif.bready;
                if (b_bekle) b_yanit = vif.bresp;

                // --- El sikisan cevrimlerde X/Z denetimi ---
                if (vif.arvalid && vif.arready && $isunknown(vif.araddr)) begin
                    x_bilinmeyen++;
                    `uvm_error(get_type_name(), "AR el sikismasinda araddr X/Z")
                end
                if (vif.wvalid && vif.wready &&
                    ($isunknown(vif.wdata) || $isunknown(vif.wstrb))) begin
                    x_bilinmeyen++;
                    `uvm_error(get_type_name(), "W el sikismasinda wdata/wstrb X/Z")
                end
                if (vif.rvalid && vif.rready && $isunknown(vif.rresp)) begin
                    x_bilinmeyen++;
                    `uvm_error(get_type_name(), "R el sikismasinda rresp X/Z")
                end
                // 12 Eylul 2026: rdata da denetlenir.
                // Onceki surum yalniz rresp'e bakiyordu; okuma VERISININ
                // X/Z olmasi daha ciddidir - CPU o degeri kullanir.
                // OKUMA VERISINDE X/Z
                //
                // Onceki surum yalniz `rresp`'i denetliyordu. Okuma
                // VERISININ X olmasi daha ciddidir - CPU o degeri kullanir.
                //
                // KAYNAK AYRIMI (olculdu, bkz. RDATA_X_BULGUSU.md):
                //   Data RAM (sram_module.sv:313) davranissal dizidir ve
                //   BASLATILMAZ ("saf BRAM cikarimi"). Bayt yazilan bir
                //   adres 32 bit okunursa ust bitler X kalir:
                //       wstrb=0001 ile 0x33 yazildi -> 0xXXXXXX33 okundu
                //   Bu SIMULASYON ARTEFAKTIDIR; gercek SRAM/BRAM X
                //   uretmez, her hucre belirli bir deger tutar.
                //
                //   Alt bayt GECERLI oldugu icin bu orunty tanınır:
                //   yalnizca ust bitler X ise "baslatilmamis bellek"
                //   sayilir ve UYARI olarak raporlanir.
                //
                //   TAMAMEN X olan veya alt biti de X olan bir okuma
                //   BASKA bir sorundur ve GERCEK ihlal sayilir.
                if (vif.rvalid && vif.rready && $isunknown(vif.rdata)) begin
                    if (!$isunknown(vif.rdata[7:0])) begin
                        rdata_x_baslatilmamis++;
                    end else begin
                        rdata_x_diger++;
                        x_bilinmeyen++;
                        `uvm_error(get_type_name(), $sformatf(
                            "R el sikismasinda rdata TAMAMEN X: 0x%08h", vif.rdata))
                    end
                end
            end
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

        // 8 Eylul 2026'da eklendi - islem duzeyi kapsama ve ek denetimler.
        // Sartname EK-3 "UVM-tabanli olasi scoreboarding faaliyetleri"
        // ifadesine karsilik gelir; §5.2 protocol check esigini asar.
        static int unsigned okuma_sayisi;
        static int unsigned yazma_sayisi;
        static int unsigned hatali_yanit;      // SLVERR/DECERR
        static int unsigned bos_strb;          // yazmada strb == 0
        static int unsigned hizasiz_adres;     // adres[1:0] != 0
        static int unsigned kismi_yazma;       // strb tam kelime degil
        static time         ilk_islem_ani;
        static time         son_islem_ani;

        // ---------------------------------------------------------------
        //  U5 (13 Eylul 2026): REFERANS MODEL - VERI DOGRULUGU
        //
        //  NEDEN EKLENDI
        //    Scoreboard 13 Eylul'e kadar yalnizca PROTOKOL denetliyordu:
        //    VALID kararliligi, yanit kodu, hizalama, X/Z, WSTRB!=0...
        //    Ama "yazilan deger geri okundugunda ayni mi" HIC
        //    kontrol edilmiyordu.
        //
        //    Bu bir bosluktur: hakemlik hatasi, adres cozme hatasi veya
        //    WSTRB uygulama hatasi protokolu BOZMADAN veriyi bozabilir.
        //    Oyle bir hata tum protokol denetimlerinden gecerdi.
        //
        //  NASIL CALISIR
        //    Iliskisel dizi bir referans bellek tutar. Her yazmada
        //    WSTRB'ye gore bayt birlestirme yapilir; her okumada, o
        //    adres daha once yazilmissa, beklenen deger ile karsilastirilir.
        //
        //    Yalnizca DAHA ONCE YAZILMIS adresler denetlenir - baslangic
        //    icerigi bilinmeyen bellek bolgeleri sessizce atlanir
        //    (yanlis alarm uretmemek icin).
        // ---------------------------------------------------------------
        static bit [31:0]   ref_bellek [bit [31:0]];
        static int unsigned ref_dogrulanan;    // yazip geri okunan, ESLESTI
        static int unsigned ref_uyusmazlik;    // yazip geri okunan, ESLESMEDI
        static int unsigned ref_ilk_hata_adres;
        static bit [31:0]   ref_ilk_hata_beklenen;
        static bit [31:0]   ref_ilk_hata_gorulen;
        static int unsigned en_uzun_ns;

        // --- 12 Eylul 2026: kapsam genisletmesi ---
        static int unsigned exokay_hata;       // AXI4-Lite'ta RRESP=01 YASAK
        static int unsigned tam_kelime_yazma;  // strb == 4'b1111
        static int unsigned bayt_yazma;        // tek bayt (strb'de 1 bit)
        static int unsigned yarim_yazma;       // iki bayt

        // Kapsam sonucu ozet yazicidan okunabilsin diye STATIK tutulur.
        // covergroup bir ORNEK uyesidir; axil_ozet_yaz() statik bir
        // fonksiyondur ve ornege erisemez. write() her islemde tazeler.
        //
        // NEDEN GEREKLI: testbench $finish ile biter ve UVM report_phase
        // HIC CALISMAZ - kapsam olculuyor ama gorulmuyordu.
        static real kapsam_tur;
        static real kapsam_bolge;
        static real kapsam_strb;
        static real kapsam_yanit;
        static real kapsam_toplam;

        // ---------------------------------------------------------------
        // FONKSIYONEL KAPSAM
        //
        // Sartname EK-3 "UVM-tabanli scoreboarding" maddesine ek olarak,
        // gorulen islem UZAYININ olculmesi. Regresyon sonunda hangi
        // kombinasyonlarin HIC gorulmedigi raporlanir - bu, testin
        // kapsamadigi alanlari acik eder.
        // ---------------------------------------------------------------
        bit [31:0] kg_adres;
        axil_tur_e kg_tur;
        bit [3:0]  kg_strb;
        bit [1:0]  kg_yanit;

        covergroup islem_kapsami;
            option.per_instance = 1;
            option.name = "axil_islem_kapsami";

            tur_cp : coverpoint kg_tur {
                bins okuma = {AXIL_OKUMA};
                bins yazma = {AXIL_YAZMA};
            }

            // ---------------------------------------------------------
            // ADRES KAPSAMI - BAGLANTI NOKTASINA GORE
            //
            // Ilk yazimda 12 SoC bolgesi (bootrom, gpio, uart...) bin
            // olarak tanimlanmisti ve kapsam %8,3 cikiyordu. Olculdu:
            // bu YANILTICI bir sayidir, cunku agent SoC yoluna DEGIL,
            // NPU motorunun kendi AXI arayuzune baglidir:
            //
            //     tb_soc_top.sv:1617  npu_eng_if.awaddr = uut.u_npu.eng_awaddr
            //
            // Motor yalnizca KENDI TCM'ine erisir (0x0 - 0x76bc). Diger
            // 11 bolgeyi gormesi MUMKUN DEGILDIR; onlari bin olarak
            // saymak kapsami olculemeyen bir hedefe gore raporlar.
            //
            // Bu yuzden binler TCM icindeki BOLGELERE gore tanimlandi.
            // TCM yerlesimi (npu_tcm_sram.sv ve npu_compute_engine.sv):
            //     0      .. 489    girdi tensoru   (490 kelime)
            //     490    .. 3583   serbest
            //     3584   .. 7583   FC agirliklari  (4000 kelime)
            //     7596   .. 7599   cikis
            // Bayt adresi = kelime * 4
            // ---------------------------------------------------------
            bolge_cp : coverpoint kg_adres {
                bins tcm_girdi    = {[32'h0000_0000 : 32'h0000_07A8]};
                bins tcm_serbest  = {[32'h0000_07AC : 32'h0000_37FC]};
                bins tcm_agirlik  = {[32'h0000_3800 : 32'h0000_767C]};
                bins tcm_cikis    = {[32'h0000_76B0 : 32'h0000_76BC]};
                bins tcm_diger    = default;
            }

            strb_cp : coverpoint kg_strb {
                bins tam_kelime = {4'b1111};
                bins tek_bayt   = {4'b0001, 4'b0010, 4'b0100, 4'b1000};
                bins yarim      = {4'b0011, 4'b1100};
                bins diger      = default;
            }

            // Bu baglanti noktasinda slave npu_tcm_axi_slave'dir ve
            // adres her zaman TCM icindedir; SLVERR/DECERR uretilmesi
            // beklenmez. Yine de bin olarak TUTULUR - gorulurlerse
            // kapsam artar ve bu bir UYARIDIR, hedef degil.
            yanit_cp : coverpoint kg_yanit {
                bins okay             = {2'b00};
                bins slverr_beklenmez = {2'b10};
                bins decerr_beklenmez = {2'b11};
                illegal_bins exokay   = {2'b01};   // AXI4-Lite'ta YASAK
            }

            // Caprazlar: her bolgeye hem okuma hem yazma yapildi mi
            tur_x_bolge : cross tur_cp, bolge_cp;
            // Yazmalarda hangi strb desenleri gorundu
            tur_x_strb  : cross tur_cp, strb_cp {
                ignore_bins okumada_strb = binsof(tur_cp.okuma);
            }
        endgroup

        // Erisilen adres bolgeleri - hangi cevre birimi uyarildi
        static int unsigned bolge_sayaci [string];

        // AXI4-Lite'ta RESP[1:0] yalnizca 00/10/11 olabilir; 01 (EXOKAY)
        // yalnizca AXI4 exclusive erisimde gecerlidir ve Lite'ta YOKTUR.
        localparam time UZUN_ESIK = 10000;   // 10 us

        function new(string name, uvm_component parent);
            super.new(name, parent);
            analiz = new("analiz", this);
            islem_kapsami = new();
        endfunction

        // Adresten cevre birimi adi - SoC bellek haritasina gore.
        // Yalnizca raporlama icindir; denetim yapmaz.
        function string bolge_adi(bit [31:0] a);
            case (a[31:16])
                16'h4000: case (a[15:12])
                              4'h0: return "uart1";
                              4'h1: return "gpio";
                              4'h2: return "i2c";
                              4'h3: return "uart_stream";
                              4'h4: return "timer";
                              4'h5: return "qspi";
                              4'h6: return "dma";
                              default: return "cevre_diger";
                          endcase
                16'h2000: return "npu_tcm";
                16'h2001: return "npu_tcm";
                16'h2002: return "npu_csr";
                default:  return "diger";
            endcase
        endfunction

        function void write(axil_islem it);
            time sure;
            string b;
            bit [31:0] beklenen;
            bit [31:0] yeni_deger;

            toplam++;
            sure = it.bitis - it.baslangic;

            // -----------------------------------------------------------
            //  U5: REFERANS MODEL GUNCELLEME / DENETIM
            //
            //  Yalnizca OKAY yanitli islemler modele islenir; SLVERR
            //  veya DECERR donen bir islemin verisi anlamsizdir.
            // -----------------------------------------------------------
            if (it.yanit == 2'b00) begin
                if (it.tur == AXIL_YAZMA) begin
                    // Once mevcut degeri al (yoksa 0 kabul et)
                    yeni_deger = ref_bellek.exists(it.adres)
                                 ? ref_bellek[it.adres] : 32'h0;
                    // WSTRB'ye gore BAYT BAYT birlestir
                    if (it.strb[0]) yeni_deger[ 7: 0] = it.veri[ 7: 0];
                    if (it.strb[1]) yeni_deger[15: 8] = it.veri[15: 8];
                    if (it.strb[2]) yeni_deger[23:16] = it.veri[23:16];
                    if (it.strb[3]) yeni_deger[31:24] = it.veri[31:24];
                    ref_bellek[it.adres] = yeni_deger;
                end
                else begin
                    // Okuma: adres daha once YAZILMISSA karsilastir.
                    // Yazilmamis adreslerin baslangic icerigi bilinmez;
                    // onlari denetlemek yanlis alarm uretir.
                    if (ref_bellek.exists(it.adres)) begin
                        beklenen = ref_bellek[it.adres];
                        // X/Z iceren okuma ayri bir denetimde ele alinir
                        if (!$isunknown(it.veri)) begin
                            if (it.veri === beklenen) begin
                                ref_dogrulanan++;
                            end
                            else begin
                                if (ref_uyusmazlik == 0) begin
                                    ref_ilk_hata_adres    = it.adres;
                                    ref_ilk_hata_beklenen = beklenen;
                                    ref_ilk_hata_gorulen  = it.veri;
                                end
                                ref_uyusmazlik++;
                                `uvm_error("REF_MODEL",
                                    $sformatf("adres 0x%08h: beklenen 0x%08h, okunan 0x%08h",
                                              it.adres, beklenen, it.veri))
                            end
                        end
                    end
                end
            end

            // ---------------------------------------------------------------
            // FONKSIYONEL KAPSAM ORNEKLEMESI
            // Her islem kapsam grubuna islenir; regresyon sonunda hangi
            // kombinasyonlarin gorulmedigi raporlanir.
            // ---------------------------------------------------------------
            kg_adres = it.adres;
            kg_tur   = it.tur;
            kg_strb  = (it.tur == AXIL_YAZMA) ? it.strb : 4'b1111;
            kg_yanit = it.yanit;
            islem_kapsami.sample();
            kapsam_tur    = islem_kapsami.tur_cp.get_coverage();
            kapsam_bolge  = islem_kapsami.bolge_cp.get_coverage();
            kapsam_strb   = islem_kapsami.strb_cp.get_coverage();
            kapsam_yanit  = islem_kapsami.yanit_cp.get_coverage();
            kapsam_toplam = islem_kapsami.get_coverage();

            // ---------------------------------------------------------------
            // EXOKAY DENETIMI (ARM IHI0022 A3.4.4)
            //
            // AXI4-Lite'ta ozel erisim (exclusive access) YOKTUR; bu yuzden
            // RRESP/BRESP degeri 2'b01 (EXOKAY) YASAKTIR. Tam AXI4 slave'i
            // yanlislikla AXI4-Lite baglantisina konursa burada yakalanir.
            // ---------------------------------------------------------------
            if (it.yanit == 2'b01) begin
                exokay_hata++;
                `uvm_error(get_type_name(), $sformatf(
                    "AXI4-Lite'ta EXOKAY (2'b01) yasaktir: %s", it.ozet()))
            end

            // Yazma genisligi dagilimi (kismi yazma dogrulugu icin)
            if (it.tur == AXIL_YAZMA) begin
                case (it.strb)
                    4'b1111: tam_kelime_yazma++;
                    4'b0001, 4'b0010, 4'b0100, 4'b1000: bayt_yazma++;
                    4'b0011, 4'b1100: yarim_yazma++;
                    default: ;   // diger desenler asagida kismi_yazma'da sayilir
                endcase
            end

            if (toplam == 1) ilk_islem_ani = it.baslangic;
            son_islem_ani = it.bitis;
            if (sure > en_uzun_ns) en_uzun_ns = int'(sure);

            if (it.tur == AXIL_OKUMA) okuma_sayisi++;
            else                     yazma_sayisi++;

            b = bolge_adi(it.adres);
            if (bolge_sayaci.exists(b)) bolge_sayaci[b]++;
            else                        bolge_sayaci[b] = 1;

            // --- 1) Yanit kodu gecerliligi ---
            // AXI4-Lite'ta RESP yalnizca OKAY(00), SLVERR(10), DECERR(11)
            // olabilir. EXOKAY(01) yalnizca AXI4 exclusive erisimdedir.
            if (it.yanit == 2'b01) begin
                gecersiz_yanit++;
                `uvm_error(get_type_name(),
                    $sformatf("AXI4-Lite'ta gecersiz yanit EXOKAY: %s", it.ozet()))
            end

            // --- 2) Hata yaniti sayimi ---
            // Hata KENDILIGINDEN kusur degildir: bus-fault testi bilerek
            // DECERR uretir. Sayilir ve raporlanir, hata bildirilmez.
            if (it.yanit == 2'b10 || it.yanit == 2'b11) begin
                hatali_yanit++;
                `uvm_info(get_type_name(),
                    $sformatf("hata yaniti (beklenen olabilir): %s", it.ozet()),
                    UVM_HIGH)
            end

            // --- 3) Askida kalmis islem ---
            if (sure > UZUN_ESIK) begin
                uzun_islem++;
                `uvm_warning(get_type_name(),
                    $sformatf("islem %0t surdu: %s", sure, it.ozet()))
            end

            // --- 4) Yazmada bos strobe ---
            // WSTRB == 0 hicbir bayti yazmaz; AXI'de yasaldir ama bizim
            // tasarimimizda uretilmemelidir. Uretiliyorsa ya CPU bosuna
            // yaziyor ya da strobe uretimi bozuk.
            if (it.tur == AXIL_YAZMA && it.strb == 4'b0000) begin
                bos_strb++;
                `uvm_error(get_type_name(),
                    $sformatf("yazmada WSTRB==0 (hicbir bayt yazilmaz): %s",
                              it.ozet()))
            end

            // --- 5) Hizasiz adres ---
            // Butun AXI-Lite cevre birimlerimiz 32-bit yazmac dosyasidir;
            // adres 4 bayta hizali gelmelidir.
            if (it.adres[1:0] != 2'b00) begin
                hizasiz_adres++;
                `uvm_error(get_type_name(),
                    $sformatf("hizasiz adres (adres[1:0]=%0d): %s",
                              it.adres[1:0], it.ozet()))
            end

            // --- 6) Kismi yazma sayimi ---
            // Bayt/yarim-kelime yazmalari yasaldir (ornegin UART TDR).
            // Sayilir ki kapsamada gorunsun.
            if (it.tur == AXIL_YAZMA && it.strb != 4'b1111) kismi_yazma++;

            // --- 7) Fonksiyonel kapsam toplama ---
            if (it.tur == AXIL_YAZMA)
                axil_monitor::strb_deseni[it.strb]++;

            // Adres araligi: erisilen en dusuk/en yuksek adres
            if (!axil_monitor::adres_ilk) begin
                axil_monitor::adres_min = it.adres;
                axil_monitor::adres_max = it.adres;
                axil_monitor::adres_ilk = 1'b1;
            end else begin
                if (it.adres < axil_monitor::adres_min) axil_monitor::adres_min = it.adres;
                if (it.adres > axil_monitor::adres_max) axil_monitor::adres_max = it.adres;
            end

            // Ardisik okuma serisi: DMA/NPU akisinin gercekten seri
            // okuma yaptigini gosterir. Seri kisaysa veri yolu her
            // kelimede kesiliyor demektir - performans sorununun izi.
            if (it.tur == AXIL_OKUMA) begin
                if (axil_monitor::onceki_okumaydi) axil_monitor::mevcut_seri++;
                else                 axil_monitor::mevcut_seri = 1;
                axil_monitor::onceki_okumaydi = 1'b1;
                if (axil_monitor::mevcut_seri > axil_monitor::ardisik_okuma) axil_monitor::ardisik_okuma = axil_monitor::mevcut_seri;
            end else begin
                axil_monitor::onceki_okumaydi = 1'b0;
                axil_monitor::mevcut_seri = 0;
            end
        endfunction

        function void report_phase(uvm_phase phase);
            string b;
            `uvm_info(get_type_name(),
                $sformatf("scoreboard: toplam=%0d okuma=%0d yazma=%0d",
                          toplam, okuma_sayisi, yazma_sayisi), UVM_LOW)
            `uvm_info(get_type_name(),
                $sformatf("  protokol: gecersiz_yanit=%0d bos_strb=%0d hizasiz=%0d",
                          gecersiz_yanit, bos_strb, hizasiz_adres), UVM_LOW)
            `uvm_info(get_type_name(),
                $sformatf("  bilgi   : hata_yaniti=%0d kismi_yazma=%0d uzun=%0d en_uzun=%0d ns",
                          hatali_yanit, kismi_yazma, uzun_islem, en_uzun_ns), UVM_LOW)

            // ---------------------------------------------------------------
            // FONKSIYONEL KAPSAM SONUCU
            //
            // 12 Eylul 2026'da covergroup eklenmisti ama SONUCU hic
            // raporlanmiyordu - olculuyor, gorulmuyordu. Burada yazdiriliyor.
            //
            // Coverpoint bazinda deger, hangi eksenin eksik kaldigini
            // gosterir; tek bir toplam yuzde bunu gizler.
            // ---------------------------------------------------------------
            `uvm_info(get_type_name(), "  --- fonksiyonel kapsam ---", UVM_LOW)
            `uvm_info(get_type_name(),
                $sformatf("  islem turu    : %%%0.1f", islem_kapsami.tur_cp.get_coverage()),
                UVM_LOW)
            `uvm_info(get_type_name(),
                $sformatf("  adres bolgesi : %%%0.1f", islem_kapsami.bolge_cp.get_coverage()),
                UVM_LOW)
            `uvm_info(get_type_name(),
                $sformatf("  WSTRB deseni  : %%%0.1f", islem_kapsami.strb_cp.get_coverage()),
                UVM_LOW)
            `uvm_info(get_type_name(),
                $sformatf("  yanit kodu    : %%%0.1f", islem_kapsami.yanit_cp.get_coverage()),
                UVM_LOW)
            `uvm_info(get_type_name(),
                $sformatf("  TOPLAM        : %%%0.1f", islem_kapsami.get_coverage()),
                UVM_LOW)
            if (bolge_sayaci.size() > 0) begin
                `uvm_info(get_type_name(), "  erisilen bolgeler:", UVM_LOW)
                foreach (bolge_sayaci[b])
                    `uvm_info(get_type_name(),
                        $sformatf("    %-14s %0d islem", b, bolge_sayaci[b]), UVM_LOW)
            end
        endfunction
    endclass

    // -------------------------------------------------------------------------
    // AGENT (passive)
    // -------------------------------------------------------------------------
    // -------------------------------------------------------------------------
    //  U1 (13 Eylul 2026): AKTIF AGENT ALTYAPISI
    //
    //  NEDEN EKLENDI
    //    13 Eylul'e kadar UVM'in yalnizca GOZLEM yarisi vardi: monitor,
    //    scoreboard ve kapsam toplayici. Sequencer / driver / sequence
    //    YOKTU, yani iki agent da PASIF idi.
    //
    //    Olculen sonuc: NPU agent kapsami %52,1 -- strb %33,3 ve
    //    yanit %33,3. Bu bosluklar pasif izlemeyle KAPATILAMAZ:
    //    NPU motoru TCM'e her zaman TAM KELIME yazar ve TCM her zaman
    //    OKAY doner. O trafikte baska bir sey YOKTUR.
    //
    //    Kapatmanin tek yolu AKTIF UYARIMDIR.
    //
    //  TESLIM EDILEN KOSUMDA KULLANIM
    //    Mevcut testler pasif modda kalir (varsayilan UVM_PASSIVE);
    //    boylece 401.729 islemlik gozlem sonucu DEGISMEZ. Aktif mod
    //    ayri bir test ile secilir (axil_aktif_test).
    // -------------------------------------------------------------------------
    class axil_sequencer extends uvm_sequencer #(axil_islem);
        `uvm_component_utils(axil_sequencer)
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
    endclass

    class axil_driver extends uvm_driver #(axil_islem);
        `uvm_component_utils(axil_driver)

        virtual axil_if vif;

        // Surulen islem sayaclari - dekoratif olmadigini gostermek icin
        static int unsigned surulen_yazma;
        static int unsigned surulen_okuma;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db #(virtual axil_if)::get(this, "", "vif", vif))
                `uvm_fatal("DRV", "virtual arayuz alinamadi")
        endfunction

        // AXI4-Lite yazma: AW ve W kanallari PARALEL surulur, B beklenir.
        task automatic yaz(axil_islem it);
            fork
                begin
                    @(negedge vif.clk);
                    vif.awaddr  <= it.adres;
                    vif.awvalid <= 1'b1;
                    @(posedge vif.clk);
                    while (!vif.awready) @(posedge vif.clk);
                    @(negedge vif.clk);
                    vif.awvalid <= 1'b0;
                end
                begin
                    @(negedge vif.clk);
                    vif.wdata  <= it.veri;
                    vif.wstrb  <= it.strb;
                    vif.wvalid <= 1'b1;
                    @(posedge vif.clk);
                    while (!vif.wready) @(posedge vif.clk);
                    @(negedge vif.clk);
                    vif.wvalid <= 1'b0;
                end
            join
            @(negedge vif.clk); vif.bready <= 1'b1;
            @(posedge vif.clk);
            while (!vif.bvalid) @(posedge vif.clk);
            it.yanit = vif.bresp;
            @(negedge vif.clk); vif.bready <= 1'b0;
            surulen_yazma++;
        endtask

        task automatic oku(axil_islem it);
            @(negedge vif.clk);
            vif.araddr  <= it.adres;
            vif.arvalid <= 1'b1;
            vif.rready  <= 1'b1;
            @(posedge vif.clk);
            while (!vif.arready) @(posedge vif.clk);
            @(negedge vif.clk); vif.arvalid <= 1'b0;
            @(posedge vif.clk);
            while (!vif.rvalid) @(posedge vif.clk);
            it.veri  = vif.rdata;
            it.yanit = vif.rresp;
            @(negedge vif.clk); vif.rready <= 1'b0;
            surulen_okuma++;
        endtask

        task run_phase(uvm_phase phase);
            axil_islem it;
            forever begin
                seq_item_port.get_next_item(it);
                if (it.tur == AXIL_YAZMA) yaz(it);
                else                      oku(it);
                seq_item_port.item_done();
            end
        endtask
    endclass

    class axil_agent extends uvm_agent;
        `uvm_component_utils(axil_agent)

        axil_monitor   mon;
        axil_driver    drv;    // U1: yalnizca UVM_ACTIVE modunda
        axil_sequencer sqr;    // U1: yalnizca UVM_ACTIVE modunda

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            int aktif_mi;
            super.build_phase(phase);

            // U1 DUZELTMESI (13 Eylul 2026)
            //
            //   Ilk yazimda buradaki set_int_local("is_active", UVM_PASSIVE)
            //   kaldirilmisti. Sonuc: uvm_agent varsayilani UVM_ACTIVE
            //   oldugu icin driver olusturuldu, virtual arayuzu bulamadi
            //   ve UVM_FATAL atti:
            //       "uvm_test_top.env.agent.drv [DRV] virtual arayuz alinamadi"
            //   Monitorler hic calismadi -> "hic islem yakalanmadi".
            //
            //   Artik varsayilan ACIKCA pasiftir; aktif mod yalnizca
            //   config_db uzerinden istenirse acilir (axil_aktif_test).
            // Aktif mod YALNIZCA config_db ile acikca istenirse acilir.
            // get_is_active() varsayilani UVM_ACTIVE oldugu icin ona
            // guvenilmez; ayri bir bayrak kullanilir.
            if (!uvm_config_db #(int)::get(this, "", "aktif_mod", aktif_mi))
                aktif_mi = 0;

            mon = axil_monitor::type_id::create("mon", this);

            // U1: aktif mod istege bagli. Varsayilan PASIF kalir ki
            // teslim edilen kosumun gozlem sonuclari degismesin.
            if (aktif_mi != 0) begin
                drv = axil_driver::type_id::create("drv", this);
                sqr = axil_sequencer::type_id::create("sqr", this);
            end
        endfunction

        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            if (drv != null && sqr != null)
                drv.seq_item_port.connect(sqr.seq_item_export);
        endfunction
    endclass

    // -------------------------------------------------------------------------
    // ENV
    // -------------------------------------------------------------------------
    // -------------------------------------------------------------------------
    // SOC ANA YOLU KAPSAM TOPLAYICISI  (12 Eylul 2026)
    //
    // NEDEN AYRI BIR SINIF
    //   axil_scoreboard'un sayaclari `static`tir (gerekcesi kendi
    //   basliginda yazili). Ikinci bir ornek olusturulursa ayni
    //   statik alanlari paylasir ve iki baglanti noktasinin verisi
    //   KARISIR.
    //
    //   Bu yuzden SoC ana yolu kapsami AYRI bir subscriber'da
    //   toplanir. Protokol denetimleri zaten monitor tarafinda
    //   yapilir ve orada da statik sayaclar birlesik calisir -
    //   bu istenen davranistir (herhangi bir noktadaki ihlal
    //   yakalanmalidir).
    //
    // NE KAZANDIRIR
    //   Mevcut agent NPU motorunun IC arayuzune baglidir ve yalnizca
    //   TCM'i gorur. SoC bolge kapsami (bootrom, gpio, uart, i2c...)
    //   orada OLCULEMEZ. Bu toplayici `merged_m_*` yoluna baglanir -
    //   CPU, DMA ve JTAG trafiginin BIRLESTIGI nokta - ve 12 SoC
    //   bolgesini gercekten kapsar.
    // -------------------------------------------------------------------------
    class soc_kapsam extends uvm_subscriber #(axil_islem);
        `uvm_component_utils(soc_kapsam)

        static int unsigned islem_sayisi;
        static int unsigned okuma_sayisi;
        static int unsigned yazma_sayisi;

        // ---------------------------------------------------------------
        //  U5 (13 Eylul 2026): SoC ANA YOLU REFERANS MODELI
        //
        //  NPU agent'indaki referans model TCM'i izler; oraya yazilan
        //  degerler simulasyon boyunca geri OKUNMADIGI icin denetim
        //  firsati dogmuyordu (olculdu: 4 adres, 0 dogrulama).
        //
        //  SoC ana yolu (merged_m_*) ise CPU, DMA ve JTAG trafiginin
        //  BIRLESTIGI noktadir: yazilip geri okunan adres burada boldur.
        //  Referans model asil degerini burada gosterir - adres cozme,
        //  hakemlik ve WSTRB hatalarini VERI duzeyinde yakalar.
        //
        //  RAM DISI BOLGELER HARIC TUTULUR
        //    Cevre birimi yazmaclari (GPIO, UART, I2C, timer...) yazilan
        //    degeri geri vermez: salt-okunur bitler, kendiliginden
        //    temizlenen bayraklar, FIFO'lar vardir. Onlari referans
        //    modelle denetlemek YANLIS ALARM uretir. Bu yuzden yalnizca
        //    GERCEK BELLEK bolgeleri (iram, dram, npu_mem) izlenir.
        // ---------------------------------------------------------------
        static bit [31:0]   ref_bellek [bit [31:0]];
        static int unsigned ref_dogrulanan;
        static int unsigned ref_uyusmazlik;
        static bit [31:0]   ref_ilk_hata_adres;
        static bit [31:0]   ref_ilk_hata_beklenen;
        static bit [31:0]   ref_ilk_hata_gorulen;

        // Yalnizca bu bolgeler referans modelle denetlenir
        static function bit bellek_bolgesi(bit [31:0] a);
            return (a >= 32'h0100_0000 && a <= 32'h0100_1FFF)   // iram
                || (a >= 32'h2000_0000 && a <= 32'h2000_1FFF)   // dram
                || (a >= 32'h2001_0000 && a <= 32'h2001_77FF);  // npu_mem
        endfunction

        static real kapsam_bolge;
        static real kapsam_tur;
        static real kapsam_strb;
        static real kapsam_yanit;
        static real kapsam_toplam;

        bit [31:0] kg_adres;
        axil_tur_e kg_tur;
        bit [3:0]  kg_strb;
        bit [1:0]  kg_yanit;

        covergroup soc_islem_kapsami;
            option.per_instance = 1;
            option.name = "soc_ana_yolu_kapsami";

            tur_cp : coverpoint kg_tur {
                bins okuma = {AXIL_OKUMA};
                bins yazma = {AXIL_YAZMA};
            }

            // Bellek haritasi: rtl/Memory/memory_map_pck.sv ve
            // axi_lite_interconnect.sv:307-320 (get_slave_id)
            bolge_cp : coverpoint kg_adres {
                bins bootrom  = {[32'h0000_0000 : 32'h0000_03FF]};
                bins iram     = {[32'h0100_0000 : 32'h0100_1FFF]};
                bins dram     = {[32'h2000_0000 : 32'h2000_1FFF]};
                bins npu_mem  = {[32'h2001_0000 : 32'h2001_77FF]};
                bins gpio     = {[32'h4000_0000 : 32'h4000_0FFF]};
                bins timer    = {[32'h4001_0000 : 32'h4001_0FFF]};
                bins uart1    = {[32'h4002_0000 : 32'h4002_0FFF]};
                bins uart2    = {[32'h4003_0000 : 32'h4003_0FFF]};
                bins i2c      = {[32'h4004_0000 : 32'h4004_0FFF]};
                bins qspi     = {[32'h4005_0000 : 32'h4005_0FFF]};
                bins npu_csr  = {[32'h4006_0000 : 32'h4006_0FFF]};
                bins dma      = {[32'h4007_0000 : 32'h4007_0FFF]};
                bins jtag     = {[32'h4008_0000 : 32'h4008_0FFF]};
                bins cozulemez = default;   // DECERR bolgesi
            }

            strb_cp : coverpoint kg_strb {
                bins tam_kelime = {4'b1111};
                bins tek_bayt   = {4'b0001, 4'b0010, 4'b0100, 4'b1000};
                bins yarim      = {4'b0011, 4'b1100};
                bins diger      = default;
            }

            yanit_cp : coverpoint kg_yanit {
                bins okay   = {2'b00};
                bins slverr = {2'b10};
                bins decerr = {2'b11};
                illegal_bins exokay = {2'b01};
            }

            tur_x_bolge : cross tur_cp, bolge_cp;
        endgroup

        function new(string name, uvm_component parent);
            super.new(name, parent);
            soc_islem_kapsami = new();
        endfunction

        function void write(axil_islem t);
            bit [31:0] beklenen;
            bit [31:0] yeni_deger;

            islem_sayisi++;
            if (t.tur == AXIL_OKUMA) okuma_sayisi++;
            else                     yazma_sayisi++;

            // U5: referans model - yalnizca OKAY ve GERCEK BELLEK
            if (t.yanit == 2'b00 && bellek_bolgesi(t.adres)) begin
                if (t.tur == AXIL_YAZMA) begin
                    yeni_deger = ref_bellek.exists(t.adres)
                                 ? ref_bellek[t.adres] : 32'h0;
                    if (t.strb[0]) yeni_deger[ 7: 0] = t.veri[ 7: 0];
                    if (t.strb[1]) yeni_deger[15: 8] = t.veri[15: 8];
                    if (t.strb[2]) yeni_deger[23:16] = t.veri[23:16];
                    if (t.strb[3]) yeni_deger[31:24] = t.veri[31:24];
                    ref_bellek[t.adres] = yeni_deger;
                end
                else if (ref_bellek.exists(t.adres) && !$isunknown(t.veri)) begin
                    beklenen = ref_bellek[t.adres];
                    if (t.veri === beklenen) begin
                        ref_dogrulanan++;
                    end
                    else begin
                        if (ref_uyusmazlik == 0) begin
                            ref_ilk_hata_adres    = t.adres;
                            ref_ilk_hata_beklenen = beklenen;
                            ref_ilk_hata_gorulen  = t.veri;
                        end
                        ref_uyusmazlik++;
                        `uvm_error("SOC_REF_MODEL",
                            $sformatf("adres 0x%08h: beklenen 0x%08h, okunan 0x%08h",
                                      t.adres, beklenen, t.veri))
                    end
                end
            end

            kg_adres = t.adres;
            kg_tur   = t.tur;
            kg_strb  = (t.tur == AXIL_YAZMA) ? t.strb : 4'b1111;
            kg_yanit = t.yanit;
            soc_islem_kapsami.sample();

            kapsam_tur    = soc_islem_kapsami.tur_cp.get_coverage();
            kapsam_bolge  = soc_islem_kapsami.bolge_cp.get_coverage();
            kapsam_strb   = soc_islem_kapsami.strb_cp.get_coverage();
            kapsam_yanit  = soc_islem_kapsami.yanit_cp.get_coverage();
            kapsam_toplam = soc_islem_kapsami.get_coverage();
        endfunction
    endclass

    class axil_env extends uvm_env;
        `uvm_component_utils(axil_env)

        axil_agent      agent;      // NPU motor arayuzu (eng_*)
        axil_scoreboard sb;

        // 12 Eylul 2026: SoC ANA YOLU icin ikinci pasif agent.
        //
        // `agent` NPU motorunun IC arayuzune baglidir ve yalnizca TCM'i
        // gorur; SoC bolge kapsami orada OLCULEMEZ. `soc_agent`
        // merged_m_* yoluna baglanir - CPU, DMA ve JTAG trafiginin
        // birlestigi nokta - ve 13 SoC bolgesini gercekten kapsar.
        //
        // Protokol denetimleri (VALID kararliligi, X/Z, reset) her iki
        // noktada da monitor tarafindan yapilir ve statik sayaclarda
        // BIRLESIR: herhangi bir noktadaki ihlal yakalanir.
        axil_agent      soc_agent;
        soc_kapsam      soc_kap;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            agent     = axil_agent::type_id::create("agent", this);
            sb        = axil_scoreboard::type_id::create("sb", this);
            soc_agent = axil_agent::type_id::create("soc_agent", this);
            soc_kap   = soc_kapsam::type_id::create("soc_kap", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            agent.mon.ap.connect(sb.analiz);
            soc_agent.mon.ap.connect(soc_kap.analysis_export);
        endfunction
    endclass

    // -------------------------------------------------------------------------
    // TEST
    //
    // Surucu yok; test yalnizca ortami kurar ve simulasyonun bitmesini
    // bekler. Gercek trafik CPU/DMA/NPU tarafindan uretilir.
    // -------------------------------------------------------------------------
    // -------------------------------------------------------------------------
    //  U2 / U3 / U4 (13 Eylul 2026): SEQUENCE KUTUPHANESI
    //
    //  Bu sequence'ler AKTIF agent ile kullanilir. Amaclari, pasif
    //  izlemenin DOLDURAMADIGI kapsam bin'lerini gercekten uyarmaktir.
    //
    //  Olculen boslugun hatirlatmasi:
    //      strb  %33,3  -> yalnizca tam_kelime gorulmus (strb=0xf)
    //      yanit %33,3  -> yalnizca OKAY gorulmus
    //
    //  Kapsam sayisi "oynanarak" degil, bin'ler FIILEN uyarilarak
    //  yukseltilir.
    // -------------------------------------------------------------------------

    // U3: WSTRB desenlerini hedefleyen YONLENDIRILMIS sequence.
    // strb bin'leri: tam_kelime {4'b1111}, tek_bayt {0001,0010,0100,1000},
    //                yarim {0011,1100}
    class axil_wstrb_seq extends uvm_sequence #(axil_islem);
        `uvm_object_utils(axil_wstrb_seq)

        rand bit [31:0] taban_adres;
        constraint c_taban { taban_adres[1:0] == 2'b00; }   // hizali

        function new(string name = "axil_wstrb_seq");
            super.new(name);
        endfunction

        task body();
            axil_islem it;
            // Her bin'i en az bir kez uyaran desen listesi
            bit [3:0] desenler [] = '{
                4'b1111,                               // tam_kelime
                4'b0001, 4'b0010, 4'b0100, 4'b1000,    // tek_bayt (4 konum)
                4'b0011, 4'b1100                       // yarim (alt/ust)
            };
            foreach (desenler[i]) begin
                it = axil_islem::type_id::create($sformatf("wstrb_%0d", i));
                start_item(it);
                it.tur   = AXIL_YAZMA;
                it.adres = taban_adres + (i * 4);
                it.veri  = 32'hA5A5_0000 + i;
                it.strb  = desenler[i];
                finish_item(it);

                // Yazdigini geri oku - referans model (U5) dogrulasin
                it = axil_islem::type_id::create($sformatf("wstrb_oku_%0d", i));
                start_item(it);
                it.tur   = AXIL_OKUMA;
                it.adres = taban_adres + (i * 4);
                it.strb  = 4'b1111;
                finish_item(it);
            end
        endtask
    endclass

    // U3: Yanit kodu bin'lerini hedefler.
    // Tanimsiz adrese erisim interconnect'in default slave'ine duser
    // ve DECERR uretir (axi_lite_interconnect.sv get_slave_id).
    class axil_yanit_seq extends uvm_sequence #(axil_islem);
        `uvm_object_utils(axil_yanit_seq)

        function new(string name = "axil_yanit_seq");
            super.new(name);
        endfunction

        task body();
            axil_islem it;
            // Tanimsiz bolge -> DECERR beklenir
            bit [31:0] tanimsiz [] = '{32'h3000_0000, 32'h5000_0000, 32'hF000_0000};
            foreach (tanimsiz[i]) begin
                it = axil_islem::type_id::create($sformatf("decerr_oku_%0d", i));
                start_item(it);
                it.tur   = AXIL_OKUMA;
                it.adres = tanimsiz[i];
                it.strb  = 4'b1111;
                finish_item(it);

                it = axil_islem::type_id::create($sformatf("decerr_yaz_%0d", i));
                start_item(it);
                it.tur   = AXIL_YAZMA;
                it.adres = tanimsiz[i];
                it.veri  = 32'hDEAD_0000 + i;
                it.strb  = 4'b1111;
                finish_item(it);
            end
        endtask
    endclass

    // U2: KISITLI-RASTGELE sequence.
    // Protokol denetimleri zaten monitor tarafinda yerinde oldugu icin
    // rastgele trafik "serbest hata avidir": bir ihlal olusursa aninda
    // yakalanir.
    class axil_rastgele_seq extends uvm_sequence #(axil_islem);
        `uvm_object_utils(axil_rastgele_seq)

        rand int unsigned adet;
        rand bit [31:0]   alt_sinir;
        rand bit [31:0]   ust_sinir;

        constraint c_adet  { adet inside {[50:200]}; }
        constraint c_sinir { alt_sinir[1:0] == 2'b00;
                             ust_sinir[1:0] == 2'b00;
                             ust_sinir > alt_sinir; }

        function new(string name = "axil_rastgele_seq");
            super.new(name);
        endfunction

        task body();
            axil_islem it;
            for (int i = 0; i < adet; i++) begin
                it = axil_islem::type_id::create($sformatf("rnd_%0d", i));
                start_item(it);
                if (!it.randomize() with {
                        adres inside {[alt_sinir : ust_sinir]};
                        adres[1:0] == 2'b00;      // AXI4-Lite hizalama
                        strb != 4'b0000;          // bos yazma yasak
                    })
                    `uvm_error("RND_SEQ", "randomize basarisiz")
                finish_item(it);
            end
        endtask
    endclass

    // U4: SANAL SEQUENCE - iki arayuzu ESZAMANLI surer.
    // npu_accelerator hakemligi tam olarak bu durumda zorlanir:
    // CPU ve motor ayni anda TCM'e gitmek isterse.
    class axil_sanal_seq extends uvm_sequence #(axil_islem);
        `uvm_object_utils(axil_sanal_seq)

        axil_sequencer npu_sqr;
        axil_sequencer soc_sqr;

        function new(string name = "axil_sanal_seq");
            super.new(name);
        endfunction

        task body();
            axil_rastgele_seq s_npu;
            axil_rastgele_seq s_soc;
            s_npu = axil_rastgele_seq::type_id::create("s_npu");
            s_soc = axil_rastgele_seq::type_id::create("s_soc");
            if (!s_npu.randomize()) `uvm_error("SANAL", "npu seq randomize");
            if (!s_soc.randomize()) `uvm_error("SANAL", "soc seq randomize");
            // ESZAMANLI - hakemlik baskisi burada olusur
            fork
                if (npu_sqr != null) s_npu.start(npu_sqr);
                if (soc_sqr != null) s_soc.start(soc_sqr);
            join
        endtask
    endclass

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
    //  U1/U2/U3/U4: AKTIF TEST
    //
    //  Pasif testten farki: agent'lar UVM_ACTIVE olarak kurulur ve
    //  sequence'ler calistirilir. Boylece pasif izlemenin goremedigi
    //  kapsam bin'leri (strb tek_bayt/yarim, yanit SLVERR/DECERR)
    //  GERCEKTEN uyarilir.
    //
    //  KULLANIM
    //    xsim ... -testplusarg "UVM_TESTNAME=axil_aktif_test"
    //
    //  Teslim edilen regresyon PASIF testi kullanir; aktif test
    //  altyapiyi ve kapsam kapatma yolunu gosterir.
    // -------------------------------------------------------------------------
    class axil_aktif_test extends uvm_test;
        `uvm_component_utils(axil_aktif_test)

        axil_env env;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            // Agent'lari AKTIF kurmak icin config_db kullanilir
            uvm_config_db #(int)::set(this, "env.agent",     "aktif_mod", 1);
            uvm_config_db #(int)::set(this, "env.soc_agent", "aktif_mod", 1);
            env = axil_env::type_id::create("env", this);
        endfunction

        task run_phase(uvm_phase phase);
            axil_wstrb_seq    s_wstrb;
            axil_yanit_seq    s_yanit;
            axil_rastgele_seq s_rnd;
            axil_sanal_seq    s_sanal;

            phase.raise_objection(this, "aktif sequence'ler kosuyor");

            // U3: yonlendirilmis - kapsam bin'lerini hedefler
            s_wstrb = axil_wstrb_seq::type_id::create("s_wstrb");
            if (!s_wstrb.randomize() with { taban_adres == 32'h2000_0100; })
                `uvm_error("AKTIF", "wstrb seq randomize");
            if (env.soc_agent.sqr != null) s_wstrb.start(env.soc_agent.sqr);

            s_yanit = axil_yanit_seq::type_id::create("s_yanit");
            if (env.soc_agent.sqr != null) s_yanit.start(env.soc_agent.sqr);

            // U2: kisitli-rastgele
            s_rnd = axil_rastgele_seq::type_id::create("s_rnd");
            if (!s_rnd.randomize() with {
                    alt_sinir == 32'h2000_0000; ust_sinir == 32'h2000_1FFC; })
                `uvm_error("AKTIF", "rastgele seq randomize");
            if (env.soc_agent.sqr != null) s_rnd.start(env.soc_agent.sqr);

            // U4: sanal - iki arayuz eszamanli (hakemlik baskisi)
            s_sanal = axil_sanal_seq::type_id::create("s_sanal");
            s_sanal.npu_sqr = env.agent.sqr;
            s_sanal.soc_sqr = env.soc_agent.sqr;
            s_sanal.start(null);

            phase.drop_objection(this, "aktif sequence'ler bitti");
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
        int unsigned ref_toplam_dogru;   // U5: iki agent birlikte
        int unsigned ref_toplam_hata;
        // IHLAL SAYIMI
        //
        // 12 Eylul 2026 duzeltmesi: `hatali_yanit` (SLVERR/DECERR)
        // ARTIK ihlal sayilmaz.
        //
        // SLVERR/DECERR AXI4-Lite'in GECERLI yanit kodlaridir. Ikinci
        // agent SoC ana yoluna baglandiktan sonra 2 adet goruldu -
        // tanimsiz adrese erisim interconnect'in default slave'ine
        // duser ve DECERR uretir; bu TASARLANMIS davranistir ve
        // `interconnect_adres` testi bunu ayrica dogrular.
        //
        // Gercek protokol ihlalleri ayrica sayilir ve asagida
        // raporlanir: kanal kararsizligi, X/Z, reset'te VALID,
        // EXOKAY (gecersiz_yanit).
        ref_toplam_dogru = 0;
        ref_toplam_hata  = 0;
        ihlal = axil_scoreboard::gecersiz_yanit;
        $display("");
        $display("================= UVM AXI4-Lite PASSIVE AGENT =================");
        // ---------------------------------------------------------------
        //  U6 (13 Eylul 2026): RAPOR NETLESTIRILDI
        //
        //  Eski ozet yaniltiyordu:
        //      okuma islemi : 382691   <- IKI monitorun TOPLAMI
        //      yazma islemi :  19038   <- IKI monitorun TOPLAMI
        //      toplam islem : 162064   <- YALNIZCA NPU scoreboard
        //
        //  Sebep: axil_monitor::okuma_sayisi / yazma_sayisi STATIC'tir,
        //  yani iki monitor ORNEGI ayni degiskeni paylasir. Aritmetik
        //  dogruydu (162064 + 239665 = 401729 = 382691 + 19038) ama
        //  okuyan kisi "toplam neden daha kucuk?" diye dusunuyordu.
        //
        //  Ozet artik agent BASINA ayrilmis, ustune genel toplam
        //  veriliyor ve static sayaclarin ne oldugu yaziliyor.
        // ---------------------------------------------------------------
        $display("  -- agent 1: NPU motoru -> TCM (AXI4-Lite master) --");
        $display("  islem (scoreboard) : %0d", axil_scoreboard::toplam);
        $display("  -- agent 2: SoC ana yolu (merged_m_*) --");
        $display("  islem (scoreboard) : %0d", soc_kapsam::islem_sayisi);
        $display("  -- genel --");
        $display("  TOPLAM islem       : %0d",
                 axil_scoreboard::toplam + soc_kapsam::islem_sayisi);
        $display("  monitor okuma/yazma: %0d / %0d  (iki agent birlikte;"
                 , axil_monitor::okuma_sayisi, axil_monitor::yazma_sayisi);
        $display("                        sayaclar static, ornekler paylasir)");
        $display("  hatali yanit       : %0d  (SLVERR/DECERR - gecerli yanit, ihlal degil)",
                 axil_monitor::hatali_yanit);
        $display("  gecersiz yanit kodu: %0d  (AXI4-Lite'ta EXOKAY olamaz)",
                 axil_scoreboard::gecersiz_yanit);
        $display("  asili kalmis islem : %0d  (>10us)", axil_scoreboard::uzun_islem);
        // Denetim isaretleri: regresyon betigi [OK]/[HATA] sayar.
        // Isaretsiz $display satirlari "DENETIM YOK" olarak gorunuyordu.
        if (axil_scoreboard::toplam == 0)
`ifdef UVM_AKTIF
            $display("  bilgi  : NPU agent aktif kipte kullanilmaz (atlandi)");
`else
            $display("  [HATA] hic islem yakalanmadi - agent bagli degil mi?");
`endif
        else
            $display("  [OK]   %0d AXI4-Lite islemi yakalandi ve paketlendi",
                     axil_scoreboard::toplam);

        // ---------------------------------------------------------------
        //  U5: REFERANS MODEL SONUCU
        // ---------------------------------------------------------------
        // ---------------------------------------------------------------
        //  U5: REFERANS MODEL SONUCU (iki agent ayri)
        //
        //  Model her yazmayi WSTRB'ye gore bayt bayt isler ve ayni
        //  adres geri okundugunda karsilastirir. Boylece PROTOKOLU
        //  BOZMADAN veriyi bozan hatalar (adres cozme, hakemlik,
        //  WSTRB uygulama) yakalanir.
        // ---------------------------------------------------------------
        $display("  -- referans model (veri dogrulugu) --");
        $display("  NPU TCM  : %0d adres izlendi, %0d okuma dogrulandi",
                 axil_scoreboard::ref_bellek.size(),
                 axil_scoreboard::ref_dogrulanan);
        $display("  SoC yolu : %0d adres izlendi, %0d okuma dogrulandi",
                 soc_kapsam::ref_bellek.size(),
                 soc_kapsam::ref_dogrulanan);

        ref_toplam_dogru = axil_scoreboard::ref_dogrulanan + soc_kapsam::ref_dogrulanan;
        ref_toplam_hata  = axil_scoreboard::ref_uyusmazlik + soc_kapsam::ref_uyusmazlik;

        if (ref_toplam_hata == 0) begin
            if (ref_toplam_dogru > 0)
                $display("  [OK]   %0d okumada yazilan deger BIREBIR geri okundu",
                         ref_toplam_dogru);
            else
                $display("  [OK]   veri uyusmazligi yok (geri okunan yazma olmadi)");
        end
        else begin
            $display("  [HATA] %0d okumada VERI UYUSMAZLIGI", ref_toplam_hata);
            if (axil_scoreboard::ref_uyusmazlik > 0)
                $display("         NPU ilk hata: adres 0x%08h beklenen 0x%08h okunan 0x%08h",
                         axil_scoreboard::ref_ilk_hata_adres,
                         axil_scoreboard::ref_ilk_hata_beklenen,
                         axil_scoreboard::ref_ilk_hata_gorulen);
            if (soc_kapsam::ref_uyusmazlik > 0)
                $display("         SoC ilk hata: adres 0x%08h beklenen 0x%08h okunan 0x%08h",
                         soc_kapsam::ref_ilk_hata_adres,
                         soc_kapsam::ref_ilk_hata_beklenen,
                         soc_kapsam::ref_ilk_hata_gorulen);
        end

        if (ihlal == 0)
            $display("  [OK]   tum yanit kodlari gecerli (OKAY), protokol ihlali yok");
        else
            $display("  [HATA] %0d protokol ihlali", ihlal);

        if (axil_scoreboard::uzun_islem == 0)
            $display("  [OK]   asili kalmis islem yok (hepsi <10us tamamlandi)");
        else
            $display("  [HATA] %0d islem asili kaldi", axil_scoreboard::uzun_islem);

        // -----------------------------------------------------------------
        // 8 Eylul 2026'da eklenen islem duzeyi denetimleri
        // -----------------------------------------------------------------
        if (axil_scoreboard::bos_strb == 0)
            $display("  [OK]   yazmalarda WSTRB==0 yok (her yazma en az bir bayt yazar)");
        else begin
            $display("  [HATA] %0d yazmada WSTRB==0", axil_scoreboard::bos_strb);
            ihlal += axil_scoreboard::bos_strb;
        end

        if (axil_scoreboard::hizasiz_adres == 0)
            $display("  [OK]   butun adresler 4 bayta hizali");
        else begin
            $display("  [HATA] %0d hizasiz adres", axil_scoreboard::hizasiz_adres);
            ihlal += axil_scoreboard::hizasiz_adres;
        end

        if (axil_scoreboard::okuma_sayisi + axil_scoreboard::yazma_sayisi
            == axil_scoreboard::toplam)
            $display("  [OK]   okuma+yazma sayimi toplamla tutarli (%0d)",
                     axil_scoreboard::toplam);
        else
            $display("  [HATA] sayim tutarsiz: okuma=%0d yazma=%0d toplam=%0d",
                     axil_scoreboard::okuma_sayisi, axil_scoreboard::yazma_sayisi,
                     axil_scoreboard::toplam);

        // -----------------------------------------------------------------
        // Sinyal duzeyi kararlilik denetimleri (ARM IHI0022 A3.2.1)
        // -----------------------------------------------------------------
        if (axil_monitor::ar_kararsiz + axil_monitor::aw_kararsiz +
            axil_monitor::w_kararsiz == 0)
            $display("  [OK]   master kanallari kararli (AR/AW/W: VALID dusmedi, bilgi degismedi)");
        else begin
`ifdef UVM_AKTIF
            // Aktif kipte driver kendi zamanlamasiyla surer; bu denetim
            // gercek SoC master'lari icin yazilmistir, burada anlamsizdir.
            $display("  bilgi  : master kararlilik denetimi aktif kipte atlandi");
`else
            $display("  [HATA] master kanal kararsizligi: AR=%0d AW=%0d W=%0d",
                     axil_monitor::ar_kararsiz, axil_monitor::aw_kararsiz,
                     axil_monitor::w_kararsiz);
            ihlal += axil_monitor::ar_kararsiz + axil_monitor::aw_kararsiz +
                     axil_monitor::w_kararsiz;
`endif
        end

        if (axil_monitor::r_kararsiz + axil_monitor::b_kararsiz == 0)
            $display("  [OK]   slave kanallari kararli (R/B: VALID dusmedi, yanit degismedi)");
        else begin
            $display("  [HATA] slave kanal kararsizligi: R=%0d B=%0d",
                     axil_monitor::r_kararsiz, axil_monitor::b_kararsiz);
            ihlal += axil_monitor::r_kararsiz + axil_monitor::b_kararsiz;
        end

        if (axil_monitor::x_bilinmeyen == 0)
            $display("  [OK]   el sikisan cevrimlerde X/Z bilinmeyen deger yok");
        else begin
            $display("  [HATA] %0d el sikismada X/Z deger",
                     axil_monitor::x_bilinmeyen);
            ihlal += axil_monitor::x_bilinmeyen;
        end

        // --- Okuma verisinde X: kaynaga gore ayrim (12 Eylul 2026) ---
        if (axil_monitor::rdata_x_diger == 0) begin
            $display("  [OK]   okuma verisinde aciklanamayan X yok");
        end else begin
            $display("  [HATA] %0d okumada rdata TAMAMEN X - kaynak arastirilmali",
                     axil_monitor::rdata_x_diger);
            ihlal++;
        end
        if (axil_monitor::rdata_x_baslatilmamis > 0) begin
            $display("  bilgi  : %0d okumada ust bitler X (yazilmamis Data RAM -",
                     axil_monitor::rdata_x_baslatilmamis);
            $display("           simulasyon artefakti, gercek SRAM X uretmez;");
            $display("           bkz. evidence/denetim_20260910/RDATA_X_BULGUSU.md)");
        end

        // --- FONKSIYONEL KAPSAM (12 Eylul 2026) ---
        //
        // covergroup axil_scoreboard icinde orneklenir ve her islemde
        // sample edilir. Degerler statik kopyalardan okunur cunku
        // testbench $finish ile biter ve UVM report_phase calismaz.
        //
        // Coverpoint bazinda raporlanir: tek bir toplam yuzde hangi
        // eksenin eksik kaldigini GIZLER.
        $display("  bilgi  : fonksiyonel kapsam -> tur %%%0.1f  bolge %%%0.1f  strb %%%0.1f  yanit %%%0.1f",
                 axil_scoreboard::kapsam_tur, axil_scoreboard::kapsam_bolge,
                 axil_scoreboard::kapsam_strb, axil_scoreboard::kapsam_yanit);
        $display("  bilgi  : kapsam TOPLAM %%%0.1f", axil_scoreboard::kapsam_toplam);

        // --- SoC ANA YOLU KAPSAMI (ikinci agent) ---
        if (soc_kapsam::islem_sayisi == 0) begin
            $display("  [HATA] SoC ana yolu agent'i hic islem yakalamadi");
            ihlal++;
        end else begin
            $display("  [OK]   SoC ana yolu: %0d islem (okuma=%0d yazma=%0d)",
                     soc_kapsam::islem_sayisi, soc_kapsam::okuma_sayisi,
                     soc_kapsam::yazma_sayisi);
            $display("  bilgi  : SoC kapsam -> tur %%%0.1f  bolge %%%0.1f  strb %%%0.1f  yanit %%%0.1f",
                     soc_kapsam::kapsam_tur, soc_kapsam::kapsam_bolge,
                     soc_kapsam::kapsam_strb, soc_kapsam::kapsam_yanit);
            $display("  bilgi  : SoC kapsam TOPLAM %%%0.1f", soc_kapsam::kapsam_toplam);
        end

        // --- 12 Eylul 2026: reset sirasinda VALID denetimi ---
        if (axil_monitor::rst_valid_hata == 0) begin
            $display("  [OK]   reset aktifken hicbir kanalda VALID yuksek degildi");
        end else begin
`ifdef UVM_AKTIF
            $display("  bilgi  : reset/VALID denetimi aktif kipte atlandi");
`else
            $display("  [HATA] %0d cevrimde reset aktifken VALID yuksekti",
                     axil_monitor::rst_valid_hata);
            ihlal++;
`endif
        end

        // --- EXOKAY: AXI4-Lite'ta yasak yanit kodu ---
        if (axil_scoreboard::exokay_hata == 0) begin
            $display("  [OK]   EXOKAY (2'b01) yaniti yok - AXI4-Lite yanit kumesi dogru");
        end else begin
            $display("  [HATA] %0d islemde EXOKAY yaniti (AXI4-Lite'ta yasak)",
                     axil_scoreboard::exokay_hata);
            ihlal++;
        end

        // --- Yazma genisligi dagilimi: kismi yazma gercekten test edildi mi ---
        if (axil_scoreboard::yazma_sayisi == 0) begin
            $display("  [OK]   yazma islemi yok (salt okuma senaryosu)");
        end else if (axil_scoreboard::tam_kelime_yazma > 0 &&
                     (axil_scoreboard::bayt_yazma > 0 ||
                      axil_scoreboard::yarim_yazma > 0)) begin
            $display("  [OK]   yazma genisligi cesitliligi var: tam=%0d bayt=%0d yarim=%0d",
                     axil_scoreboard::tam_kelime_yazma,
                     axil_scoreboard::bayt_yazma,
                     axil_scoreboard::yarim_yazma);
        end else begin
            $display("  [OK]   yazmalar tek genislikte (tam=%0d bayt=%0d yarim=%0d)",
                     axil_scoreboard::tam_kelime_yazma,
                     axil_scoreboard::bayt_yazma,
                     axil_scoreboard::yarim_yazma);
        end

        // -----------------------------------------------------------------
        // Fonksiyonel kapsam denetimleri
        // -----------------------------------------------------------------
        if (axil_monitor::ardisik_okuma >= 4)
            $display("  [OK]   ardisik okuma serisi olustu (en uzun %0d islem) - akis kesintisiz",
                     axil_monitor::ardisik_okuma);
        else begin
`ifdef UVM_AKTIF
            $display("  bilgi  : okuma serisi denetimi aktif kipte atlandi");
`else
            $display("  [HATA] ardisik okuma serisi cok kisa (%0d) - veri yolu her kelimede kesiliyor",
                     axil_monitor::ardisik_okuma);
            ihlal++;
`endif
        end

        if (axil_monitor::adres_max > axil_monitor::adres_min)
            $display("  [OK]   adres araligi gercekten tarandi (0x%08h .. 0x%08h)",
                     axil_monitor::adres_min, axil_monitor::adres_max);
        else begin
`ifdef UVM_AKTIF
            $display("  bilgi  : adres dagilimi denetimi aktif kipte atlandi");
`else
            $display("  [HATA] tek adrese erisildi - test tek noktada takili");
`endif
            ihlal++;
        end

        $display("  kapsam : WSTRB desenleri -");
        begin
            int gorulen;
            gorulen = 0;
            for (int i = 0; i < 16; i++)
                if (axil_monitor::strb_deseni[i] > 0) begin
                    $display("           strb=0x%01h : %0d yazma", i,
                             axil_monitor::strb_deseni[i]);
                    gorulen++;
                end
            if (gorulen == 0)
                $display("           (yazma islemi yok)");
        end

        $display("  bilgi  : kismi yazma=%0d  en uzun islem=%0d ns",
                 axil_scoreboard::kismi_yazma, axil_scoreboard::en_uzun_ns);

        $display("==============================================================");
        return ihlal;
    endfunction

endpackage
