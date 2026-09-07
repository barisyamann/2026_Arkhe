#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Arkhe NPU - TFLite Micro Speech "TinyConv" yazilim referans modeli.

Bu modul, npu_compute_engine.sv'nin gerceklestirdigi aritmetigin BIREBIR
yazilim karsiligidir. Sartname EK-1 su isteri koyar:

    "Yarismacilar, YZ hizlandiricisini kullanarak, yazilim ile gerceklenen
     modelin dogrulugunu (accuracy) %10'luk bir pencere dahilinde
     yakalamalidir."

Burada referans "yazilim gerceklemesi"dir. Ayni 1960 INT8 girdi hem bu
modele hem RTL'e verilir; siniflandirmalar karsilastirilir.

Kaynak: tb/npu_golden/golden_reference.py (deterministik tek vektor testi).
Bu surum yeniden kullanilabilir bir infer() fonksiyonuna donusturulmustur.
"""
from pathlib import Path

# -----------------------------------------------------------------------------
# TFLite Micro sabit nokta ilkelleri
# -----------------------------------------------------------------------------

def trunc_div(a, b):
    """C'nin sifira dogru yuvarlayan tamsayi bolmesi (Python'unki asagi yuvarlar)."""
    return a // b if a >= 0 else -((-a) // b)


def sat_round_high_mul(a, b):
    """gemmlowp SaturatingRoundingDoublingHighMul."""
    if a == -(1 << 31) and b == -(1 << 31):
        return (1 << 31) - 1
    ab = a * b
    nudge = (1 << 30) if ab >= 0 else (1 - (1 << 30))
    return trunc_div(ab + nudge, 1 << 31)


def rounding_divide_by_pot(x, exponent):
    """gemmlowp RoundingDivideByPOT."""
    mask = (1 << exponent) - 1
    remainder = x & mask
    threshold = (mask >> 1) + (1 if x < 0 else 0)
    return (x >> exponent) + (1 if remainder > threshold else 0)


def multiply_quantized(x, multiplier, right_shift):
    return rounding_divide_by_pot(sat_round_high_mul(x, multiplier), right_shift)


# -----------------------------------------------------------------------------
# Model sabitleri - micro_speech_quantized.tflite'tan cikarilmistir
# -----------------------------------------------------------------------------
DW_MULT   = [1653229999, 1516545207, 2000799311, 1159928266,
             1498403863, 1285645282, 2146175029, 1756589032]
DW_RSHIFT = [10, 12, 10, 10, 10, 10, 10, 10]
FC_MULT   = 1932201080
FC_RSHIFT = 11
FC_ZERO   = 14          # cikis sifir noktasi

SINIF_ADLARI = ["SILENCE", "UNKNOWN", "YES", "NO"]

GIRIS_UZUNLUK = 1960    # 49 zaman adimi x 40 frekans bolmesi


def _read_hex_signed(path, bits):
    vals = []
    for line in Path(path).read_text().split():
        u = int(line, 16)
        if u >= (1 << (bits - 1)):
            u -= 1 << bits
        vals.append(u)
    return vals


class NpuReferansModel:
    """Agirliklari bir kez okur, sonra istenildigi kadar cikarim yapar."""

    def __init__(self, weights_dir=None):
        if weights_dir is None:
            here = Path(__file__).resolve().parent
            adaylar = [here / "weights", here.parent / "weights",
                       here.parent.parent / "weights"]
            weights_dir = next((p for p in adaylar
                                if (p / "dw_weights.mem").exists()), None)
            if weights_dir is None:
                raise FileNotFoundError("weights/ klasoru bulunamadi")
        weights_dir = Path(weights_dir)

        self.dw_weights = _read_hex_signed(weights_dir / "dw_weights.mem", 8)
        self.dw_bias    = _read_hex_signed(weights_dir / "dw_bias.mem", 32)
        self.fc_weights = _read_hex_signed(weights_dir / "fc_weights.mem", 8)
        self.fc_bias    = _read_hex_signed(weights_dir / "fc_bias.mem", 32)
        self.exp_lut    = [int(x, 16) for x in
                           (weights_dir / "softmax_exp_lut.mem").read_text().split()]

        assert len(self.dw_weights) == 640,   len(self.dw_weights)
        assert len(self.fc_weights) == 16000, len(self.fc_weights)

    # -------------------------------------------------------------------------
    def depthwise_relu(self, qin):
        """DepthwiseConv2D (10x8 kernel, 8 filtre, stride 2, SAME) + ReLU.

        Cikti: 25 x 20 x 8 = 4000 elemanli duz vektor (UINT8 araligi 0..255).
        """
        dw_w, dw_b = self.dw_weights, self.dw_bias
        out = []
        for t in range(25):
            for f in range(20):
                for d in range(8):
                    acc = dw_b[d]
                    for kh in range(10):
                        ti = t * 2 - 4 + kh
                        if not (0 <= ti < 49):
                            continue
                        base = ti * 40
                        for kw in range(8):
                            fi = f * 2 - 3 + kw
                            if 0 <= fi < 40:
                                # Girdi sifir noktasi -128 -> +128 ile kaydir
                                acc += (qin[base + fi] + 128) * dw_w[kh * 64 + kw * 8 + d]
                    sc = multiply_quantized(acc, DW_MULT[d], DW_RSHIFT[d])
                    out.append(max(0, min(255, sc)))
        return out

    def fully_connected(self, conv):
        """Flatten + FullyConnected: 4000 -> 4 sinif."""
        fc_acc = list(self.fc_bias)
        fw = self.fc_weights
        for c in range(4):
            base = c * 4000
            s = fc_acc[c]
            for i, y in enumerate(conv):
                s += y * fw[base + i]
            fc_acc[c] = s
        logits = []
        for a in fc_acc:
            q = multiply_quantized(a, FC_MULT, FC_RSHIFT) + FC_ZERO
            logits.append(max(-128, min(127, q)))
        return fc_acc, logits

    def softmax_q12(self, logits):
        """Donanimla ayni: max cikarma + exp LUT + tek bolucu. Q0.12 formati."""
        m = max(logits)
        exps = [4096 if m - x <= 0 else (0 if m - x >= 256 else self.exp_lut[m - x])
                for x in logits]
        den = sum(exps)
        return [((e << 12) // den) if den else 0 for e in exps]

    def infer(self, qin):
        """1960 INT8 girdi -> sonuc sozlugu."""
        if len(qin) != GIRIS_UZUNLUK:
            raise ValueError("girdi %d olmali, %d geldi" % (GIRIS_UZUNLUK, len(qin)))
        conv        = self.depthwise_relu(qin)
        fc_acc, lg  = self.fully_connected(conv)
        probs       = self.softmax_q12(lg)
        cls = 0
        for i in range(1, 4):
            if lg[i] > lg[cls]:
                cls = i
        return dict(fc_acc=fc_acc, logits=lg, probs=probs,
                    sinif=cls, sinif_adi=SINIF_ADLARI[cls])


if __name__ == "__main__":
    # Kendi kendini sinama: npu_golden ile ayni deterministik vektor
    m = NpuReferansModel()
    qin = [((i * 37 + 13) % 256) - 128 for i in range(GIRIS_UZUNLUK)]
    r = m.infer(qin)
    print("fc_acc      =", r["fc_acc"])
    print("logits      =", r["logits"])
    print("probs Q0.12 =", r["probs"])
    print("sinif       = %d (%s)" % (r["sinif"], r["sinif_adi"]))
