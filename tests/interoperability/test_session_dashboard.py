import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('session_dashboard', Path(__file__).resolve().parents[2] / 'scripts/session-dashboard.py')
dashboard = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dashboard)


class DashboardTests(unittest.TestCase):
    def test_completed_reports_are_escaped_and_missing_values_remain_unknown(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'covoo-one.json').write_text(json.dumps({'pcm_continuity_verified': True}))
            (root / 'covoo-one.live.json').write_text(json.dumps({'endpoint': '<script>alert(1)</script>', 'underruns': 0}))
            (root / 'pairing.json').write_text('{"token":"SECRET"}')
            page = dashboard.render(root)
            self.assertIn('&lt;script&gt;', page)
            self.assertNotIn('<script>', page)
            self.assertNotIn('SECRET', page)
            self.assertIn('Not reported', page)
            self.assertIn('<td>0</td>', page)
            self.assertEqual(page.count('<td>covoo-one</td>'), 1)

    def test_corrupt_reports_are_visible_without_hiding_good_sessions(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'covoo-bad.json').write_text('[]')
            (root / 'covoo-good.json').write_text('{}')
            (root / 'covoo-broken.json').write_text('{')
            page = dashboard.render(root)
            self.assertIn('Report must be an object', page)
            self.assertIn('covoo-broken.json', page)
            self.assertIn('<td>covoo-good</td>', page)
