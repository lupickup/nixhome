import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"


class SshWrapperTests(unittest.TestCase):
    """Runs ssh-vscode-wrapper with a stub resolver and ssh."""

    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        root = Path(self.directory.name)
        self.home = root / "home"
        (self.home / ".ssh").mkdir(parents=True)
        tools = root / "tools"
        tools.mkdir()
        shutil.copy(SCRIPTS / "ssh-vscode-wrapper", tools / "ssh-vscode-wrapper")
        resolver = tools / "resolve-vscode-ssh-sock"
        resolver.write_text('#!/bin/sh\nprintf "%s\\n" /tmp/agent.sock\n')
        resolver.chmod(0o755)
        bin_dir = root / "bin"
        bin_dir.mkdir()
        ssh = bin_dir / "ssh"
        ssh.write_text('#!/bin/sh\nprintf "%s\\n" "$@"\n')
        ssh.chmod(0o755)
        self.wrapper = tools / "ssh-vscode-wrapper"
        self.env = dict(os.environ, HOME=str(self.home),
                        PATH=f"{bin_dir}:/usr/bin:/bin")

    def run_wrapper(self, *args):
        result = subprocess.run(["bash", str(self.wrapper), *args], env=self.env,
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        return result.stdout.splitlines()

    def key(self, name):
        path = self.home / ".ssh" / f"{name}.pub"
        path.write_text("ssh-ed25519 AAAA test\n")
        return str(path)

    def test_alias_forms_select_matching_public_key(self):
        key = self.key("acme")
        for target in ("git@github.com-acme:org/repo.git",
                       "ssh://git@github.com-acme/org/repo.git",
                       "ssh://git@github.com-acme:22/org/repo.git",
                       "github.com-acme"):
            with self.subTest(target=target):
                args = self.run_wrapper(target, "git-upload-pack 'org/repo.git'")
                self.assertEqual(args[:4], ["-o", "IdentityAgent=/tmp/agent.sock",
                                            "-i", key])

    def test_explicit_identity_file_wins(self):
        self.key("acme")
        explicit = self.key("other")
        args = self.run_wrapper("-i", explicit, "git@github.com-acme:org/repo.git")
        self.assertEqual(args[2:4], ["-i", explicit])

    def test_plain_hosts_and_missing_keys_get_no_identity(self):
        for target in ("git@github.com:org/repo.git", "git@github.com-absent:o/r.git"):
            with self.subTest(target=target):
                args = self.run_wrapper(target, "git-upload-pack 'o/r.git'")
                self.assertEqual(args[:2], ["-o", "IdentityAgent=/tmp/agent.sock"])
                self.assertNotIn("-i", args[:3])


class DevBoxSshAddTests(unittest.TestCase):
    def test_requires_a_key_argument(self):
        result = subprocess.run(["bash", str(SCRIPTS / "dev-box-ssh-add")],
                                text=True, capture_output=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("usage: dev-box-ssh-add", result.stderr)


if __name__ == "__main__":
    unittest.main()
