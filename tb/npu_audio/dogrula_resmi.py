#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Referans modelimizi RESMI TFLite yorumlayicisina karsi dogrular.

NEDEN GEREKLI - DOGRULAMADAKI DONGUSELLIK

Bu noktaya kadarki zincir sudur:

    weights/*.mem  ->  npu_ref_model.py  ->  beklenen degerler
                                              |
                                              v
                                      tb_npu_audio.sv  ->  RTL

RTL, kendi Python modelimize karsi dogrulaniyordu. Model yanlis olsaydi
RTL de "dogru" gorunurdu. Yani zincirin BAGIMSIZ bir capasi yoktu.

COZUM

micro_speech_quantized.tflite YALNIZCA standart islemciler kullanir
(Conv2D, FullyConnected, Relu, Reshape, Softmax) - ozel Signal* oplari
yalnizca ON ISLEYICI modelindedir. Yani standart LiteRT bu modeli
calistirabilir.

Bu betik ayni girdiyi hem resmi yorumlayiciya hem bizim modele verir ve
karsilastirir. Uyum saglanirsa zincirin capasi Google'in kendi
gerceklemesi olur.

    pip install ai-edge-litert

OLCEK DONUSUMU

    Resmi cikis : int8, scale 1/256, zero_point -128
                  olasilik = (q + 128) / 256
    Bizim cikis : Q0.12 tamsayi
                  olasilik = probs / 4096

KULLANIM

    python tb/npu_audio/dogrula_resmi.py
"""
import json
import sys
from pathlib import Path

import numpy as np

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
sys.path.insert(0, str(HERE))

from npu_ref_model import NpuReferansModel, SINIF_ADLARI  # noqa: E402

MODEL = ROOT / "model" / "micro_speech_quantized.tflite"

# Olasilik farki toleransi (yuzde puan). Iki gerceklemenin softmax
# kuantizasyonu farkli oldugu icin (1/256 vs 1/4096) birkac puanlik
# yuvarlama farki beklenir. Sartname EK-1 %10 pencere istiyor.
TOLERANS_YUZDE = 3.0


def vektorleri_oku():
    meta = json.loads((HERE / "vectors_meta.json").read_text(encoding="utf-8"))
    words = [int(x, 16) for x in (HERE / "vectors.mem").read_text().split()]

    vektorler = []
    for i, v in enumerate(meta["vektorler"]):
        w = words[i * 490:(i + 1) * 490]
        q = []
        for x in w:
            for b in range(4):
                u = (x >> (8 * b)) & 0xFF
                q.append(u - 256 if u >= 128 else u)
        vektorler.append((v, q[:1960]))
    return vektorler


def main():
    try:
        from ai_edge_litert.interpreter import Interpreter
    except ImportError:
        print("ai-edge-litert kurulu degil:  pip install ai-edge-litert")
        return 1

    if not MODEL.exists():
        print("Model bulunamadi: %s" % MODEL)
        return 1

    it = Interpreter(model_path=str(MODEL))
    it.allocate_tensors()
    gi = it.get_input_details()[0]
    go = it.get_output_details()[0]

    model = NpuReferansModel()
    vektorler = vektorleri_oku()

    print("=" * 70)
    print(" REFERANS MODEL  vs  RESMI TFLite YORUMLAYICISI")
    print(" Model: %s" % MODEL.name)
    print("=" * 70)

    hata = 0
    for v, q in vektorler:
        it.set_tensor(gi["index"], np.array([q], dtype=np.int8))
        it.invoke()
        resmi_q = it.get_tensor(go["index"])[0].astype(np.int32) + 128
        resmi_sinif = int(np.argmax(resmi_q))
        resmi_yuzde = resmi_q / 256.0 * 100.0

        r = model.infer(q)
        bizim_sinif = r["sinif"]
        bizim_yuzde = np.array(r["probs"]) / 4096.0 * 100.0

        sapma = float(np.max(np.abs(resmi_yuzde - bizim_yuzde)))
        sinif_ok = (resmi_sinif == bizim_sinif)
        sapma_ok = (sapma <= TOLERANS_YUZDE)

        durum = "OK" if (sinif_ok and sapma_ok) else "HATA"
        if durum == "HATA":
            hata += 1

        print("\n%-28s [%s]" % (v["ad"], durum))
        print("   resmi : %-8s  %s" % (SINIF_ADLARI[resmi_sinif],
                                       np.round(resmi_yuzde, 1)))
        print("   bizim : %-8s  %s" % (SINIF_ADLARI[bizim_sinif],
                                       np.round(bizim_yuzde, 1)))
        print("   en buyuk olasilik sapmasi: %.2f puan" % sapma)

    print("\n" + "=" * 70)
    if hata:
        print(" BASARISIZ - %d / %d vektorde uyumsuzluk" % (hata, len(vektorler)))
        return 1
    print(" GECTI - %d / %d vektor, siniflar ayni, sapma <= %.1f puan"
          % (len(vektorler), len(vektorler), TOLERANS_YUZDE))
    print("")
    print(" Sartname EK-1: 'yazilim ile gerceklenen modelin dogrulugunu")
    print(" %10'luk bir pencere dahilinde yakalamalidir' -> KARSILANDI.")
    print(" Referans, Google'in kendi gerceklemesidir.")
    print("=" * 70)
    return 0


if __name__ == "__main__":
    sys.exit(main())
