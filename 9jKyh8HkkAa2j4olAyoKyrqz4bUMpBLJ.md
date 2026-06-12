" “ * ie IN i ® t Ee) ri ie # “ « ; * " . . ‘ = ÇİP TASARIM YARIŞMASI MİKRODENETLEYİCİ TASARIM ; ‘de : . wi gi . + ) j| | « * ° ts q \« j * | | * : | A KATEGORİSİ * : ;: ae ? * 3 * : q ÖN TASARIM RAPORU 4 K 

## **1. Giriş** 

Bu  raporun  amacı,  Teknofest  çip  yarışması  mikrodenetleyici  tasarımı  kategorisinde tasarlanması amaçlanan yapay zeka uygulamaları için optimize edilmiş, RISC-V tabanlı, düşük güç tüketimini amaçlayan yenilikçi bir mikrodenetleyici(SoC) mimarisinin ön tasarım detaylarını, çalışma şekilleri ve doğrulama stratejileri sunmaktır. Sistem proje kapsamı dahilinde sadece genel amaçlı bir mikrodenetleyici olmakla kalmayıp yapay zeka görevlerini işleyebilen donanımsal bir yapay zeka hızlandırıcı  bulundurmaktadır.  Raporun  ilerleyen  kısımlarında  sistemin  genel  mimarisi,  işlemci çekirdeğinin özellikleri, veriyolu entegrasyonu, bellek hiyerarşisi, boot süreçleri, YZ hızlandırıcının veri akış mantığı ve doğrulama metodları detaylı bir şekilde incelenecektir. 

## **2. Sistem Mimarisi** 

Tasarlanan mikrodenetleyici, 32 bit açık kaynaklı RISC-V komut setini mimarisine sahip RV32IMFC komut setini kullanmaktadır. Mikrodenetleyici donanım yazılım ortak tasarımı prensibiyle kurgulanmıştır. Sistem komponentlerinin birbirleriyle haberleşmesini 32-bit AMBA AXI4-Lite veriyolu oluşturmaktadır.  İşlemci çekirdeği ana yönetici olarak sistemi kontrol edecektir bunun yanından çevre birimleri ve hızlandırıcılar köle (slave) olarak bağlanmıştır.  Tablo 2.1’ de tasarlanan sistemin alt blokları ve temel fonksiyonları,  Tablo 2.2’de ise tasarım ve doğrulama amaçları verilmiştir. Ayrıca mikrodenetleyicinin genel SoC blok diyagramı Resim 3.1’te verilmiştir. 

|**Blok Adı**|**Blok Adı**|**İçerik ve Donanımsal Fonksiyon**|
|---|---|---|
|**İşlemci**<br>**Bloğu(CV32E40P**<br>**&**<br>**OBI-AXI):**||<br>AXI veri yolu üzerinden sistemi yöneten ana kontrolcüdür.|
|**Bellek ve Boot Bloğu**||Sistemin ilk uyanma, harici kod kopyalama ve yürütme<br>süreçlerini sağlar.|
|**YZ Hızlandırıcı Bloğu (NPU)**||İşlemci uykudayken (WFI) sensör verilerini alıp otonom<br>çıkarım (inference) yapar.|
|**Çevre Birimleri (I/O)**||Sensör<br>haberleşmesini,<br>veri<br>akışını<br>(streaming)<br>ve<br>donanımsal zamanlamayı yönetr.|
|Tablo 2.1|||
|Tasarım / Doğrulama Aşaması|Kullanılacak Temel Araçlar ve Metodolojiler||
|**Donanım Tasarımı (RTL)**|SystemVerilog ve Verilog HDL||
|**Çekirdek Doğrulaması**|Spike ISS (Instructon Set Simulator)||
|**Sistem ve UVM Doğrulaması**|Metrics DSim, Verilator, SystemVerilog Assertions (SVA)||
|**Fiziksel Tasarım ve Sentez (PnR)**|OpenLane Akışı (Yosys, OpenROAD, Magic vb. açık kaynak araçlar)||



Tablo 2.2 

## **3. Tasarım Detayları** 

Tasarlanan sistemin genel diyagramı aşağıda Resim 3.1’de verilmiştir. 

Resim 3.1 

## **3.1. Bellek Mimarisi ve Organizasyonu** 

Sistemimizde Harvard Mimarisi örnek alınmıştır. Bu kapsamda, buyruk ve veri bellekleri birbirinden ayrılarak  bağımsız  yollardan  doğrudan  çekirdeğe  bağlanmıştır.  Bu  sayede  işlemci,  aynı  saat çevriminde hem buyruk belleğinden yeni komut çekebilmekte hem de verilere erişebilmektedir. Böylece sistemin birim zamandaki işlem kapasitesi maksimize edilmiştir **[1]** . Sistemde yer alan bellek birimleri ve teknik özellikleri aşağıda detaylandırılmıştır: 

1. **Harici Bellek (NOR Flash):** Program kodlarının yüklendiği harici bellektir. İşlemci, SoC içerisinde yer alan QSPI Master üzerinden bu harici birime erişir. Boot sürecinde program kodları bu birimden okunarak buyruk belleğine aktarılır. 

2. **Buyruk  belleği : İ** şlemcinin yürüteceği program buyruklarının depolandığı bellektir 

3. **Veri Belleği:** İşlemcinin çalışma sırasında ihtiyaç duyduğu geçici verilerin ve değişkenlerin depolandığı bellektir. 

4. **YZ Hızlandırıcı Belleği:** Yapay zeka çıkarım süreçlerindeki yüksek hacimli veri setleri için tahsis edilmiş bellektir. 

5. **BOOT  ROM:** Donanım  başlatma  rutinlerini  ve  harici  bellekteki  programın  ana  belleklere taşınmasını yöneten bootloader yazılımını bulunduran kalıcı bellektir. 

6. **Hafıza Adreslemesi:** Sistemdeki komutlara, verilere ve çevre birimlere ulaşabilmek için benzersiz erişim adresleri tanımlanmasıdır. Sistem mimarisinde adres çözümleme sürecini optimize etmek amacıyla adres haritasının hizalanmış yapıda olması planlanmaktadır. 

## **3.2 Çevre Birimleri** 

## **3.2.1 Genel Bakış ve Mimari Yaklaşım** 

Sistemimiz; dış dünya ile veri alışverişine imkan sağlayan ve işlemciyi besleyen GPIO, I2C, Timer, QSPI ve UART General&Stream birimlerinden oluşmaktadır. Yönetim **AXI4-Lite** protokolü üzerinden **Bellek Haritalandırmalı Giriş-Çıkış (MMIO)** yöntemi iledir. Ayrıca tüm çevre birimleri, sürekli kontrol (polling) yerine **kesme (interrupt)** tabanlı çalışacak şekilde kurgulanarak sistemin hem enerji verimliliği hem de tepki hızı artırılması hedeflenmektedir. 

## **3.2.2 GPIO** 

Dış  dünyadan dijital sinyalleri almak ve dış  birimleri kontrol etmesi için 16 input ve 16 output toplamda 32-bit genişliğinde sabitlenmiş bir GPIO birimidir. **Giriş Veri Yazmacı** dışarıdan gelen sinyal değerleri tutar. **Çıkış Veri Yazmacı** yazılan veriyi doğrudan fiziksel çıkış pinlerine iletir. **Kontrol ve Erişim** AXI4-Lite arayüzü üzerinden bellek haritalandırmalı olarak erişilebilir olup işlemcinin dijital giriş-çıkış operasyonlarını en az çevrim kaybıyla gerçekleştirmesi hedeflenmiştir. **[3]** 

## **3.2.3 Timer** 

Sistem saat frekansına bağlı çalışan 32-bitlik bir sayaç birimidir. Temel görevi, işlemciye bağımlı kalmadan  belirli  zaman  aralıkları  oluşturmak  ve  periyodik  görevleri  yönetmektir.  Hedef  değere ulaşıldığında ise bir kesme( interrupt) üreterek işlemciyi uyarır. Bu sayede işlemci beklemek yerine kesme gelene kadar diğer işlemleri yürütebilir veya düşük güç modunda bekleyebilir. 

## **3.2.4 UART(General & Stream)** 

UART- General işlemci tarafından doğrudan kontrol edilen, kullanıcı komutlarını almak ve sistem durumunu raporlamak için kullanılan standart haberleşme birimidir. UART- Stream ise farklı olarak veriyoluna master bağlantısı sayesinde dışarıdan gelen verileri doğrudan yapay zeka belleğine yazar. Bu "doğrudan aktarım" mimarisi, CPU üzerindeki veri taşıma yükünü sıfıra indirerek sistem performansını maksimize eder. **[4]** 

## **3.2.5 I2C Master** 

Genel amacı sistemdeki dış sensörleri ve çevre birimleriyle düşük hızda haberleşmeyi sağlayan bu modül, **400 kHz (Fast Mode)** sabit frekansta çalışacak şekilde kurgulanmıştır.Haberleşme için SCL ve SDA pinlerini kullanır. 7-bit adresleme protokolü sayesinde, aynı iki pin üzerinden **127 farklı cihaza** kadar adresleme yapabilme yeteneğine sahiptir. 

## **3.2.6 QSPI Master** 

Sistem açılışında program kodlarını harici bir **NOR Flash** bellekten dahili belleğe yüksek hızla taşımak amacıyla tasarlanmıştır. İletişim hızını maximumda tutmak için x1,x2,x3 x4 modunu destekler. Bu sayede veri aynı anda 4 hat üzerinden taşınabildiği için açılış süresi standart SPI arayüzüne göre dört kat daha hızlıdır. 

## **3.2.7 JTAG(Hata Ayıklama Arayüzü)** 

Sistemin  geliştirme  ve  test  aşamalarını  kolaylaştırmak  amacıyla  opsiyonel  bir  donanımsal  hata ayıklama (debug) modülü kurgulanılacaktır. Bu birim, CV32E40P işlemci çekirdeğinin üzerinde bulunan özel **"debug  port"** uçlarına  doğrudan  entegre  edilmiştir. İşlemciye  ihtiyaç  duymaksızın  yazmacı içeriklerini  okuyabilme  ve  belleğe  erişebilme,  herhangi  bir  crash  durumunda veriyolundan  hata tespitini yapabilmesi için veriyoluna master olarak bağlanacaktır. 

## **3.2.8 DMA** 

**DMA** , sistem mimarisinde işlemci üzerindeki veri transfer yükünü devralan, veriyolu üzerinde **Master** 

yetkisine sahip bir kontrol birimidir. Bellek ve çevre birimleri arasındaki yüksek hacimli veri akışlarını özellikle UART- Stream üzerinden gelen yüksek yoğunluklu ses verisi akışını işlemci müdahalesine ihtiyaç duymaksızın düşük güç tüketimli ve yüksek performanslı bir şekilde yöneterek sistemin eş zamanlılık ve performans kabiliyetini artırır. 

## **3.3 Donanım Hızlandırıcı** 

Sistemde,sesleri  sınıflandıran  yapay  zeka  görevleri  için  otonom  bir  yapay  zeka  hızlandırıcı tasarlanmıştır. **TFLite Micro Speech** modelinin hesaplamalarını ve kararlarını donanımsal olarak alan bu birim, **INT8 MAC dizisi** ve **30 kB yerel bellek** (TCM) içerir. Çalışma prensibinde işlemci hızlandırıcıyı yapılandırdıktan sonra uykuya dalar veya farklı işlere yoğunlaşır ve hızlandırıcıdan kesme bekler. **UartStreamden** alınan  ve **DMA** üzerinden **YZH  belleğine** aktarılan  veriler **YZH’de** çeşitli  işlemler gerçekleştir ve işlem bilgisi ve kesme işlemciye gönderilir. Bu sayede sistemde enerji ve görev yükü verimliliği olur. 

## **3.4 Bus Yapısı** 

Mikrodenetleyici  içerisindeki  işlemci  çekirdeği,  bellek  birimleri,  çevre  birimleri  ve  yapay  zekâ hızlandırıcısı arasındaki veri iletimini sağlamak amacıyla **AMBA AXI tabanlı bir veriyolu mimarisi** kullanılacak. Tasarımda **AXI4 ve AXI4-Lite protokolleri** birlikte kullanılacak. 

## **3.4.1 Genel Bus Mimarisi** 

Sistemde merkezi bir **AXI Interconnect** master ve slave bileşenleri arasındaki veri transferini yöneten haberleşme hattını oluşturur **[5]** . RISC-V işlemci çekirdeği sistemdeki ana **master** olarak görev alırken, çevre ve bellek birimleri **slave** olarak çalışacak. Sistem içindeki master birimleri **CV32E40P işlemci çekirdeği, DMA, JTAG/Debug Modülü ve Yapay zekâ hızlandırıcı** ; slave birimleri **Buyruk Belleği Kontrolcüsü, Veri Belleği Kontrolcüsü, Yapay Zeka Belleği Kontrolcüsü, GPIO, QSPI, I2C Master, TIMER, UART-General, UART-Stream ve BOOT ROM** idir. Bu yapı sayesinde işlemci, çevre birimleri ve bellekler arasında eş zamanlı veri transferleri gerçekleştirilebilecek. 

## **3.4.2 AXI / AXI4-Lite Kullanımı** 

Tasarımda  veri  iletimi  gereksinimlerine  göre  AXI4  yada  AXI4-Lite  kullanılacak. **AXI4** yüksek  bant genişliği gerektiren veri transferlerinde, yapay zekâ hızlandırıcısının kendi belleği ile veri alışverişinde ve burst veri transferlerinde kullanılacak **[6]** . **AXI4-Lite** düşük gecikmeli kontrol işlemlerinde ve çevre birimlerinin  kontrol  ve  durum  yazmaçlarına  erişimde  kullanılacak.Bu  ayrım  sayesinde  sistemdeki veriyolu etkili ve verimli bir şekilde kullanılabilecek ve gereksiz karmaşıklık önlenecek **[7]** . 

## **3.5 Boot Mimarisi** 

Sistem başlatıldığı zaman kararlı bir  şekilde çalışabilmesi için donanım destekli, iki aşamalı bir boot mimarisi tasarlanmıştır. Bu mimaride temek bloklar işlemci çekirdeği, dahili bellekler (8 kb buyruk, 8 kb veri bellekleri), Boot ROM ve harici bellektir. 

Öngörülen boot akışı sisteme güç verilmesiyle başlayarak çekirdek ilk komutlarını donanımsal olarak eşleşmiş Boot ROM içerisindeki bootloader üzerinden çekerek bootloader yazılımı devreye girerek sistemin dış dünyasındaki QSPI flash belleğe QSPI master arayüzüyle okuma isteği gönderir. Flash bellekten okunan uygulama kodu buyruk ve data belleklerine kopyalanır (Shadowing) . Kopyalama ve bellek hazırlık aşamaları tamamlandığında bootloader bir dal komutuyla yürütmeyi doğrudan buyruk belleğine devreder. Böylece işlemci, asıl programı akıcı bir şekilde çalıştırmaya başlar ve donanım 

bileşenleri arasındaki görev geçişleri WFI (wait for interrupt) komutuyla otonom olarak yapılacaktır **[9]** . 

## **3.6 İşlemci Çekirdeği** 

Şartname kapsamında OpenHW Group tarafından 32 bit RISC-V mimarisinde geliştirilen, tek çekirdekli açık kaynaklı CV32E40P çekirdeği, tasarlanan SoC mimarisinde ana kontrol birimi olarak kullanılacaktır **[10]** . Çekirdek; düşük güç tüketimi ve silikon alanı verimliliğini amaçlamaktadır. 

## **3.6.1 Boru Hattı ve Yürütme Mimarisi** 

CV32E40P, 4-aşamalı, sırayla çalışan (in-order) bir pipeline mimarisine sahiptir. Bu sayede komut başına verimini (IPC) maksimize etmeyi amaçlamıştır. Aşamalar sırasıyla Komut Getirme (IF), Komut Çözme (ID), Çalıştırma (EX) ve Geri Yazma (WB)’dır. Bu pipeline tasarımı sayesinde işlemcinin yüksek saat frekanslarında çalışması, sistemin güç tüketiminin ve kapladığı silikon alanının minimum olması sağlanmıştır. 

## **3.6.2 Komut Seti Mimarisi (RV32IMFC) ve Veri Yolu Arayüzü** 

CV32E40P çekirdeği temel RV32I komut setinin yanı sıra RV32IMFC eklentilerini desteklemektedir. Bu sayede mikrodenetleyici sistemine yüksek işlem kapasitesi kazandırmaktadır. Bu kapsamda Multiply/Divide  (M)  eklentisi,  YZ  hızlandırıcısına  veri  hazırlama  ve  sinyal  işleme  gibi  işlemlerde performans  artışı  sağlamaktadır.  Floating-Point  (F)  eklentisi  hassasiyet  isteyen  matematiksel işlemlerde doğrudan ivme katar. Son olarak Compressed (C) eklentisinin 16-bit sıkıştırılmış komut desteği sayesinde kod yoğunluğu artırılarak buyruk belleğindeki ayak izi küçültülmekte ve işlemcinin komut getirme sırasındaki enerji harcaması doğrudan azaltılmaktadır. 

Çekirdek;  çevre  birimleri,  bellek  ve  sistem  yoluyla  haberleşmek  için  standart  OBI  arayüzünü kullanmaktadır. Veri yolu AXI4-Lite protokolünde çalıştığı için çekirdek ile veri yolu arasında özel birOBI-AXI köprüsü üzerinden iletişim sağlanacaktır. CV32E40P; DMA, yapay zeka hızlandırıcısı ve standart çevre birimleri ile kayıpsız ve yüksek bant genişliğinde bir iletişim kurabilmektedir. 

## **3.7 RISC-V Çekirdeğinin Doğrulanması** 

İşlemci çekirdeğinin komut seti doğruluğu, referans model olarak Spike ISS (Instruction Set Simulator) kullanılarak test edilecektir **[11]** . Referans modelle karşılaştırmak için öncelikle C ve Assembly tabanlı test programları koşularak elde edilen komut izleri kullanılacaktır. Test ortamı, müdahale olmadan kendi kendine kontrol eden (self-checking) bir yapıda kurgulanacaktır. 

## **3.8 Sistem Doğrulaması** 

Çekirdek doğrulaması tamamlandıktan sonra, SoC bütünlüğünü test etmek amacıyla donanıma özel C/C++ tabanlı sistem testleri geliştirilecektir. Bu testlerde; bellek eşlemli G/Ç (MMIO) üzerinden çevre birimlerinin başlatılması ve kesme (interrupt) tabanlı veri akışının yönetimi doğrulanacaktır. Şartname isterleri kapsamında, YZ hızlandırıcı bloğuna TFLite Micro referans ses verileri sürülecek ve elde edilen çıkarım (inference) sonuçları, donanım seviyesinde kendi kendini kontrol eden (self-checking) bir mekanizmayla otomatik olarak onaylanacaktır **[12]** . 

## **3.9 UVM Doğrulama** 

Proje  takvimi  göz  önüne  alınarak  tam  teşekküllü  UVM  yerine,  AXI  veri  yollarının  güvenilirliğini sağlamak için "Hedefli Doğrulama" (Targeted Verification) yaklaşımı izlenecektir. Metrics DSim veya Verilator simülatörleri kullanılarak AXI arayüzlerine VIP (Verification IP) ajanları bağlanacaktır **[13]** . SystemVerilog Assertions (SVA) ve işlem (transaction) seviyesinde Scoreboard'lar kullanılarak hatalı el 

sıkışma (handshake) gibi protokol ihlalleri anında yakalanacaktır **[14]** . Ek olarak, Code ve Functional Coverage (Kapsam) metrikleri toplanarak; yazılan testlerin donanım tasarımını ne oranda kapsadığı ve köşe durumların (corner cases) test edilebilirliği sayısal olarak raporlanacaktır. 

## **3.10 Yazılım Uygulamalarının Çalıştırılması ve Boot Süreci** 

Geliştirilen  C/C++  uygulamaları  hedef  mimariye  uygun  (örneğin  riscv32-unknown-elf-gcc)  çapraz derleyicisi kullanılarak makine koduna dönüştürülür bir sonraki aşamada bağlayıcı betiği (.ld) üretilen kodun  (.text)  ve  global  değişkenlerin  (.bss/.data)  harici  flash  bellek  ile  dahili  belleklerin  fiziksel adreslerine doğru şekilde haritalanmasını sağlar **[15]** . Elde edilen .bin/hex dosyası, Jtag arayüzü veya 

donanımsal SPI pinleri üzerinden flash belleğe yazılır (flashing) Son olarak sisteme güç verildiğinde bootloader akışı devreye girerek bu kodları dahili belleğe kopyalar (shadowing) C/C++ çalışma ortamı (C runtime) kurulur ve yürütme main() fonksiyonuna evredilir **[16]** . 

## **3.11 Yapay Zeka Hızlandırıcı** 

Resim 3.2’de yapay zekâ hızlandırıcısının iç yapısı (mavi kısım) gösterilmiştir. Veri, UART-stream üzerinden AXI4 veri yolu aracılığıyla hızlandırıcıya ait 30 kB belleğe aktarılmaktadır. Bellekten alınan veriler sırasıyla; AXI Controller, Input Buffer, Compute Engine ve Karar Birimi (Softmax/Argmax) blokları üzerinden işlenmekte, elde edilen sınıflandırma sonucu ise AXI4 arayüzü üzerinden ilgili bellek alanına geri yazılmaktadır. 

Önerilen mimaride AXI Controller dış veri yolu erişimlerini düzenleyen arayüz birimi, Input Buffer ise kesintisiz veri aktarımı için ara bellek yapısıdır. Compute Engine, şartnamede tanımlanan TFLite Micro Speech modelinin temel işlem hattını donanımsal olarak gerçekleştirmek üzere tasarlanmıştır **[12]** . Bu kapsamda giriş verisi sırasıyla; DepthwiseConv2D, ReLU, Flatten ve Fully Connected aşamalarından geçirilerek  işlenir.  Son  aşamada  bütünleşik  Karar  Birimi  (Softmax/Argmax),  4  sınıfın  olasılığını donanımsal olarak hesaplar ve en yüksek olasılıklı sınıfı seçerek nihai kararı üretir. 

Kontrol akışı, CPU’nun AXI4-Lite veri yolu üzerinden UART-stream çevre birimi ve YZ hızlandırıcısına ait kontrol/durum  yazmaçlarını  (CSR)  yapılandırmasıyla  başlatılır.  Başlatma  sonrasında  CPU, `WFI` komutuyla uykuya geçer ve NPU’nun içindeki kontrol birimi (FSM) tüm hesaplama ve çıkarım sürecini otonom  olarak  yönetir **[9]** . İşlem  tamamlanıp  sınıflandırma  sonucu  hazır  olduğunda  hızlandırıcı tarafından donanımsal bir kesme (IRQ) üretilmekte; CPU ise bu kesme sonrasında uyanıp ilgili sonuç bilgisini okuyarak program akışına devam etmektedir. 

Resim 3.2 

**3.12 RTL to PNR** 

Tasarımın  fiziksel  üretim  dosyasına  (GDSII)  dönüştürülmesinde,  endüstriyel  standarttaki  ticari 

araçlarla  (Innovus,  ICC2)  metodolojik  olarak  paralel  olan  ve  literatürde  güncelliği  kanıtlanmış OpenLane araç zinciri kullanılacaktır [2]. Bu akış; RTL kodlarının mantık kapılarına dönüştürüldüğü “Sentez”, çip alanı ve güç ağının belirlendiği “Kat Planlaması”, hücrelerin optimum yerleşiminin yapıldığı “Yerleştirme” ve saat sinyalinin senkronize dağıtıldığı “Saat Ağacı Sentezi” aşamalarını kapsar. Süreç, fiziksel bağlantıların sağlandığı “Yönlendirme” adımının ardından DRC/LVS kontrolleriyle üretim kurallarına uygunluğun denetlendiği “Sign-off” aşamasıyla nihai GDSII çıktısına ulaşarak tamamlanır. 

## **4.Takım Organizasyonu ve İş Planı** 

|**4.Takım Organizasyonu**|**veİşPlanı**||
|---|---|---|
|Ad Soyad|Bölüm (Sınıf)|Temel Sorumluluk Alanları|
|**Barış Yaman (Kaptan)**|Gazi Üniversitesi Bilgisayar<br>mühendisliği (3.sınıf)|Genel Mimari, Boot Süreçleri,<br>NPU Tasarımı, UVM Doğrulama|
|**Berkay Demir**|Gazi Üniversitesi Elektrik ve<br>Elektronik Mühensiliği (3.sınıf)|Bellek Mimarisi AXI4-Lite Veri<br>Yolu Entegrasyonu|
|**Talha Eraslan**|Gazi Üniversitesi Elektrik ve<br>Elektronik Mühensiliği (3.sınıf)|NPU RTL Tasarımı, Spike ISS<br>ve DSim Doğrulama Ortamları|
|**Bayram Taha Şanlı**|Gazi Üniversitesi Elektrik ve<br>Elektronik Mühensiliği (3.sınıf)|Bellek Kontrolcüleri, AXI Protokol<br>Kontrolleri(SVA)|
|**Selim H. Aytekin**|Gazi Üniversitesi Bilgisayar<br>mühendisliği (Hazırlı)|Çevre Birimleri (UART, I2C,<br>Timer,GPIO)RTL Tasarımı|



|İş Paketi<br>(WP) / Faz|Yapılacak Teknik Çalışmalar ve Hedefler|Başlangıç -<br>Bitiş Tarihleri|Resmi Kilometre Taşı<br>(Milestone)|
|---|---|---|---|
|**Mimari**<br>**Konsept ve**<br>**ÖTR**|SoC mimarisinin belirlenmesi, blok<br>diyagramların çizilmesi ve Ön Tasarım<br>Raporu'nun yazımı.|28.03.26<br>–<br>16.03.26|**16 Mart: ÖTR Son**<br>**Teslimi (06 Nisan:**<br>**Sonuçların İlanı)**|
|**Temel RTL**<br>**ve**<br>**Entegrasyon**|CV32E40P çekirdeği, AXI veriyolu,<br>bellek kontrolcüleri ve çevre birimlerinin<br>RTL kodlaması.|17.03.26<br>–<br>17.04.26|_13-17_<br>_Nisan:_<br>_Soru-_<br>_Cevap Oturumu_|
|**NPU**<br>**ve**<br>**Doğrulama**<br>**(DTR)**|YZ Hızlandırıcı (MAC) tasarımı, Spike<br>ISS çekirdek testleri, UVM/AXI kontrolleri<br>ve DTR yazımı.|<br>18.04<br>–<br>15.05.2026|**15 Mayıs: DTR Son**<br>**Teslimi (05 Haziran:**<br>**Finalist İlanı)**|
|**WP4:**<br>**Kapsam ve**<br>**Optimizasyo**<br>**n**|Simülasyonlardan Code/Functional<br>Coverage alınması, RTL hatalarının<br>giderilmesi, donanım optimizasyonu.|16.05.26<br>–<br>10.07.26|_6-10_<br>_Temmuz:Soru-_<br>_Cevap Oturumu_|
|**Fiziksel**<br>**Tasarım ve**<br>**Tape-out**|RTL kodlarının OpenLane akışına<br>sokulması ve GDSII çıktısının alınması.|11.05.26<br>–<br>31<br>.07.26|**31 Temmuz:**<br>**Tasarımın Nihai Hale**<br>**Getirilmesi**|
|**Final**<br>**Sunumu ve**<br>**Demo**|FPGS/Simülasyon üzerinden sistemin<br>canlı demosu, YZ çıkarım sonuçlarının<br>sergilenmesi ve final sunumu.|Ağustos –<br>Eylül 2026|_Ağustos -_<br>_Eylül:_<br>_Final_<br>_Değerlendirme_|



**4. Kaynakça ve Ekler** 

[1] D. A. Patterson and J. L. Hennessy, Computer Organization and Design RISC-V Edition: The Hardware Software Interface. Cambridge, MA, USA: Morgan Kaufmann, 2017. 

[2] G. Leyva et al., "Comprehensive RTL-to-GDSII Workflow for Custom Embedded FPGA Architectures Using Open-Source Tools," Electronics, vol. 14, no. 19, p. 3866, 2025. 

[3] CodeNode. (t.y.). GPIO (General Purpose Input/Output). CodeNode Docs. [Çevrimiçi]. Erişim adresi: https://elmfrain.github.io/code-node-docs/modules/gpio.html 

[4] Universal asynchronous receiver-transmitter. (2024, 12 Mart). Wikipedia. [Çevrimiçi]. Erişim adresi: https://en.wikipedia.org/wiki/Universal_asynchronous_receiver-transmitter 

[5] AMD. (t.y.). AXI Interconnect. [Çevrimiçi]. Erişim adresi: https://www.amd.com/en/products/adaptive-socs-and-fpgas/intellectual-property/axi_intercon nect.html 

[6] AMD. (2022, 8 Ağustos). AXI Memory Mapped to Stream Mapper v1.1 LogiCORE IP product guide (PG102).. Erişim adresi: https://docs.amd.com/r/en-US/pg102-axi-mm2s-mapper/Simulation 

[7] AMD. (2023, 18 Ekim). AXI Quad SPI v3.2 LogiCORE IP product guide (PG153). Erişim adresi: https://docs.amd.com/r/en-US/pg153-axi-quad-spi/AXI4-Lite-Interface-Module 

[8] T. Noergaard, Embedded Systems Architecture: A Comprehensive Guide for Engineers and Programmers, 2nd ed. Oxford, UK: Newnes, 2012. Erişim adresi: https://www.sciencedirect.com/book/9780123821966/embedded-systems-architecture 

[9] A. Waterman and K. Asanović, "The RISC-V Instruction Set Manual Volume II: Privileged Architecture," RISC-V International, Document Version 20211203, 2021. . Erişim adresi: https://github.com/riscv/riscv-isa-manual/releases/download/Priv-v1.12/riscv-privileged-20211 203.pdf 

[10] OpenHW Group, "core-v-mcu/cv32e40p: OpenHW Group CORE-V CV32E40P RISC-V IP." GitHub. [Çevrimiçi]. Erişim adresi: https://github.com/openhwgroup/cv32e40p 

[11] RISC-V International, "riscv-software-src/riscv-isa-sim: Spike, a RISC-V ISA Simulator." GitHub. [Çevrimiçi]. Erişim adresi: https://github.com/riscv-software-src/riscv-isa-sim 

[12] R. David et al., "TensorFlow Lite Micro: Embedded Machine Learning for TinyML Systems," Proc. Mach. Learn. Res., vol. 149, pp. 800-811, 2021. [Çevrimiçi]. Erişim adresi: https://arxiv.org/abs/2010.08678 

[13] W. Snyder, "Verilator: Open simulation - growing up," in Proc. DVCon, 2013. [Çevrimiçi]. Erişim adresi: https://www.veripool.org/verilator/ 

[14] IEEE  Standard  for  SystemVerilog—Unified  Hardware  Design,  Specification,  and Verification Language, IEEE Std 1800-2017, 2017. [Çevrimiçi]. Erişim adresi: https://standards.ieee.org/ieee/1800/6700/ 

[15] Free Software Foundation, "The GNU linker: ld manual," GNU Project.Erişim adresi: https://sourceware.org/binutils/docs/ld/ 

[16] RISC-V  Collaboration,  "riscv-gnu-toolchain:  GNU  compiler  toolchain  for  RISC-V, including GCC," GitHub. Erişim adresi: https://github.com/riscv-collab/riscv-gnu-toolchain 

