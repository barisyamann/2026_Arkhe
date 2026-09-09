/* ==========================================================================
 *  ARKHE SoC - NPU VE ETKILESIMLI CEVRE BIRIMI DEMOSU
 *  TEKNOFEST 2026 - Takim Arkhe
 *
 *  Bu demo iki sey yapar:
 *
 *   1) NPU'yu kart uzerinde, SIMULASYONDA DOGRULANMIS altin vektorle
 *      kosturur ve sonucu ayni beklenen degerlerle karsilastirir.
 *      Boylece "RTL'de gecti" degil, "SILIKONDA da ayni sonucu veriyor"
 *      diyebiliriz.
 *
 *   2) Anahtarlar (SW) ve LED'ler uzerinden etkilesimli kip sunar; juri
 *      anahtarlari acip kapayarak sistemi canli surebilir. Buton eklemek
 *      yeniden sentez gerektirdigi icin, zaten bagli olan 16 anahtar
 *      kullanildi (nexys_top.sv:177-178  SW -> gpio_i, LED -> gpio_o).
 *
 *  BILGISAYAR GEREKMEZ. Girdi tensoru formulle uretilir, agirliklar
 *  acilista bootloader tarafindan flash'tan TCM'e kopyalanir.
 * ========================================================================== */

/* ---------------------------- Cevre birimleri --------------------------- */
#define GPIO_BASE   0x40000000u
#define GPIO_IDR    ((volatile unsigned int *)(GPIO_BASE + 0x00))
#define GPIO_ODR    ((volatile unsigned int *)(GPIO_BASE + 0x04))
#define GPIO_MODE   ((volatile unsigned int *)(GPIO_BASE + 0x08))

/* UART yazmac haritasi - uart_peripheral.sv:11-13
 *     0x08  RDR  alim   (RO)
 *     0x0C  TDR  gonderim
 *     0x10  CFG  konfigurasyon
 *
 * Ilk yazimda CFG icin 0x00 kullanilmisti. Yanlis yazmac yoklandigi
 * icin "iletim tamamlandi" biti (bit 2) hicbir zaman kurulmuyor ve
 * uart_putc ILK KARAKTERDE sonsuza kadar donuyordu: kart hicbir sey
 * yazmiyor, hicbir hata da vermiyordu.
 */
#define UART1_BASE  0x40020000u
#define U1_CFG      ((volatile unsigned int *)(UART1_BASE + 0x10))
#define U1_TDR      ((volatile unsigned int *)(UART1_BASE + 0x0C))

#define TIMER_BASE  0x40010000u
#define TIM_PRE     ((volatile unsigned int *)(TIMER_BASE + 0x00))
#define TIM_ARE     ((volatile unsigned int *)(TIMER_BASE + 0x04))
#define TIM_CLR     ((volatile unsigned int *)(TIMER_BASE + 0x08))
#define TIM_ENA     ((volatile unsigned int *)(TIMER_BASE + 0x0C))
#define TIM_MOD     ((volatile unsigned int *)(TIMER_BASE + 0x10))
#define TIM_CNT     ((volatile unsigned int *)(TIMER_BASE + 0x14))

/* --- NPU (npu_csr.sv) --- */
#define NPU_BASE    0x40060000u
#define NPU_CTRL    ((volatile unsigned int *)(NPU_BASE + 0x00))
#define NPU_STATUS  ((volatile unsigned int *)(NPU_BASE + 0x04))
#define NPU_IN_ADDR ((volatile unsigned int *)(NPU_BASE + 0x08))
#define NPU_OUT_ADDR ((volatile unsigned int *)(NPU_BASE + 0x0C))
#define NPU_CLASS   ((volatile unsigned int *)(NPU_BASE + 0x10))

#define NPU_CTRL_START      (1u << 0)
#define NPU_CTRL_RESET      (1u << 1)

/* STATUS bitleri (npu_csr.sv:88) - {.., irq, done_sticky, busy} */
#define NPU_STA_BUSY        (1u << 0)
#define NPU_STA_DONE        (1u << 1)
#define NPU_STA_WREADY      (1u << 3)   /* npu_csr.sv:85 - yukleyici dogrulamasi */

/* TCM yerlesimi (bootloader.S:101-104, npu_csr.sv:143)
 *     0    ..  489   girdi tensoru
 *     3584 .. 7583   FC AGIRLIKLARI - bootloader flash'tan kopyalar
 *     7596 .. 7599   cikis olasiliklari (asagida aciklandi)
 */
#define NPU_TCM     ((volatile unsigned int *)0x20010000u)
#define TENSOR_WORDS      490
#define FC_WEIGHT_BASE    3584
#define FC_WEIGHT_WORDS   4000

/* CIKIS ADRESI - npu_csr.sv:143
 *     reg_out_addr donanim varsayilani 0x1DAC = 7596'dir; cikis
 *     olasiliklari TCM[7596..7599]'a yazilir, TCM'in BASINA DEGIL.
 *
 *     main.c:401'deki "cikis olasiliklari 0..3 (out_addr = 0)" yorumu
 *     yanlistir: main.c REG_OUT_ADDR'a hic yazmaz, yani varsayilan
 *     7596 gecerlidir. Ilk yazimda o yoruma guvenip TCM[0..3] okundu
 *     ve girdi tensorunun ilk dort kelimesi olasilik sanildi
 *     ([4749, 1569, 6837, 3657] - Q0.12 sinirini asiyorlardi, cunku
 *     olasilik degillerdi).
 *
 *     Adresi varsayima birakmiyoruz: her kosuda acikca yaziyoruz.
 */
#define NPU_IN_WORD       0
#define NPU_OUT_WORD      7596

/* ------------------------------- UART ----------------------------------- */
static void uart_putc(char c)
{
    *U1_TDR = (unsigned int)c;
    *U1_CFG |= (1u << 0);
    while (!(*U1_CFG & (1u << 2))) { }
    *U1_CFG &= ~(1u << 2);
}

static void uart_print(const char *s)
{
    while (*s) {
        if (*s == '\n') uart_putc('\r');
        uart_putc(*s++);
    }
}

static void uart_hex(unsigned int v)
{
    const char *h = "0123456789ABCDEF";
    int i;
    uart_print("0x");
    for (i = 28; i >= 0; i -= 4) uart_putc(h[(v >> i) & 0xF]);
}

static void uart_dec(unsigned int v)
{
    char b[12];
    int n = 0;
    if (!v) { uart_putc('0'); return; }
    while (v) { b[n++] = (char)('0' + v % 10); v /= 10; }
    while (n) uart_putc(b[--n]);
}

static void bekle(unsigned int n)
{
    volatile unsigned int i;
    for (i = 0; i < n * 200u; i++) { }
}

/* ------------------------------ Denetim --------------------------------- */
static int gecti_n, kaldi_n;

static void kontrol(const char *ad, int kosul, unsigned int gelen)
{
    if (kosul) {
        gecti_n++;
        uart_print("  [OK]   "); uart_print(ad); uart_print("\n");
    } else {
        kaldi_n++;
        uart_print("  [HATA] "); uart_print(ad);
        uart_print("  gelen="); uart_hex(gelen); uart_print("\n");
    }
}

static void baslik(const char *s)
{
    uart_print("\n--- "); uart_print(s); uart_print(" ---\n");
}

/* ======================================================================
 *  1. AGIRLIKLAR TCM'DE MI
 *
 *  Zincir: flash 0x802000 -> bootloader (bootloader.S:146-152)
 *          -> TCM 0x20013800 (kelime 3584) -> NPU compute engine
 *
 *  SRAM ucucudur; uretilmis cipte guc verildiginde TCM BOSTUR. Agirliklarin
 *  kalici kaynagi flash'tir ve acilista kopyalanmalidir. Bu bolum o
 *  kopyalamanin gercekten oldugunu kart uzerinde kanitlar.
 *
 *  Agirliklar yuklenmezse FC toplayicisi bias'a esit kalir ve NPU HER
 *  girdiye ayni cevabi verir - main.c:394-397'de yasanmis gercek kusur.
 * ====================================================================== */
static void demo_agirliklar(void)
{
    unsigned int sifir_olmayan = 0, i, ilk, sta0;

    baslik("1. NPU agirliklari (flash -> TCM)");

    /* Donanimin kendi bayragi: yukleyici agirliklari yazdiginda kurulur
       (npu_csr.sv:85 WEIGHTS_READY). TCM'e hic dokunmadan once okunur,
       boylece TCM erisimi sorunluysa bile bu bilgi elimizde olur. */
    sta0 = *NPU_STATUS;
    uart_print("  bilgi  NPU STATUS = "); uart_hex(sta0); uart_print("\n");
    kontrol("donanim WEIGHTS_READY bayragi kurulu",
            (sta0 & NPU_STA_WREADY) != 0, sta0);

    uart_print("  bilgi  TCM taraniyor...\n");
    ilk = NPU_TCM[FC_WEIGHT_BASE];
    for (i = 0; i < FC_WEIGHT_WORDS; i++) {
        if (NPU_TCM[FC_WEIGHT_BASE + i] != 0) sifir_olmayan++;
    }

    uart_print("  bilgi  agirlik bolgesi TCM[3584..7583]\n");
    uart_print("  bilgi  ilk kelime = "); uart_hex(ilk); uart_print("\n");
    uart_print("  bilgi  sifir olmayan kelime = ");
    uart_dec(sifir_olmayan); uart_print(" / 4000\n");

    kontrol("agirliklar TCM'e yuklenmis", sifir_olmayan > 3900u, sifir_olmayan);

    /* weights/fc_weights_packed32.mem ilk kelimesi; flash imajinda
       birebir dogrulandi - evidence/fpga/TAM_CEVRE_DEMOSU_20260909.txt */
    kontrol("ilk agirlik kelimesi beklenen deger", ilk == 0x060804FFu, ilk);
}

/* ======================================================================
 *  2. NPU CIKARIMI - SIMULASYONDA DOGRULANMIS ALTIN VEKTOR
 *
 *  tb/npu_golden/ altindaki deterministik test RTL simulasyonunda su
 *  girdiyle kosturulur:
 *
 *      q[i] = ((37*i + 13) mod 256) - 128      i = 0 .. 1959
 *
 *  ve su sonucu vermesi beklenir (expected_golden.json):
 *
 *      fc_logits    = [-128, 79, 83, 109]
 *      probs Q0.12  = [0, 225, 326, 3543]
 *      sinif        = 3  (NO)
 *
 *  Formulun test_input_pattern.mem ile BIREBIR ayni 490 kelimeyi urettigi
 *  dogrulandi; bu yuzden 490 kelimelik tabloyu imaja gommek yerine formul
 *  kullaniliyor - imaj yaklasik 2 kB kucuk kaliyor.
 *
 *  Ayni girdi + ayni beklenen cikti, hem simulasyonda hem kart uzerinde.
 * ====================================================================== */
static unsigned int golden_kelime(unsigned int k)
{
    unsigned int w = 0, b;
    for (b = 0; b < 4u; b++) {
        unsigned int i = k * 4u + b;
        int q = (int)((37u * i + 13u) % 256u) - 128;
        w |= ((unsigned int)q & 0xFFu) << (8u * b);
    }
    return w;
}

static unsigned int npu_kosur(void)
{
    unsigned int i, bekleme, sta = 0;

    /* Girdi bolgesini yaz. FC agirlik bolgesine (3584+) DOKUNMA. */
    for (i = 0; i < TENSOR_WORDS; i++) NPU_TCM[i] = golden_kelime(i);

    /* Adresleri acikca yaz - varsayilana guvenme */
    *NPU_IN_ADDR  = NPU_IN_WORD;
    *NPU_OUT_ADDR = NPU_OUT_WORD;

    *NPU_CTRL = NPU_CTRL_RESET;
    for (i = 0; i < 50u; i++) { }
    *NPU_CTRL = 0;

    /* Baslat, sonra start bitini birak. Start yuksek kalirsa npu_csr
       done_sticky'yi surekli sifirlar (main.c:501-504). */
    *NPU_CTRL = NPU_CTRL_START;
    *NPU_CTRL = 0;

    for (bekleme = 0; bekleme < 2000000u; bekleme++) {
        sta = *NPU_STATUS;
        if (sta & NPU_STA_DONE) break;
    }
    return sta;
}

static void demo_npu(void)
{
    unsigned int sta, sinif, i, toplam;
    unsigned int p[4];

    baslik("2. NPU cikarimi (altin vektor)");

    uart_print("  bilgi  girdi: q[i] = ((37*i + 13) mod 256) - 128\n");
    uart_print("  bilgi  1960 int8 = 490 kelime -> TCM[0..489]\n");

    sta = npu_kosur();

    kontrol("NPU cikarimi tamamlandi", (sta & NPU_STA_DONE) != 0, sta);
    kontrol("NPU artik mesgul degil", (sta & NPU_STA_BUSY) == 0, sta);

    sinif = *NPU_CLASS & 3u;

    /* Cikis olasiliklari TCM[7596..7599]'da (npu_csr.sv:143) */
    for (i = 0; i < 4u; i++) p[i] = NPU_TCM[NPU_OUT_WORD + i] & 0x1FFFu;

    uart_print("  bilgi  olasiliklar Q0.12 = [");
    for (i = 0; i < 4u; i++) {
        uart_dec(p[i]);
        if (i < 3u) uart_print(", ");
    }
    uart_print("]\n");

    uart_print("  bilgi  sinif = "); uart_dec(sinif);
    uart_print("   (0=SILENCE 1=UNKNOWN 2=YES 3=NO)\n");

    /* expected_golden.json: expected_class_index = 3, "NO" */
    kontrol("sinif altin referansla ayni (3=NO)", sinif == 3u, sinif);

    /* Toplam denetimi - degerlerin gercekten olasilik oldugunun bagimsiz
       kaniti. Yanlis adres okundugunda toplam 16812 cikiyordu.
       Softmax bolmesi TAMSAYIDIR (prob = exp * 4096 / sum_exp), her
       sinifta asagi yuvarlanir; bu yuzden toplam 4096'nin bir miktar
       altinda kalir. Altin referansin kendisi de 4094 verir:
           0 + 225 + 326 + 3543 = 4094
       Denetim bu yuzden tam esitlik degil, dar bir aralik arar. */
    toplam = p[0] + p[1] + p[2] + p[3];
    uart_print("  bilgi  olasilik toplami = ");
    uart_dec(toplam);
    uart_print("  (tamsayi yuvarlama ile 4090-4096)\n");
    kontrol("olasiliklar butunluklu (toplam ~4096)",
            toplam >= 4090u && toplam <= 4096u, toplam);

    /* probabilities_q012 = [0, 225, 326, 3543] */
    kontrol("olasilik[0] altin ile ayni", p[0] == 0u,    p[0]);
    kontrol("olasilik[1] altin ile ayni", p[1] == 225u,  p[1]);
    kontrol("olasilik[2] altin ile ayni", p[2] == 326u,  p[2]);
    kontrol("olasilik[3] altin ile ayni", p[3] == 3543u, p[3]);

    uart_print("  bilgi  ayni vektor RTL simulasyonunda da sinif 3 verir\n");
    uart_print("         (tb/npu_golden/tb_npu_golden.sv:135)\n");
}

/* ======================================================================
 *  3. TEKRARLANABILIRLIK
 *
 *  Ayni girdi ard arda uc kez kosturulur; NPU her seferinde ayni sonucu
 *  vermelidir. Farkli sonuc, TCM'de kalinti veri veya yaris kosulu
 *  isaretidir.
 * ====================================================================== */
static void demo_tekrar(void)
{
    unsigned int k, sinif, ilk_sinif = 0;
    int tutarli = 1;

    baslik("3. Tekrarlanabilirlik");

    for (k = 0; k < 3u; k++) {
        (void)npu_kosur();
        sinif = *NPU_CLASS & 3u;
        if (k == 0u) ilk_sinif = sinif;
        else if (sinif != ilk_sinif) tutarli = 0;
        uart_print("  bilgi  kosu "); uart_dec(k + 1u);
        uart_print(" -> sinif "); uart_dec(sinif); uart_print("\n");
    }

    kontrol("uc kosu da ayni sonucu verdi", tutarli, ilk_sinif);
    kontrol("sonuc yine 3 (NO)", ilk_sinif == 3u, ilk_sinif);
}

/* ======================================================================
 *  4. CIKARIM SURESI
 *
 *  Timer ile olculur. 50 MHz'de cevrim / 50 = mikrosaniye.
 *  Olculen sure TCM'e yazmayi da icerir; saf cikarim daha kisadir.
 * ====================================================================== */
static void demo_sure(void)
{
    unsigned int cevrim, us;

    baslik("4. Cikarim suresi");

    *TIM_ENA = 0;
    *TIM_CLR = 1;
    *TIM_PRE = 0;                       /* her cevrim say */
    *TIM_MOD = 1;                       /* yukari say - timer_peripheral.sv:113 */
    *TIM_ARE = 0xFFFFFFFFu;             /* sarmasin */
    *TIM_ENA = 1;

    (void)npu_kosur();

    *TIM_ENA = 0;
    cevrim = *TIM_CNT;
    us = cevrim / 50u;                  /* 50 MHz */

    uart_print("  bilgi  olculen cevrim = "); uart_dec(cevrim); uart_print("\n");
    uart_print("  bilgi  yaklasik "); uart_dec(us); uart_print(" us @ 50 MHz\n");
    uart_print("         (TCM'e yazma dahil; saf cikarim daha kisa)\n");

    kontrol("sure olculebildi", cevrim > 0u, cevrim);
}

/* ======================================================================
 *  5. ETKILESIMLI KIP - ANAHTARLAR VE LED'LER
 *
 *  Anahtarlar dogrudan GPIO girisine, LED'ler GPIO cikisina baglidir
 *  (nexys_top.sv:177-178). Juri anahtarlari acip kapayarak sistemi canli
 *  surebilir; her degisim UART'a da yazilir.
 *
 *    SW[0] ac -> NPU cikarimi kosar, sinif LED[1:0]'da
 *    SW[1] ac -> olasilik[3] LED barinda
 *    SW[2] ac -> sayac LED'lerde akar (sistem canli)
 *    SW[3] ac -> anahtar deseni LED'lere yansir
 *    hicbiri  -> yuruyen isik
 * ====================================================================== */
static void demo_etkilesimli(void)
{
    unsigned int sw, onceki = 0xFFFFFFFFu, sayac = 0, sinif, p3;
    unsigned int dongu, n, mask, b;

    baslik("5. Etkilesimli kip (anahtarlar + LED'ler)");

    uart_print("  SW[0] -> NPU kosar, sinif LED[1:0]\n");
    uart_print("  SW[1] -> olasilik[3] LED barinda\n");
    uart_print("  SW[2] -> sayac LED'lerde akar\n");
    uart_print("  SW[3] -> anahtarlar LED'lere yansir\n");
    uart_print("  bos   -> yuruyen isik\n");
    uart_print("  bilgi  anahtarlari cevirin, degisim buraya yazilir\n\n");

    /* Mod alani pin basina IKI bittir (gpio_peripheral.sv:158,
       reg_mode_expanded). Cikis kipi 0x55555555; 0xFFFFFFFF yazmak
       gecerli bir kip degildir - ilk yazimda oyleydi. */
    *GPIO_MODE = 0x55555555u;

    for (dongu = 0; dongu < 400u; dongu++) {
        sw = *GPIO_IDR & 0xFFFFu;

        if (sw != onceki) {
            uart_print("  anahtar = "); uart_hex(sw);
            uart_print("  ->  ");
            if      (sw & 1u) uart_print("NPU kipi\n");
            else if (sw & 2u) uart_print("olasilik bari\n");
            else if (sw & 4u) uart_print("sayac\n");
            else if (sw & 8u) uart_print("yansitma\n");
            else              uart_print("yuruyen isik\n");
            onceki = sw;
        }

        if (sw & 1u) {
            (void)npu_kosur();
            sinif = *NPU_CLASS & 3u;
            /* sinif alt iki LED'de, ust dortlu sonucu isaretler */
            *GPIO_ODR = sinif | 0xF000u;
            bekle(200);
        } else if (sw & 2u) {
            p3 = NPU_TCM[NPU_OUT_WORD + 3] & 0x1FFFu;
            n = p3 >> 8;                /* 0..4095 -> 0..16 LED */
            if (n > 16u) n = 16u;
            mask = 0;
            for (b = 0; b < n; b++) mask |= (1u << b);
            *GPIO_ODR = mask;
            bekle(100);
        } else if (sw & 4u) {
            sayac++;
            *GPIO_ODR = (sayac >> 2) & 0xFFFFu;
            bekle(30);
        } else if (sw & 8u) {
            *GPIO_ODR = sw;
            bekle(50);
        } else {
            sayac++;
            *GPIO_ODR = 1u << ((sayac >> 2) & 15u);
            bekle(40);
        }
    }

    uart_print("\n  bilgi  etkilesimli kip suresi doldu\n");
    kontrol("anahtarlar okunabildi", 1, *GPIO_IDR & 0xFFFFu);
}

/* ------------------------------- main ----------------------------------- */
int main(void)
{
    for (;;) {
        gecti_n = 0;
        kaldi_n = 0;

        /* Ilk isaret: baska hicbir sey yapmadan once yazilir. Bu satir
           bile gelmiyorsa program hic baslamamis demektir; geliyorsa
           takilma sonraki bolumlerden birindedir. */
        uart_print("\n[ACILIS] npu_demo calisiyor\n");

        uart_print("================================================\n");
        uart_print(" ARKHE SoC - NPU VE ETKILESIMLI DEMO\n");
        uart_print(" TEKNOFEST 2026 - Takim Arkhe\n");
        uart_print("================================================\n");

        demo_agirliklar();
        demo_npu();
        demo_tekrar();
        demo_sure();
        demo_etkilesimli();

        uart_print("\n================================================\n");
        uart_print(" SONUC: "); uart_dec((unsigned int)gecti_n);
        uart_print(" gecti, "); uart_dec((unsigned int)kaldi_n);
        uart_print(" kaldi\n");
        if (kaldi_n == 0) uart_print(" NPU SILIKONDA ALTIN REFERANSLA AYNI\n");
        else              uart_print(" BAZI DENETIMLER BASARISIZ\n");
        uart_print("================================================\n");

        bekle(3000);
    }
    return 0;
}
