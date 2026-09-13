#!/usr/bin/env python3
"""RTL kaynaklarinin hash manifestini uretir/dogrular.

NEDEN VAR
  10 Eylul 2026'da yapilan dis denetim, TUM ASIC kosumlarinin (A, C, D,
  E, G) ESKI RTL ile yapildigini ortaya cikardi: yereldeki duzeltilmis
  sram_module.sv sunucuya hic tasinmamisti (sunucu kopyasi 22 Agustos
  tarihliydi). Bu, en kotu setup yolunun neden SRAM cikisindan CPU ALU
  girisine kadar uzandigini da acikliyordu.

  Bir daha olmamasi icin her kosumdan once kaynak esitligi KANITLANMALI.

KULLANIM
    python scripts/rtl_manifest.py uret  > rtl_manifest.txt
    python scripts/rtl_manifest.py dogrula rtl_manifest.txt

  Satir sonlari LF'ye normalize edilerek hash alinir; CRLF/LF farki
  gercek bir kaynak farki sayilmaz.
"""
import hashlib
import io
import os
import sys

KOK = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FILELIST = os.path.join(KOK, "asic", "filelist.f")


def dosyalar():
    for ln in io.open(FILELIST, encoding="utf8"):
        p = ln.strip()
        if p and not p.startswith("#"):
            yield p


def hashle(yol):
    with open(yol, "rb") as f:
        return hashlib.sha256(f.read().replace(b"\r\n", b"\n")).hexdigest()


def uret():
    for p in sorted(dosyalar()):
        tam = os.path.join(KOK, p)
        if not os.path.isfile(tam):
            print("EKSIK %s" % p, file=sys.stderr)
            return 1
        print("%s  %s" % (hashle(tam), p))
    return 0


def dogrula(manifest):
    bekl = {}
    for ln in io.open(manifest, encoding="utf8"):
        if ln.strip():
            h, p = ln.split(None, 1)
            bekl[p.strip()] = h
    fark, eksik = [], []
    for p, h in sorted(bekl.items()):
        tam = os.path.join(KOK, p)
        if not os.path.isfile(tam):
            eksik.append(p)
        elif hashle(tam) != h:
            fark.append(p)
    print("toplam %d dosya" % len(bekl))
    if not fark and not eksik:
        print("SONUC: TUM DOSYALAR ESLESIYOR")
        return 0
    for p in fark:
        print("  FARKLI: %s" % p)
    for p in eksik:
        print("  EKSIK : %s" % p)
    print("SONUC: ESLESMIYOR - kosum baslatilmamali")
    return 1


if __name__ == "__main__":
    if len(sys.argv) >= 2 and sys.argv[1] == "uret":
        sys.exit(uret())
    if len(sys.argv) >= 3 and sys.argv[1] == "dogrula":
        sys.exit(dogrula(sys.argv[2]))
    print(__doc__)
    sys.exit(2)
