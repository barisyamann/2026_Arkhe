# Bulgu: NPU kesmesi yazilim tarafindan temizlenemiyor

Tarih : 18 Agustos 2026
Dosya : rtl/npu/npu_csr.sv

## Belirti

ISR kesmeyi temizliyor, mret ile donuyor, ama kesme aninda
yeniden tetikleniyor. Ana dongu hic ilerlemiyor, sistem
sonsuz kesme dongusune giriyor.

## Kok neden

    end else if (reg_npu_reset || irq_clear_pulse || reg_start)
        done_sticky <= 1'b0;
    else if (done_i)
        done_sticky <= 1'b1;

Hesaplama motoru bittikten sonra DONE durumunda kaliyor ve
done_i surekli 1. irq_clear darbesi done_sticky'yi bir cevrim
sifirliyor, sonraki cevrimde done_i onu yeniden 1 yapiyor.

Yani yapiskan bayrak, seviye tabanli bir kaynakla besleniyor.
Bu haliyle yazilimin kesmeyi temizlemesi imkansiz.

## Gecici cozum (uygulandi)

ISR, irq_clear darbesiyle birlikte irq_enable bitini de
dusuruyor: *NPU_REG_CTRL = NPU_CTRL_IRQ_CLEAR (bit3 = 0).
irq_o = done_sticky && reg_irq_enable oldugu icin kesme kesiliyor.
Ana dongu bir sonraki calistirmadan once yeniden aciyor.

## Kalici cozum (onerilen, G07)

done_i'nin kenarini yakalamak:

    logic done_d;
    always_ff @(posedge clk) done_d <= done_i;
    // done_sticky yalnizca yukselen kenarda set edilsin
    else if (done_i && !done_d) done_sticky <= 1'b1;

Boylece irq_clear kalici olur ve yazilimin irq_enable ile
oynamasina gerek kalmaz.
