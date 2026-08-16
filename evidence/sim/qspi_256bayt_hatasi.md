# Bulgu: QSPI master 256 baytlik islem yapamiyordu

Tarih   : 16 Agustos 2026
Bulundu : Iki asamali boot zinciri kurulurken
Dosya   : rtl/Cevre_Birimleri/qspi_master.sv

## Belirti

Yukleyici QSPI'dan 256 bayt istedi, yalnizca 4 bayt (bir kelime)
geldi ve sistem bekleyerek takildi.

## Kok neden

CCR yazmacinin [23:16] alani okunacak bayt sayisini (deger + 1)
belirtir, yani 256 bayta kadar soz verir. Ancak:

    logic [7:0]  total_bytes;
    total_bytes <= reg_ccr[23:16] + 1;

total_bytes 8 bitti. 0xFF + 1 = 0x100 tasarak 0 oldu. Ardindan

    if (byte_cnt + 1 >= total_bytes)

kosulu ilk baytta dogru olup islemi sonlandirdi. Sonlanirken kismi
kelime FIFO'ya yazildigi icin tam olarak bir kelime gorunuyordu.

## Duzeltme

byte_cnt ve total_bytes sayaclari 9 bite cikarildi. Toplama islemi
artik atamanin hedef genisliginde yapiliyor ve 256 tasmiyor.

## Neden daha once yakalanmadi

Hicbir test QSPI'dan 4 bayttan fazla okumamisti. Sistem testbench'i
QSPI RX FIFO'sunu elle dolduruyor, fiziksel protokolu hic
calistirmiyordu. Bu hata ancak gercek bir flash modeli baglanip
uctan uca boot denendiginde ortaya cikti.
