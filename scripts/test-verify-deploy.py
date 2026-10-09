import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

REVISION = "a" * 40
SCRIPT = Path(__file__).with_name("verify-deploy.py")


class ExternalDeployTests(unittest.TestCase):
    def run_verification(self, fail_probe=False, emit_ready=True, remote_status=0):
        with tempfile.TemporaryDirectory(prefix="proser-external-check-") as directory:
            root = Path(directory)
            log = root / "probes.jsonl"
            curl = root / "curl"
            curl.write_text(f"#!{sys.executable}\n" + '''import json, os, sys
with open(os.environ["PROBE_LOG"], "a") as log:
 log.write(json.dumps(sys.argv[1:]) + "\\n")
sys.exit(22 if os.environ["FAIL_PROBE"] == "1" else 0)
''')
            curl.chmod(0o755)
            remote_code = (
                f"import sys\nprint('PROSER_PUBLIC_HEALTH_READY {REVISION}', flush=True)\n"
                "verdict = input()\nprint(verdict, flush=True)\n"
                f"sys.exit({remote_status} if verdict == 'PROSER_PUBLIC_HEALTH_OK {REVISION}' else 1)\n"
            ) if emit_ready else "print('Remote exited before public verification')"
            result = subprocess.run([
                sys.executable, str(SCRIPT), REVISION, sys.executable, "-c", remote_code,
            ], env={**os.environ, "PATH": directory + os.pathsep + os.environ["PATH"],
                    "PROBE_LOG": str(log), "FAIL_PROBE": "1" if fail_probe else "0"},
                text=True, capture_output=True, timeout=20)
            probes = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
            return result, probes

    def test_all_public_routes_are_required_before_exact_revision_approval(self):
        result, probes = self.run_verification()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"PROSER_PUBLIC_HEALTH_OK {REVISION}", result.stdout)
        self.assertEqual([args[-1] for args in probes], [
            "https://app.proser.studio/up", "https://api.proser.studio/up",
            "https://app.proser.studio/api/v1/releases",
        ])
        for args in probes:
            self.assertIn("-fsS", args)
            self.assertNotIn("--insecure", args)
            self.assertNotIn("-k", args)

    def test_http_failure_sends_failure_to_server_and_stops(self):
        result, probes = self.run_verification(fail_probe=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(f"PROSER_PUBLIC_HEALTH_FAILED {REVISION}", result.stdout)
        self.assertEqual(len(probes), 1)

    def test_successful_remote_exit_without_public_verification_is_rejected(self):
        result, probes = self.run_verification(emit_ready=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(probes, [])

    def test_remote_failure_after_public_approval_is_rejected(self):
        result, _ = self.run_verification(remote_status=1)
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
