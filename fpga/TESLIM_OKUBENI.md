# FPGA Demo

Şartname §5.2 ödül kriteri FPGA üzerinde test senaryolarının
çalıştırılmasını istiyor. Bu dizin o doğrulamanın çıktılarını içerir.

---

## İki sürüm var — karıştırmayın

### `nexys_demo/` — GÜNCEL DEMO

Ortak SoC RTL'i + Pmod UART2 sarmalayıcısı. Jüri gösterimi için
kullanılacak sürüm budur.

    bitstream/     nexys_top.bit — karta programlanacak dosya
    firmware/      gömülü yazılım kaynakları ve derlenmiş imaj
    constraints/   Nexys A7-100T pin kısıtları (XDC)
    rtl/           FPGA'ye özgü üst seviye sarmalayıcı
    demo/          demo senaryoları ve kayıtları
    reports/       Vivado sentez/implementasyon raporları
    build_fpga.tcl Vivado proje kurulum betiği

### `JURI_FPGA_TESTI/` — TANILAMA SÜRÜMÜ

5 Eylül 2026 tarihli, tek USB üzerinden çalışan tanılama firmware'i.
Kart üzerinde hızlı kontrol için kullanılır.

**UYARI:** Bu sürümün `.bit` / `.mcs` çiftini `nexys_demo/`
sürümüyle karıştırmayın — farklı pin haritaları ve firmware
kullanırlar.

---

## Doğrulanan senaryolar

| Senaryo | Sonuç |
|---|---|
| Çevre birimi testleri | **34/34** |
| NPU testleri | **15/15** |
| Self-checking boot + çevre birimi | `sistem_gercek_boot` ile doğrulandı |
| YZ hızlandırıcı altın vektör | Kartta `[0, 225, 326, 3543]` |

---

## Sistem saati

FPGA hedefi **50 MHz**'dir. ASIC hedefi 43,2 MHz'dir; ikisi farklıdır
ve şartname buna izin verir ("farklı MHz'lerde çalıştırabilirsiniz
ama aynı tasarımı istiyoruz").

**RTL kaynağı iki hedefte AYNIDIR** — `ifdef` ile ayrılmamıştır.
Yalnızca `soc_top.sv`'deki `SYS_CLK_HZ` parametresi farklı verilir:

    FPGA : 50_000_000  -> I2C bölen 125 -> SCL tam 400.000,00 Hz
    ASIC : 43_200_000  -> I2C bölen 108 -> SCL tam 400.000,00 Hz

Her iki hedefte de şartname EK-2'nin "SCL 400 kHz sabit" isteri
**tam** karşılanır. Ölçüm: `verification/testler/tb_i2c_scl_frekans.sv`
(9 denetim) ve `tb_i2c_scl_periyot.sv` (4 denetim, dalga formundan).

Ayrıntı: `docs/ASIC_SAAT_BAGIMLILIGI.md`

---

## Dahil edilmeyenler

Vivado ara dosyaları (`build/` — 61 MB proje önbelleği, çalışma
dizinleri, IP kullanıcı dosyaları) teslime dahil edilmedi. Bunlar
`build_fpga.tcl` ile yeniden üretilebilir.

Orijinal konum: `fpga/nexys_demo_20260908/build/`

---

## Karta programlama

    # Vivado Hardware Manager ile
    nexys_demo/bitstream/nexys_top.bit

Ayrıntılı adımlar: `nexys_demo/README.md`
