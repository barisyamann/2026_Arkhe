"""Tek USB ile kart uzerinde denetimli juri senaryosu. Python 3 + pyserial."""
from pathlib import Path
from collections import Counter
import argparse
import hashlib
import json
import random
import re
import time

ROOT = Path(__file__).resolve().parent
CATALOG = dict.fromkeys([
    'CPU_ADD', 'CPU_SUB', 'CPU_XOR', 'CPU_AND', 'CPU_SHIFT', 'CPU_MUL',
    'CPU_DIVU', 'CPU_REMU', 'CPU_DIV_ZERO', 'CPU_REM_ZERO', 'CPU_DIV_OVERFLOW',
    'DRAM_BYTE_ENABLE', 'DRAM_HALF_ENABLE', 'TCM_ALL_BANK_EDGES',
    'GPIO_SET', 'GPIO_CLEAR', 'GPIO_TOGGLE', 'GPIO_WALKING_REGISTER',
    'DMA_FIXED_SOURCE', 'DMA_FIXED_SOURCE_DATA', 'DMA_FIXED_DEST',
    'DMA_FIXED_DEST_DATA', 'ROM_WRITE_IRQ', 'ROM_WRITE_ADDR', 'ROM_WRITE_STATUS',
    'I2C_NO_SLAVE_DONE'], 1)
CATALOG.update(dict.fromkeys(['DRAM_PATTERNS', 'TCM_WORK_PATTERNS', 'TCM_TAIL_PATTERNS',
    'DMA_DRAM_TCM', 'DMA_DATA', 'DMA_GUARD_LEFT', 'DMA_GUARD_RIGHT',
    'DMA_TCM_DRAM', 'DMA_RETURN_DATA'], 5))
CATALOG.update(dict.fromkeys(['TIMER_IRQ', 'TIMER_IRQ_COUNT', 'TIMER_STOPPED',
    'TIMER_EVENT_CLEARED'], 3))
INFER_CHECKS = dict.fromkeys(['STREAM_DMA', 'STREAM_DMA_IRQ', 'NPU_IRQ', 'NPU_IRQ_COUNT'], 1)


def require(ok, message):
    if not ok:
        raise RuntimeError(message)


def fnv(data):
    h = 2166136261
    for b in data:
        h = ((h ^ b) * 16777619) & 0xffffffff
    return h


def values(lines, name):
    return [line.split()[1:] for line in lines if line.startswith(name + ' ')]


def one_hex(lines, name):
    found = values(lines, name)
    require(len(found) == 1 and len(found[0]) == 1 and
            re.fullmatch('[0-9A-F]{8}', found[0][0]), f'Eksik/gecersiz {name}: {found}')
    return int(found[0][0], 16)


def verify_checks(lines, catalog):
    counts = Counter()
    for line in lines:
        if not line.startswith('CHECK '):
            continue
        m = re.fullmatch(r'CHECK (\w+) PASS ([0-9A-F]{8}) ([0-9A-F]{8})', line)
        require(m is not None, f'Basarisiz veya bozuk test satiri: {line}')
        require(m[2] == m[3], f'Beklenen/okunan farkli: {line}')
        counts[m[1]] += 1
    require(counts == Counter(catalog), f'Test kapsami eksik/fazla: {counts - Counter(catalog)} / {Counter(catalog) - counts}')


def verify_selftest(lines, expected, sim=False):
    require(lines.count('SELFTEST_BEGIN') == 1, 'SELFTEST_BEGIN eksik/tekrarli')
    require(values(lines, 'SELFTEST_END') == [[str(sum(CATALOG.values())), '0']], 'Oztest sayisi/hata sayisi hatali')
    verify_checks(lines, CATALOG)
    require(one_hex(lines, 'BOOT_IRAM_FNV') == expected['iram_sim_fnv' if sim else 'iram_fnv'], 'Flash -> I-RAM kod ozeti uyusmadi; yanlis/eski imaj olabilir')
    for name in ['WEIGHTS_FNV', 'WEIGHTS_AFTER_MEMORY_FNV']:
        require(one_hex(lines, name) == expected['weights_fnv'], f'{name}: agirliklar bozulmus')


def verify_infer(lines, case, payload, probs):
    verify_checks(lines, INFER_CHECKS)
    require(one_hex(lines, 'INPUT_FNV') == fnv(payload), 'UART/DMA girdi ozeti uyusmadi')
    irq = [x for x in lines if x.startswith('[IRQ]')]
    require(irq == [f'[IRQ] Class: {case["expected_class"]}'], f'NPU ISR sonucu hatali: {irq}')
    result = values(lines, 'RESULT')
    require(len(result) == 1 and len(result[0]) == 6, 'RESULT eksik/gecersiz')
    c, *rest = result[0]
    actual = [int(x, 16) for x in rest[:4]]
    require(int(c) == case['expected_class'] and actual == probs, f'NPU referans farki: sinif={c}, probs={actual}; beklenen={probs}')
    require(int(rest[4]) > 0, 'Cevrim sayaci ilerlemiyor')
    return {'name': case['name'], 'class': int(c), 'probs': actual,
            'cycles_including_isr_and_uart': int(rest[4]), 'passed': True}


class Console:
    def __init__(self, port, log, timeout):
        self.port, self.log, self.timeout = port, log, timeout
        self.pending = bytearray()

    def until(self, marker):
        lines = []
        deadline = time.monotonic() + self.timeout
        while time.monotonic() < deadline:
            if b'\n' in self.pending:
                raw, _, self.pending = self.pending.partition(b'\n')
                line = raw.rstrip(b'\r').decode('ascii', errors='strict')
                self.log.write(line + '\n'); self.log.flush()
                print(line, flush=True)
                lines.append(line)
                if line == marker:
                    return lines
                require(not line.startswith('CHECK ') or ' PASS ' in line, f'Kart testi basarisiz: {line}')
            else:
                self.pending.extend(self.port.read(max(1, self.port.in_waiting)))
        raise TimeoutError(f'{marker} beklenirken zaman asimi; son satirlar: {lines[-5:]}')

    def send(self, data, chunk=0):
        chunk = chunk or len(data)
        for i in range(0, len(data), chunk):
            part = data[i:i + chunk]
            require(self.port.write(part) == len(part), 'Eksik USB yazmasi')
            self.port.flush()
            if chunk < len(data):
                time.sleep(0.002)

    def command(self, command):
        self.send(command)
        return self.until('READY')


def manual(c, report):
    input('\n16 anahtarin hepsini OFF/0 yap, sonra Enter: ')
    require(one_hex(c.command(b'G'), 'GPIO_INPUT') == 0, 'Anahtarlar 0 okunmadi')
    for mode, state, label in [(1, 65535, 'ON/1'), (2, 0, 'OFF/0')]:
        require(one_hex(c.command(b'E' + bytes([mode])), 'GPIO_EDGE_ARMED') == mode, 'GPIO kesmesi kurulamadi')
        input(f'16 anahtarin hepsini {label} yap, sonra Enter: ')
        lines = c.command(b'G')
        require(one_hex(lines, 'GPIO_INPUT') == state, 'Anahtar okuma uyusmadi')
        require(one_hex(lines, 'GPIO_IRQ_MASK') == 65535, 'Tum anahtarlar icin kenar kesmesi gorulmedi')
        require(one_hex(lines, 'GPIO_IRQ_COUNT') >= 1, 'GPIO ISR calismadi')
    c.command(b'E\0')
    for pattern, label in [(0, 'hepsi sonuk'), (65535, 'hepsi yanik'),
                           (0x5555, 'LED0,2,4,...14 yanik'), (0xaaaa, 'LED1,3,5,...15 yanik')]:
        require(one_hex(c.command(b'L' + pattern.to_bytes(2, 'little')), 'GPIO_OUTPUT') == pattern, 'LED yazmaci uyusmadi')
        require(input(f'LED kontrolu: {label}. Dogru mu? e/h: ').strip().lower() == 'e', 'Gorsel LED kontrolu onaylanmadi')
    c.command(b'L\0\0')
    report['manual_gpio'] = 'PASS: 16 anahtar, yukselen/dusen kenar IRQ, dort LED deseni'


def load_assets():
    cases = json.loads((ROOT / 'cases.json').read_text())
    meta = {v['ad']: v for v in json.loads((ROOT / 'vectors_meta.json').read_text(encoding='utf-8'))['vektorler']}
    payloads = {}
    for case in cases:
        data = (ROOT / case['file']).read_bytes()
        require(len(data) == 1960 and hashlib.sha256(data).hexdigest() == case['sha256'], f'Bozuk girdi: {case["file"]}')
        require(meta[case['name']]['sinif'] == case['expected_class'], 'Referans sinif uyusmazligi')
        payloads[case['name']] = data
    return cases, payloads, meta, json.loads((ROOT / 'expected.json').read_text())


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--port', default='COM16')
    ap.add_argument('--rounds', type=int, default=3, help='7 orneklik tur sayisi (varsayilan 3)')
    ap.add_argument('--seed', type=int, default=20260905)
    ap.add_argument('--timeout', type=float, default=90)
    ap.add_argument('--skip-manual', action='store_true')
    ap.add_argument('--validate', action='store_true', help='Yalnizca yerel girdi dosyalarini denetler')
    args = ap.parse_args()
    require(args.rounds > 0 and args.timeout > 0, 'rounds ve timeout pozitif olmali')
    cases, payloads, meta, expected = load_assets()
    if args.validate:
        print(f'Girdi kontrolu gecti: {len(cases)} vektor; oztest katalogu {sum(CATALOG.values())} kontrol. Kart testi yapilmadi.')
        return 0
    import serial
    stamp = time.strftime('%Y%m%d_%H%M%S')
    report_path = ROOT / f'juri_board_{stamp}.json'
    report = {'passed': False, 'physical_board_test': True, 'port': args.port,
              'seed': args.seed, 'rounds': args.rounds, 'inferences': [], 'selftests': 0,
              'manual_gpio': 'NOT_RUN', 'limits': [
                  'I2C: harici slave yok; yalnizca bos hat islem tamamlanmasi',
                  'QSPI: boot okuma; flash yazma/silme ve tum opcode modlari yok',
                  'D-RAM: 1KB test alani; calisan stack ve tum 8KB hucreler yok',
                  'JTAG debug/halt/resume, CPU tum ISA ve ASIC zamanlama kapsami yok',
                  'NPU: 7 referans vektorun tekrari; yeni ses/veri dogrulugu iddiasi yok']}
    try:
        with serial.Serial(args.port, 115200, timeout=0.1, write_timeout=10) as port, (ROOT / f'juri_board_{stamp}.log').open('w', encoding='utf-8') as log:
            c = Console(port, log, args.timeout)
            print('Hazir. Kartin CPU RESET dugmesine BIR KEZ basin. Test boyunca yeniden reset atmayin.', flush=True)
            lines = c.until('READY')
            require(lines.count('ARKHE_JURY_V1') == 1, 'Juri firmware surumu yok; yeni MCS ve bit dosyasini yukleyin')
            verify_selftest(lines, expected); report['selftests'] += 1
            for chunk in [0, 7]:
                c.send(b'U'); c.until('UART_READY'); data = bytes(range(256)); c.send(data, chunk)
                require(one_hex(c.until('READY'), 'UART_BYTES_FNV') == fnv(data), '256 bayt UART testi basarisiz')
            require(c.command(b'?') == ['COMMAND_REJECTED', 'READY'], 'Gecersiz komut reddedilmedi')
            rng = random.Random(args.seed)
            for turn in range(args.rounds):
                order = list(cases); rng.shuffle(order)
                for case in order:
                    chunk = [0, 17, 127][turn % 3]
                    print(f'\nTUR {turn+1}/{args.rounds}: {case["name"]}, parca={chunk or "tam"}')
                    c.send(b'N'); c.until('INPUT_READY'); data = payloads[case['name']]; c.send(data, chunk)
                    result = verify_infer(c.until('READY'), case, data, meta[case['name']]['probs'])
                    result.update(round=turn + 1, chunk=chunk); report['inferences'].append(result)
            verify_selftest(c.command(b'B'), expected); report['selftests'] += 1
            if args.skip_manual:
                report['manual_gpio'] = 'SKIP: kullanici --skip-manual secti'
            else:
                manual(c, report)
            report['passed'] = True
    except (Exception, KeyboardInterrupt) as exc:
        report['error'] = f'{type(exc).__name__}: {exc}'
        print('BASARISIZ / TAMAMLANMADI:', report['error'])
    finally:
        report_path.write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding='utf-8')
        print('Kayit:', report_path)
    if report['passed']:
        print(f'GECTI: 2 x 83 oztest kontrolu, {len(report["inferences"])} NPU sonucu, UART bayt testleri. GPIO: {report["manual_gpio"]}')
        print('Bu sonuc yalnizca raporda belirtilen kapsami dogrular.')
    return 0 if report['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
