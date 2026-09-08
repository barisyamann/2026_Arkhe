#!/bin/bash
# =============================================================================
#  Arkhe ASIC - gece zinciri: 17. kosum -> 18. kosum (35 MHz)
#
#  GUVENLIK KURALLARI (DEVIR_NOTU ders 5: gozcu bir kere asic_clean calistirip
#  sentez kesif dizinini silmis ve yanlis config'le kosum baslatmisti)
#    * make asic_clean CAGRILMAZ
#    * hicbir kosum dizini SILINMEZ
#    * yalnizca ara fiziksel dosyalar budanir; final/ ve raporlar KORUNUR
# =============================================================================
set -u
cd ~/arkhe_exp/asic
K=/tmp/gece.log
yaz() { echo "[$(date '+%m-%d %H:%M:%S')] $*" | tee -a $K; }

# Hafif budama: yalnizca ara *.odb. final/ ve butun raporlar/kutukler kalir.
# Kosum yeniden surdurulemez hale gelir ama teslim ciktilari etkilenmez.
buda() {
    local T=$1
    [ -d "run/$T" ] || return 0
    local O=$(du -sb run/$T 2>/dev/null | cut -f1)
    find run/$T \( -name '*.odb' -o -name '*.odb.gz' \) -not -path "*/final/*" -delete 2>/dev/null
    local Y=$(du -sb run/$T 2>/dev/null | cut -f1)
    yaz "budandi/hafif $T : $(( (O-Y)/1073741824 )) GB kazanildi, kalan $(du -sh run/$T | cut -f1)"
}

# Derin budama: SADECE 15. kosum. O kosum artik teslim adayi degil - GDS'i
# DEGISTIRILMIS CV32E40P ile sentezlendi (sentez 08:41, geri alma commit'i
# 17:17). Beyanimiz "cekirdege dokunulmadi" oldugu icin teslim edilemez.
# KANIT olarak duruyor: final/, butun raporlar, kutukler ve metrikler
# KORUNUR; yalnizca adim adim uretilmis fiziksel ara dosyalar silinir.
buda_derin() {
    local T=$1
    [ -d "run/$T" ] || return 0
    local O=$(du -sb run/$T 2>/dev/null | cut -f1)
    find run/$T \( -name '*.odb' -o -name '*.odb.gz' -o -name '*.def' \
                  -o -name '*.spef' -o -name '*.gds' -o -name '*.nl.v' \
                  -o -name '*.pnl.v' \) -not -path "*/final/*" -delete 2>/dev/null
    local Y=$(du -sb run/$T 2>/dev/null | cut -f1)
    yaz "budandi/derin $T : $(( (O-Y)/1073741824 )) GB kazanildi, kalan $(du -sh run/$T | cut -f1)"
}

bekle() { while pgrep -f 'bin/.librelane' >/dev/null; do sleep 60; done; }

ozet() {
    local T=$1
    local S=$(ls run/$T/*stapostpnr*/summary.rpt 2>/dev/null | head -1)
    if [ -n "$S" ]; then
        yaz "--- $T STA ozeti ---"
        sed 's/│/|/g' "$S" | grep -E '^\|' | sed 's/^/    /' | tee -a $K
    else
        yaz "--- $T : STA ozeti YOK ---"
    fi
    for C in nom_tt_025C_1v80 max_tt_025C_1v80 max_ff_n40C_1v95 max_ss_100C_1v60; do
        local V=$(awk '/^Clock clk_i/{f=1} f&&/setup skew/{print $1; exit}' \
                  run/$T/*stapostpnr*/$C/skew.max.rpt 2>/dev/null)
        yaz "    carpiklik $C : ${V:-yok}"
    done
}

yaz "=========== GECE ZINCIRI BASLADI ==========="
yaz "16. kosumun bitmesi bekleniyor..."
bekle
yaz "16. kosum bitti. adim $(ls run/arkhe16 | grep -cE '^[0-9]')/78"
ozet arkhe16

# --- yer ac -----------------------------------------------------------------
yaz "disk once : $(df -h ~ | tail -1 | awk '{print $4}') bos"
buda_derin arkhe15
buda arkhe16
# run/olcum_ile ve run/olcum_haric KORUNUYOR - aligner A/B karsilastirmasinin
# ham kaniti; toplam 0,9 GB, disk hesabini bozmuyor.
yaz "disk sonra: $(df -h ~ | tail -1 | awk '{print $4}') bos"

# --- 17. kosum: CTS duzeltmesi, 20 ns / 50 MHz ------------------------------
git -C ~/arkhe_exp add asic/config.yaml
git -C ~/arkhe_exp commit -q -m "asic: saat agaci ayarlandi - 17. kosum

16. kosumda hold tt kosesinde de bozuldu. Sebep olculdu: hold marji ya da
aligner degil, SAAT CARPIKLIGI.

    kose        15. kosum   16. kosum
    nom_tt       1,254       1,718
    max_tt       1,391       1,893
    max_ff       1,167       1,480
    max_ss       2,021       2,660

max_ff'teki +0,31 ns artis, hold'un -0,083'ten -0,455'e dusmesini birebir
aciklar. Netlist cok az degisti (aligner geri alindi) ama CTS bambaska ve
daha kotu bir agac kurdu.

Asil bulgu: config.yaml'da bugune kadar HIC CTS ayari yoktu. 23 sert makro
ve 12 322 saat yapragi olan bir tasarimda agac hic ayarlanmamisti. En kotu
carpiklik yolunun kaynagi da bir makro saat pini:
u_npu.u_npu_sram.g_sram[10].u_macro/clk0, kaynak gecikmesi 3,158 ns.

CTS_OBSTRUCTION_AWARE : saat tamponlari makrolarin uzerine konmasin
CTS_BALANCE_LEVELS    : dallar arasi tampon seviyesi dengelensin
GRT_RESIZER_HOLD_SLACK_MARGIN 0,28 -> 0,15 (0,28 olculdu, etkisiz)" 2>/dev/null

yaz ">>> 17. KOSUM BASLIYOR - CTS duzeltmesi, 20 ns / 50 MHz"
mkdir -p run/arkhe17
librelane config.yaml --run-tag arkhe17 --force-run-dir run/arkhe17 >> /tmp/asic_kosum17.log 2>&1
yaz "17. kosum bitti. adim $(ls run/arkhe17 2>/dev/null | grep -cE '^[0-9]')/78  hata $(grep -cE '\[ERROR|CRITICAL' /tmp/asic_kosum17.log)"
ozet arkhe17
buda arkhe17
yaz "disk: $(df -h ~ | tail -1 | awk '{print $4}') bos"

# --- 18. kosum: 35 MHz ------------------------------------------------------
# 1000/35 = 28,571 ns. NOT: olculen max_ss (16. kosum) -9,720 ns idi;
# 28,571 ns'de yaklasik -1,15 ns kalir, CTS kazanci da dusulunce ~-0,55 ns.
# Yani 35 MHz ss kosesini TAM kapatmayabilir; tam kapanma icin ~30 ns
# (33 MHz) gerekir. Sabah karari icin ikisi de olculmus olacak.
python3 - <<'PY'
import io
p="/home/tatua7806/arkhe_exp/asic/config.yaml"
s=io.open(p,encoding="utf-8").read()
s=s.replace("CLOCK_PERIOD: 20.0","CLOCK_PERIOD: 28.571",1)
io.open("/home/tatua7806/arkhe_exp/asic/config_35mhz.yaml","w",encoding="utf-8").write(s)
print("config_35mhz.yaml yazildi")
PY
yaz ">>> 18. KOSUM BASLIYOR - 28,571 ns / 35 MHz"
mkdir -p run/arkhe18
librelane config_35mhz.yaml --run-tag arkhe18 --force-run-dir run/arkhe18 >> /tmp/asic_kosum18.log 2>&1
yaz "18. kosum bitti. adim $(ls run/arkhe18 2>/dev/null | grep -cE '^[0-9]')/78  hata $(grep -cE '\[ERROR|CRITICAL' /tmp/asic_kosum18.log)"
ozet arkhe18

yaz "=========== GECE ZINCIRI BITTI ==========="
yaz "kosumlar arkhe15/16/17/18 - hicbiri silinmedi, final/ ve raporlar tam"
