# Demo Degerlendirme Raporu - ARKHE

- Tarih: 2026-09-14T02:49:43+03:00
- Harness surumu: 1.0.1
- Konfigurasyon kaynagi: `arkhe_icd.json`
- Etkin konfigurasyon: `config_used.json` (SHA256 `6c75e10d81e7ba2a`)
- Veri seti: public_dataset/manifest.csv | seed: 1337
- Arayuzler: stream `COM12@1000000`, core `COM16@115200`

## 1. Ozet - RTL / Golden Model Uyumu

> **Olculen sey modelin dogrulugu degil, tasarimin golden modele sadakatidir.**
> Birincil olcut, donanimin urettigi sinifin golden modelin ayni vektor icin
> urettigi sinifla ayni olmasidir. Gercek etiket (truth) yalnizca bilgi
> amaciyla raporlanir ve puanlamada kullanilmaz.

**UYARI: veri setinde 'golden' sutunu yok - uyum orani hesaplanamadi.**

| Metrik | Deger |
|---|---|
| Gonderilen ornek | 0 |
| Golden referansi olan | 0 |
| Yanitlanan | 0 |
| **Golden ile uyum** | -  (0/0) |
| Uyusmazlik | 0 |
| Zaman asimi (referansli ornek) | 0 |
| Uyum (zaman asimlari da hata sayilirsa) | - |
| Saglamlik senaryolari | 0 / 0 |

> Not: gecikme, cerceve yaziminin bittigi an ile sonuc satirinin son baytinin
> alindigi an arasidir; UART aktarim ve ISR suresini icerir. Saf hizlandirici
> cevrim sayisi icin RTL simulasyon capraz kontrolu esastir.

## 2. Uyum Matrisi (satir = golden referans, sutun = donanim ciktisi)

_Golden referansi olan ornek yok._

## 3. Saglamlik Senaryolari (Secenek F)

| Senaryo | Sonuc | Aciklama |
|---|---|---|

## 4. Golden Modelden Ayrisan Ornekler

_Yok._

## 5. Dosyalar

- `samples.csv` - ornek bazli ham kayit ve skor hata bilgisi
- `robustness.csv` - senaryo sonuclari
- `summary.json` - makine okunabilir ozet
- `transcript.log` - core UART ham ciktisi
- `config_used.json` - kosumda gercekten kullanilan etkin ICD
