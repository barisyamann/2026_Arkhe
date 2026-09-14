# ARKHE jüri provası — tek USB

Bu, kartta daha önce geçen 7 örnekli demodan ayrı bir **tanılama senaryosudur**. Gerçek jüri tarafından sağlanmış bir senaryo değildir. Nexys A7-100T ve kartın normal USB bağlantısıyla çalışır; ayrıca USB-UART adaptörü gerekmez. Önceki `TEK_USB_DEMO` klasörü korunmuştur.

## Karta yükleme

1. Kartı normal USB kablosuyla bağla. Vivado → Hardware Manager → Open Target → Auto Connect.
2. Kartın configuration memory cihazını seç. Önceden kullanılan `s25fl128s...` cihazı varsa onu kullan.
3. **Program Configuration Memory Device** içinde **bu klasördeki `arkhe_jury.mcs`** dosyasını seç. Erase, Program ve Verify işaretli olsun. Bu işlem karttaki önceki flash imajının yerine jüri imajını yazar.
4. İşlem tamamlanınca **Program Device** ile **bu klasördeki `nexys_usb_top.bit`** dosyasını yükle. Eski demo klasöründeki aynı adlı bit dosyasını seçme: jüri sürümünün boot ROM'u farklıdır.
5. Diğer seri terminal/Python programlarını kapat; aynı COM portu aynı anda iki programda açılmamalı.

Yalnızca bit dosyasını yüklemek yetmez: genişleyen test yazılımı flash'taki yeni MCS içinde bulunuyor. GUI'de iki dosyayı da bu klasörden seç.

## Çalıştırma

PowerShell:

```powershell
cd C:\Users\ybari\OneDrive\Desktop\arkhe2\JURI_FPGA_TESTI
python -m serial.tools.list_ports
python run_jury.py --port COM16
```

`Hazir... CPU RESET...` mesajını gördüğünde kartın **CPU RESET düğmesine bir kez bas**. Sonrasında program bitene kadar reset atma. COM numarası değiştiyse komuttaki COM16'yı değiştir. `No module named serial` hatası olursa `python -m pip install pyserial` çalıştır.

Otomatik bölümden sonra program 16 anahtarı önce 0, sonra 1, sonra tekrar 0 yapmanı isteyecek. Her adımda anahtarları ayarla ve PowerShell'de Enter'a bas. Anahtarların okunması ve yükselen/düşen kenar kesmeleri denetlenir. LED adımlarında gösterilen desen doğruysa `e`, yanlışsa `h` yaz. Anahtarları değiştirirken CPU RESET'e basma.

Otomatik bölümü tek başına çalıştırmak için:

```powershell
python run_jury.py --port COM16 --skip-manual
```

Bu durumda fiziksel anahtar/LED bölümü rapora **SKIP** yazılır. Daha uzun test için `--rounds 20` kullan: yedi örnek 140 kez çalışır. Bunlar aynı yedi referansın tekrarlarıdır. Dosyaları karta bağlanmadan kontrol etmek için `python run_jury.py --validate` kullan; bu komut donanım testi yapmaz.

## Senaryo

| Aşama | Kontrol |
|---|---|
| Flash → CPU açılışı | 8 KB yüklenen programın ve 16 KB NPU ağırlığının FNV özeti |
| CPU | Toplama, çıkarma, mantık, kaydırma, çarpma/bölme/kalan; sıfıra bölme ve işaretli taşma uç durumları |
| D-RAM | Ayrılmış 1 KB alanda beş desen, bayt ve yarım kelime yazma |
| NPU TCM | Çalışma ve kuyruk alanlarında beş desen; 15 bankanın ilk/son kelimelerinde yürüyen bit; ağırlıkları koruma |
| GPIO yazmaçları | SET, CLEAR, TOGGLE, yürüyen bit |
| Timer | Yukarı/aşağı sayım, üç ayrı kesme, ISR sayısı, durdurma ve olay temizleme |
| DMA | 1/2/3/16/65 kelime; D-RAM↔TCM, banka sınırı geçişi, koruma kelimeleri; sabit kaynak/hedef |
| Bus fault | ROM'a yazma girişiminin reddi, hata kesmesi/adresi/durum kodu |
| I2C | Harici slave olmadan başlatılan işlemin tamamlanması |
| UART2 bayt yolu | 0–255 tüm bayt değerleri, tek ve parçalı gönderim, özet karşılaştırması |
| NPU uçtan uca | UART2 → 490 kelimelik DMA → girdi özeti → gerçek NPU → ISR → dört çıktı ve sınıfın referansla birebir karşılaştırılması |
| Tekrarlama | Yedi örnek × üç tur; karışık sıra; tek parça, 17 ve 127 baytlık parçalar; resetsiz |
| Son kontrol | Başlangıçtaki 83 öztestin tekrar çalışması ve ağırlık bütünlüğü |
| Kullanıcı kontrolü | 16 anahtar, yükselen/düşen kenar kesmeleri, dört LED deseni |

Her öztest turu 83 kontrol, her NPU çıkarımı ayrıca dört DMA/kesme kontrolü üretir. Bilgisayar tarafı satırların eksiksiz geldiğini, sayısal değerleri ve referans çıktıları denetler. Süre alanı ISR ve UART yazdırma süresini de içerir; saf NPU performans ölçümü değildir.

## Sonuç ve sınırlar

Program `juri_board_TARIH_SAAT.json` ve aynı adlı `.log` üretir. Hata, zaman aşımı veya Ctrl+C durumunda test geçmiş sayılmaz; rapor kısmi sonucu kaydeder. Son satırdaki `GECTI` yalnızca yukarıdaki kapsam için geçerlidir.

Bu senaryo tüm RTL durumlarının veya yarışma şartnamesinin tam doğrulaması değildir. Çalışan programın stack'i ve D-RAM'in tamamı desen testine alınmaz. Ağırlık hücrelerinin tamamına yazma testi yapılmaz; okuma özeti ve banka uçları kontrol edilir. I2C için harici slave veri alışverişi/ACK doğrulaması, flash programlama/silme komutları, JTAG debug halt/resume ve tüm CPU ISA testi bu kart senaryosunda yoktur. USB RX FPGA sarmalayıcısında UART2'ye bağlıdır; UART1 RX bu düzenle denenmez. ASIC 50 MHz kapanışı, UVM coverage ve Spike karşılaştırması ayrı kanıtlardır.

Yeni jüri paketi fiziksel kartta sen çalıştırınca doğrulanmış olacak. Önceki 7/7 kart sonucu bu yeni paketin sonucu değildir. Paketle birlikte verilen simülasyon ve FPGA zamanlama kayıtlarının kapsamı `DOGRULAMA.json` içindedir.
