# A1 — NPU hakemliğinin motor dalı kapatıldı

**Tarih:** 13 Eylül 2026
**Kapsam:** `rtl/npu/npu_accelerator.sv` satır 206–209
**Test:** `tb/tb_npu_accelerator.sv` (11 → **16 denetim**)
**Mutasyon:** `npu_hakem_motor_dali`

---

## Açık neydi

`KAPSAM_ANALIZI_20260912.md` şunu ölçmüştü:

    npu_accelerator   statement %0,0   <- hicbir blok testinde YOK

12 Eylül'de `tb_npu_accelerator.sv` yazıldı (11 denetim) ve sarmalayıcı
test edilmeye başlandı. Ancak modülün **hakemlik mantığı** iki dallıdır:

```systemverilog
assign tcm_en_a    = eng_wr_req ? 1'b1            : ram_en_a;
assign tcm_we_a    = eng_wr_req ? axi_ram_we_a    : ram_we_a;
assign tcm_addr_a  = eng_wr_req ? axi_ram_addr_a  : ram_addr_a;
assign tcm_wdata_a = eng_wr_req ? axi_ram_wdata_a : ram_wdata_a;
```

Test yalnızca **CPU dalını** (`eng_wr_req = 0`) uyarıyordu. `eng_wr_req`
hiç 1 olmuyordu, çünkü o sinyal ancak **hesaplama motoru sonucunu
TCM'e yazmak istediğinde** yükselir — bunun için NPU'nun gerçekten
çalışması gerekir.

Bu açık 12 Eylül'de dürüstçe "bilinen sınır" olarak belgelenmişti.
Bu belge onun kapatılmasını anlatır.

---

## Motoru uyandırmak — iki engel

### 1. `weights_ready` biti

İlk denemede yalnızca `REG_CTRL` bit0 (`start`) yazıldı; motor
çalışmadı. `npu_csr.sv` satır 76 sebebi gösteriyor:

```systemverilog
assign start_o = reg_start && reg_weights_ready;
```

`weights_ready` (bit 4) **yapışkan** bir bittir ve ayrıca
kurulmalıdır. Test şimdi iki yazma yapar:

    csr_yaz(0x00, 0x00000010);   // weights_ready
    csr_yaz(0x00, 0x00000011);   // weights_ready + start

### 2. Çıkarım süresi

Motor başladı ama yine yazmaya gelmedi. Tanı çıktısı motorun
`state = 5` (`CONV_ReLU_FC`) durumunda olduğunu gösterdi — yani
ilerliyordu, sadece süre yetmiyordu.

`tb_npu_audio` ölçümüne göre tam çıkarım **85.587 çevrim** sürer.
Bekleme 4.000 → 60.000 → **120.000** çevrime çıkarıldı; motor
`state = 13` (`DONE`) durumuna ulaştı.

---

## İlk test dekoratifti — mutasyon yakaladı

Test geçer hâle geldikten sonra mutasyon denendi:

```systemverilog
assign tcm_we_a = ram_we_a;   // MUTASYON: motor dali YOK SAYILIR
```

**Test yine geçti.** Yani hakem motor dalını hiç seçmese bile test
bunu fark etmiyordu.

**Sebep:** sayaçlar `eng_wr_req` sinyalini izliyordu, mutasyon ise
`tcm_we_a`'yı bozuyordu. Test "dal seçildi mi" sorusunu ölçüyordu,
"doğru veriyi taşıdı mı" sorusunu değil.

### Düzeltme — veri yolu denetimi

Gözlemciye, hakemin **her çevrimde doğru kaynağı TCM'e bağladığını**
doğrulayan bir denetim eklendi:

```systemverilog
if (dut.eng_wr_req) begin
    if (dut.tcm_we_a    !== dut.axi_ram_we_a   ||
        dut.tcm_addr_a  !== dut.axi_ram_addr_a ||
        dut.tcm_wdata_a !== dut.axi_ram_wdata_a||
        dut.tcm_en_a    !== 1'b1)
        veri_yolu_hatasi++;
end else if (dut.ram_en_a) begin
    // CPU kazanirken de TCM CPU kaynagini tasimali
    ...
end
```

Mutasyon artık **4 çevrimde yakalanıyor** ve test kırmızıya dönüyor.

---

## Ölçülen sonuç (temiz RTL)

    motor dali secildi    : 4 cevrim     (WRITE_OUT_0..3 ile tutarli)
    CPU dali secildi      : 74 cevrim
    motor kazanirken stall: 4 / 4        (her cevrim AXI bastirildi)
    veri yolu hatasi      : 0

**Dört denetim eklendi:**

1. Hakemliğin **MOTOR** dalı uyarıldı (sayaç > 0)
2. Hakem her çevrimde **doğru kaynağı** TCM'e bağladı (veri yolu)
3. Hakemliğin **CPU** dalı da çalışıyor (iki dal birlikte yaşıyor)
4. Motor kazanırken AXI denetleyicisi **her çevrim** bastırıldı
   (`stall_i`, satır 286 — veri yarışı yok)

Ayrıca motor trafiğinin CPU verisini bozmadığı doğrulanır.

---

## Sonuç

| | Önce | Sonra |
|---|---|---|
| `tb_npu_accelerator` denetim | 11 | **16** |
| Hakemlik motor dalı | **uyarılmıyor** | **uyarılıyor + doğrulanıyor** |
| Mutasyon kampanyası | 8 | **9** |
| Regresyon | 35 test / 677 denetim | **36 test / 688 denetim** |

`docs/TESLIM_OZETI.md` içindeki "Bilinen doğrulama sınırları"
listesinden **birinci madde kaldırılmıştır**.

---

## Alınan ders

Bir kapsam açığını kapatmak için yazılan testin kendisi de
**dekoratif olabilir**. Bu olayda test, hedeflediği dalı uyandırdı
ama o dalın *doğru çalıştığını* ölçmedi — yalnızca *seçildiğini*
ölçtü.

Farkı ortaya çıkaran şey mutasyon denemesiydi. Yeni yazılan her
testin, hedeflediği hatayı gerçekten yakaladığı kampanyaya
eklenerek kanıtlanmalıdır.
