"""Host denetleyicisi eksik/bozuk kaniti basarili saymamali."""
import unittest
import run_jury as j


class ValidationTests(unittest.TestCase):
    def setUp(self):
        self.lines = ['SELFTEST_BEGIN', 'BOOT_IRAM_FNV 00000001',
                      'WEIGHTS_FNV 00000002', 'WEIGHTS_AFTER_MEMORY_FNV 00000002']
        for name, count in j.CATALOG.items():
            self.lines.extend([f'CHECK {name} PASS 00000000 00000000'] * count)
        self.lines.append('SELFTEST_END 83 0')
        self.expected = {'iram_fnv': 1, 'weights_fnv': 2}

    def test_complete(self):
        j.verify_selftest(self.lines, self.expected)

    def test_missing(self):
        with self.assertRaises(RuntimeError):
            j.verify_selftest(self.lines[:4] + self.lines[5:], self.expected)

    def test_duplicate(self):
        with self.assertRaises(RuntimeError):
            j.verify_selftest(self.lines + [self.lines[4]], self.expected)

    def test_unknown_bits(self):
        with self.assertRaises(RuntimeError):
            j.verify_checks(['CHECK NPU_IRQ PASS xxxxxxxx 00000001'], {'NPU_IRQ': 1})

    def test_pass_label_cannot_hide_wrong_value(self):
        with self.assertRaises(RuntimeError):
            j.verify_checks(['CHECK NPU_IRQ PASS 00000000 00000001'], {'NPU_IRQ': 1})

    def test_wrong_image(self):
        with self.assertRaises(RuntimeError):
            j.verify_selftest(self.lines, {'iram_fnv': 3, 'weights_fnv': 2})

    def test_inference_and_wrong_probability(self):
        cases, payloads, meta, _ = j.load_assets()
        c = cases[0]; data = payloads[c['name']]; probs = meta[c['name']]['probs']
        lines = [f'CHECK {n} PASS 00000001 00000001' for n in j.INFER_CHECKS]
        lines += [f'INPUT_FNV {j.fnv(data):08X}', f'[IRQ] Class: {c["expected_class"]}',
                  'RESULT 3 ' + ' '.join(f'{x:08X}' for x in probs) + ' 1000']
        j.verify_infer(lines, c, data, probs)
        with self.assertRaises(RuntimeError):
            j.verify_infer(lines, c, data, [0, 0, 0, 0])
        with self.assertRaises(RuntimeError):
            j.verify_infer(lines, c, bytes(1960), probs)


if __name__ == '__main__':
    unittest.main()
