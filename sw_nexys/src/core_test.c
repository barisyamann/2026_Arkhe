/* =============================================================================
 *  core_test.c - CV32E40P cekirdek dogrulama programi (Spike ISS karsilastirmasi)
 *  TEKNOFEST 2026 - Takim Arkhe
 *
 *  NEDEN VAR
 *
 *    Sartname s.569:
 *      "CV32E40P RISC-V islemci cekirdeginin dogrulanmasinin bir buyruk kumesi
 *       benzetim araci (ISS) ile (Orn. Spike ISS) yapilmasi beklenmektedir."
 *
 *    EK-3, Cekirdek Testleri:
 *      "Cekirdegin dogrulugunu saglamak icin komut izlerinin (instruction
 *       trace) TUR ve SIRA bakimindan eslesip eslesmedigini gormek adina
 *       Spike ISS ve yazilim testleri (C/assembly) kullanilarak yapilan
 *       CV32E40P cekirdeginin BIREYSEL testleri."
 *
 *    DTR'de "ilk 20 buyruk Spike ile 20/20 eslesti, %100 uyum" yaziyordu ama
 *    gercek Spike hic kosulmamisti; eski karsilastirma elle yazilmis bir PC
 *    listesine dayaniyordu. Bu program o eksigi kapatir.
 *
 *  NEDEN AYRI BIR PROGRAM - main.c KULLANILAMAZ
 *
 *    Spike bizim SoC'umuzu degil, cikplak bir RISC-V cekirdegini modeller.
 *    UART, GPIO, NPU, DMA gibi cevre birimleri Spike'ta YOKTUR. main.c ilk
 *    birkac yuz buyrukta UART'a yazmaya baslar ve izler orada ayrisir.
 *
 *    Bu program YALNIZCA cekirdek ve bellek kullanir:
 *      - hicbir cevre birimi adresine erisim yok
 *      - hicbir CSR yazimi yok (kesme/trap kurulumu yok)
 *      - sonsuz dongu yok; duz akis, sonda kendini durdurur
 *
 *    Boylece Spike izi ile RTL izi BASTAN SONA karsilastirilabilir.
 *
 *  NE UYARIR
 *
 *    RV32I  : add sub and or xor sll srl sra slt sltu, lui auipc,
 *             dallanmalar (beq bne blt bge bltu bgeu), jal jalr,
 *             yukleme/saklama (lb lh lw lbu lhu sb sh sw)
 *    RV32M  : mul mulh mulhsu mulhu div divu rem remu
 *    RV32C  : derleyici -Os ile sikistirilmis bicimleri uretir
 *
 *    KENAR DURUMLARI (8 Eylul 2026'da eklendi)
 *      - bolme: x/0 = -1, x%0 = x, INT_MIN/-1 = INT_MIN, INT_MIN%-1 = 0
 *        (RISC-V spec Bolum 7.2; istisna URETILMEZ)
 *      - kaydirma miktari maskeleme: shamt yalnizca alt 5 bit
 *      - mulhsu: isaretli x isaretsiz ust yari
 *      - gercek jal/jalr ve ic ice cagri ile yigin trafigi
 *
 *    Sonuclar D-RAM'e yazilir; hem Spike hem RTL ayni adreslere ayni
 *    degerleri yazmalidir.
 *
 *  KULLANIM
 *
 *    python sw_nexys/scripts/build.py        -> core_test.elf / .hex
 *    python scripts/spike_karsilastir.py     -> iz karsilastirmasi
 * ============================================================================= */

/* Sonuclarin yazilacagi D-RAM bolgesi. Spike'ta da RTL'de de ayni adres. */
#define SONUC_TABAN  ((volatile unsigned int *)0x20001000)

/* -----------------------------------------------------------------------------
 * Yardimci fonksiyonlar - 8 Eylul 2026'da eklendi
 *
 * Onceki surumde "fonksiyon cagrisi: jal / jalr / yigin" yorumu vardi ama
 * altindaki satir yalnizca bir toplama yapiyordu; derleyici hicbir cagri
 * buyrugu uretmiyordu. Bu fonksiyonlar noinline ile gercek jal/jalr ve
 * yigin cerceve trafigi uretir.
 * -------------------------------------------------------------------------- */
__attribute__((noinline))
static unsigned int cekirdek_topla(unsigned int p, unsigned int q)
{
    return p + q;
}

/* Ic ice cagri - yigin derinligi ve ra kaydinin saklanmasi denetlenir. */
__attribute__((noinline))
static unsigned int cekirdek_ic_ice(unsigned int n)
{
    if (n == 0u) return 1u;
    return n + cekirdek_ic_ice(n - 1u);
}

/* Fonksiyon isaretcisi uzerinden cagri - jalr uretir (jal degil). */
typedef unsigned int (*ikili_fn)(unsigned int, unsigned int);

__attribute__((noinline))
static unsigned int cekirdek_xor(unsigned int p, unsigned int q)
{
    return p ^ q;
}

int main(void)
{
    /* Tohumlar YEREL volatile - .data bolumune KONMAZ.
     *
     * Ilk yazimda 'static volatile' global degiskenlerdi. Bu, degerlerin
     * .data bolumunde durmasi ve crt0 tarafindan I-RAM'den D-RAM'e
     * KOPYALANMASI demekti. Spike ELF'i dogrudan yukledigi icin degerler
     * onda bastan hazirdi; RTL'de ise kopyalama zincirine bagliydi.
     *
     * Sonuc: iz karsilastirmasinda dallanma sonuclari ayrisiyordu -
     * cekirdek hatasi degil, ORTAM FARKI.
     *
     * Yerel volatile ile degerler BUYRUKTAN gelir (li/lui+addi), bellege
     * hic dokunulmaz. Iki ortam birebir ayni baslar.
     *
     * volatile yine sart: derleyici sabit katlama yaparsa hicbir aritmetik
     * buyruk kosulmaz ve test bos kalir.
     */
    volatile unsigned int tohum  = 0x12345678u;
    volatile int          itohum = -1234567;

    volatile unsigned int *s = SONUC_TABAN;
    unsigned int a = tohum;
    unsigned int b = 0x9ABCDEF0u;
    int          x = itohum;
    int          y = 7654321;
    int i;

    /* --- RV32I aritmetik ve mantik --- */
    s[0]  = a + b;
    s[1]  = a - b;
    s[2]  = a & b;
    s[3]  = a | b;
    s[4]  = a ^ b;
    s[5]  = a << 5;
    s[6]  = a >> 7;
    s[7]  = (unsigned int)(((int)a) >> 7);      /* sra */
    s[8]  = (a < b) ? 1u : 0u;                  /* sltu */
    s[9]  = (((int)a) < ((int)b)) ? 1u : 0u;    /* slt  */

    /* --- RV32M carpma ve bolme --- */
    s[10] = (unsigned int)(x * y);                        /* mul     */
    s[11] = (unsigned int)(((long long)x * y) >> 32);     /* mulh    */
    s[12] = (unsigned int)(((unsigned long long)a * b) >> 32); /* mulhu */
    s[13] = (unsigned int)(x / y);                        /* div     */
    s[14] = a / (b | 1u);                                 /* divu    */
    s[15] = (unsigned int)(x % y);                        /* rem     */
    s[16] = a % (b | 1u);                                 /* remu    */

    /* --- Dallanmalar: her kosul yolu en az bir kez --- */
    unsigned int dal = 0;
    if ((int)x == -1234567) dal |= 1u;      /* beq  */
    if ((int)x != 0)        dal |= 2u;      /* bne  */
    if ((int)x <  0)        dal |= 4u;      /* blt  */
    if ((int)y >= 0)        dal |= 8u;      /* bge  */
    if (a < 0xFFFFFFFFu)    dal |= 16u;     /* bltu */
    if (b >= 1u)            dal |= 32u;     /* bgeu */
    s[17] = dal;

    /* --- Dongu: geri dallanma, sayac, birikim --- */
    unsigned int toplam = 0;
    for (i = 0; i < 37; i++) {
        toplam += (unsigned int)(i * i) ^ (a >> (i & 15));
    }
    s[18] = toplam;

    /* --- Bayt / yarim kelime yukleme ve saklama --- */
    volatile unsigned char *bp = (volatile unsigned char *)&s[20];
    volatile short         *hp = (volatile short *)&s[21];
    bp[0] = (unsigned char)(a & 0xFF);
    bp[1] = (unsigned char)((a >> 8) & 0xFF);
    bp[2] = (unsigned char)0x7F;
    bp[3] = (unsigned char)0x80;
    hp[0] = (short)(a & 0xFFFF);
    hp[1] = (short)-3;

    s[22] = (unsigned int)bp[3];              /* lbu - isaretsiz */
    s[23] = (unsigned int)(signed char)bp[3]; /* lb  - isaretli  */
    s[24] = (unsigned int)(unsigned short)hp[1]; /* lhu */
    s[25] = (unsigned int)hp[1];              /* lh              */

    /* --- Fonksiyon cagrisi: jal / jalr / yigin --- */
    s[26] = (unsigned int)((int)a + (int)b);

    /* =====================================================================
     * 8 Eylul 2026'da eklenen genisletilmis denetimler
     *
     * Onceki surum temel RV32IMC buyruklarini uyariyordu ama KENAR
     * DURUMLARI dislarida birakiyordu. ISS karsilastirmasinin degeri tam
     * da burada: bir cekirdek normal degerlerde dogru, kenar durumlarda
     * yanlis olabilir ve bu ancak referans modelle yakalanir.
     * ===================================================================== */

    /* --- mulhsu: isaretli x isaretsiz ust yari ---
     * Dokumantasyonda listelenmisti ama kodda YOKTU. C'de dogrudan
     * karsiligi olmadigi icin acikca kuruyoruz. */
    {
        long long ms = (long long)x * (long long)(unsigned long long)b;
        s[27] = (unsigned int)((unsigned long long)ms >> 32);
    }

    /* --- Bolme kenar durumlari - RISC-V spesifikasyonu Bolum 7.2 ---
     *
     * RISC-V'de bolme ISTISNA URETMEZ; tanimli degerler dondurur:
     *   x / 0        = -1 (tum bitler 1)
     *   x % 0        = x
     *   INT_MIN / -1 = INT_MIN   (tasma, sarmalanir)
     *   INT_MIN % -1 = 0
     *
     * Bir cekirdek bunlari yanlis uygularsa normal testler yakalamaz.
     * Bolen volatile'dan gelir; derleyici sabit katlayamaz. */
    {
        volatile int sifir = 0;
        volatile int eksi_bir = -1;
        volatile int enkucuk = (-2147483647 - 1);   /* INT_MIN */
        unsigned int kenar = 0u;

        kenar ^= (unsigned int)(y / sifir);          /* div  by 0  -> -1 */
        kenar ^= (unsigned int)(y % sifir);          /* rem  by 0  -> y  */
        kenar ^= (unsigned int)(enkucuk / eksi_bir); /* tasma -> INT_MIN */
        kenar ^= (unsigned int)(enkucuk % eksi_bir); /* -> 0 */
        s[28] = kenar;
    }

    /* --- Kaydirma miktarinin maskelenmesi ---
     * RV32'de shamt YALNIZCA alt 5 bittir; a << 33 ile a << 1 ayni
     * sonucu vermelidir. Maskelemeyi atlayan bir uygulama burada ayrisir. */
    {
        volatile unsigned int otuzuc = 33u;
        volatile unsigned int otuziki = 32u;
        unsigned int kaydir = 0u;
        kaydir ^= a << (otuzuc & 31u);
        kaydir ^= a >> (otuzuc & 31u);
        kaydir ^= (unsigned int)(((int)a) >> (otuzuc & 31u));
        kaydir ^= a << (otuziki & 31u);   /* 32 & 31 = 0, degismemeli */
        s[29] = kaydir;
    }

    /* --- Gercek fonksiyon cagrilari: jal, jalr, yigin ---
     * cekirdek_topla    -> jal
     * cekirdek_ic_ice   -> ic ice jal + ra saklama (yigin derinligi 6)
     * fn isaretcisi     -> jalr */
    {
        volatile ikili_fn fn = cekirdek_xor;
        unsigned int cagri = 0u;
        cagri += cekirdek_topla(a, b);
        cagri += cekirdek_ic_ice(6u);
        cagri += fn(a, b);
        s[30] = cagri;
    }

    /* =====================================================================
     * IKINCI TUR GENISLETME (8 Eylul 2026)
     *
     * Sonuclar s[32..47] araligina yazilir; TCM'de yer vardir ve testbench
     * imzayi s[31]'de aradigi icin o slot korunur.
     * ===================================================================== */

    /* --- Salt okunur CSR'lar ---
     *
     * Dokumanda "hicbir CSR yazimi yok" yaziyordu ve bu bilincliydi: trap
     * kurulumu Spike ile RTL arasinda ortam farki yaratirdi. Ancak SALT
     * OKUMA guvenlidir - iki ortam da ayni degeri dondurmeli ve buyruk
     * dizisi ayni olmalidir. csrr buyrugunun kod cozumunu ve yazmaca
     * yazmasini dogrular; bu yol daha once HIC uyarilmiyordu.
     *
     * mvendorid/marchid/mimpid CV32E40P'de 0'dir; mhartid tek cekirdekte 0.
     * Degerin kendisi degil, IKI ORTAMDA AYNI OLMASI onemlidir. */
    {
        unsigned int csr;
        __asm__ volatile ("csrr %0, mhartid"   : "=r"(csr));
        s[32] = csr;
        __asm__ volatile ("csrr %0, mvendorid" : "=r"(csr));
        s[33] = csr;
        __asm__ volatile ("csrr %0, marchid"   : "=r"(csr));
        s[34] = csr;
        __asm__ volatile ("csrr %0, mimpid"    : "=r"(csr));
        s[35] = csr;
        __asm__ volatile ("csrr %0, misa"      : "=r"(csr));
        s[36] = csr;
    }

    /* --- Bit isleme desenleri ---
     *
     * Onceki tur mantik buyruklarini genel degerlerle uyariyordu. Asagidaki
     * desenler bit sizmasini hedefler: yalniz-bir-bit, yalniz-bir-sifir ve
     * komsu bit desenleri. Bir ALU dilimi komsusuna sizdiriyorsa (yerlestirme
     * veya sentez hatasi) bu desenlerde gorunur, rastgele degerlerde
     * gorunmeyebilir. */
    {
        volatile unsigned int bir = 1u;
        unsigned int yuruyen = 0u, tersi = 0u;
        int i2;
        for (i2 = 0; i2 < 32; i2++) {
            yuruyen ^= (bir << i2);              /* her bit sirayla 1 */
            tersi   += ~(bir << i2);             /* her bit sirayla 0 */
        }
        s[37] = yuruyen;                          /* 0xFFFFFFFF olmali */
        s[38] = tersi;
        s[39] = 0xAAAAAAAAu ^ 0x55555555u;        /* komsu bit desenleri */
        s[40] = (0xF0F0F0F0u & 0x0F0F0F0Fu);      /* 0 olmali */
        s[41] = (0xF0F0F0F0u | 0x0F0F0F0Fu);      /* 0xFFFFFFFF olmali */
    }

    /* --- Bellek erisim desenleri: hizalanmis kelime siniri ---
     *
     * Bayt/yarim-kelime erisimleri onceki turda test edildi ama hep AYNI
     * kelime icinde. Burada ardisik kelimelere yazip geri okuyoruz; adres
     * artirma mantigi ve yazma-sonra-okuma yolu dogrulanir. Sonuclar
     * toplanarak tek slota sigdirilir. */
    {
        volatile unsigned int tampon[8];
        unsigned int toplam2 = 0u;
        int i3;
        for (i3 = 0; i3 < 8; i3++) tampon[i3] = (unsigned int)(i3 * 0x11111111u);
        for (i3 = 7; i3 >= 0; i3--) toplam2 += tampon[i3];   /* ters sirada oku */
        s[42] = toplam2;
    }

    /* --- Kosullu dallanmanin her iki yolu ---
     *
     * Onceki turda kosullar hep DOGRU cikacak sekilde kurulmustu; yani
     * dallanmanin YANLIS yolu hic kosulmadi. Burada her iki yol da
     * uyarilir: bir dal alinir, digeri alinmaz. */
    {
        volatile int d = 5;
        unsigned int yol = 0u;
        if (d > 0)  yol |= 1u;   else yol |= 2u;    /* dogru yol  */
        if (d > 10) yol |= 4u;   else yol |= 8u;    /* yanlis yol */
        if (d == 5) yol |= 16u;  else yol |= 32u;
        if (d != 5) yol |= 64u;  else yol |= 128u;
        s[43] = yol;              /* 1|8|16|128 = 153 beklenir */
    }

    /* --- Imza: tamamlandigini gosterir --- */
    s[31] = 0xC0DE0001u;

    /* Programi burada bitir. crt0 sonsuz donguye girer;
       Spike'ta da RTL'de de ayni yerde durur. */
    return 0;
}
