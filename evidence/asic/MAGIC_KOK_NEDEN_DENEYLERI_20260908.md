# Magic DRC kök neden incelemesi — 8 Eylül 2026

Ana koşulara ve teslim GDS dosyalarına müdahale edilmedi. Sunucuda küçük hücre kopyaları ve bağımsız Magic testleri `/home/tatua7806/magic_cause_probe_20260908` altında üretildi. Deneyler aynı sky130A PDK ve Magic 8.3.623 ile yapıldı. Bu rapor final signoff PASS raporu değildir.

## Bulgular

İki ayrı hata grubu var:

1. LEF/DEF kontrolündeki 7658 nwell.4 bulgusu: tap geometrisinin soyut görünümde eksik olmasıyla ilişkili.
2. Tam GDS kontrolündeki 108197954 bulgu: tek SRAM bit hücresinde bile yeniden üretilebilen kontak/difüzyon/polysilicon kural hatalarını içeriyor. Sadece standart hücre MAGLEF'lerinin yüklenmemesine bağlanamaz.

## Küçük deneyler

| Hücre | Kaynak/görünüm | DRC sonucu |
|---|---|---|
| sky130_fd_sc_hd__tapvpwrvgnd_1 | Final GDS'ten hücre | 0 |
| Aynı tap | PDK GDS | 0 |
| Aynı tap | PDK MAG | 0 |
| Aynı tap | PDK MAGLEF | 1 nwell.4 |
| sky130_fd_sc_hd__mux2_2 | Final GDS / PDK GDS / MAG | Her biri 19; nwell.4 ve LU.2/LU.3 |
| Aynı mux | MAGLEF | 1 nwell.4 |
| sky130_fd_sc_hd__buf_8 | Final GDS / PDK GDS / MAG | Her biri 25; nwell.4 ve LU.2/LU.3 |
| Aynı buffer | MAGLEF | 1 nwell.4 |
| SRAM row_addr_dff ve bağımlılıkları | Kaynak SRAM GDS | 0 |
| Aynı SRAM yazmacı | Final GDS | 0 |
| sky130_fd_bd_sram__openram_sense_amp | Kaynak SRAM GDS | 0 |
| sky130_fd_bd_sram__openram_dp_cell | Kaynak SRAM GDS | 404 |

İzole mux/buffer için tap uzaklığı hataları tek başına hücrenin bozuk olduğunu göstermez: komşu tap ve üst düzey yerleşim bağlamı bu deneyde yok. Önemli gözlem, büyük rapordaki kontak/genişlik hata grubunun bu standart hücrelerde çıkmamasıdır.

SRAM bit hücresinde kontak adlarına `gds flatglob *contact*` uygulanınca da 404 hata kaldı. Bu deney yalnızca kontak alt hücrelerini düzleştirmeyi test eder; bütün SRAM hiyerarşisi için sonuç sayılmaz. SRAM row_addr_dff ve sense amplifier iki modda da 0 verdi.

## SRAM bit hücresindeki hata örnekleri

- poly contact width / licon.1: 11
- Diffusion width / diff/tap.1: 22
- Local interconnect width / li.1: 31
- N-diffusion spacing to N-well / diff/tap.9: 41
- poly overhang of SRAM core transistor / poly.8: 32
- Via1 width / via.1a + via.4a: 28
- Toplam 29 hata türü, 404 koordinat girdisi.

Bu türler büyük çip raporundaki baskın türlerle örtüşüyor. Tek hücre çok sayıda tekrarlandığı için toplam sayının büyümesi beklenir; üst hiyerarşinin hataları birleştirmesi/çözmesi nedeniyle 404 × hücre sayısı birebir final sayı değildir. 108 milyon girdinin tamamının bu sebepten geldiği henüz kanıtlanmadı.

## Ölçek ve aktarım kontrolü

Final GDS ile PDK standart hücre GDS'inin UNITS kayıtları aynı. Üç standart hücre iki kaynaktan da aynı DRC sonuçlarını veriyor. Kaynak SRAM ile final GDS'teki row_addr_dff, openram_dff ve üç kontak hücresinin yapıları tarih kaydı dışında birebir aynı. Bu, örneklenen hücrelerde streamout bozulması veya genel birim hatası ihtimalini zayıflatır; tüm GDS'in eksiksiz geometrik eşdeğerlik kanıtı değildir.

Eski rapor `units internal` ile çalışıyor: 34 iç birim 0,17 um'ye, 30 iç birim 0,15 um'ye karşılık geliyor. Yeni küçük deneylerde mikrometreyle görünen aynı eşikler, sayıların farklı yazılmasının tek başına ölçek hatası olmadığını gösteriyor.

## MAGLEF deneyinin kapsamı

LibreLane drc.tcl, MAGIC_DRC_MAGLEFS listesini önceden yükleyip `gds noduplicates true` ile GDS içindeki aynı adlı hücrelerin bu görünümleri değiştirmesini önlüyor. Bu desteklenen fakat isteğe bağlı bir blackbox yöntemidir.

`gdsdrc2` logunda 445 standart hücre MAGLEF'i yüklendiği doğrulandı. SRAM iç hücreleri yine okunuyor. Bu yüzden standart hücrelerin blackbox edilmesi tek başına SRAM bit hücresi problemine çözüm kanıtı değil.

Tap MAGLEF dosyasında nwell, metal ve `LEFview TRUE` var; gerçek MAG'deki nsubdiff/nsubdiffcont yok. Tek hücre deneyi bu görünümün nwell.4 ürettiğini gösterdi. Dolayısıyla gerçek GDS'teki tap bağlantısını sınamak için tap'ı yeniden soyutlaştırmanın etkisi ayrıca değerlendirilmelidir.

## Henüz belirlenmeyen ayrım

SRAM bit hücresindeki hataların ne kadarının Magic'in vendor maske geometrisini iç katmanlara çevirme sınırlamasından, ne kadarının hücrenin dizi bağlamından/kural istisnalarından veya gerçek makro kusurundan geldiği henüz kesin değil. Kaynak makroda yeniden üretildikleri için bunların tamamını ARKHE RTL veya yönlendirmesine yüklemek doğru değil. Hepsini otomatik olarak görmezden gelmek de doğru değil.

Magic geliştiricisinin açıklaması, sky130 SRAM vendor GDS'inin optik düzeltme katmanlarının Magic teknoloji dosyasında tam uygulanmadığını ve korunmuş vendor GDS'in kullanıldığını belirtiyor. Bu bir mekanizma açıklamasıdır; bizim 404 veya 108 milyon hatamızın otomatik muafiyet kanıtı değildir.

Kaynak: https://web.open-source-silicon.dev/t/10275668/u016em8l91b-u017x0nm2e7-while-reading-openram-memory-macro-g

LibreLane blackbox tanımı: https://librelane.readthedocs.io/en/latest/reference/step_config_vars.html

## Sonraki hedefli kontroller

1. Aynı SRAM bit hücresi ve küçük komşuluk dizisini bağımsız maske tabanlı DRC ile karşılaştır; ilgili SRAM kurallarının/istisnalarının deck'te gerçekten kapsandığını doğrula.
2. Kaynak makro DRC/LVS kanıtlarını ve PDK sürüm eşleşmesini toparla.
3. Makro iç doğrulaması ile SoC bağlantı/sınır doğrulamasını ayrı raporla. Gerekçeli blackbox listesi kullan; tüm hücreleri körlemesine kapsam dışına çıkarma.
4. nwell.4 için gerçek tap geometrisini koruyan küçük yerleşim kesitlerinde inceleme yap; eski 7658 koordinatı tap/power bağlantılarıyla eşleştir.
5. Sonuç sıfır olsa bile kullanılan abstract görünümleri ve kontrol kapsamını teslim raporunda açıkça belirt.
