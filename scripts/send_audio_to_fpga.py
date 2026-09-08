#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
ARKHE SoC - Nexys A7 FPGA Canlı UART & Ses Verisi Gönderici Test Arayüzü
"""
import sys
import time
import serial
import serial.tools.list_ports

PORT = "COM16"
BAUD = 115200

def find_port():
    ports = [p.device for p in serial.tools.list_ports.comports() if "USB Serial Port" in p.description or "COM16" in p.device]
    if ports:
        return ports[0]
    return PORT

def main():
    port_name = find_port()
    print(f"[*] Port açılıyor: {port_name} @ {BAUD} baud...")
    try:
        ser = serial.Serial(port_name, BAUD, timeout=0.1)
    except Exception as e:
        print(f"[!] HATA: Port açılamadı ({e}). PuTTY açıksa lütfen kapatıp tekrar deneyin.")
        return

    print("[*] Bağlantı sağlandı! FPGA'dan gelen canlı çıktılar dinleniyor...")
    print("[*] (İpucu: Enter'a basarak FPGA'ya 1960 baytlık ses spektrogramı gönderebilirsiniz)\n")

    last_send = 0
    try:
        while True:
            # FPGA'dan gelenleri oku ve ekrana bas
            raw = ser.readline()
            if raw:
                try:
                    text = raw.decode('ascii', errors='ignore').strip('\r\n')
                    if text:
                        print(f"FPGA > {text}")
                except Exception:
                    pass
            time.sleep(0.01)
    except KeyboardInterrupt:
        print("\n[*] Program kullanıcı tarafından durduruldu.")
        ser.close()

if __name__ == "__main__":
    main()
