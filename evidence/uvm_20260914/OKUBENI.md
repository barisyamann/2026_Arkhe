# UVM AXI4-Lite doğrulama kanıtı — 14 Eylül 2026 (HEAD)

Bu klasör, `verification/AXI_UVM_KAPSAM_MATRISI.md` içindeki bütün
sayıların **ham kaynağıdır**. Matris bu loglardan yazılmıştır; iddia
değil ölçümdür.

## Üretim

```bash
python scripts/run_regression.py            # 37/37 test, 702 denetim
# ilgili iki test:
python scripts/run_regression.py --test uvm_axi_agent
python scripts/run_regression.py --test uvm_aktif
```

Simülatör: Vivado xsim 2025.2, UVM 1.2 (`-L uvm`).

## `uvm_axi_agent_sim.log` — pasif agent (38 denetim)

Tasarımın gerçek AXI trafiğini izler. **Tasarım doğrulamasının esas
kanıtı budur.**

| Ölçüm | Değer |
|---|---:|
| `env.agent` (NPU motoru → TCM) | **162.064** işlem |
| `env.soc_agent` (`merged_m_*`, tüm SoC) | **239.665** işlem |
| **TOPLAM** | **401.729** |
| Protokol ihlali | **0** |
| Geçersiz yanıt kodu (EXOKAY) | **0** |
| Askıda kalmış işlem (>10 µs) | **0** |
| `WSTRB == 0` olan yazma | **0** |
| El sıkışan çevrimlerde X/Z | **0** |
| Reset aktifken VALID yüksek | **0** çevrim |
| Monitör kaçırma (ham sinyal çapraz kontrolü) | R ve B sayımları birebir tutuyor |

### Referans bellek modeli

Protokol doğru ama **veri yanlış yere yazıldı** hatalarını yakalar:

```
SoC yolu : 3647 adres izlendi, 1038 okuma dogrulandi
[OK] 1038 okumada yazilan deger BIREBIR geri okundu
```

### Fonksiyonel kapsam

| | NPU agent | SoC agent |
|---|---:|---:|
| İşlem türü | %100,0 | %100,0 |
| **Adres bölgesi** | %75,0 | **%100,0** |
| WSTRB deseni | %33,3 | %66,7 |
| Yanıt kodu | %33,3 | %100,0 |
| TOPLAM | %52,1 | **%91,0** |

**Adres bölgesi %100,0** — şartname §5.2'nin istediği kanıt budur: 13
bölgenin (Boot ROM, I-RAM, D-RAM, NPU belleği, GPIO, Timer, UART1,
UART2, I2C, QSPI, NPU CSR, DMA, JTAG) **tamamı** gerçek trafikle
uyarılmıştır.

NPU agent'ının %52,1'i bir boşluk değildir: gerçek NPU motoru yalnızca
tam-word erişim yapar ve slave her zaman OKAY döner. Pasif izleme var
olmayan trafiği uyaramaz.

## `uvm_aktif_sim.log` — aktif test (13 denetim)

Agent'ları `UVM_ACTIVE` kurar ve dört sequence koşar
(`axil_wstrb_seq`, `axil_yanit_seq`, `axil_rastgele_seq`,
`axil_sanal_seq`). Pasif izlemenin uyaramadığı kapsam bin'lerini
kapatır; `strb` kapsamı %100'e çıkar.

### Dürüst sınır

Aktif test **tasarıma sürmez**, bağımsız bir arayüz ve davranışsal
AXI4-Lite slave üzerinde koşar. Sebebi mimaridir: `soc_bus_if` ve
`npu_eng_if` pasif gözlem noktalarıdır — sinyalleri `assign` ile
tasarıma bağlıdır ve sürekli atama driver'ı ezer. SoC'ta boş
(kullanılmayan) bir AXI slave portu da yoktur; aktif agent'ı tasarıma
bağlamak RTL değişikliği gerektirirdi ve teslim edilen GDS'nin kaynak
SHA-256 bütünlüğünü bozardı.

Dolayısıyla:

- **Tasarımın AXI uyumu** → pasif agent (401.729 işlem) + 5 SVA checker
- **`uvm_aktif`** → UVM ortamının kendi altyapısını (driver, sequencer,
  sequence, scoreboard, kapsam kapanışı) doğrular

Bu ayrım bilerek korunmuştur; aktif testin ürettiği kapsam tasarım
doğrulaması olarak sunulmamaktadır.

## SVA protokol denetleyicileri

UVM'ye ek olarak beş `axil_protocol_checker` bind edilmiştir ve
`UVM_AXI` bayrağı olmadan da **her regresyon koşumunda** aktiftir:

| Örnek | Nokta |
|---|---|
| `u_protocol_checker` | `soc_top.merged_m_*` (birleşik master yolu) |
| `u_pc_cpu` | M0 — CPU veri portu (OBI→AXI köprüsü) |
| `u_pc_jtag` | M1 — JTAG/Debug master |
| `u_pc_dma` | M2 — DMA master |
| `u_pc_npu_eng` | NPU motoru AXI master |

Ayrıntılı matris: `verification/AXI_UVM_KAPSAM_MATRISI.md`
