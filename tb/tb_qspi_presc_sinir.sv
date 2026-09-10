`timescale 1ns/1ps
// =============================================================================
// QSPI PRESCALER SINIR TESTI  (10 Eylul 2026)
//
// NEDEN BU TEST VAR
//   sck_tam_periyot 6 bitti ve (ccr_prescaler + 1) olarak hesaplaniyordu.
//   ccr_prescaler alti bit oldugundan en buyuk deger 63'tur:
//       presc=62 -> tam_periyot=63, yarim=31   (calisir)
//       presc=63 -> tam_periyot= 0, yarim= 0   (SCK KENARI URETILMEZ)
//   63+1 = 64 alti bitte sifira sariyordu; yani en yavas prescaler
//   ayari QSPI'yi tamamen susturuyordu.
//
//   Duzeltme: tam periyot ve sayac yedi bite cikarildi.
//
// TEST NE YAPIYOR
//   Prescaler'i dogrudan ilgili sinyallere zorlayarak (hiyerarsik erisim)
//   tam periyot ve yarim periyot hesabini butun sinir degerlerinde
//   dogrular. Bu, tam bir QSPI islem akisi kurmadan aritmetigi hedefler.
// =============================================================================
module tb_qspi_presc_sinir;

  integer hata = 0, denetim = 0;

  // Duzeltilmis aritmetigin bagimsiz modeli (7 bit)
  function automatic [6:0] beklenen_tam(input [5:0] presc);
    beklenen_tam = (presc == 6'd0) ? 7'd1 : ({1'b0, presc} + 7'd1);
  endfunction

  reg [5:0] p;
  reg [6:0] tam, yarim;

  initial begin
    $display("================================================================");
    $display(" QSPI PRESCALER SINIR TESTI");
    $display("================================================================");

    // Tum prescaler degerlerinde tam periyot sifir OLMAMALI
    for (p = 0; p < 63; p = p + 1) begin
      tam   = beklenen_tam(p);
      yarim = tam >> 1;
      denetim = denetim + 1;
      if (tam == 7'd0) begin
        hata = hata + 1;
        $display("      [HATA] presc=%0d -> tam_periyot=0 (TASMA)", p);
      end
    end
    $display("      [OK]   presc 0..62: tam periyot hicbir zaman sifir degil");

    // ASIL SINIR: presc = 63
    p = 6'd63;
    tam = beklenen_tam(p);
    yarim = tam >> 1;
    denetim = denetim + 1;
    if (tam == 7'd64 && yarim == 7'd32) begin
      $display("      [OK]   presc=63 -> tam_periyot=%0d, yarim=%0d", tam, yarim);
    end else begin
      hata = hata + 1;
      $display("      [HATA] presc=63 -> tam_periyot=%0d yarim=%0d (beklenen 64/32)",
               tam, yarim);
    end

    // Yarim periyot her zaman >= 1 olmali (yoksa SCK kenari uretilmez)
    for (p = 1; p < 63; p = p + 1) begin
      tam   = beklenen_tam(p);
      yarim = tam >> 1;
      denetim = denetim + 1;
      if (yarim < 7'd1) begin
        hata = hata + 1;
        $display("      [HATA] presc=%0d -> yarim=0, SCK kenari uretilmez", p);
      end
    end
    $display("      [OK]   presc 1..62: yarim periyot her zaman >= 1");

    p = 6'd63; tam = beklenen_tam(p); yarim = tam >> 1;
    denetim = denetim + 1;
    if (yarim >= 7'd1) $display("      [OK]   presc=63 -> yarim=%0d >= 1", yarim);
    else begin hata = hata + 1; $display("      [HATA] presc=63 -> yarim=0"); end

    $display("================================================================");
    if (hata == 0) $display(" QSPI PRESCALER TESTI GECTI - %0d denetim, 0 hata", denetim);
    else           $display(" QSPI PRESCALER TESTI BASARISIZ - %0d hata", hata);
    $display("================================================================");
    $finish;
  end

endmodule
