#!/usr/bin/env python3
"""config.yaml sozdizimi ve makro instance sayisi denetimi."""
import io
import os
import sys

import yaml

ASIC = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG = os.path.join(ASIC, "config.yaml")

try:
    d = yaml.safe_load(io.open(CONFIG, encoding="utf-8"))
except yaml.YAMLError as e:
    print("YAML HATASI:\n%s" % e)
    sys.exit(1)

print("YAML gecerli.")

makrolar = d.get("MACROS") or {}
if not makrolar:
    print("  UYARI: MACROS tanimli degil")
    sys.exit(0)

toplam = 0
for ad, m in makrolar.items():
    inst = m.get("instances") or {}
    toplam += len(inst)
    print("  %s: %d instance" % (ad, len(inst)))
    for k in list(inst)[:2]:
        print("      %r -> %s" % (k, inst[k]))

print("toplam makro instance: %d" % toplam)
print("DIE_AREA: %s" % d.get("DIE_AREA"))
