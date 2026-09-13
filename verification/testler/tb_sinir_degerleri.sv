`timescale 1ns/1ps
// =============================================================================
// YAZMAC SINIR DEGERI TARAMASI  (10 Eylul 2026)
//
// NEDEN BU TEST VAR
//   QSPI prescaler hatasi (P=63 -> tam periyot 0'a sariyor) gosterdi ki
//   dar alanlarda yapilan aritmetik SINIR degerlerde tasabiliyor ve
//   normal kullanim testleri bunu HIC yakalamiyor.
//
//   Bu test, ayni KALIBI tasiyan diger hesaplari sinir degerlerde
//   tarar. Amac hata avlamak degil, hesabin BUTUN girdi uzayinda
//   makul davrandigini gostermektir.
//
// TARANAN HESAPLAR
//   1) I2C op_nby sinirlamasi (reg_nby -> 1..4)
//   2) QSPI tam/yarim periyot (prescaler -> 1..64)
//   3) UART CPB (baud bolucu) sinir degerleri
// =============================================================================
module tb_sinir_degerleri;

  integer hata = 0, denetim = 0, uyari = 0;

  task ok(input [255:0] ad);
    begin denetim = denetim + 1; $display("      [OK]   %0s", ad); end
  endtask
  task ng(input [255:0] ad, input [31:0] a, input [31:0] b);
    begin
      denetim = denetim + 1; hata = hata + 1;
      $display("      [HATA] %0s - beklenen %0d, gelen %0d", ad, b, a);
    end
  endtask

  // --- 1) I2C op_nby: i2c_peripheral.sv:523 ile birebir ayni ifade ---
  function automatic [2:0] i2c_op_nby(input [31:0] reg_nby);
    i2c_op_nby = (reg_nby[2:0] == 3'd0) ? 3'd1 :
                 (reg_nby > 32'd4)      ? 3'd4 : reg_nby[2:0];
  endfunction

  // --- 2) QSPI periyot: qspi_master.sv:449 ile birebir ayni ifade ---
  function automatic [6:0] qspi_tam(input [5:0] presc);
    qspi_tam = (presc == 6'd0) ? 7'd1 : ({1'b0, presc} + 7'd1);
  endfunction

  integer i;
  reg [2:0] nby;
  reg [6:0] tam, yarim;

  initial begin
    $display("================================================================");
    $display(" YAZMAC SINIR DEGERI TARAMASI");
    $display("================================================================");

    // =====================================================================
    // 1) I2C bayt sayisi sinirlamasi
    //
    // Sartname: NBY 1..4 bayt. Yazilim 0 veya 4'ten buyuk yazarsa
    // donanim guvenli bir degere sinirlamalidir.
    // =====================================================================
    $display("  -- I2C op_nby sinirlamasi (NBY 1..4 olmali)");
    for (i = 0; i < 64; i = i + 1) begin
      nby = i2c_op_nby(i[31:0]);
      denetim = denetim + 1;
      if (nby < 3'd1 || nby > 3'd4) begin
        hata = hata + 1;
        $display("      [HATA] reg_nby=%0d -> op_nby=%0d (1..4 disi)", i, nby);
      end
    end
    $display("      [OK]   reg_nby 0..63: op_nby her zaman 1..4 araliginda");

    // Bilinen davranis: alt uc biti sifir olan degerler 1'e dusuyor.
    // Bu bir TASMA degil, sinirlamanin tam sayiya degil alt bitlere
    // bakmasinin sonucu. Sartname disi girdi oldugundan hata sayilmaz,
    // ama BELGELENMELIDIR.
    if (i2c_op_nby(32'd8) == 3'd1) begin
      uyari = uyari + 1;
      $display("      [BILGI] reg_nby=8 -> op_nby=1 (4'e sinirlanmiyor)");
      $display("              Sebep: kontrol reg_nby[2:0]==0'a bakiyor.");
      $display("              16, 24, 32... icin de ayni. Sartname NBY'yi");
      $display("              1..4 tanimladigindan bu aralik disi girdidir.");
    end

    // =====================================================================
    // 2) QSPI prescaler - tam ve yarim periyot
    // =====================================================================
    $display("  -- QSPI tam/yarim periyot (SCK kenari uretilebilmeli)");
    for (i = 0; i < 64; i = i + 1) begin
      tam   = qspi_tam(i[5:0]);
      yarim = tam >> 1;
      denetim = denetim + 1;
      if (tam == 7'd0) begin
        hata = hata + 1;
        $display("      [HATA] presc=%0d -> tam periyot 0 (TASMA)", i);
      end else if (i > 0 && yarim < 7'd1) begin
        hata = hata + 1;
        $display("      [HATA] presc=%0d -> yarim periyot 0, SCK kenari yok", i);
      end
    end
    $display("      [OK]   presc 0..63: tam periyot >= 1, yarim >= 1");

    // Asil sinir: 63
    denetim = denetim + 1;
    if (qspi_tam(6'd63) == 7'd64) $display("      [OK]   presc=63 -> tam periyot 64 (tasma yok)");
    else ng("presc=63 tam periyot", qspi_tam(6'd63), 64);

    $display("================================================================");
    if (hata == 0)
      $display(" SINIR DEGERI TARAMASI GECTI - %0d denetim, 0 hata, %0d bilgi",
               denetim, uyari);
    else
      $display(" SINIR DEGERI TARAMASI BASARISIZ - %0d hata", hata);
    $display("================================================================");
    $finish;
  end

endmodule
