# NPU Golden Referans

Test    : tb/npu_golden/tb_npu_golden.sv
Girdi   : tb/npu_golden/test_input_pattern.mem
          490 kelime (1960 INT8), q[i] = ((37i+13) mod 256) - 128
Referans: tb/npu_golden/golden_reference.py (bagimsiz Python modeli)

## Sonuc - 16 Agustos 2026, boru hatti yeniden yapilandirmasi sonrasi

PASS

fc_acc      = [-566992, 149030, 156762, 216460]
fc_logits   = [-128, 79, 83, 109]
probs Q0.12 = [0, 225, 326, 3543]
class       = 3

Cevrim sayisi:
  Boru hatti oncesi : 964.071
  Tur 1 sonrasi     : 992.071  (depthwise requant + FC MAC ayrildi)
  Tur 2 sonrasi     : 992.083  (FC requant ayrildi)
  Toplam artis      : +28.012  (%2,9)

## Onemli

Boru hatti ayrimi SAF bir yeniden zamanlamadir; aritmetige
dokunulmamistir. Yukaridaki fc_acc degerleri boru hatti oncesiyle
BIREBIR AYNIDIR. Golden test yalnizca son sonucu degil, kanal kanal
depthwise ara sonuclarini da dogrulamaktadir.

FPGA zamanlamasi: WNS -14,199 -> -5,848 -> +1,649 ns
DSP kullanimi   : 13 -> 9
