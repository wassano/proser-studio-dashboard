#!/usr/bin/env python3
"""Run the SSH deployment and return external HTTPS results over its stdin."""
import re
import subprocess
import sys


def main():
    revision, *command = sys.argv[1:]
    if not re.fullmatch(r"[a-f0-9]{40}", revision) or not command:
        raise SystemExit("Expected a commit SHA and SSH command")
    ready = f"PROSER_PUBLIC_HEALTH_READY {revision}"
    verified = False
    received_ready = False
    with subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True) as remote:
        try:
            for line in remote.stdout:
                print(line, end="", flush=True)
                if line.strip() != ready:
                    continue
                if received_ready:
                    raise RuntimeError("Duplicate public verification request")
                received_ready = True
                verified = True
                for endpoint in (
                    "https://app.proser.studio/up",
                    "https://api.proser.studio/up",
                    "https://app.proser.studio/api/v1/releases",
                ):
                    print(f"Verificando HTTPS pelo runner: {endpoint}", flush=True)
                    result = subprocess.run([
                        "curl", "-fsS", "--max-time", "15", "--retry", "2", "--retry-delay", "2",
                        "--retry-max-time", "40", "--user-agent", "Proser-Deploy-Healthcheck/1.0", endpoint,
                    ], stdout=subprocess.DEVNULL)
                    if result.returncode:
                        verified = False
                        break
                verdict = "OK" if verified else "FAILED"
                remote.stdin.write(f"PROSER_PUBLIC_HEALTH_{verdict} {revision}\n")
                remote.stdin.flush()
                remote.stdin.close()
        finally:
            if not remote.stdin.closed:
                # EOF makes the server restore the previous image on errors.
                remote.stdin.close()
        status = remote.wait()
    return 0 if received_ready and verified and status == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
