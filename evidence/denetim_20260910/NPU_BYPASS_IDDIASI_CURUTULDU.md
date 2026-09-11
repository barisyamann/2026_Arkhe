# NPU bypass iddiam OLCUMLE CURUTULDU (11 Eylul 2026)

Kullanici hakli olarak sordu: "iyice bir arastir, emin misin hem
holdun hem de MHz'nin dusebilecegine". Arastirdim ve **iddiam
yanlis cikti.**

## ILK IDDIAM (YANLIS)

"npu_tcm_sram.sv:197'deki bypass 26 setup ihlalinin kaynagi;
kaldirilirsa 20 ns'de setup kapanabilir."

    assign rdata_a = en_a_q ? (inr_a_q ? dout_a[sel_a_q] : 32'h0)
                            : rdata_a_hold;     <- BYPASS

## CURUTEN OLCUM

Ihlalli yollarin HEDEFLERI netlistten cikarildi:

    _191794_ -> u_npu.u_npu_sram.rdata_a_hold[9]
    _191816_ -> u_npu.u_npu_sram.rdata_a_hold[31]
    _191813_ -> u_npu.u_npu_sram.rdata_a_hold[28]
    _191803_ -> u_npu.u_npu_sram.rdata_a_hold[18]
    _191806_ -> u_npu.u_npu_sram.rdata_a_hold[21]
    _189610_ -> s10_rdata[9]

Netlistten birebir:

    sky130_fd_sc_hd__dfxtp_2 _191794_ (.CLK(...), .D(net12476),
        .Q(\u_npu.u_npu_sram.rdata_a_hold[9] ));

Yani ihlalli yollarin hedefi **rdata_a_hold KAYDI**.

## NEDEN BU IDDIAMI CURUTUYOR

Mux zinciri IKI yerde birden var:

    satir 172:  rdata_a_hold <= (inr_a_q ? dout_a[sel_a_q] : 32'h0);
                                           ^^^ mux KAYDIN GIRISINDE
    satir 197:  rdata_a = en_a_q ? (inr_a_q ? dout_a[sel_a_q] : ...)
                                              ^^^ mux BYPASS yolunda

Kritik yol **satir 172'deki** yoldan geciyor: SRAM dout -> 15 makroluk
mux -> rdata_a_hold kaydi.

Satir 197'deki bypass'i kaldirmak bu yola **DOKUNMAZ**. Kayit zaten
her cevrim yaziliyor ve mux onun girisinde.

## KRITIK YOLUN GERCEK DOKUMU (max_ss, olculdu)

    SRAM dout0 cikisi ............... 15,991 ns
    _097713_ mux2_2 ................. +2,100
    _097714_ mux2_2 ................. +2,236
    _097715_ mux2_2 ................. +2,589
    _097723_ mux2_2 ................. +3,184
    _097724_ a22o_2 ................. +0,870
      MUX ZINCIRI TOPLAMI ........... 10,979 ns  (yolun %91'i)
    hold12475 dlygate4sd3_1 ......... +1,084
    hedef rdata_a_hold[9] D girisi .. 28,054 ns
      VERI YOLU TOPLAMI ............. 12,063 ns

Yolun %91'i **15 makro arasindan secim yapan coklayici**.

## GERCEK SORUN: 15 MAKROLUK MUX

NPU TCM 15 SRAM makrosundan olusuyor ve okuma yolu bunlarin
cikisini tek bir 32 bitlik veri yoluna cokluyor. Sentez bunu
4 kademeli mux agacina cevirmis; max_ss kosesinde her kademe
2-3 ns.

Bu, bypass meselesi DEGIL, **mimari bir darbogaz**.

## DOGRU COZUM ADAYLARI (hicbiri olculmedi)

1. **Mux'u pipeline'a bolmek**
   Mux agacini iki cevrime yaymak: once 4'lu gruplar, sonra
   gruplar arasi secim. Her kademe ~5,5 ns olur.
   Bedeli: NPU okumasina bir cevrim daha; motor ve AXI yaniti
   birlikte duzenlenmeli.

2. **Bank secimini adres kaydiyla one almak**
   sel_a_q zaten kayitli. Secimi SRAM'e girmeden yapmak yerine
   cikista yapiyoruz. Makro basina ayri yakalama kaydi konursa
   mux kayittan SONRA gelir ve kritik yol kisalir.
   Bedeli: 15 x 32 bit ek kayit (alan artar).

3. **Makro sayisini azaltmak**
   15 yerine daha az, daha buyuk makro. PDK'da mevcut makro
   secenekleri incelenmeli.

4. **Kabul etmek**
   23 ns'de dokuz kose zaten pozitif. 50 MHz sart degilse
   bu yol hic acilmayabilir.

## SONUC

Kullanicinin sorgusu hakliydi. "Iki satir degistir, 50 MHz'e cik"
iddiam OLCUMLE CURUTULDU. Gercek sorun mimari ve cozumu iki satir
degil.

23 ns (43,5 MHz) hedefi degistirmeye deger bir kazanc icin
onemli bir RTL calismasi ve yeniden dogrulama gerekir.
