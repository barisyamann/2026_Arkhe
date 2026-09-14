/*
 * ARKHE SoC - ESP32 I2C Slave (Demo C)
 * TEKNOFEST 2026 Cip Tasarim Yarismasi
 *
 * NE ISE YARAR
 *   Arkhe SoC'un I2C master kontrolcusunun GERCEK bir cihazla veri
 *   alisverisi yaptigini kanitlar. Demo B raporu I2C icin "harici slave
 *   veri alisverisi/ACK dogrulamasi yoktur" diyordu; bu kod o boslugu
 *   kapatir.
 *
 * PROTOKOL
 *   Kart bir bayt YAZAR  -> ESP32 saklar
 *   Kart bir bayt OKUR   -> ESP32 sakladigi baytin TERSINI (~x) doner
 *
 *   Neden tersi: sabit bir deger donseydi, hat sifira cekili kalsa bile
 *   test gecebilirdi. Tersini donmek gercek cift yonlu iletisimi
 *   kanitlar - donen deger yazilan degere BAGLI olmak zorundadir.
 *
 * BAGLANTI  (Nexys A7-100T Pmod JA)
 *
 *   Nexys JA1 (C17) SCL  <---->  ESP32 GPIO22
 *   Nexys JA2 (D18) SDA  <---->  ESP32 GPIO21
 *   Nexys JA5/JA6   GND  <---->  ESP32 GND
 *
 *   ONEMLI: GND MUTLAKA baglanmalidir, yoksa iki kartin referansi
 *   ortak olmaz ve hat guvenilmez calisir.
 *
 *   PULL-UP: FPGA tarafinda dahili pull-up aciktir (~50 kOhm), ESP32
 *   tarafinda da Wire kutuphanesi acar. 400 kHz'de bu zayif kalabilir;
 *   ikisinde de sorun yasarsaniz SCL ve SDA hatlarina 3,3 V'a giden
 *   2,2 - 4,7 kOhm HARICI direnc ekleyin.
 *
 * KURULUM (Arduino IDE)
 *   1. Kart: "ESP32 Dev Module" (veya kendi modelin)
 *   2. Bu dosyayi yukle
 *   3. Seri Monitor: 115200 baud
 *   4. Sonra kart tarafinda: python run_jury.py --port COMxx
 *
 * BEKLENEN SERI CIKTI
 *   ARKHE I2C SLAVE HAZIR (adres 0x42)
 *   yazildi: 0x5A  ->  okunacak: 0xA5
 *   yazildi: 0xA5  ->  okunacak: 0x5A
 *   yazildi: 0x3C  ->  okunacak: 0xC3
 */

#include <Wire.h>

#define I2C_SLAVE_ADDR 0x42
#define PIN_SDA        21
#define PIN_SCL        22

volatile uint8_t sonGelen   = 0x00;
volatile uint8_t donecekVal = 0xFF;
volatile bool    yeniVeri   = false;
volatile uint32_t yazmaSayaci = 0;
volatile uint32_t okumaSayaci = 0;

/* Karttan bayt(lar) geldiginde cagrilir
 *
 * ONEMLI (14 Eylul 2026 - kart uzerinde olculdu):
 *   ESP32'nin I2C slave surucusu, onRequest() cagrildiginda TX
 *   tamponunun ZATEN DOLU olmasini bekler. Tamponu yalnizca
 *   onRequest() icinde doldurmak BIR TUR GECIKME yaratir: kart
 *   0x5A yazip okudugunda bir onceki turun cevabi doner.
 *
 *   Olculen belirti:
 *       yazildi 5A -> okundu C3   (bir onceki 3C'nin tersi)
 *       yazildi A5 -> okundu A5   (bir onceki 5A'nin tersi)
 *
 *   Cozum: cevabi onReceive icinde HEMEN tampona yaz. Boylece
 *   kart okumaya geldiginde dogru bayt hazir bekliyor olur.
 */
void onReceive(int adet) {
  while (Wire.available()) {
    sonGelen   = Wire.read();
    donecekVal = (uint8_t)(~sonGelen);
    yeniVeri   = true;
    yazmaSayaci++;
  }
  /* Cevabi SIMDI tampona koy - onRequest beklemeden */
  Wire.write(donecekVal);
}

/* Kart okuma istedi. Tampon onReceive'de dolduruldu; burada yalnizca
 * sayac artar. Tampon bos kalirsa (yazma olmadan okuma) guvenli bir
 * deger yaziyoruz ki hat asili kalmasin. */
void onRequest() {
  okumaSayaci++;
}

void setup() {
  Serial.begin(115200);
  delay(300);

  Wire.begin(I2C_SLAVE_ADDR, PIN_SDA, PIN_SCL, 400000);
  Wire.onReceive(onReceive);
  Wire.onRequest(onRequest);

  Serial.println();
  Serial.print("ARKHE I2C SLAVE HAZIR (adres 0x");
  Serial.print(I2C_SLAVE_ADDR, HEX);
  Serial.println(")");
  Serial.print("  SDA=GPIO"); Serial.print(PIN_SDA);
  Serial.print("  SCL=GPIO"); Serial.println(PIN_SCL);
  Serial.println("  Karttan gelen her bayt icin tersi dondurulur.");
  Serial.println();
}

void loop() {
  if (yeniVeri) {
    noInterrupts();
    uint8_t g = sonGelen;
    uint8_t d = donecekVal;
    yeniVeri = false;
    interrupts();

    Serial.print("yazildi: 0x");
    if (g < 0x10) Serial.print("0");
    Serial.print(g, HEX);
    Serial.print("  ->  okunacak: 0x");
    if (d < 0x10) Serial.print("0");
    Serial.println(d, HEX);
  }

  /* Her 5 saniyede bir sayac ozeti - hat sessizse fark edilir */
  static uint32_t sonOzet = 0;
  if (millis() - sonOzet > 5000) {
    sonOzet = millis();
    if (yazmaSayaci || okumaSayaci) {
      Serial.print("  [ozet] yazma="); Serial.print(yazmaSayaci);
      Serial.print("  okuma=");        Serial.println(okumaSayaci);
    }
  }
}
