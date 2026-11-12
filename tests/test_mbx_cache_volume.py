"""Run mbx-cache-volume against fake diskutil, tmutil, mdutil, sudo, ps and mbx.

Every system command comes from MBX_CACHE_VOLUME_* or --mbx and points at a
fake in a temporary directory; the fake sudo runs commands as the caller, and
the "volumes" are directories there. No test reaches a real disk, Time Machine
setting, Spotlight index or mbx cache.
"""

import hashlib
import json
import os
from pathlib import Path
import platform
import stat
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "mbx-cache-volume"
GIB = 1073741824
NAME = "BuildCacheTest"

FAKE_DISKUTIL = """#!{python}
import json, os, plistlib, sys
from pathlib import Path

state_dir = Path({state!r})
with (state_dir / "diskutil.calls").open("a") as calls:
    calls.write(" ".join(sys.argv[1:]) + "\\n")
path = state_dir / "diskutil.json"
state = json.loads(path.read_text())
args = sys.argv[1:]

def find(key):
    for container in state["containers"]:
        for volume in container["volumes"]:
            if key in (volume["device"], volume.get("mount")):
                return container, volume
    return None, None

def save():
    path.write_text(json.dumps(state))

def mount(volume):
    point = Path(state["volumes_root"]) / volume["name"]
    point.mkdir(parents=True, exist_ok=True)
    volume["mount"] = str(point)

if args[:2] == ["info", "-plist"]:
    container, volume = find(args[2])
    if volume is None:
        sys.exit(1)
    sys.stdout.buffer.write(plistlib.dumps({{
        "APFSContainerReference": container["ref"],
        "DeviceIdentifier": volume["device"],
        "GlobalPermissionsEnabled": volume["owners"],
        "MountPoint": volume.get("mount") or "",
        "VolumeName": volume["name"],
        "VolumeUUID": volume["uuid"],
    }}))
elif args == ["apfs", "list", "-plist"]:
    sys.stdout.buffer.write(plistlib.dumps({{"Containers": [{{
        "ContainerReference": container["ref"],
        "Volumes": [{{
            "DeviceIdentifier": volume["device"],
            "Name": volume["name"],
            "CapacityQuota": volume["quota"],
        }} for volume in container["volumes"]],
    }} for container in state["containers"]]}}))
elif args[:2] == ["apfs", "addVolume"]:
    reference, name = args[2], args[4]
    quota = int(args[args.index("-quota") + 1])
    container = next(c for c in state["containers"] if c["ref"] == reference)
    volume = {{
        "device": "%ss%d" % (reference, 20 + len(container["volumes"])),
        "name": name, "quota": quota, "owners": state.get("new_owners", True),
        "uuid": "0C0FFEE0-0000-4000-8000-000000000001",
    }}
    container["volumes"].append(volume)
    mount(volume)
    save()
    print("Created new APFS Volume " + volume["device"])
elif args[0] == "mount":
    container, volume = find(args[1])
    mount(volume)
    save()
elif args[0] == "enableOwnership":
    container, volume = find(args[1])
    volume["owners"] = True
    save()
else:
    sys.exit(64)
"""

FAKE_TMUTIL = """#!/bin/sh
state='{state}'
printf '%s\\n' "$*" >> "$state/tmutil.calls"
case $1 in
  isexcluded)
    if grep -qxF "$2" "$state/excluded" 2>/dev/null; then
      echo "[Excluded]    $2"
    else
      echo "[Included]    $2"
    fi
    ;;
  addexclusion)
    [ "$2" = -v ] || exit 64
    if [ -e "$state/tmutil.denied" ]; then
      echo "tmutil: addexclusion requires Full Disk Access privileges." >&2
      exit 1
    fi
    printf '%s\\n' "$3" >> "$state/excluded"
    ;;
  *) exit 64 ;;
esac
"""

FAKE_MDUTIL = """#!/bin/sh
state='{state}'
printf '%s\\n' "$*" >> "$state/mdutil.calls"
case $1 in
  -s)
    printf '%s:\\n' "$2"
    if grep -qxF "$2" "$state/unindexed" 2>/dev/null; then
      printf '\\tIndexing disabled.\\n'
    else
      printf '\\tIndexing enabled.\\n'
    fi
    ;;
  -i)
    [ "$2" = off ] || exit 64
    printf '%s\\n' "$3" >> "$state/unindexed"
    printf '%s:\\n\\tIndexing disabled.\\n' "$3"
    ;;
  *) exit 64 ;;
esac
"""

FAKE_SUDO = """#!/bin/sh
printf '%s\\n' "$*" >> '{state}/sudo.calls'
exec "$@"
"""

FAKE_PS = """#!/bin/sh
case "$*" in
  *comm=*) cat '{state}/ps.comm' 2>/dev/null ;;
  *) cat '{state}/ps.args' 2>/dev/null ;;
esac
exit 0
"""

FAKE_MBX = """#!/bin/sh
state='{state}'
printf '%s\\n' "$*" >> "$state/mbx.calls"
case "$1 $2" in
  "cache dir")
    dir=$(cat "$state/setting.cache_dir" 2>/dev/null)
    printf '%s/actions\\n' "${{dir:-$HOME/Library/Caches/mbx}}"
    ;;
  "cache stats") printf '{{\\n  "combined_total_bytes": 79512091604\\n}}\\n' ;;
  "settings get") cat "$state/setting.$3" 2>/dev/null; echo ;;
  "settings set") printf '%s' "$4" > "$state/setting.$3" ;;
  *) exit 64 ;;
esac
"""


@unittest.skipUnless(platform.system() == "Darwin", "mbx-cache-volume runs only on macOS")
class MbxCacheVolumeTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.state = self.root / "fake"
        self.state.mkdir()
        self.home = self.root / "home"
        self.volumes = self.root / "Volumes"
        self.old_cache = self.home / "Library/Caches/mbx"
        (self.old_cache / "actions").mkdir(parents=True)
        (self.old_cache / "actions/object").write_text("cached")
        (self.old_cache / "shims").mkdir()
        (self.old_cache / "shims/.mbx-shims").write_text("")
        locked = self.old_cache / "targets/v1/locked"
        locked.mkdir(parents=True)
        (locked / "output").write_text("built")
        (locked / "output").chmod(0o444)
        locked.chmod(0o555)
        self.addCleanup(lambda: locked.exists() and locked.chmod(0o755))
        self.write_disks([{"ref": "disk3", "volumes": [self.volume("disk3s5", "Data", "/System/Volumes/Data")]},
                          {"ref": "disk1", "volumes": [self.volume("disk1s1", "iSCPreboot", None)]}])
        bodies = {"diskutil": FAKE_DISKUTIL, "tmutil": FAKE_TMUTIL, "mdutil": FAKE_MDUTIL,
                  "sudo": FAKE_SUDO, "ps": FAKE_PS, "mbx": FAKE_MBX}
        fakes = {}
        for name, body in bodies.items():
            path = self.root / "fakes" / name
            path.parent.mkdir(exist_ok=True)
            path.write_text(body.format(state=str(self.state), python=sys.executable))
            path.chmod(0o755)
            fakes[name] = path
        self.mbx = fakes["mbx"]
        self.env = {
            "HOME": str(self.home),
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            "TMPDIR": str(self.root),
            "MBX_CACHE_VOLUME_DISKUTIL": str(fakes["diskutil"]),
            "MBX_CACHE_VOLUME_TMUTIL": str(fakes["tmutil"]),
            "MBX_CACHE_VOLUME_MDUTIL": str(fakes["mdutil"]),
            "MBX_CACHE_VOLUME_SUDO": str(fakes["sudo"]),
            "MBX_CACHE_VOLUME_PS": str(fakes["ps"]),
        }
        self.mount = self.volumes / NAME
        self.dir = self.mount / "mbx"
        self.previous_file = self.home / ".local/state/mbx-cache-volume/previous-cache"
        self.make_checkouts()

    @staticmethod
    def digest(text):
        return hashlib.sha256(text.encode()).hexdigest()

    def make_checkouts(self):
        """Checkouts with every kind of target. Three are mbx's links into the
        old cache, named by each kind of record mbx keeps, and must go; the
        others must stay."""
        views = self.old_cache / "targets/v1"
        checkouts = self.root / "checkouts"
        self.checkout = {name: checkouts / name for name in (
            "recorded", "dangling", "probed", "own-link", "real-dir", "odd-name", "moved")}
        for path in self.checkout.values():
            path.mkdir(parents=True)
        recorded = self.digest("recorded")
        (views / recorded).mkdir()
        (views / f"{recorded}.json").write_text(json.dumps(
            {"version": 1, "workspace_root": str(self.checkout["recorded"]), "updated_secs": 1}))
        (self.checkout["recorded"] / "target").symlink_to(views / recorded)
        for name in ("dangling", "probed"):
            (self.checkout[name] / "target").symlink_to(views / self.digest(name))
        (self.checkout["own-link"] / "target").symlink_to(self.root / "elsewhere")
        (self.checkout["real-dir"] / "target").mkdir()
        (self.checkout["real-dir"] / "target/output").write_text("built")
        (self.checkout["odd-name"] / "target").symlink_to(views / "not-a-digest")
        (self.checkout["moved"] / "target").symlink_to(
            self.dir / "targets/v1" / self.digest("moved"))

        def record(path, workspace):
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(json.dumps({"version": 1, "workspace_root": str(workspace),
                                        "target_dir": str(workspace / "target")}))
        store = self.old_cache / "actions/checkouts/v1"
        for name in ("dangling", "own-link", "real-dir", "odd-name", "moved"):
            record(store / self.digest(name)[:8] / f"{self.digest(name)}.json", self.checkout[name])
        record(store / "deleted/record.json", checkouts / "deleted")
        (store / "deleted/broken.json").write_text("{not json")
        record(self.old_cache / "cargo-roots/v1" / f"{self.digest('probed')}.json", self.checkout["probed"])
        self.stale = ["recorded", "dangling", "probed"]

    def links_left(self):
        return {name: os.path.islink(path / "target") for name, path in self.checkout.items()}

    @staticmethod
    def volume(device, name, mount, quota=0, owners=True):
        return {"device": device, "name": name, "mount": mount, "quota": quota,
                "owners": owners, "uuid": "UUID-" + device}

    def write_disks(self, containers):
        (self.state / "diskutil.json").write_text(json.dumps(
            {"containers": containers, "volumes_root": str(self.volumes)}))

    def disks(self):
        return json.loads((self.state / "diskutil.json").read_text())

    def calls(self, name):
        path = self.state / f"{name}.calls"
        return path.read_text().splitlines() if path.exists() else []

    def clear_calls(self):
        for path in self.state.glob("*.calls"):
            path.unlink()

    def setting(self, name):
        path = self.state / f"setting.{name}"
        return path.read_text() if path.exists() else None

    def run_script(self, *args, env=None):
        for name, value in self.env.items():
            if name.startswith("MBX_CACHE_VOLUME_"):
                self.assertTrue(value.startswith(str(self.root)), name)
        return subprocess.run(["/bin/sh", str(SCRIPT), "--name", NAME, "--mbx", str(self.mbx), *args],
                              env=env or self.env, text=True, capture_output=True, timeout=300)

    def mutating_calls(self):
        return ([c for c in self.calls("diskutil") if not c.startswith(("info", "apfs list"))]
                + [c for c in self.calls("tmutil") if not c.startswith("isexcluded")]
                + [c for c in self.calls("mdutil") if not c.startswith("-s")]
                + self.calls("sudo")
                + [c for c in self.calls("mbx") if c.startswith("settings set")])

    def test_dry_run_plans_every_step_and_changes_nothing(self):
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        out = result.stdout
        for line in (
            f"would run: sudo diskutil apfs addVolume disk3 APFS {NAME} -quota 429496729600  (400 GiB)",
            f"would run: sudo tmutil addexclusion -v /Volumes/{NAME}",
            f"would run: sudo mdutil -i off /Volumes/{NAME}",
            f"would run: sudo install -d -m 700 -o {self.user()} -g {self.group()} /Volumes/{NAME}/mbx",
            f"would run: mbx settings set cache_dir /Volumes/{NAME}/mbx",
            f"previous cache: {self.old_cache} (74 GiB by mbx's count)",
            f"would run: rm -rf {self.old_cache}, once mbx uses /Volumes/{NAME}/mbx and nothing uses {self.old_cache}",
            f"target links: 3 checkouts link into {self.old_cache}; each gets a new link on its next build",
            f"would remove the link {self.checkout['recorded']}/target",
            f"would remove the link {self.checkout['dangling']}/target",
            f"would remove the link {self.checkout['probed']}/target",
            "note: BuildCacheTest gets no FileVault password",
            "Nothing changed.",
        ):
            self.assertIn(line, out)
        for name in ("own-link", "real-dir", "odd-name", "moved"):
            self.assertNotIn(str(self.checkout[name]), out)
        self.assertTrue(all(self.links_left()[name] for name in self.stale))
        self.assertEqual(self.mutating_calls(), [])
        self.assertTrue((self.old_cache / "actions/object").exists())
        self.assertFalse(self.volumes.exists())
        self.assertFalse(self.previous_file.parent.exists())
        self.assertNotIn("atime:", out)

    @staticmethod
    def user():
        return subprocess.run(["id", "-un"], text=True, capture_output=True).stdout.strip()

    @staticmethod
    def group():
        return subprocess.run(["id", "-gn"], text=True, capture_output=True).stdout.strip()

    def test_apply_moves_the_cache_and_deletes_the_old_one(self):
        result = self.run_script("--apply")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        volume = next(v for v in self.disks()["containers"][0]["volumes"] if v["name"] == NAME)
        self.assertEqual(volume["quota"], 400 * GIB)
        self.assertEqual(volume["mount"], str(self.mount))
        self.assertEqual((self.state / "excluded").read_text().splitlines(), [str(self.mount)])
        self.assertEqual((self.state / "unindexed").read_text().splitlines(), [str(self.mount)])
        mode = self.dir.stat()
        self.assertEqual(stat.S_IMODE(mode.st_mode), 0o700)
        self.assertEqual(mode.st_uid, os.getuid())
        self.assertEqual(self.setting("cache_dir"), str(self.dir))
        self.assertFalse(self.old_cache.exists())
        self.assertFalse(self.previous_file.exists())
        self.assertEqual(self.links_left(), {
            "recorded": False, "dangling": False, "probed": False, "own-link": True,
            "real-dir": False, "odd-name": True, "moved": True})
        self.assertEqual(os.readlink(self.checkout["own-link"] / "target"), str(self.root / "elsewhere"))
        self.assertEqual((self.checkout["real-dir"] / "target/output").read_text(), "built")
        for name in self.stale:
            self.assertIn(f"removed the link {self.checkout[name]}/target", result.stdout)
        self.assertIn(f"running: mv {self.old_cache} {self.old_cache}.mbx-cache-volume-deleting", result.stdout)
        self.assertEqual(list(self.old_cache.parent.iterdir()), [])
        sudo = self.calls("sudo")
        self.assertEqual([c.split(" ", 1)[0].rsplit("/", 1)[-1] for c in sudo],
                         ["diskutil", "tmutil", "mdutil", "install"])
        self.assertIn("atime: reads on", result.stdout)
        self.assertIn(f"done: mbx's cache is {self.dir}", result.stdout)

    def test_a_second_apply_changes_nothing(self):
        self.assertEqual(self.run_script("--apply").returncode, 0)
        self.clear_calls()
        result = self.run_script("--apply")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(self.mutating_calls(), [])
        for line in ("ok: quota 400 GiB", "ok: ownership enabled", f"ok: Time Machine excludes {self.mount}",
                     f"ok: Spotlight does not index {self.mount}", f"ok: {self.dir} exists",
                     f"ok: mbx uses {self.dir}"):
            self.assertIn(line, result.stdout)
        dry = self.run_script()
        self.assertEqual(dry.returncode, 0)
        self.assertNotIn("would run", dry.stdout)

    def test_the_cache_moves_only_while_nothing_uses_it(self):
        (self.state / "ps.comm").write_text(
            "  123 /nix/store/abc-mbx-1.29.2/bin/mbx\n"
            "  124 /Applications/Some App.app/Contents/MacOS/Some App\n"
            f"  456 {self.old_cache}/targets/v1/{self.digest('recorded')}/debug/server\n")
        (self.state / "ps.args").write_text(
            f"  456 {self.old_cache}/targets/v1/{self.digest('recorded')}/debug/server --port 1\n"
            f"  789 /usr/bin/cargo build --target-dir {self.home}/elsewhere\n")
        result = self.run_script("--apply")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("in use by 123 mbx, 456 server, so the cache stays where it is", result.stdout)
        self.assertIsNone(self.setting("cache_dir"))
        self.assertFalse(self.previous_file.exists())
        self.assertTrue((self.old_cache / "actions/object").exists())
        self.assertTrue(all(self.links_left()[name] for name in self.stale))
        dry = self.run_script()
        self.assertIn("note: in use now by 123 mbx, 456 server; --apply moves the cache only once", dry.stdout)
        (self.state / "ps.comm").unlink()
        (self.state / "ps.args").unlink()
        result = self.run_script("--apply")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(self.old_cache.exists())
        self.assertFalse(self.previous_file.exists())
        self.assertFalse(any(self.links_left()[name] for name in self.stale))

    def test_a_cache_in_use_after_the_move_waits_for_the_next_run(self):
        self.assertEqual(self.run_script("--apply", "--keep-old-cache").returncode, 0)
        self.assertTrue(self.old_cache.exists())
        (self.state / "ps.args").write_text(f"  456 {self.old_cache}/shims/rust/rustc --crate-name demo\n")
        result = self.run_script("--apply")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn(f"previous cache: {self.old_cache} stays for now: it is in use by 456", result.stdout)
        self.assertTrue((self.old_cache / "actions/object").exists())
        (self.state / "ps.args").unlink()
        result = self.run_script("--apply")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(self.old_cache.exists())

    def test_a_failed_exclusion_stops_before_mbx_moves(self):
        (self.state / "tmutil.denied").write_text("")
        result = self.run_script("--apply")
        self.assertEqual(result.returncode, 1)
        self.assertIn("Full Disk Access", result.stderr)
        self.assertIsNone(self.setting("cache_dir"))
        self.assertTrue((self.old_cache / "actions/object").exists())
        (self.state / "tmutil.denied").unlink()
        self.clear_calls()
        result = self.run_script("--apply")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(any("addVolume" in c for c in self.calls("diskutil")))
        self.assertEqual(self.setting("cache_dir"), str(self.dir))
        self.assertFalse(self.old_cache.exists())

    def test_an_existing_volume_is_mounted_and_owned_but_its_quota_kept(self):
        self.write_disks([{"ref": "disk3", "volumes": [
            self.volume("disk3s5", "Data", "/System/Volumes/Data"),
            self.volume("disk3s9", NAME, None, quota=200 * GIB, owners=False)]}])
        result = self.run_script("--apply", "--keep-old-cache")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("its quota is 200 GiB, not 400 GiB", result.stdout)
        self.assertEqual([c.split(" ", 1)[1] for c in self.calls("sudo")[:2]],
                         ["mount disk3s9", "enableOwnership disk3s9"])
        self.assertFalse(any("addVolume" in c for c in self.calls("diskutil")))
        self.assertIn(f"previous cache: kept at {self.old_cache} (--keep-old-cache); run this again without it", result.stdout)
        self.assertTrue((self.old_cache / "actions/object").exists())
        self.assertFalse(any(self.links_left()[name] for name in self.stale))

    def test_a_previous_cache_that_is_not_an_mbx_cache_stays(self):
        self.assertEqual(self.run_script("--apply").returncode, 0)
        for previous, message in ((self.home, "does not look like an mbx cache, so it stays"),
                                  (self.root / "not-a-cache", "does not look like an mbx cache, so it stays"),
                                  (self.mount, "is the new one, so nothing is removed")):
            with self.subTest(previous=previous):
                previous.mkdir(exist_ok=True)
                (previous / "keep").write_text("mine")
                self.previous_file.parent.mkdir(parents=True, exist_ok=True)
                self.previous_file.write_text(f"{previous}\n")
                result = self.run_script("--apply")
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn(message, result.stdout)
                self.assertEqual((previous / "keep").read_text(), "mine")
                self.assertFalse(self.previous_file.exists())

    def test_a_deletion_that_stopped_partway_finishes_on_the_next_run(self):
        self.assertEqual(self.run_script("--apply", "--keep-old-cache").returncode, 0)
        doomed = Path(f"{self.old_cache}.mbx-cache-volume-deleting")
        self.old_cache.rename(doomed)
        for leftover in ("actions", "shims"):
            subprocess.run(["rm", "-rf", str(doomed / leftover)], check=True)
        self.previous_file.write_text(f"{doomed}\n")
        self.clear_calls()
        result = self.run_script("--apply")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(doomed.exists())
        self.assertFalse(self.previous_file.exists())

    def test_a_run_stopped_between_moving_aside_and_recording_it_is_finished(self):
        self.assertEqual(self.run_script("--apply", "--keep-old-cache").returncode, 0)
        self.assertEqual(self.previous_file.read_text().strip(), str(self.old_cache))
        doomed = Path(f"{self.old_cache}.mbx-cache-volume-deleting")
        self.old_cache.rename(doomed)
        result = self.run_script("--apply")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertFalse(doomed.exists())
        self.assertFalse(self.previous_file.exists())

    def test_a_pending_earlier_cache_is_not_forgotten(self):
        earlier = self.root / "earlier-cache"
        (earlier / "actions").mkdir(parents=True)
        self.previous_file.parent.mkdir(parents=True)
        self.previous_file.write_text(f"{earlier}\n")
        for args in ((), ("--apply",)):
            with self.subTest(args=args):
                result = self.run_script(*args)
                self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                self.assertIn(f"names {earlier}, a cache an earlier run moved away from", result.stderr)
        self.assertIsNone(self.setting("cache_dir"))
        self.assertEqual(self.previous_file.read_text().strip(), str(earlier))
        self.assertTrue((earlier / "actions").is_dir())
        self.assertTrue(all(self.links_left()[name] for name in self.stale))

    def test_the_new_cache_is_never_removed_as_the_previous_one(self):
        self.assertEqual(self.run_script("--apply").returncode, 0)
        new_link = self.checkout["moved"] / "target"
        self.previous_file.parent.mkdir(parents=True, exist_ok=True)
        self.previous_file.write_text(f"{self.dir}\n")
        result = self.run_script("--apply")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn(f"previous cache: {self.dir} is the new one, so nothing is removed", result.stdout)
        self.assertTrue(self.dir.is_dir())
        self.assertTrue(new_link.is_symlink())
        self.assertFalse(self.previous_file.exists())

    def test_a_tight_quota_is_noted(self):
        (self.state / "setting.gc.max_total_size").write_text("350GiB")
        (self.state / "setting.gc.min_free_size").write_text("100GiB")
        result = self.run_script()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("gc.max_total_size 350GiB, gc.min_free_size 100GiB", result.stdout)
        self.assertIn("with a 400 GiB quota it collects once the volume holds 300 GiB", result.stdout)
        result = self.run_script("--quota", "500")
        self.assertNotIn("note: mbx keeps", result.stdout)

    def test_refusals_change_nothing(self):
        (self.state / "setting.target.root").write_text("/Volumes/Elsewhere/targets")
        cases = {
            "an absolute target.root": ([], self.env, "target.root is /Volumes/Elsewhere/targets"),
            "MBX_CACHE_DIR": ([], {**self.env, "MBX_CACHE_DIR": "/tmp/x"}, "MBX_CACHE_DIR is set"),
            "a bad quota": (["--quota", "0"], self.env, "--quota needs a whole number"),
            "a bad name": (["--name", "Build Cache"], self.env, "--name takes letters"),
            "an unknown flag": (["--force"], self.env, "unknown argument"),
        }
        for label, (args, env, message) in cases.items():
            with self.subTest(label):
                result = self.run_script("--apply", *args, env=env)
                self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
                self.assertIn(message, result.stderr)
        (self.state / "setting.target.root").unlink()
        self.write_disks([
            {"ref": "disk3", "volumes": [self.volume("disk3s5", "Data", "/System/Volumes/Data")]},
            {"ref": "disk7", "volumes": [self.volume("disk7s1", NAME, "/Volumes/External")]}])
        result = self.run_script("--apply")
        self.assertEqual(result.returncode, 2)
        self.assertIn(f"a volume named {NAME} already exists in disk7", result.stderr)
        self.assertEqual(self.mutating_calls(), [])
        self.assertTrue((self.old_cache / "actions/object").exists())


@unittest.skipUnless(platform.system() == "Darwin", "macOS's /bin/sh is bash 3.2")
class MbxCacheVolumeSyntaxTests(unittest.TestCase):
    def test_parses_with_the_system_shell(self):
        subprocess.run(["/bin/sh", "-n", str(SCRIPT)], check=True)


if __name__ == "__main__":
    unittest.main()
