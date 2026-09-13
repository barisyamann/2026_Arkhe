#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
TFLite Micro Speech on-isleme zinciri - NumPy gerceklemesi.

WAV (16 kHz, mono, 1000 ms)  ->  49 x 40 = 1960 INT8 spektrogram

NEDEN ELLE YAZILDI

Resmi on isleyici (audio_preprocessor_int8.tflite) TFLM'e OZGU ozel
islemciler kullanir:

    SignalWindow   SignalFftAutoScale   SignalRfft   SignalEnergy
    SignalFilterBank   SignalFilterBankSquareRoot
    SignalFilterBankSpectralSubtraction   SignalPCAN   SignalFilterBankLog

Standart TensorFlow / LiteRT bu islemcileri tanimaz; calistirmak icin
kaynaktan derlenen tflm_runtime gerekir ve Windows icin hazir paketi
yoktur. Bu yuzden zincir microfrontend algoritmasina gore yeniden
yazilmistir.

KAPSAM VE SINIR

Bu gerceklemede aritmetik KAYAN NOKTADIR; C kutuphanesinin sabit nokta
sonuclarina BIT-BIREBIR esit degildir. Amac bit esitligi degil, gercek
ses klibinin dogru sinifa dusmesidir.

Bu kabul edilebilir cunku ON ISLEME CIPTE DEGILDIR: sartname mimarisinde
ses verisi UART-stream uzerinden ZATEN islenmis olarak gelir; hizlandiricinin
girdisi 1960 INT8 spektrogram degeridir. Cipin dogrulugu, ayni girdide
yazilim modeliyle bit-birebir esitlik uzerinden ayrica kanitlanmistir
(bkz. tb/npu_audio/tb_npu_audio.sv).

Gerceklemenin dogrulugu KENDINI SINAR: zincir yanlissa yes_1000ms.wav
YES sinifina dusmez.

Kaynak: tensorflow/lite/experimental/microfrontend/lib/
"""
import struct
import wave
from pathlib import Path

import numpy as np

# --- microfrontend yapilandirmasi (micro_features_generator.cc) -------------
ORNEK_HIZI       = 16000
PENCERE_MS       = 30
ADIM_MS          = 20
KANAL_SAYISI     = 40
ALT_BANT_HZ      = 125.0
UST_BANT_HZ      = 7500.0
FFT_BOYU         = 512

# Gurultu azaltma
NR_EVEN_SMOOTH   = 0.025
NR_ODD_SMOOTH    = 0.06
NR_MIN_SIGNAL    = 0.05

# PCAN otomatik kazanc
PCAN_STRENGTH    = 0.95
PCAN_OFFSET      = 80.0

# micro_features olcekleme: value_div = int(25.6 * 26.0 + 0.5)
VALUE_SCALE      = 256
VALUE_DIV        = 666

# PCAN kazanc olcegi - C tarafindaki (1 << gain_bits) >> snr_shift karsiligi.
# Kayan nokta gerceklemede bu olcek kayboldugu icin ampirik kalibre edilir;
# olcut, dort referans klibin dogru sinifa dusmesidir.
PCAN_SCALE       = 1.0

PENCERE_ORNEK    = ORNEK_HIZI * PENCERE_MS // 1000      # 480
ADIM_ORNEK       = ORNEK_HIZI * ADIM_MS // 1000         # 320
ZAMAN_ADIMI      = 49


def wav_oku(yol):
    """16 kHz, mono, 16-bit PCM WAV -> float64 dizi (-32768..32767)."""
    with wave.open(str(yol), "rb") as w:
        if w.getnchannels() != 1:
            raise ValueError("mono bekleniyordu: %s" % yol)
        if w.getsampwidth() != 2:
            raise ValueError("16-bit bekleniyordu: %s" % yol)
        if w.getframerate() != ORNEK_HIZI:
            raise ValueError("16 kHz bekleniyordu: %s" % yol)
        ham = w.readframes(w.getnframes())
    n = len(ham) // 2
    return np.array(struct.unpack("<%dh" % n, ham), dtype=np.float64)


def freq_to_mel(f):
    return 1127.0 * np.log1p(f / 700.0)


def filtre_bankasi_kur():
    """Ucgen mel filtre bankasi agirliklari (filterbank_util.c ile ayni duzen).

    Donen: (KANAL_SAYISI, FFT_BOYU//2 + 1) agirlik matrisi
    """
    mel_alt  = freq_to_mel(ALT_BANT_HZ)
    mel_ust  = freq_to_mel(UST_BANT_HZ)
    # num_channels + 1 aralik -> merkez frekanslari
    mel_araligi  = (mel_ust - mel_alt) / (KANAL_SAYISI + 1)
    merkezler = mel_alt + mel_araligi * np.arange(1, KANAL_SAYISI + 2)

    bin_sayisi   = FFT_BOYU // 2 + 1
    hz_per_bin   = (ORNEK_HIZI / 2.0) / (FFT_BOYU / 2.0)
    bin_hz       = np.arange(bin_sayisi) * hz_per_bin
    bin_mel      = freq_to_mel(np.maximum(bin_hz, 0.0))

    W = np.zeros((KANAL_SAYISI, bin_sayisi), dtype=np.float64)
    for c in range(KANAL_SAYISI):
        sol   = mel_alt if c == 0 else merkezler[c - 1]
        orta  = merkezler[c]
        sag   = merkezler[c + 1]
        for b in range(bin_sayisi):
            m = bin_mel[b]
            if m <= sol or m >= sag:
                continue
            if m <= orta:
                W[c, b] = (m - sol) / (orta - sol)
            else:
                W[c, b] = (sag - m) / (sag - orta)
    return W


_FB = None


def ozellik_cikar(ornekler):
    """1 saniyelik ornek dizisi -> (49, 40) INT8 ozellik matrisi."""
    global _FB
    if _FB is None:
        _FB = filtre_bankasi_kur()

    # Hanning benzeri pencere (window_util.c)
    i = np.arange(PENCERE_ORNEK)
    pencere = 0.5 - 0.5 * np.cos(2.0 * np.pi * (i + 0.5) / PENCERE_ORNEK)

    # Gurultu tahmini kanal basina tutulur ve cerceveler boyunca guncellenir
    gurultu_tahmini = np.zeros(KANAL_SAYISI, dtype=np.float64)
    ilk_cerceve = True

    cikti = np.zeros((ZAMAN_ADIMI, KANAL_SAYISI), dtype=np.int8)

    for t in range(ZAMAN_ADIMI):
        bas = t * ADIM_ORNEK
        parca = ornekler[bas:bas + PENCERE_ORNEK]
        if len(parca) < PENCERE_ORNEK:
            parca = np.pad(parca, (0, PENCERE_ORNEK - len(parca)))

        spektrum = np.fft.rfft(parca * pencere, n=FFT_BOYU)
        enerji   = (spektrum.real ** 2 + spektrum.imag ** 2)

        # Filtre bankasi + karekok  (SignalFilterBank + SquareRoot)
        bant = np.sqrt(np.maximum(_FB @ enerji, 0.0))

        # --- Gurultu azaltma / spektral cikarma ---------------------------
        # Cift ve tek kanallar farkli duzlestirme katsayisi kullanir
        duzlestirme = np.where(np.arange(KANAL_SAYISI) % 2 == 0,
                               NR_EVEN_SMOOTH, NR_ODD_SMOOTH)
        if ilk_cerceve:
            gurultu_tahmini = bant.copy()
            ilk_cerceve = False
        else:
            gurultu_tahmini = (duzlestirme * bant
                               + (1.0 - duzlestirme) * gurultu_tahmini)
        cikarilmis = np.maximum(bant - gurultu_tahmini,
                                NR_MIN_SIGNAL * bant)

        # --- PCAN otomatik kazanc ----------------------------------------
        # gain = (noise + offset) ^ -strength
        #
        # C gerceklemesinde kazanc tablosu (1 << gain_bits) ile olceklenir
        # ve sonra snr_shift kadar kaydirilir; net etki isaretin kullanilabilir
        # bir tamsayi araliginda kalmasidir. Kayan noktada o olcek kaybolur,
        # bu yuzden PCAN_SCALE ile geri verilir (bkz. modul basligi).
        kazanc = np.power(gurultu_tahmini + PCAN_OFFSET, -PCAN_STRENGTH)
        kazancli = cikarilmis * kazanc * PCAN_SCALE

        # --- Logaritmik olcekleme ----------------------------------------
        logged = np.log1p(np.maximum(kazancli, 0.0)) * (1 << 6)

        # --- micro_features INT8 olceklemesi ------------------------------
        deger = np.floor((logged * VALUE_SCALE + VALUE_DIV // 2) / VALUE_DIV) - 128
        cikti[t] = np.clip(deger, -128, 127).astype(np.int8)

    return cikti


def wav_to_features(yol):
    """WAV yolu -> 1960 elemanli INT8 listesi (zaman-major, RTL duzeni)."""
    ornekler = wav_oku(yol)
    m = ozellik_cikar(ornekler)
    return [int(x) for x in m.reshape(-1)]


if __name__ == "__main__":
    import sys
    HERE = Path(__file__).resolve().parent
    for ad in ["yes_1000ms.wav", "no_1000ms.wav",
               "silence_1000ms.wav", "noise_1000ms.wav"]:
        p = HERE / "testdata" / ad
        if not p.exists():
            print("%-22s YOK" % ad)
            continue
        f = wav_to_features(p)
        print("%-22s %d deger  min=%4d max=%4d ort=%7.2f"
              % (ad, len(f), min(f), max(f), sum(f) / len(f)))
