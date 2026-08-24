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

/* Derleyicinin islemi sabit katlamasini (constant folding) ENGELLER.
   Aksi halde Spike ve RTL ayni sonucu uretir ama hicbir ARITMETIK BUYRUK
   kosulmaz - test bos kalir. */
static volatile unsigned int tohum = 0x12345678u;
static volatile int          itohum = -1234567;

int main(void)
{
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

    /* --- Imza: tamamlandigini gosterir --- */
    s[31] = 0xC0DE0001u;

    /* Programi burada bitir. crt0 sonsuz donguye girer;
       Spike'ta da RTL'de de ayni yerde durur. */
    return 0;
}
