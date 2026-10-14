"""Exercise real SSH signatures without touching the caller's HOME or Git config."""

import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "scripts/git-agent-signing"


class AgentSigningTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.home = Path(self.temporary.name)
        self.env = os.environ.copy()
        for name in list(self.env):
            if name.startswith("GIT_") or name in ("XDG_STATE_HOME", "XDG_CONFIG_HOME"):
                self.env.pop(name)
        self.env.update(HOME=str(self.home), GIT_CONFIG_NOSYSTEM="1",
                        SSH_AUTH_SOCK=str(self.home / "unavailable-agent"))
        self.git("config", "--global", "user.name", "Signing Test")
        self.git("config", "--global", "user.email", "signing@example.test")
        self.git("config", "--global", "gpg.format", "ssh")
        self.git("config", "--global", "gpg.ssh.program", "/nonexistent/op-ssh-sign")
        self.repo = self.home / "target repo"
        self.other = self.home / "other"
        for repo in (self.repo, self.other):
            self.git("init", "--quiet", str(repo))

    def command(self, *args, check=True):
        return subprocess.run(args, env=self.env, text=True, capture_output=True,
                              stdin=subprocess.DEVNULL, timeout=30, check=check)

    def git(self, *args, repo=None, check=True):
        prefix = ["git"] + (["-C", str(repo)] if repo else [])
        return self.command(*prefix, *args, check=check)

    def helper(self, *args, check=True):
        return self.command(str(HELPER), *(str(a) for a in args), check=check)

    def test_init_is_idempotent_and_private(self):
        self.helper("init")
        directory = self.home / ".local/state/git-agent-signing"
        key = directory / "signing-key"
        original = key.read_bytes()
        self.helper("init")
        self.assertEqual(key.read_bytes(), original)
        self.assertEqual(stat.S_IMODE(directory.stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE(key.stat().st_mode), 0o600)
        self.assertNotIn("PRIVATE KEY", self.helper("init").stdout)
        self.assertFalse((self.repo / ".git/git-agent-signing-backup.json").exists())

    def test_commit_and_tag_verify_without_agent_or_global_signer(self):
        self.helper("init")
        global_config = (self.home / ".gitconfig").read_bytes()
        other_config = (self.other / ".git/config").read_bytes()
        self.helper("enable", self.repo)
        self.helper("enable", self.repo)
        self.git("commit", "--allow-empty", "-m", "Signed unattended", repo=self.repo)
        verified = self.git("verify-commit", "HEAD", repo=self.repo)
        self.assertIn("Good", verified.stderr)
        self.assertIn("signing@example.test", verified.stderr)
        self.git("tag", "-m", "Signed tag", "test-tag", repo=self.repo)
        self.assertIn("Good", self.git("verify-tag", "test-tag", repo=self.repo).stderr)
        self.assertEqual((self.home / ".gitconfig").read_bytes(), global_config)
        self.assertEqual((self.other / ".git/config").read_bytes(), other_config)
        self.assertIn("enabled", self.helper("status", self.repo).stdout)

    def test_disable_restores_absent_and_multivalued_local_settings(self):
        self.helper("init")
        self.git("config", "--local", "--add", "gpg.ssh.program", "/first/signer", repo=self.repo)
        self.git("config", "--local", "--add", "gpg.ssh.program", "/second/signer", repo=self.repo)
        before = self.git("config", "--local", "--null", "--list", repo=self.repo).stdout
        self.helper("enable", self.repo)
        self.helper("disable", self.repo)
        after = self.git("config", "--local", "--null", "--list", repo=self.repo).stdout
        self.assertEqual(sorted(before.split("\0")), sorted(after.split("\0")))
        self.assertFalse((self.repo / ".git/git-agent-signing-backup.json").exists())
        self.assertIn("no git-agent-signing", self.helper("status", self.repo).stdout)

    def test_manual_changes_are_preserved(self):
        self.helper("init")
        self.helper("enable", self.repo)
        self.git("config", "--local", "commit.gpgSign", "false", repo=self.repo)
        self.assertNotEqual(self.helper("disable", self.repo, check=False).returncode, 0)
        self.assertNotEqual(self.helper("enable", self.repo, check=False).returncode, 0)
        self.assertEqual(self.git("config", "--local", "commit.gpgSign", repo=self.repo).stdout.strip(), "false")

    def test_enable_requires_init_and_respects_xdg_state_home(self):
        before = (self.repo / ".git/config").read_bytes()
        self.assertNotEqual(self.helper("enable", self.repo, check=False).returncode, 0)
        self.assertEqual((self.repo / ".git/config").read_bytes(), before)
        self.env["XDG_STATE_HOME"] = str(self.home / "custom state")
        self.helper("init")
        self.helper("enable", self.repo)
        key = self.home / "custom state/git-agent-signing/signing-key"
        self.assertEqual(self.git("config", "--local", "user.signingKey", repo=self.repo).stdout.strip(), str(key))
        self.assertFalse((self.home / ".local/state/git-agent-signing").exists())

    def test_init_refuses_mismatched_public_key_and_key_symlinks(self):
        self.helper("init")
        directory = self.home / ".local/state/git-agent-signing"
        public = directory / "signing-key.pub"
        public.write_text("ssh-ed25519 mismatched\n")
        self.assertNotEqual(self.helper("init", check=False).returncode, 0)
        key = directory / "signing-key"
        original = key.read_bytes()
        outside = self.home / "outside-key"
        key.rename(outside)
        key.symlink_to(outside)
        self.assertNotEqual(self.helper("init", check=False).returncode, 0)
        self.assertEqual(outside.read_bytes(), original)


if __name__ == "__main__":
    unittest.main()
