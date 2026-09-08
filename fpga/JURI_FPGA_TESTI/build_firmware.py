from pathlib import Path
import importlib.util,json,re,shutil
root=Path(__file__).resolve().parents[1];d=root/'jury_demo'
s=importlib.util.spec_from_file_location('fw',root/'sw_nexys/scripts/build.py');m=importlib.util.module_from_spec(s);s.loader.exec_module(m)
m.BUILD_DIR=d/'firmware'
prefix='C:/xpack-riscv-none-elf-gcc-13.2.0-2/bin/riscv-none-elf'
gcc,oc,sz=[m.resolve_executable(prefix,n) for n in ['gcc','objcopy','size']]
m.build_image(gcc,oc,sz,'boot_jury',[],[d/'bootloader_jury.S'],root/'sw_nexys/link/bootloader.ld',1024,d/'boot.hex')
old=(root/'rtl/boot/boot_rom_pkg.sv').read_text();words=(d/'boot.hex').read_text().split()
(d/'boot_rom_pkg.sv').write_text(re.sub(r"8192'h[0-9a-fA-F]+","8192'h"+''.join(reversed(words)),old))
def fnv(data):
    h=2166136261
    for b in data:h=((h^b)*16777619)&0xffffffff
    return h
weights=b''.join(int(x,16).to_bytes(4,'little') for x in (root/'weights/fc_weights_packed32.mem').read_text().split())
expected={'weights_fnv':fnv(weights)}
for name,defs in [('jury',[]),('jury_sim',['-DJURY_SIM'])]:
    m.build_image(gcc,oc,sz,name,[d/'jury.c'],[root/'sw_nexys/src/crt0.S'],d/'app.ld',8192,d/(name+'.hex'),d/(name+'.bin'),defs)
    data=(d/(name+'.bin')).read_bytes()+weights
    (d/('flash_sim.hex' if defs else 'flash_jury.hex')).write_text('\n'.join(f'{int.from_bytes(data[i:i+4],"little"):08x}' for i in range(0,len(data),4))+'\n')
    expected['iram_sim_fnv' if defs else 'iram_fnv']=fnv(data[:8192])
    if not defs:(d/'flash_jury.bin').write_bytes(data)
(d/'expected.json').write_text(json.dumps(expected,indent=2))
t=(root/'demo_usb/build_usb.tcl').read_text().replace('demo_usb/','jury_demo/').replace('Arkhe_USB','Arkhe_Jury').replace('flash_usb.bin','flash_jury.bin').replace('arkhe_usb.mcs','arkhe_jury.mcs')
t=t.replace('add_files -norecurse [file normalize [file join asic $line]]','if {[string match "*boot_rom_pkg.sv" $line]} {add_files -norecurse jury_demo/boot_rom_pkg.sv} else {add_files -norecurse [file normalize [file join asic $line]]}')
(d/'build_fpga.tcl').write_text(t)
shutil.copy2(root/'demo_usb/nexys_usb_top.sv',d/'nexys_usb_top.sv');shutil.copy2(root/'demo_usb/nexys_usb.xdc',d/'nexys_usb.xdc')
shutil.copy2(root/'tb/npu_audio/vectors_meta.json',d/'vectors_meta.json')
shutil.copy2(root/'demo_usb/cases.json',d/'cases.json')
for c in json.loads((d/'cases.json').read_text()):shutil.copy2(root/'demo_usb'/c['file'],d/c['file'])
print('Jury firmware and separate boot ROM ready')
