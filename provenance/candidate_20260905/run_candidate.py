from pathlib import Path
import os, subprocess, json, time, hashlib, difflib

b = Path(__file__).resolve().parent
d = b / 'validation'
status_path = b / 'status.json'

def status(stage, **extra):
    data = {'stage': stage, 'utc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()), **extra}
    status_path.write_text(json.dumps(data, indent=2))
    print(json.dumps(data), flush=True)

env = os.environ.copy()
bins = []
for pattern in ['*-gcc-wrapper-14*/bin', '*-binutils-wrapper-*/bin', '*-gnumake-*/bin',
                '*-coreutils-*/bin', '*-gnused-*/bin', '*-gnugrep-*/bin']:
    bins.extend(str(p) for p in Path('/nix/store').glob(pattern))
env['PATH'] = ':'.join(bins + [env.get('PATH', '/usr/bin:/bin')])

def run(stage, command, cwd, timeout):
    status(stage, command=command)
    with (d / (stage + '.log')).open('w') as f:
        try:
            p = subprocess.run(command, cwd=cwd, env=env, stdout=f,
                               stderr=subprocess.STDOUT, timeout=timeout)
        except subprocess.TimeoutExpired:
            status(stage + '_timeout')
            raise SystemExit(124)
    if p.returncode:
        status(stage + '_failed', exit_code=p.returncode)
        raise SystemExit(p.returncode)

try:
    # Preserve exact source provenance before starting expensive steps.
    base = Path.home() / 'arkhe_exp'
    src = b / 'rtl/Memory/sram_module.sv'
    original = (base / 'rtl/Memory/sram_module.sv').read_text()
    current = src.read_text()
    (b / 'sram_read_pipeline.patch').write_text(''.join(difflib.unified_diff(
        original.splitlines(True), current.splitlines(True),
        fromfile='baseline/rtl/Memory/sram_module.sv', tofile='candidate/rtl/Memory/sram_module.sv')))
    manifest = json.loads((b / 'manifest.json').read_text())
    manifest['candidate_sram_sha256'] = hashlib.sha256(current.encode()).hexdigest()
    manifest['source_hashes'] = {str(p.relative_to(b)): hashlib.sha256(p.read_bytes()).hexdigest()
                                 for p in (b / 'rtl').rglob('*') if p.is_file()}
    (b / 'manifest.json').write_text(json.dumps(manifest, indent=2))

    sources = [str((b / 'asic' / line.strip()).resolve())
               for line in (b / 'asic/filelist.f').read_text().splitlines()
               if line.strip() and not line.lstrip().startswith('#')]
    macro = b / 'asic/macros/sky130_sram_2kbyte_1rw1r_32x512_8/verilog/sky130_sram_2kbyte_1rw1r_32x512_8.v'
    verilator = next(Path('/nix/store').glob('*-verilator-*/bin/verilator'))
    cmd = [str(verilator), '--binary', '--timing', '--assert', '-Wno-fatal', '-j', '4',
           '--top-module', 'tb_soc_top', '--Mdir', str(d / 'obj_soc'),
           '+define+USE_SRAM_MACRO', '+define+SIM_MACRO_INIT', '+define+REAL_BOOT']
    for inc in ['rtl/cv32e40p-master/rtl/include', 'rtl/Memory', 'rtl/Cevre_Birimleri/files_1']:
        cmd += ['-I' + str(b / inc)]
    cmd += sources + [str(macro), str(b / 'rtl/Memory/axil_protocol_checker.sv'),
                      str(b / 'tb/spi_flash_model.sv'), str(b / 'tb/tb_soc_top.sv')]
    run('soc_compile', cmd, d, 1200)
    run('soc_test', [str(d / 'obj_soc/Vtb_soc_top')], d, 1200)
    if 'TUM TESTLER GECTI - 0 hata' not in (d / 'soc_test.log').read_text():
        status('soc_test_missing_pass_marker')
        raise SystemExit(1)

    run('pnr', [str(Path.home() / '.nix-profile/bin/librelane'),
                '--manual-pdk', '--pdk-root',
                str(Path.home() / '.ciel/ciel/sky130/versions/8afc8346a57fe1ab7934ba5a6056ea8b43078e71'),
                '--run-tag', 'sramreg_100to50', '--to', 'OpenROAD.STAPostPNR',
                '--hide-progress-bar', '-j', '8', 'config_sramreg.yaml'], b / 'asic', 57600)
    run_dir = b / 'asic/runs/sramreg_100to50'
    dirs = sorted(run_dir.glob('*stapostpnr*'))
    if not dirs:
        status('pnr_missing_sta', run_dir=str(run_dir))
        raise SystemExit(1)
    corners = {}
    for c in sorted(dirs[-1].glob('*_*C_*')):
        corners[c.name] = {}
        for kind, filename in [('setup', 'ws.max.rpt'), ('hold', 'ws.min.rpt')]:
            p = c / filename
            corners[c.name][kind] = float(p.read_text().strip().splitlines()[-1].split()[-1]) if p.exists() else None
    closed = len(corners) == 9 and all(v is not None and v >= 0 for c in corners.values() for v in c.values())
    status('timing_complete', closed=closed, corners=corners, run_dir=str(run_dir))
except Exception as e:
    status('runner_error', error=repr(e))
    raise
