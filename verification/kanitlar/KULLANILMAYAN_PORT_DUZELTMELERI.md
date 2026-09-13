# Kullanılmayan giriş portları — bulgu ve düzeltme

**Tarih:** 12 Eylül 2026
**Kapsam:** `jtag_debug.sv` (AXI yanıt kodu), `i2c_peripheral.sv` (saat germe)

---

## Nasıl bulundu

`asic/README.md` §9 için kullanılmayan giriş portları taraması yapıldı.
Yöntem basit: her modülün giriş portu için RTL gövdesinde kaç kez
okunduğu sayıldı.

    grep -c "<port>" <dosya>

Sonuç 1 ise port **yalnızca tanımda** geçiyor, gövdede hiç okunmuyor
demektir. Yedi port bu durumdaydı. Beşi zararsızdı (ileride kullanım
için ayrılmış, sabit bağlı veya gözlem amaçlı). **İkisi gerçek
işlevsel eksiklikti** ve bu belge onları anlatır.

---

## Bulgu 1 — JTAG AXI yanıt kodunu hiç okumuyordu

### Sorun

    jtag_debug : m_axi_rresp   -> sadece port tanımı
    jtag_debug : m_axi_bresp   -> sadece port tanımı

JTAG debug master, interconnect üzerinden **tüm slave'lere** erişir.
Tanımsız bir adres okunduğunda interconnect `DECERR` (2'b11) ve
`0xDEADBEEF` döndürür.

Yanıt kodu okunmadığı için JTAG bu çöp veriyi **geçerli sanıyordu**.
Hata ayıklama oturumunda sessiz yanlış okuma anlamına gelir: ne bir
hata bayrağı, ne kesme — yalnızca yanlış veri.

### Düzeltme

`rtl/Cevre_Birimleri/jtag_debug.sv` yanıt kodunu yakalar ve iki
yoldan bildirir:

| Yol | Alan | Anlam |
|---|---|---|
| CSR | `REG_DBG_STATUS[3]` | hata bayrağı (yanıt OKAY değil) |
| CSR | `REG_DBG_STATUS[5:4]` | son AXI yanıt kodu |
| JTAG DR | `IR_MEM_READ` alt 32 bit | `0x00000000` = OKAY, üst 30 bit `0x39101B9` = hata imzası |

Yeni bir işlem başladığında (`IR_MEM_READ` / `IR_MEM_WRITE`) bayrak
temizlenir, böylece eski hata yeni okumayı kirletmez.

### Kanıt

`tb/tb_jtag_yanit_kodu.sv` — 9 denetim. Sahte slave ile yanıt kodu
**zorlanır**:

    1. OKAY   (2'b00) -> bayrak düşük kalır, kod 00
    2. SLVERR (2'b10) -> bayrak yükselir, kod 10 doğru yakalanır
    3. DECERR (2'b11) -> bayrak yükselir, kod 11  (tanımsız adres senaryosu)
    4. yeni OKAY işlemi -> bayrak temizlenir
    5. yazma yolu (bresp) -> aynı davranış

Mutasyon `jtag_yanit_kodu`: `bus_hata <= 1'b0` yapıldığında test
9 denetimden 7'ye düşer ve **kalır**.

---

## Bulgu 2 — I2C saat germeyi (clock stretching) hiç görmüyordu

### Sorun

    i2c_peripheral : scl_i   -> sadece port tanımı

I2C **açık drenaj** bir hattır. `scl_oe = 0` "hattı bırak" demektir,
"hat yüksek" demek **değildir**. Yavaş bir slave SCL'i aşağı çekerek
"henüz hazır değilim" der — buna **saat germe** denir (NXP UM10204
§3.1.9).

Germeyi görmeyen bir master zamanlamasını yürütmeye devam eder.
Slave o sırada bitleri kaçırır ve veri **sessizce bozulur**.

### Düzeltme

`scl_i` iki kademeli senkronizatörden geçirilir. Master hattı
bıraktığında (`scl_oe = 0`) hat hâlâ aşağıdaysa çeyrek sayacı
**olduğu yerde dondurulur**; hat yükselince kaldığı yerden devam eder.

`sample` ve `bit_done` darbeleri de germe boyunca bastırılır — aksi
hâlde `sample` faz 2'de `tick_cnt == 0` üzerinde donup germe boyunca
**her çevrim** darbelenir ve SDA defalarca örneklenirdi.

### Senkronizatör gecikmesinin telafisi — ölçülerek bulundu

İlk uygulama `germe_dur = !scl_oe && !scl_snk[1]` idi.
`tb_i2c_scl_periyot` bunu hemen yakaladı:

    periyot 2500 ns -> 2540 ns   (bit başına TAM 2 çevrim, 40 ns @ 50 MHz)

Neden: master hattı bıraktığı anda senkronizatör hâlâ eski (düşük)
değeri taşıyor, bu yüzden germe olmadığı hâlde her bitte iki çevrim
donuluyordu.

Çözüm: senkronizatör boru hattı **tazelenene kadar** germe kararı
verilmez (`birakma_yasi == 2`). Böylece:

| Durum | Sonuç |
|---|---|
| Germe yok | Sayaç hiç durmaz, periyot **tam 2500 ns** |
| Germe var | İki çevrim sonra yakalanır, sayaç donar |

Yani 400 kHz ölçümü **değişmedi** — germe yalnızca bir slave hattı
çektiğinde devreye girer.

### Kanıt

`tb/tb_i2c_saat_germe.sv` — 4 denetim.

---

## Testin kendisi de yanlıştı — hata enjeksiyonu yakaladı

Bu, kampanyanın neden var olduğunun iyi bir örneğidir.

Testin **ilk yazımı** `scl` **telini** ölçüyordu:

    SCL yüksek süresi (germesiz) : 1240 ns
    SCL yüksek süresi (germeli)  : 6240 ns    -> uzama tam 5000 ns

Sayılar kusursuz görünüyordu ve test geçiyordu. Ama `germe_dur = 1'b0`
mutasyonu uygulandığında — yani **saat germe tamamen kapalıyken** —
test yine 6240 ns ölçüp **GEÇTİ**.

Sebep: `scl` telini 5 µs boyunca **zaten testbench'in kendisi**
aşağı çekiyordu. Ölçülen uzama DUT'un tepkisi değil, kendi
sürüşümüzdü — **totolojik bir ölçüm**.

### Doğru ölçüm

Germenin tanımı "master **zamanlamasını** dondurur"dur. Bunun
gözlenebilir yeri DUT'un **iç çeyrek sayacıdır**.

Ayrıca yalnızca baş/son örneği almak da aldatıcıdır: sayaç germe
boyunca ilerleyip tam tur atarak aynı değere dönebilir (ilk denemede
tam olarak bu oldu — `tick_cnt` 15 → 15 görünüyordu ama aslında
248 kez hareket etmişti). Bu yüzden sayaç **her çevrim** izlenir ve
toplam hareket sayılır.

| RTL | Germe boyunca sayaç hareketi |
|---|---:|
| **Düzeltilmiş** | **0 çevrim** |
| Mutasyonlu (germe kapalı) | **248 çevrim** (~250 beklenir) |

Ayrım kesin. Test artık gerçekten DUT davranışını ölçüyor.

---

## Kampanya sonucu

Her iki düzeltme de kalıcı hata enjeksiyonu kampanyasına eklendi:

    yakalanan : 7
    KACIRILAN : 0
    atlanan   : 0

RTL bütünlüğü kampanya sonrası doğrulandı — yalnızca kasıtlı olarak
değiştirilen dosyalar farklı, kampanyanın geçici değişiklikleri
eksiksiz geri yüklendi.
