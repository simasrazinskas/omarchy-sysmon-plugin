import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('processes', Path(__file__).resolve().parents[1] / 'scripts/processes.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class ProcessesTest(unittest.TestCase):
    def test_names_with_parentheses_and_spaces(self):
        fields = ['S'] + ['0'] * 21
        fields[11], fields[12], fields[19], fields[21] = '12', '5', '234', '10'
        row = module.parse_stat('123 (worker (pool)) ' + ' '.join(fields), 4096)
        self.assertEqual(row['name'], 'worker (pool)')
        self.assertEqual(row['ticks'], 17)
        self.assertEqual(row['start'], '234')
        self.assertEqual(row['rss'], 40960)

    def test_disappeared_or_unreadable_process_is_skipped(self):
        with tempfile.TemporaryDirectory() as path:
            (Path(path) / '123').mkdir()
            self.assertEqual(module.snapshot(Path(path))['processes'], [])

    def test_live_snapshot_has_valid_counters(self):
        data = module.snapshot()
        self.assertGreater(data['hz'], 0)
        self.assertGreater(data['time'], 0)
        self.assertTrue(data['processes'])
        self.assertTrue(all(row['ticks'] >= 0 and row['rss'] >= 0 for row in data['processes']))

if __name__ == '__main__':
    unittest.main()
