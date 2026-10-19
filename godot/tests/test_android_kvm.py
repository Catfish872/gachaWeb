#!/usr/bin/env python3
"""Mocked KVM ACL lifecycle checks. Never touches a device or runs sudo."""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'tools/android/run_emulator.sh'
MOCKS = r'''
source "$SCRIPT"
kvm_accessible() { [[ -f "$RUNNER_TEMP/granted" ]]; }
kvm_device_exists() { return 0; }
getfacl() { printf '# file: /dev/kvm\nuser::rw-\ngroup::rw-\nother::---\n'; }
setfacl() { echo 'Unexpected direct ACL invocation' >&2; return 99; }
sudo() {
  printf '%s\n' "$*" >> "$RUNNER_TEMP/trace"
  if [[ "$*" == *--restore=* ]]; then
    [[ "${RESTORE_FAIL:-0}" == 0 ]] || return 1
    rm -f "$RUNNER_TEMP/granted"
  else
    touch "$RUNNER_TEMP/granted"
    [[ "${GRANT_FAIL:-0}" == 0 ]] || return 1
  fi
}
trap cleanup_android EXIT
'''


class AndroidKvmTests(unittest.TestCase):
    def run_mock(self, body, **updates):
        with tempfile.TemporaryDirectory() as directory:
            env = {**os.environ, 'SCRIPT': str(SCRIPT), 'RUNNER_TEMP': directory,
                   'ALLOW_TEMP_KVM_ACL': '1', 'GITHUB_ACTIONS': 'true',
                   'RUNNER_ENVIRONMENT': 'github-hosted', 'RUNNER_OS': 'Linux', **updates}
            result = subprocess.run(['bash', '-c', MOCKS + body], env=env, capture_output=True, text=True)
            trace = Path(directory, 'trace')
            lines = trace.read_text().splitlines() if trace.exists() else []
            backup = list(Path(directory).glob('voidrift-kvm-acl.*'))
            return result, lines, len(backup)

    def test_named_user_grant_restores_exact_original_acl(self):
        result, lines, backups = self.run_mock('acquire_kvm_access\n')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(lines[0], f'-n setfacl -m u:{os.getuid()}:rw /dev/kvm')
        self.assertTrue(lines[1].startswith('-n setfacl --restore='))
        self.assertEqual(backups, 0)

    def test_missing_opt_in_or_wrong_runner_never_grants(self):
        for values in [{'ALLOW_TEMP_KVM_ACL': ''}, {'GITHUB_ACTIONS': 'false'}, {'RUNNER_ENVIRONMENT': 'self-hosted'}, {'RUNNER_OS': 'Windows'}]:
            with self.subTest(values=values):
                result, lines, _ = self.run_mock('acquire_kvm_access\n', **values)
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(lines, [])

    def test_existing_access_requires_no_acl_change(self):
        result, lines, _ = self.run_mock('touch "$RUNNER_TEMP/granted"\nacquire_kvm_access\n', ALLOW_TEMP_KVM_ACL='')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(lines, [])

    def test_original_failure_status_is_preserved(self):
        result, lines, backups = self.run_mock('acquire_kvm_access\nexit 7\n')
        self.assertEqual(result.returncode, 7)
        self.assertTrue(lines[-1].startswith('-n setfacl --restore='))
        self.assertEqual(backups, 0)

    def test_partial_grant_failure_still_restores(self):
        result, lines, backups = self.run_mock('acquire_kvm_access\n', GRANT_FAIL='1')
        self.assertNotEqual(result.returncode, 0)
        self.assertTrue(lines[-1].startswith('-n setfacl --restore='))
        self.assertEqual(backups, 0)

    def test_cleanup_failure_fails_otherwise_successful_run(self):
        result, lines, backups = self.run_mock('acquire_kvm_access\n', RESTORE_FAIL='1')
        self.assertEqual(result.returncode, 1)
        self.assertIn('Failed to restore', result.stderr)
        self.assertEqual(backups, 1)

    def test_emulator_stops_before_acl_restore(self):
        body = r'''
acquire_kvm_access
ADB=true
EMULATOR_PID=99999
kill() { echo stop >> "$RUNNER_TEMP/trace"; return 1; }
wait() { return 0; }
'''
        result, lines, _ = self.run_mock(body)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertLess(lines.index('stop'), next(i for i, line in enumerate(lines) if '--restore=' in line))


if __name__ == '__main__':
    unittest.main(verbosity=2)
