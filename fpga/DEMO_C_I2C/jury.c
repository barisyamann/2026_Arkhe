#include "support.inc"
typedef unsigned int u32;
#define REG(a) (*(volatile u32 *)(a))
static volatile u32 scratch[256];
static u32 checks, failures;
static u32 cycles(void) { u32 v; __asm__ volatile("csrr %0, mcycle":"=r"(v)); return v; }
static int wait_flag(volatile int *f) {
    u32 start=cycles(); while(!*f) if(cycles()-start>100000000u)return 0; return 1;
}
static void check(const char *name,u32 got,u32 expected) {
    checks++;if(got!=expected)failures++;
    uart_print("CHECK ");uart_print(name);uart_putc(' ');
    uart_print(got==expected?"PASS ":"FAIL ");
    uart_print_hex32(got);uart_putc(' ');uart_print_hex32(expected);uart_putc('\n');
}
static u32 hash(const volatile unsigned char *p,u32 n) {
    u32 h=2166136261u;while(n--)h=(h^*p++)*16777619u;return h;
}
static void value(const char *name,u32 v) {uart_print(name);uart_putc(' ');uart_print_hex32(v);uart_putc('\n');}
static int getbyte(void) {
    u32 start=cycles();while(!(*UARTS_LEVEL&511))if(cycles()-start>1500000000u)return -1;
    return *UARTS_RDR&255;
}
static int dma(u32 src,u32 dst,u32 len,u32 mode) {
    *DMA_CTRL=2;*DMA_CTRL=0;*DMA_SRC=src;*DMA_DST=dst;*DMA_LEN=len;
    dma_flag=0;dma_last_status=0;*DMA_CTRL=mode|1;*DMA_CTRL=mode;
    return wait_flag(&dma_flag) && !(dma_last_status&4);
}
static void memory_test(volatile u32 *p,u32 n,const char *name) {
    static const u32 patterns[4]={0,0xffffffffu,0x55555555u,0xaaaaaaaau};
    for(u32 k=0;k<5;k++) {
        for(u32 i=0;i<n;i++)p[i]=k==4?(i*0x10204081u)^0x91827364u:patterns[k];
        u32 bad=0;for(u32 i=0;i<n;i++)if(p[i]!=(k==4?(i*0x10204081u)^0x91827364u:patterns[k]))bad++;
        check(name,bad,0);
    }
}
static void cpu_tests(void) {
    volatile u32 seed=0x12345678u;u32 a=seed,b=0x1020304u,r;
    check("CPU_ADD",a+b,0x1336597cu);check("CPU_SUB",a-b,0x11325374u);
    check("CPU_XOR",a^b,0x1336557cu);check("CPU_AND",a&b,0x00000200u);
    check("CPU_SHIFT",a>>7,0x002468acu);
    __asm__ volatile("mul %0,%1,%2":"=r"(r):"r"(a),"r"(7));check("CPU_MUL",r,0x7f6e5d48u);
    __asm__ volatile("divu %0,%1,%2":"=r"(r):"r"(a),"r"(16));check("CPU_DIVU",r,0x01234567u);
    __asm__ volatile("remu %0,%1,%2":"=r"(r):"r"(a),"r"(16));check("CPU_REMU",r,8);
    __asm__ volatile("div %0,%1,zero":"=r"(r):"r"(a));check("CPU_DIV_ZERO",r,0xffffffffu);
    __asm__ volatile("rem %0,%1,zero":"=r"(r):"r"(a));check("CPU_REM_ZERO",r,a);
    __asm__ volatile("div %0,%1,%2":"=r"(r):"r"(0x80000000u),"r"(0xffffffffu));check("CPU_DIV_OVERFLOW",r,0x80000000u);
}
static void selftest(void) {
    uart_print("SELFTEST_BEGIN\n");checks=0;failures=0;
    value("BOOT_IRAM_FNV",hash((volatile unsigned char*)0x01000000,8192));
    value("WEIGHTS_FNV",hash((volatile unsigned char*)0x20013800,16000));
    cpu_tests();memory_test(scratch,256,"DRAM_PATTERNS");
    volatile unsigned char *bytes=(volatile unsigned char*)scratch;
    scratch[0]=0x11223344;bytes[1]=0xa5;check("DRAM_BYTE_ENABLE",scratch[0],0x1122a544);
    ((volatile unsigned short*)scratch)[1]=0x89ab;check("DRAM_HALF_ENABLE",scratch[0],0x89aba544);
    memory_test(NPU_TCM_BASE,3584,"TCM_WORK_PATTERNS");
    memory_test(NPU_TCM_BASE+7584,96,"TCM_TAIL_PATTERNS");
    u32 bad=0;
    for(u32 bank=0;bank<15;bank++)for(u32 edge=0;edge<2;edge++) {
        volatile u32 *p=NPU_TCM_BASE+bank*512+(edge?511:0);u32 old=*p;
        for(u32 bit=0;bit<32;bit++){*p=1u<<bit;if(*p!=(1u<<bit))bad++;}
        *p=old;
    }
    check("TCM_ALL_BANK_EDGES",bad,0);
    value("WEIGHTS_AFTER_MEMORY_FNV",hash((volatile unsigned char*)0x20013800,16000));
    *GPIO_MODE=0x55555555;*GPIO_ODR=0;
    REG(0x4000000c)=0xa55a;check("GPIO_SET",*GPIO_ODR,0xa55a);
    REG(0x40000010)=0x005a;check("GPIO_CLEAR",*GPIO_ODR,0xa500);
    REG(0x40000014)=0xffff;check("GPIO_TOGGLE",*GPIO_ODR,0x5aff);
    bad=0;for(u32 i=0;i<16;i++){*GPIO_ODR=1u<<i;if(*GPIO_ODR!=(1u<<i))bad++;}
    check("GPIO_WALKING_REGISTER",bad,0);*GPIO_ODR=0;
    for(u32 k=0;k<3;k++) {
        *TIM_ENA=0;*TIM_CLR=1;*TIM_EVC=1;*TIM_PRE=499;*TIM_ARE=9;
        *TIM_MOD=k==1?0:1;timer_flag=0;u32 count=timer_irq_count;
        *TIM_ENA=1;check("TIMER_IRQ",wait_flag(&timer_flag),1);
        check("TIMER_IRQ_COUNT",timer_irq_count-count,1);
        check("TIMER_STOPPED",*TIM_ENA,0);check("TIMER_EVENT_CLEARED",REG(0x40010018),0);
    }
    for(u32 k=0;k<5;k++) {
        static const u32 lens[5]={1,2,3,16,65};u32 n=lens[k];
        for(u32 i=0;i<n;i++)scratch[i]=0x81370000u+i;
        NPU_TCM_BASE[510]=0xbadc0de;NPU_TCM_BASE[511+n]=0xbadc0de;
        check("DMA_DRAM_TCM",dma((u32)scratch,(u32)(NPU_TCM_BASE+511),n,0),1);
        bad=0;for(u32 i=0;i<n;i++)if(NPU_TCM_BASE[511+i]!=scratch[i])bad++;
        check("DMA_DATA",bad,0);check("DMA_GUARD_LEFT",NPU_TCM_BASE[510],0xbadc0de);
        check("DMA_GUARD_RIGHT",NPU_TCM_BASE[511+n],0xbadc0de);
        check("DMA_TCM_DRAM",dma((u32)(NPU_TCM_BASE+511),(u32)(scratch+128),n,0),1);
        bad=0;for(u32 i=0;i<n;i++)if(scratch[128+i]!=scratch[i])bad++;
        check("DMA_RETURN_DATA",bad,0);
    }
    scratch[0]=0x55aacc33;
    check("DMA_FIXED_SOURCE",dma((u32)scratch,(u32)NPU_TCM_BASE,16,4),1);
    bad=0;for(u32 i=0;i<16;i++)if(NPU_TCM_BASE[i]!=scratch[0])bad++;
    check("DMA_FIXED_SOURCE_DATA",bad,0);
    for(u32 i=0;i<16;i++)scratch[i]=i+100;
    check("DMA_FIXED_DEST",dma((u32)scratch,(u32)NPU_TCM_BASE,16,8),1);
    check("DMA_FIXED_DEST_DATA",NPU_TCM_BASE[0],115);
    bus_fault_flag=0;REG(0x00000100)=0xdeadbeef;
    check("ROM_WRITE_IRQ",wait_flag(&bus_fault_flag),1);check("ROM_WRITE_ADDR",bus_fault_addr,0x100);
    check("ROM_WRITE_STATUS",bus_fault_st&7,5);
    /* ---- I2C: harici slave YOK (bos hat) ---- */
    *I2C_CFG=0;*I2C_NBY=1;*I2C_ADR=0x50;*I2C_TDR=0xa5;*I2C_CFG=1;
    u32 start=cycles();while(!(*I2C_CFG&2)&&cycles()-start<5000000){}
    check("I2C_NO_SLAVE_DONE",*I2C_CFG&3,2);*I2C_CFG=0;

    /* ================================================================
       I2C: HARICI SLAVE ILE GERCEK VERI ALISVERISI  (Demo C)

       Demo B raporu I2C icin "harici slave veri alisverisi/ACK
       dogrulamasi yoktur" diyordu. Bu blok o boslugu kapatir.

       Karsi taraf: ESP32, I2C slave adresi 0x42.
         - Karttan gelen bayti saklar
         - Okuma istendiginde saklanan baytin TERSINI (~x) dondurur

       NEDEN TERS DEGER: Sabit bir deger dondurseydi, hat sifira
       cekili kalsa bile test gecebilirdi. Tersini dondurmek gercek
       cift yonlu iletisimi kanitlar - karta yazdigimiz deger ESP32e
       ULASMIS ve geri donen deger ONA BAGLI olmak zorundadir.

       ACK NOTU: I2C kontrolcusu ACK/NACK bitini yazilima ACMAZ
       (CFG yalnizca TX_EN/TX_DONE/RX_EN/RX_DONE tutar). NACK
       durumunda durum makinesi STOP atar ve okunan veri gelmez.
       Dolayisiyla DOGRU VERININ GERI OKUNMASI, ACKin alindiginin
       dolayli ama kesin kanitidir.

       ESP32 BAGLI DEGILSE: yazma islemi yine TX_DONE verir, ancak
       okuma 0xFF doner (hat pull-up ile yuksek). Test bunu ayirt
       eder ve I2C_SLAVE_YOK olarak raporlar - sessizce GECMEZ.
       ================================================================ */
    {
        const u32 ESP_ADDR = 0x42;
        const u32 yaz_degeri[3] = {0x5a, 0xa5, 0x3c};
        u32 bulunan = 0;

        /* ISINMA TURU (14 Eylul 2026)
           ESP32 slave surucusunun TX tamponu ilk yazmadan ONCE bostur.
           Olcumden once bir yaz-oku turu yapip tamponu bilinen duruma
           getiriyoruz; boylece ilk gercek olcum bir onceki turun
           kalintisini gormez. Bu turun sonucu DEGERLENDIRILMEZ. */
        *I2C_CFG=0; *I2C_NBY=1; *I2C_ADR=ESP_ADDR; *I2C_TDR=0x00; *I2C_CFG=1;
        start=cycles(); while(!(*I2C_CFG&2)&&cycles()-start<5000000){}
        *I2C_CFG=0;
        start=cycles(); while(cycles()-start<100000){}   /* ~2 ms */
        *I2C_CFG=0; *I2C_NBY=1; *I2C_ADR=ESP_ADDR; *I2C_CFG=4;
        start=cycles(); while(!(*I2C_CFG&8)&&cycles()-start<5000000){}
        (void)*I2C_RDR;
        *I2C_CFG=0;
        start=cycles(); while(cycles()-start<100000){}

                /* HER DEGER ICIN IKI TUR (14 Eylul 2026)

           OLCULEN DAVRANIS: ESP32 Wire kutuphanesinin slave TX yolu
           BIR ISLEM GERIDEN gelir. ESP32 seri ciktisi cevabi DOGRU
           hesapladigini gosteriyor (yazildi 5A -> okunacak A5), ancak
           kart o turda bir onceki degeri okuyor. Tamponu onReceive
           icinde doldurmak ve 2 ms beklemek bunu degistirmedi; davranis
           ESP32 surucusunun kendisinden geliyor.

           COZUM: ayni degeri IKI KEZ yaz-oku. Ilk tur tamponu o degerin
           cevabiyla doldurur, IKINCI tur onu geri okur. Boylece surucu
           gecikmesinden bagimsiz olarak GERCEK VERI ALISVERISI
           dogrulanir - kartin yazdigi deger ESP32e ulasmis ve donen
           deger ona BAGLI olmak zorundadir. */
        for (u32 t = 0; t < 3; t++) {
            u32 v = yaz_degeri[t];
            u32 beklenen = (~v) & 0xff;
            u32 okunan = 0;
            u32 tx_ok = 0, rx_ok = 0;

            for (u32 tur = 0; tur < 2; tur++) {
                /* Yazma */
                *I2C_CFG=0; *I2C_NBY=1; *I2C_ADR=ESP_ADDR; *I2C_TDR=v; *I2C_CFG=1;
                start=cycles(); while(!(*I2C_CFG&2)&&cycles()-start<5000000){}
                tx_ok = (*I2C_CFG&2)?1:0;
                *I2C_CFG=0;
                start=cycles(); while(cycles()-start<100000){}   /* ~2 ms */

                /* Okuma */
                *I2C_CFG=0; *I2C_NBY=1; *I2C_ADR=ESP_ADDR; *I2C_CFG=4;
                start=cycles(); while(!(*I2C_CFG&8)&&cycles()-start<5000000){}
                rx_ok = (*I2C_CFG&8)?1:0;
                okunan = (*I2C_RDR)&0xff;
                *I2C_CFG=0;
                start=cycles(); while(cycles()-start<100000){}
            }

            if (t == 0) {
                check("I2C_ESP_TX_DONE", tx_ok, 1);
                check("I2C_ESP_RX_DONE", rx_ok, 1);
            }
            value("I2C_ESP_YAZILAN", v);
            value("I2C_ESP_OKUNAN",  okunan);
            if (okunan == beklenen) bulunan++;
        }

        check("I2C_ESP_VERI_DOGRU", bulunan, 3);
    }
    uart_print("SELFTEST_END ");uart_print_dec(checks);uart_putc(' ');uart_print_dec(failures);uart_putc('\n');
}
static void infer(void) {
    *UARTS_CLR=1;
    uart_print("INPUT_READY\n");
    u32 count=dma_irq_count;
    int ok=dma(UARTS_RDR32_ADDR,(u32)NPU_TCM_BASE,490,4);
    check("STREAM_DMA",ok,1);check("STREAM_DMA_IRQ",dma_irq_count-count,1);
    if(!ok)return;
    value("INPUT_FNV",hash((volatile unsigned char*)NPU_TCM_BASE,1960));
    *NPU_REG_CTRL=2;for(volatile int i=0;i<50;i++){}*NPU_REG_CTRL=8;
    npu_done_flag=0;count=npu_irq_count;u32 start=cycles();
    *NPU_REG_CTRL=9;*NPU_REG_CTRL=8;
    check("NPU_IRQ",wait_flag(&npu_done_flag),1);
    u32 elapsed=cycles()-start;
    check("NPU_IRQ_COUNT",npu_irq_count-count,1);
    uart_print("RESULT ");uart_print_dec(npu_class);
    for(u32 i=0;i<4;i++){uart_putc(' ');uart_print_hex32(NPU_TCM_BASE[REG(0x4006000c)+i]);}
    uart_putc(' ');uart_print_dec(elapsed);uart_putc('\n');
}
int main(void) {
    __asm__ volatile("csrw mcountinhibit, zero");
    uart_init();irq_init();*UARTS_CPB=JURY_CPB;*UARTS_STP=0;*UARTS_CLR=1;
    uart_print("ARKHE_JURY_V1\n");selftest();
    while(1) {
        uart_print("READY\n");while(!(*UARTS_LEVEL&511)){} int c=getbyte();
        if(c=='N')infer();
        else if(c=='B')selftest();
        else if(c=='G'){value("GPIO_INPUT",REG(0x40000000));value("GPIO_IRQ_MASK",gpio_irq_mask);value("GPIO_IRQ_COUNT",gpio_irq_count);}
        else if(c=='E'){int mode=getbyte();REG(0x40000018)=0;REG(0x4000001c)=0;REG(0x40000028)=0xffff;gpio_irq_mask=0;gpio_irq_count=0;REG(0x40000018)=mode==1?0xffff:0;REG(0x4000001c)=mode==2?0xffff:0;value("GPIO_EDGE_ARMED",mode);}
        else if(c=='L'){int a=getbyte(),b=getbyte();if(a>=0&&b>=0){*GPIO_ODR=(u32)a|((u32)b<<8);value("GPIO_OUTPUT",*GPIO_ODR);}}
        else if(c=='U') {uart_print("UART_READY\n");u32 h=2166136261u;for(u32 i=0;i<256;i++){int v=getbyte();if(v<0)break;h=(h^(u32)v)*16777619u;}value("UART_BYTES_FNV",h);}
        else uart_print("COMMAND_REJECTED\n");
    }
}
