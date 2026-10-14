from pathlib import Path
import subprocess
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "scripts/check-config-home"


class ConfigRootTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.home = self.root / "home with spaces"
        self.home.mkdir()
        self.repo = self.home / "dotfiles"
        self.repo.mkdir()
        self.config = self.home / ".config"

    def check(self, expected, config=None):
        result = subprocess.run(
            ["bash", str(SCRIPT), str(config or self.config), str(self.repo)],
            text=True, capture_output=True,
        )
        self.assertEqual(result.returncode, expected, result.stderr)
        if expected:
            self.assertIn("config-root:", result.stderr)
        else:
            self.assertEqual(result.stdout + result.stderr, "")

    def test_missing_root_is_allowed_without_creating_it(self):
        self.check(0)
        self.assertFalse(self.config.exists())

    def test_real_root_and_individual_app_links_are_allowed(self):
        self.config.mkdir()
        (self.config / "editor").symlink_to(self.repo)
        self.check(0)

    def test_config_root_symlink_is_rejected(self):
        self.config.symlink_to(self.repo)
        self.check(1)

    def test_dangling_symlink_is_rejected(self):
        self.config.symlink_to(self.home / "missing")
        self.check(1)

    def test_trailing_slash_does_not_hide_symlink(self):
        self.config.symlink_to(self.repo)
        self.check(1, str(self.config) + "/")

    def test_parent_traversal_is_rejected(self):
        self.check(1, str(self.home / "missing") + "/../dotfiles/runtime")

    def test_regular_file_is_rejected(self):
        self.config.write_text("do not replace")
        self.check(1)

    def test_directory_inside_checkout_is_rejected(self):
        directory = self.repo / "runtime"
        directory.mkdir()
        self.check(1, directory)

    def test_missing_directory_inside_checkout_is_rejected(self):
        self.check(1, self.repo / "nested" / "runtime")

    def test_symlinked_parent_into_checkout_is_rejected(self):
        alias = self.home / "alias"
        alias.symlink_to(self.repo)
        self.check(1, alias / "runtime")

    def test_similarly_named_sibling_is_allowed(self):
        self.check(0, self.home / "dotfiles-runtime")

    def test_relative_config_root_is_rejected(self):
        self.check(1, Path("relative"))


if __name__ == "__main__":
    unittest.main()
