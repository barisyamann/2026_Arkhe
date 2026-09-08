.PHONY: asic_run asic_verify collect gds_lvs

asic_run:
	python3 scripts/run_flow.py

asic_verify:
	python3 scripts/verify_delivery.py

collect:
	python3 scripts/collect_delivery.py "$(RUN)"

gds_lvs:
	python3 scripts/run_gds_lvs.py
