# =============================================================================
#  asic/Makefile - Arkhe SoC ASIC akisi
#  TEKNOFEST 2026 - Takim Arkhe
#
#  Zorunlu hedef: asic_run
#
#  Kullanim (Nix ortami icinde, asic/ dizininden):
#      make asic_run       tam LibreLane Classic akisini kosar
#      make lint           yalnizca lint adimini kosar
#      make synth          yalnizca sentez adimina kadar kosar
#      make collect        ciktilari results/ ve reports/ altina toplar
#      make check          filelist.f ile config.yaml tutarliligini denetler
#      make clean          run/ altindaki gecici calisma alanini siler
# =============================================================================

LIBRELANE ?= librelane
CONFIG    ?= config.yaml
RUN_DIR   ?= run
TAG       ?= arkhe

.PHONY: asic_run asic_verify asic_clean lint synth sources collect check clean distclean help

# -----------------------------------------------------------------------------
# ZORUNLU HEDEF - tam akis
# -----------------------------------------------------------------------------
asic_run: check
	@mkdir -p $(RUN_DIR)/$(TAG)
	$(LIBRELANE) $(CONFIG) --run-tag $(TAG) --force-run-dir $(RUN_DIR)/$(TAG)
	$(MAKE) collect

# -----------------------------------------------------------------------------
# Kismi kosumlar - hata ayiklama icin
# -----------------------------------------------------------------------------
lint: check
	@mkdir -p $(RUN_DIR)/$(TAG)-lint
	$(LIBRELANE) $(CONFIG) --run-tag $(TAG)-lint \
	    --force-run-dir $(RUN_DIR)/$(TAG)-lint \
	    --to Checker.LintErrors

synth: check
	@mkdir -p $(RUN_DIR)/$(TAG)-synth
	$(LIBRELANE) $(CONFIG) --run-tag $(TAG)-synth \
	    --force-run-dir $(RUN_DIR)/$(TAG)-synth \
	    --to Yosys.Synthesis

# -----------------------------------------------------------------------------
# Tutarlilik denetimi
#
# Sartname: "LibreLane yapilandirmasinda kullanilan RTL kaynaklari ile
# asic/filelist.f icerigi birbiriyle uyumlu olmalidir."
# Ayrica listedeki her dosya gercekten var olmali.
# -----------------------------------------------------------------------------
check:
	@python3 scripts/check_filelist.py
	@python3 scripts/gen_sources.py --check

# -----------------------------------------------------------------------------
# Kaynak listesi uretimi
#
# LibreLane dosya-listesi dosyasini dogrudan kabul etmiyor. filelist.f tek
# dogruluk kaynagidir; bu hedef config.yaml icindeki VERILOG_FILES blogunu
# ondan yeniden uretir.
# -----------------------------------------------------------------------------
sources:
	@python3 scripts/gen_sources.py

# -----------------------------------------------------------------------------
# Cikti toplama
#
# LibreLane'in run dizinindeki sonuclari sartnamenin istedigi
# results/ ve reports/ agacina kopyalar.
# -----------------------------------------------------------------------------
collect:
	@python3 scripts/collect_outputs.py $(RUN_DIR)/$(TAG)

# -----------------------------------------------------------------------------
# ONERILEN HEDEFLER  (Final Ciktilar s.34)
#
#   asic_verify : teslim edilen rapor ve ciktilarin varligini denetler,
#                 temel sonuclari ozetler
#   asic_clean  : run/ altindaki yeniden uretilebilir dosyalari temizler
# -----------------------------------------------------------------------------
asic_verify:
	python3 scripts/check_teslim.py

asic_clean:
	rm -rf $(RUN_DIR)/*
	@mkdir -p $(RUN_DIR)
	@touch $(RUN_DIR)/.gitkeep
	@echo "run/ temizlendi (.gitkeep birakildi)"

# -----------------------------------------------------------------------------
# Temizlik
# -----------------------------------------------------------------------------
clean:
	rm -rf $(RUN_DIR)/*

distclean: clean
	rm -rf results/*/ reports/*/ metrics/* config/resolved.json

help:
	@echo "Arkhe SoC ASIC akisi"
	@echo "  make asic_run   tam akis (ZORUNLU HEDEF)"
	@echo "  make lint       yalnizca lint"
	@echo "  make synth      sentez adimina kadar"
	@echo "  make collect    ciktilari topla"
	@echo "  make sources    config.yaml kaynak listesini filelist.f'ten uret"
	@echo "  make check      filelist tutarlilik denetimi"
	@echo "  make clean      gecici calisma alanini sil"
	@echo "  make asic_verify teslim denetimi (onerilen)"
	@echo "  make asic_clean  run/ temizle (onerilen)"
