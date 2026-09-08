"""Rebuild the measured full-inference program; does not touch demo firmware."""
from pathlib import Path
import importlib.util
r=Path(__file__).resolve().parents[1];d=r/'closure_20260905'
spec=importlib.util.spec_from_file_location('fw',r/'sw_nexys/scripts/build.py')
fw=importlib.util.module_from_spec(spec);spec.loader.exec_module(fw)
fw.BUILD_DIR=d/'firmware'
prefix='C:/xpack-riscv-none-elf-gcc-13.2.0-2/bin/riscv-none-elf'
gcc,objcopy,size=[fw.resolve_executable(prefix,x) for x in ['gcc','objcopy','size']]
fw.build_image(gcc,objcopy,size,'bench_full',[d/'bench_full.c'],[r/'sw_nexys/src/crt0.S'],
    r/'jury_demo/app.ld',8192,d/'bench_full.hex',d/'bench_full.bin',['-DN_OUT=4000'])
