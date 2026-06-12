TEKNOFEST 2026 Çip Tasarım Yarışması - Mikrodenetleyici Tasarımı

Bu depo, Berkay branch'i altında geliştirilen SoC (System on Chip) tasarımının güncel RTL kodlarını içermektedir.

rtl/ klasörü içeriği:
- soc_top.sv: İşlemci ve çevre birimlerini birbirine bağlayan ana modül.
- obi_to_axi_simple.sv: OBI protokolünü AXI-Lite protokolüne dönüştüren köprü modülü.
- axi_lite_interconnect.sv: İşlemciden gelen talepleri adrese göre ROM, RAM veya GPIO birimlerine yönlendiren kavşak (interconnect).
- memory_map_pck.sv: Sistemin adres haritasını tanımlayan paket dosyası.

Geliştirme aşaması: CV32E40P çekirdek entegrasyonu ve temel veri yolu bağlantıları tamamlanmıştır.
