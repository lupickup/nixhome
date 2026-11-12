"""Run free-space-guard against fake df, tmutil, mbx and osascript.

No test reaches the real commands: every run passes fakes in a temporary
directory through the FREE_SPACE_GUARD_* variables and --mbx, and run_guard
checks that before each run, so no real snapshot or cache is ever deleted.
"""

import os
from pathlib import Path
import platform
import subprocess
import tempfile
import unittest


GUARD = Path(__file__).resolve().parents[1] / "scripts" / "free-space-guard"
GIB = 1048576  # KiB

FAKE_DF = """#!/bin/sh
state='{state}'
printf '%s\\n' "$*" >> "$state/df.calls"
[ -e "$state/df.fail" ] && exit 1
free=$(cat "$state/free")
echo "Filesystem 1024-blocks Used Available Capacity Mounted on"
if [ $# -ge 2 ]; then
  echo "/dev/disk3s5 3902665360 2800000000 $free 80% /System/Volumes/Data"
else
  echo "/dev/disk3s1s1 3902665360 12582912 $free 1% /"
  echo "/dev/disk3s5 3902665360 2800000000 $free 80% /System/Volumes/Data"
  echo "/dev/disk3s6 3902665360 9437184 $free 1% /System/Volumes/VM"
  echo "/dev/disk3s7 3902665360 314572800 $free 8% /nix"
  echo "/dev/disk5s1 3902665360 3900000000 99999 99% /Volumes/Other Disk"
  echo "map auto_home 0 0 0 100% /System/Volumes/Data/home"
fi
"""

FAKE_TMUTIL = """#!/bin/sh
state='{state}'
printf '%s\\n' "$*" >> "$state/tmutil.calls"
case $1 in
  listlocalsnapshots)
    echo "Snapshots for volume group containing disk $2:"
    cat "$state/snapshots"
    ;;
  deletelocalsnapshots)
    if [ -e "$state/fail-$2" ]; then
      echo "Failed to delete local snapshot '$2'" >&2
      exit 1
    fi
    name="com.apple.TimeMachine.$2.local"
    if ! grep -qx "$name" "$state/snapshots"; then
      echo "no snapshot $2" >&2
      exit 1
    fi
    grep -vx "$name" "$state/snapshots" > "$state/snapshots.new"
    mv "$state/snapshots.new" "$state/snapshots"
    size=$(cat "$state/size-$2" 2>/dev/null || echo 0)
    echo $(( $(cat "$state/free") + size )) > "$state/free"
    echo "Deleted local snapshot '$2'"
    ;;
  *) exit 64 ;;
esac
"""

FAKE_MBX = """#!/bin/sh
state='{state}'
printf '%s\\n' "$*" >> "$state/mbx.calls"
case "$*" in
  gc)
    size=$(cat "$state/gc-frees" 2>/dev/null || echo 0)
    echo $(( $(cat "$state/free") + size )) > "$state/free"
    echo "mbx[gc]: removed 3 target directories"
    ;;
  "gc --dry-run") echo "mbx[gc]: would remove 3 target directories" ;;
  "cache stats --json") printf '{{\\n  "version": 1,\\n  "combined_total_bytes": 79512091604\\n}}\\n' ;;
  *) exit 64 ;;
esac
"""

FAKE_OSASCRIPT = """#!/bin/sh
state='{state}'
for argument in "$@"; do printf '%s\\n' "$argument"; done >> "$state/osascript.calls"
echo "--" >> "$state/osascript.calls"
"""


class FreeSpaceGuardTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = root = Path(temporary.name)
        self.state = root / "fake"
        self.state.mkdir()
        self.home = root / "home"
        self.home.mkdir()
        self.guard_state = root / "guard-state"
        fakes = {}
        for name, body in (("df", FAKE_DF), ("tmutil", FAKE_TMUTIL),
                           ("mbx", FAKE_MBX), ("osascript", FAKE_OSASCRIPT)):
            path = root / "fakes" / name
            path.parent.mkdir(exist_ok=True)
            path.write_text(body.format(state=self.state))
            path.chmod(0o755)
            fakes[name] = path
        self.mbx = fakes["mbx"]
        self.env = {
            "HOME": str(self.home),
            "PATH": "/usr/bin:/bin",
            "FREE_SPACE_GUARD_DF": str(fakes["df"]),
            "FREE_SPACE_GUARD_TMUTIL": str(fakes["tmutil"]),
            "FREE_SPACE_GUARD_OSASCRIPT": str(fakes["osascript"]),
        }
        self.set_free(500)
        self.set_snapshots([])

    def set_free(self, gib):
        (self.state / "free").write_text(f"{gib * GIB}\n")

    def free(self):
        return int((self.state / "free").read_text()) / GIB

    def set_snapshots(self, names, sizes=None):
        (self.state / "snapshots").write_text("".join(f"{n}\n" for n in names))
        for date, gib in (sizes or {}).items():
            (self.state / f"size-{date}").write_text(f"{gib * GIB}\n")

    def calls(self, name):
        path = self.state / f"{name}.calls"
        return path.read_text().splitlines() if path.exists() else []

    def deletions(self):
        return [c.split(" ", 1)[1] for c in self.calls("tmutil")
                if c.startswith("deletelocalsnapshots")]

    def notifications(self):
        text = "\n".join(self.calls("osascript"))
        return [call.strip("\n").splitlines() for call in text.split("--") if call.strip()]

    def run_guard(self, *args, mbx=True):
        command = ["/bin/sh", str(GUARD), "--settle", "0",
                   "--state-dir", str(self.guard_state)]
        if mbx:
            command += ["--mbx", str(self.mbx)]
        for name in ("FREE_SPACE_GUARD_DF", "FREE_SPACE_GUARD_TMUTIL", "FREE_SPACE_GUARD_OSASCRIPT"):
            self.assertTrue(self.env[name].startswith(str(self.root)), name)
        return subprocess.run(command + list(args), env=self.env, text=True,
                              capture_output=True, timeout=60)

    @staticmethod
    def tm(date):
        return f"com.apple.TimeMachine.{date}.local"

    def test_does_nothing_at_or_above_the_threshold(self):
        self.set_free(120)
        self.set_snapshots([self.tm("2026-11-11-100000")], {"2026-11-11-100000": 5})
        result = self.run_guard()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, "")
        self.assertEqual(self.calls("tmutil"), [])
        self.assertEqual(self.calls("mbx"), [])
        self.assertFalse(self.guard_state.exists())

    def test_thins_oldest_first_and_stops_at_the_threshold(self):
        self.set_free(110)
        dates = ["2026-11-11-100000", "2026-11-11-110000",
                 "2026-11-11-120000", "2026-11-11-130000"]
        # Listed newest first, to show the guard sorts them itself.
        self.set_snapshots([self.tm(d) for d in reversed(dates)],
                           {d: 5 for d in dates})
        result = self.run_guard()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.deletions(), dates[:2])
        self.assertEqual(self.calls("mbx"), [])
        self.assertEqual(self.free(), 120)
        self.assertIn("deleted local snapshot com.apple.TimeMachine.2026-11-11-100000.local",
                      result.stdout)

    def test_keeps_the_newest_snapshot_above_the_floor_and_runs_gc(self):
        self.set_free(105)
        dates = ["2026-11-11-100000", "2026-11-11-110000", "2026-11-11-120000"]
        self.set_snapshots([self.tm(d) for d in dates], {d: 1 for d in dates})
        (self.state / "gc-frees").write_text(f"{20 * GIB}\n")
        result = self.run_guard()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.deletions(), dates[:2])
        self.assertEqual(self.calls("mbx"), ["gc"])
        self.assertEqual(self.notifications(), [])
        self.assertIn(self.tm(dates[2]), (self.state / "snapshots").read_text())

    def test_the_floor_takes_the_newest_snapshot_before_gc_then_notifies(self):
        self.set_free(90)
        dates = ["2026-11-11-100000", "2026-11-11-110000"]
        self.set_snapshots([self.tm(d) for d in dates], {dates[0]: 1, dates[1]: 5})
        (self.state / "gc-frees").write_text(f"{2 * GIB}\n")
        log = self.home / "Library/Logs/free-space-guard.log"
        log.parent.mkdir(parents=True)
        result = self.run_guard("--log", str(log))
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(self.deletions(), dates)
        mbx_calls = [c for c in self.calls("mbx") if c == "gc"]
        self.assertEqual(mbx_calls, ["gc"])
        self.assertEqual(self.free(), 98)
        notifications = self.notifications()
        self.assertEqual(len(notifications), 1)
        title, message = notifications[0][-2:]
        self.assertEqual(title, "Disk under 100 GiB free")
        self.assertIn("98 GiB writable, under the 100 GiB floor", message)
        self.assertIn("removing 2 local snapshots and running mbx gc", message)
        self.assertIn("/System/Volumes/Data 2.6 TiB, /nix 300 GiB, / 12 GiB", message)
        self.assertIn("mbx cache 74 GiB", message)
        self.assertIn("Details: ~/Library/Logs/free-space-guard.log", message)
        self.assertNotIn(str(self.home), message)
        self.assertNotIn("Other Disk", message)
        self.assertEqual(result.stdout, "")
        self.assertIn("running", log.read_text())

    def test_only_time_machine_snapshots_are_ever_deleted(self):
        self.set_free(10)
        valid = ["2026-11-10-090000", "2026-11-11-100000"]
        self.set_snapshots([
            "com.apple.os.update-182F06D70C9D02A9A9077E3BC880E61B",
            "com.apple.os.update-MSUPrepareUpdate",
            self.tm(valid[1]),
            "com.apple.TimeMachine.2026-11-11-100000.local.extra",
            "com.apple.TimeMachine.latest.local",
            " com.apple.TimeMachine.2026-11-09-080000.local",
            "com.apple.TimeMachine.2026-11-08-0700.local",
            "/System/Volumes/Data",
            self.tm(valid[0]),
        ])
        result = self.run_guard()
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(self.deletions(), valid)
        remaining = (self.state / "snapshots").read_text()
        self.assertIn("com.apple.os.update-MSUPrepareUpdate", remaining)
        self.assertIn("/System/Volumes/Data", remaining)

    def test_dry_run_changes_nothing(self):
        self.set_free(50)
        dates = ["2026-11-11-100000", "2026-11-11-110000"]
        self.set_snapshots([self.tm(d) for d in dates], {d: 30 for d in dates})
        result = self.run_guard("--dry-run")
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(self.deletions(), [])
        self.assertNotIn("gc", self.calls("mbx"))
        self.assertIn("gc --dry-run", self.calls("mbx"))
        self.assertEqual(self.notifications(), [])
        self.assertFalse(self.guard_state.exists())
        self.assertEqual(self.free(), 50)
        out = result.stdout
        self.assertIn("would delete local snapshot com.apple.TimeMachine.2026-11-11-100000.local", out)
        self.assertIn("would delete local snapshot com.apple.TimeMachine.2026-11-11-110000.local", out)
        self.assertIn("would remove 2 local snapshots; nothing changed", out)
        self.assertIn("would notify", out)

    def test_dry_run_reports_when_nothing_is_needed(self):
        self.set_free(700)
        result = self.run_guard("--dry-run")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("700 GiB writable on /System/Volumes/Data, not under 120 GiB", result.stdout)

    def test_notifications_wait_out_the_interval(self):
        self.set_free(50)
        self.assertEqual(self.run_guard().returncode, 1)
        second = self.run_guard()
        self.assertEqual(second.returncode, 1)
        self.assertIn("last notified 0 minutes ago", second.stdout)
        self.assertEqual(len(self.notifications()), 1)
        self.run_guard("--notify-every", "0")
        self.assertEqual(len(self.notifications()), 2)

    def test_a_failed_deletion_is_logged_and_the_next_one_tried(self):
        self.set_free(100)
        dates = ["2026-11-11-100000", "2026-11-11-110000", "2026-11-11-120000"]
        self.set_snapshots([self.tm(d) for d in dates], {d: 10 for d in dates})
        (self.state / f"fail-{dates[0]}").write_text("")
        result = self.run_guard(mbx=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.deletions(), dates[:2])
        self.assertIn("could not delete local snapshot "
                      "com.apple.TimeMachine.2026-11-11-100000.local: "
                      "Failed to delete local snapshot", result.stdout)
        self.assertIn("after removing 1 local snapshots (1 failed); 2 left", result.stdout)

    def test_without_mbx_gc_is_skipped(self):
        self.set_free(80)
        result = self.run_guard(mbx=False)
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(self.calls("mbx"), [])
        message = self.notifications()[0][-1]
        self.assertIn("after removing 0 local snapshots.", message)
        self.assertNotIn("mbx", message)

    def test_a_live_lock_holder_is_left_alone_and_a_stale_lock_is_taken(self):
        self.set_free(50)
        lock = self.guard_state / "lock"
        lock.mkdir(parents=True)
        (lock / "pid").write_text(f"{os.getpid()}\n")
        result = self.run_guard()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn(f"another run (pid {os.getpid()}) is in progress", result.stdout)
        self.assertEqual(self.calls("mbx"), [])
        finished = subprocess.run(["/bin/sh", "-c", "echo $$"], text=True,
                                  capture_output=True).stdout.strip()
        (lock / "pid").write_text(f"{finished}\n")
        result = self.run_guard()
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual(self.calls("mbx"), ["gc", "cache stats --json"])
        self.assertFalse(lock.exists())

    def test_usage_errors(self):
        for args in (["--floor", "130"], ["--floor", "ten"], ["--bogus"], ["--volume"]):
            with self.subTest(args=args):
                result = self.run_guard(*args)
                self.assertEqual(result.returncode, 2)
                self.assertIn("usage: free-space-guard", result.stderr)
        self.assertEqual(self.calls("tmutil"), [])

    def test_an_unmeasurable_volume_is_an_error(self):
        (self.state / "df.fail").write_text("")
        result = self.run_guard()
        self.assertEqual(result.returncode, 2)
        self.assertIn("could not measure writable space", result.stdout)
        self.assertEqual(self.calls("tmutil"), [])


@unittest.skipUnless(platform.system() == "Darwin", "macOS's /bin/sh is bash 3.2")
class FreeSpaceGuardSyntaxTests(unittest.TestCase):
    def test_parses_with_the_system_shell(self):
        subprocess.run(["/bin/sh", "-n", str(GUARD)], check=True)


if __name__ == "__main__":
    unittest.main()
