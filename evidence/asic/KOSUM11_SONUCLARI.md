# Koşum 11 sonuçları ve Koşum 12 kararı

Tarih: 26 Ağustos 2026

## Sonuç

Koşum 11 fiziksel akışın 80 adımını tamamladı; ertelenmiş signoff
hataları nedeniyle LibreLane çıkış kodu 2 verdi. Final GDS/netlist/DEF
üretildi.

| Denetim | Sonuç |
|---|---:|
| Detaylı yönlendirme DRC | 0 |
| KLayout DRC | 0 |
| XOR | 0 |
| Netgen LVS | 0 hata |
| Güç ağı | 0 ihlal |
| Magic DRC | 7658 |
| Anten | 12 net / 15 pin |
| Hold | 80 toplam / 45 reg-reg |

## Zamanlama

- Saat hedefi değişmedi: 20 ns, 50 MHz.
- `nom_tt` setup payı: +1.358 ns.
- `nom_ss` setup payı: -10.096 ns.
- `max_ss` setup payı: -11.691 ns.
- En kötü reg-reg hold: -0.323 ns (`max_ff`).
- Reg-reg hold sayısı koşum 9'daki 687'den 45'e indi.
- En kötü setup yolu UART FIFO'dan çıktı; artık
  `u_npu.u_npu_engine.d_out[0]` ile başlayan NPU yoludur.

## Kök nedenler

1. GRT için jumper-only açıkken DRT için açık değildi. Detaylı
   yönlendirici 7591 anten diyodu ekledi.
2. `nom_tt` köşesindeki 6069 slew ihlalinin 2523'ü anten diyodu
   pinlerindedir. Daha fazla diyot eklemek slew/cap yükünü büyütür.
3. Hold ihlalleri iki NPU kümesinde yoğunlaşır: engine `state[19]` ->
   `fc_acc[]` ve SRAM `inr_b_q` -> `rdata_b_hold[]`.
4. Magic'in 7658 hatası koşumlar arasında sabittir; KLayout final GDS'te
   sıfırdır. GDS tabanlı Magic kontrolüyle kesinleştirilecektir.

## Koşum 12 değişiklikleri

- Saat hedefi 50 MHz olarak korunur.
- `DRT_ANTENNA_REPAIR_JUMPER_ONLY: true`
- `DRT_ANTENNA_REPAIR_ITERS: 5`
- `GRT_RESIZER_HOLD_SLACK_MARGIN: 0.15`
- `PL_RESIZER_HOLD_SLACK_MARGIN: 0.10` (değişmedi)
- `MAX_TRANSITION_CONSTRAINT: 1.5` (sky130 karakterize sınırı)
- `MAGIC_DRC_USE_GDS: true`
- `FIX_HOLD_FIRST` açılmaz.

Koşum 11 ham özetleri bu dizinde saklanmıştır.
