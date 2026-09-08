"""Defined SRAM startup for the all-interface protocol test, using real CPU stores."""
from pathlib import Path
import importlib.util
r=Path(__file__).resolve().parents[1];d=r/'closure_20260905'
spec=importlib.util.spec_from_file_location('fw',r/'sw_nexys/scripts/build.py')
fw=importlib.util.module_from_spec(spec);spec.loader.exec_module(fw);fw.BUILD_DIR=d/'firmware'
prefix='C:/xpack-riscv-none-elf-gcc-13.2.0-2/bin/riscv-none-elf'
g,o,z=[fw.resolve_executable(prefix,x) for x in ['gcc','objcopy','size']]
n=fw.build_image(g,o,z,'app_defined',[r/'sw_nexys/src/main.c'],[d/'crt0_deterministic.S'],
    r/'jury_demo/app.ld',8192,d/'app_defined.hex',d/'app_defined.bin',['-DARKHE_SIM'])
if n>2048:raise RuntimeError('Current ASIC boot ROM only loads 2048 program bytes')
words=(d/'app_defined.hex').read_text().split()+(r/'weights/fc_weights_packed32.mem').read_text().split()
if len(words)!=6048:raise RuntimeError('Incorrect flash payload length')
(d/'flash_sim.hex').write_text('\n'.join(words)+'\n')
