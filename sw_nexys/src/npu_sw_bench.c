/*
 * npu_sw_bench.c - TinyConv modelinin YAZILIM gerceklemesi (olcum icin)
 *
 * AMAC
 *   Sartname EK-1: "YZ hizlandiricisi modeli gerceklemeli ve RISC-V
 *   cekirdegi uzerinde calisan yazilim gerceklemesine kiyasla HIZLANMA
 *   elde etmelidir."
 *
 *   Bolum 4.2.2.1: performans "veri/saat dongusu bazinda" olculmelidir.
 *
 *   Hizlanma ORANI icin CPU tarafinin cevrim sayisi gerekir. Bu dosya o
 *   sayiyi uretir.
 *
 * YONTEM
 *   Donanim motoruyla AYNI aritmetigi (ayni kuantizasyon carpanlari, ayni
 *   yuvarlama) C ile gerceklestirir. Agirliklar NPU TCM'inden okunur -
 *   16 kB FC agirligi 8 kB'lik D-RAM'e sigmadigi icin bu SoC uzerindeki
 *   tek gercekci yazilim senaryosudur.
 *
 *   Tam cikarim ~6 milyon cevrim surer; RTL simulasyonunda bu saatler
 *   alir. Bunun yerine N_OUT adet cikis pikseli olculur ve 4000'e
 *   olceklenir. Olceklemenin gecerli olmasi icin test IKI farkli N ile
 *   kosulur ve dogrusallik dogrulanir (bkz. tb_npu_sw_bench.sv).
 *
 * SONUC YAZIMI
 *   UART yerine TCM'e yazilir - testbench hiyerarsiden dogrudan okur.
 *   Boylece UART cozme gecikmesi olcume karismaz.
 */

typedef signed char        int8_t;
typedef unsigned char      uint8_t;
typedef signed int         int32_t;
typedef unsigned int       uint32_t;
typedef signed long long   int64_t;

/* ------------------------------------------------------------------ */
/* Bellek haritasi                                                     */
/* ------------------------------------------------------------------ */
#define TCM ((volatile uint32_t *)0x20010000u)

/* gen_tcm_image.py ile AYNI olmak zorunda */
#define OFS_GIRIS   0
#define OFS_DW_W    512
#define OFS_DW_B    704
#define OFS_FC_W    768
#define OFS_FC_B    4768
#define OFS_LUT     4800

/* Sonuc alani - testbench buradan okur */
#define OFS_SONUC   7000
/*  [7000] imza 0xB0510000 | N_OUT
 *  [7001] gecen cevrim
 *  [7002] fc_acc[0] ... [7005] fc_acc[3]   (dogruluk capraz kontrolu)
 */

#define TIMER_BASE  0x40010000u
#define TIM_PRE  ((volatile uint32_t *)(TIMER_BASE + 0x00))
#define TIM_ARE  ((volatile uint32_t *)(TIMER_BASE + 0x04))
#define TIM_CLR  ((volatile uint32_t *)(TIMER_BASE + 0x08))
#define TIM_ENA  ((volatile uint32_t *)(TIMER_BASE + 0x0C))
#define TIM_MOD  ((volatile uint32_t *)(TIMER_BASE + 0x10))
#define TIM_CNT  ((volatile uint32_t *)(TIMER_BASE + 0x14))

/* Kac cikis pikseli hesaplanacak (toplam 4000). Derlemede -D ile verilir. */
#ifndef N_OUT
#define N_OUT 25
#endif

/* ------------------------------------------------------------------ */
/* Model sabitleri - npu_compute_engine.sv ile ayni                    */
/* ------------------------------------------------------------------ */
static const int32_t DW_MULT[8] = {
    1653229999, 1516545207, 2000799311, 1159928266,
    1498403863, 1285645282, 2146175029, 1756589032
};
static const int DW_RSHIFT[8] = { 10, 12, 10, 10, 10, 10, 10, 10 };

#define FC_MULT    1932201080
#define FC_RSHIFT  11
#define FC_ZERO    14

/* ------------------------------------------------------------------ */
/* TCM erisim yardimcilari                                             */
/* ------------------------------------------------------------------ */
static int8_t tcm_i8(uint32_t taban_word, int idx)
{
    uint32_t w = TCM[taban_word + (uint32_t)(idx >> 2)];
    return (int8_t)((w >> (8 * (idx & 3))) & 0xFFu);
}

static int32_t tcm_i32(uint32_t taban_word, int idx)
{
    return (int32_t)TCM[taban_word + (uint32_t)idx];
}

/* ------------------------------------------------------------------ */
/* gemmlowp sabit nokta ilkelleri                                      */
/* ------------------------------------------------------------------ */
static int32_t sat_round_high_mul(int32_t a, int32_t b)
{
    int64_t ab, nudge, s;

    if (a == (int32_t)0x80000000 && b == (int32_t)0x80000000)
        return 0x7FFFFFFF;

    ab    = (int64_t)a * (int64_t)b;
    nudge = (ab >= 0) ? (int64_t)(1 << 30) : (int64_t)(1 - (1 << 30));
    s     = ab + nudge;
    /* C'nin '/' operatoru sifira dogru yuvarlar - Python trunc_div ile ayni */
    return (int32_t)(s / ((int64_t)1 << 31));
}

static int32_t rounding_divide_by_pot(int32_t x, int exponent)
{
    int32_t mask = (1 << exponent) - 1;
    int32_t rem  = x & mask;
    int32_t thr  = (mask >> 1) + ((x < 0) ? 1 : 0);
    return (x >> exponent) + ((rem > thr) ? 1 : 0);
}

static int32_t multiply_quantized(int32_t x, int32_t mult, int rshift)
{
    return rounding_divide_by_pot(sat_round_high_mul(x, mult), rshift);
}

/* ------------------------------------------------------------------ */
/* Ana olcum                                                           */
/* ------------------------------------------------------------------ */
int main(void)
{
    int32_t fc_acc[4];
    int32_t bas, son, gecen;
    int i, sayac;
    int t, f, d;

    /* Zamanlayici: bolme yok, yukari say, sifirdan basla.
     *
     * TIM_ARE acikca yaziliyor. ZORUNLU DEGILDIR - timer_peripheral.sv
     * icinde reset degeri zaten 0xFFFFFFFF'dir (bkz. tb/timer testi,
     * "reset TIM_ARE" denetimi). Acik yazmak olcumun tasarim degisiklikleri
     * karsisinda kirilgan olmamasini saglar.
     */
    *TIM_PRE = 0u;
    *TIM_ARE = 0xFFFFFFFFu;
    *TIM_MOD = 1u;
    *TIM_ENA = 0u;
    *TIM_CLR = 1u;
    *TIM_CLR = 0u;
    *TIM_ENA = 1u;

    for (i = 0; i < 4; i++)
        fc_acc[i] = tcm_i32(OFS_FC_B, i);

    bas = (int32_t)*TIM_CNT;

    /* ---------------------------------------------------------------
     * DepthwiseConv2D + ReLU + akisli FullyConnected
     *
     * Donanimla AYNI sira: her cikis pikseli hesaplanir hesaplanmaz
     * dort sinif biriktiricisine dagitilir. Ara 4000 elemanli tampon
     * tutulmaz - zaten 8 kB D-RAM'e sigmazdi.
     * --------------------------------------------------------------- */
    sayac = 0;
    for (t = 0; t < 25 && sayac < N_OUT; t++) {
        for (f = 0; f < 20 && sayac < N_OUT; f++) {
            for (d = 0; d < 8 && sayac < N_OUT; d++) {
                int32_t acc = tcm_i32(OFS_DW_B, d);
                int kh, kw;

                for (kh = 0; kh < 10; kh++) {
                    int ti = t * 2 - 4 + kh;
                    if (ti < 0 || ti >= 49)
                        continue;
                    for (kw = 0; kw < 8; kw++) {
                        int fi = f * 2 - 3 + kw;
                        if (fi < 0 || fi >= 40)
                            continue;
                        acc += ((int32_t)tcm_i8(OFS_GIRIS, ti * 40 + fi) + 128)
                             * (int32_t)tcm_i8(OFS_DW_W, kh * 64 + kw * 8 + d);
                    }
                }

                {
                    int32_t sc = multiply_quantized(acc, DW_MULT[d], DW_RSHIFT[d]);
                    int32_t y;
                    int c;

                    if (sc < 0)        y = 0;
                    else if (sc > 255) y = 255;
                    else               y = sc;

                    /* Flatten indeksi: (t*20 + f)*8 + d */
                    for (c = 0; c < 4; c++)
                        fc_acc[c] += y * (int32_t)tcm_i8(OFS_FC_W,
                                          c * 4000 + ((t * 20 + f) * 8 + d));
                }
                sayac++;
            }
        }
    }

    son   = (int32_t)*TIM_CNT;
    gecen = son - bas;

    /* IMZA EN SONA YAZILIR
     *
     * Testbench imzayi gorunce diger kelimeleri okur. Imza once yazilirsa
     * testbench, CPU henuz sonuclari yazmadan okur ve hepsi 0 cikar -
     * ilk kosumda tam olarak bu oldu (cevrim=0, fc_acc=[0,0,0,0]).
     */
    TCM[OFS_SONUC + 1] = (uint32_t)gecen;
    for (i = 0; i < 4; i++)
        TCM[OFS_SONUC + 2 + i] = (uint32_t)fc_acc[i];

    /* Sonuclar yerinde; simdi imza */
    TCM[OFS_SONUC + 0] = 0xB0510000u | (uint32_t)N_OUT;

    for (;;) { }
    return 0;
}
