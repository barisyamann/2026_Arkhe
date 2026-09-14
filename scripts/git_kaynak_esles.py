#!/usr/bin/env python3
"""Teslim edilen RTL'in hangi git commit'iyle esleslgini kanitlar.

NEDEN VAR
  13 Eylul 2026 dis incelemesi, provenance/git_source_match.json'in hala
  ONCEKI kosumun (d45_anten2) kaynagini -- d800acb commit'ini --
  dogruladigini tespit etti. Teslim edilen kosu S_final2'dir ve RTL'i
  d800acb ile AYNI DEGILDIR (10-11 Eylul'de dort islevsel hata
  duzeltilmistir). Dosya, yanlis commit'i teslimin kaynagi gibi
  gosteriyordu.

NE YAPAR
  asic/rtl_manifest.txt icindeki 57 dosyanin SHA-256'sini, verilen git
  commit'indeki icerikle karsilastirir. Satir sonlari LF'e normalize
  edilir (rtl_manifest.py ile ayni kural); CRLF/LF farki gercek kaynak
  farki sayilmaz.

KULLANIM
    python scripts/git_kaynak_esles.py               # HEAD'i dener
    python scripts/git_kaynak_esles.py --commit <sha>
    python scripts/git_kaynak_esles.py --ara         # son 20 commit'i tarar
    python scripts/git_kaynak_esles.py --yaz         # provenance'i guncelle
"""
import argparse
import hashlib
import json
import pathlib
import subprocess
import sys

KOK = pathlib.Path(__file__).resolve().parent.parent
MANIFEST = KOK / "asic/rtl_manifest.txt"
HEDEF = KOK / "provenance/git_source_match.json"


def manifest_oku():
    m = {}
    for ln in MANIFEST.read_text(encoding="utf-8").splitlines():
        if ln.strip():
            h, f = ln.split(None, 1)
            m[f.strip()] = h
    return m


def normal_hash(b):
    return hashlib.sha256(b.replace(b"\r\n", b"\n")).hexdigest()


def esles(commit, man):
    eslesen, farkli, yok = [], [], []
    for f, h in sorted(man.items()):
        r = subprocess.run(["git", "show", f"{commit}:{f}"],
                           capture_output=True, cwd=KOK)
        if r.returncode != 0:
            yok.append(f)
        elif normal_hash(r.stdout) == h:
            eslesen.append(f)
        else:
            farkli.append(f)
    return eslesen, farkli, yok


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--commit", default="HEAD")
    ap.add_argument("--ara", action="store_true",
                    help="son 20 commit icinde tam eslesen ILK commit'i bul")
    ap.add_argument("--yaz", action="store_true")
    a = ap.parse_args()

    if not MANIFEST.is_file():
        sys.exit(f"bulunamadi: {MANIFEST}")
    man = manifest_oku()

    if a.ara:
        log = subprocess.run(["git", "log", "--format=%H %s", "-20"],
                             capture_output=True, text=True, cwd=KOK).stdout
        en_eski_tam = None
        for ln in log.splitlines():
            c, mesaj = ln.split(" ", 1)
            e, f, y = esles(c, man)
            im = ""
            if len(e) == len(man):
                en_eski_tam = (c, mesaj)
                im = "  <-- TAM ESLESME"
            print(f"  {c[:8]} eslesen={len(e):2d} farkli={len(f):2d} "
                  f"yok={len(y):2d}  {mesaj[:42]}{im}")
        if en_eski_tam:
            print(f"\n  RTL'in ilk tam eslestigi commit: {en_eski_tam[0][:8]}"
                  f"  ({en_eski_tam[1][:50]})")
        return 0

    sha = subprocess.run(["git", "rev-parse", a.commit],
                         capture_output=True, text=True, cwd=KOK).stdout.strip()
    mesaj = subprocess.run(["git", "log", "-1", "--format=%s", sha],
                           capture_output=True, text=True, cwd=KOK).stdout.strip()
    eslesen, farkli, yok = esles(sha, man)

    print(f"  commit         : {sha[:12]}  ({mesaj[:50]})")
    print(f"  kontrol edilen : {len(man)}")
    print(f"  eslesen        : {len(eslesen)}")
    print(f"  farkli         : {len(farkli)}")
    print(f"  commit'te yok  : {len(yok)}")
    for f in farkli:
        print(f"    FARKLI: {f}")
    for f in yok:
        print(f"    YOK   : {f}")

    temiz = not farkli and not yok
    print(f"\n  SONUC: {'TUM KAYNAKLAR ESLESIYOR' if temiz else 'ESLESMIYOR'}")

    if a.yaz:
        out = {
            "aciklama": ("Teslim edilen S_final2 kosumunun RTL kaynaginin "
                         "hangi git commit'iyle eslestigini kanitlar."),
            "kosum": "S_final2",
            "commit": sha,
            "commit_mesaji": mesaj,
            "checked_sources": len(man),
            "matched": len(eslesen),
            "mismatches": farkli,
            "missing_in_commit": yok,
            "method": ("SHA-256 of 'git show <commit>:<path>', satir sonlari "
                       "LF'e normalize edilerek; asic/rtl_manifest.txt ile "
                       "karsilastirilir (scripts/rtl_manifest.py ile ayni kural)."),
            "yeniden_uretme": "python scripts/git_kaynak_esles.py --commit <sha> --yaz",
            "onceki_kosu_notu": ("Bu dosyanin onceki surumu d800acb commit'ini "
                                 "dogruluyordu; o commit ONCEKI d45_anten2 "
                                 "kosumunun kaynagidir ve teslim edilen "
                                 "S_final2'nin kaynagi DEGILDIR."),
        }
        HEDEF.write_text(json.dumps(out, indent=2, ensure_ascii=False) + "\n",
                         encoding="utf-8")
        print(f"  YAZILDI: {HEDEF.relative_to(KOK)}")

    return 0 if temiz else 1


if __name__ == "__main__":
    sys.exit(main())
