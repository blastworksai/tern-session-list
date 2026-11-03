"""COMMANDER-993 boundary tests, CodexBWAI. No live Tern state is touched."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class EstateContract(unittest.TestCase):
    def setUp(self):
        self.scratch = tempfile.TemporaryDirectory(prefix="tern-estate-", dir="/var/tmp")
        self.addCleanup(self.scratch.cleanup)
        self.base = Path(self.scratch.name)
        self.data = self.base / "data"
        self.data.mkdir(mode=0o700)
        self.plan = self.base / "PLAN.md"
        self.plan.write_text("# Demo\n## Progress\n- [ ] CP1: prove outcome\n## START HERE\nCodexBWAI continues CP1.\n")
        self.env = dict(os.environ, TERN_PANE="7", SESSION_LIST_DATA=str(self.data),
                        SESSION_LIST_EPOCH="host-test-123")

    def run_cli(self, *args, ok=True):
        result = subprocess.run([str(ROOT / "bin/session-list"), *args], env=self.env,
                                text=True, capture_output=True, timeout=10)
        if ok and result.returncode:
            self.fail(result.stderr)
        return result

    def bind(self):
        return self.run_cli("bind", "--work-id", "DEMO-1", "--plan", str(self.plan))

    def view(self):
        return json.loads((self.data / "views/7.json").read_text())

    def test_projection_reads_canonical_progress_and_refuses_rebinding(self):
        """Real CLI, source edit, refresh and ownership conflict; source stays authoritative."""
        self.bind()
        text = self.plan.read_text().replace("[ ]", "[x]")
        self.plan.write_text(text)
        self.run_cli("refresh")
        self.assertEqual((self.view()["items"][0]["state"], self.plan.read_text()), ("done", text))
        result = self.run_cli("bind", "--work-id", "OTHER-1", "--plan", str(self.plan), ok=False)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(self.view()["work_id"], "DEMO-1")

    def test_private_store_and_symlink_boundary(self):
        """Another Unix user's writable store or redirected output must never be accepted."""
        self.data.chmod(0o770)
        self.assertEqual(self.run_cli("bind", "--work-id", "DEMO-1", "--plan", str(self.plan), ok=False).returncode, 1)
        self.data.chmod(0o700)
        outside = self.base / "outside"
        outside.mkdir()
        (self.data / "views").symlink_to(outside)
        self.assertEqual(self.run_cli("bind", "--work-id", "DEMO-1", "--plan", str(self.plan), ok=False).returncode, 1)
        self.assertEqual(list(outside.iterdir()), [])

    def test_failed_refresh_and_epoch_change_cannot_show_old_success(self):
        """Source failure removes old success; reused numeric pane requires a fresh binding."""
        self.bind()
        self.plan.write_text("# Broken source\n")
        self.assertEqual(self.run_cli("refresh", ok=False).returncode, 1)
        view = self.view()
        self.assertTrue(view["error"] and not view["items"])
        self.env["SESSION_LIST_EPOCH"] = "new-host-456"
        self.assertEqual(self.run_cli("refresh", ok=False).returncode, 1)


if __name__ == "__main__":
    unittest.main()
