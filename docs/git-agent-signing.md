# Optional unattended Git signing

`scripts/git-agent-signing` creates a dedicated, unencrypted Ed25519 key
outside the checkout. It enables SSH commit and tag signatures only in the
repository you select. The signing wrapper clears `SSH_AUTH_SOCK`, so an
unavailable agent or a global `op-ssh-sign` setting cannot block signing.

```sh
./scripts/git-agent-signing init
./scripts/git-agent-signing enable /path/to/repo
./scripts/git-agent-signing status /path/to/repo
git -C /path/to/repo log -1 --show-signature
```

Run `init` only when you choose to provision this key. It uses
`$XDG_STATE_HOME/git-agent-signing/`, or
`~/.local/state/git-agent-signing/`, with a `0700` directory and `0600` key.
Existing keys are never overwritten. The helper needs Python 3, Git with SSH
signing support, and OpenSSH's `ssh-keygen`. Keep both scripts beside each
other at a stable absolute path after enabling repositories.

`enable` requires an effective Git `user.email`. It records the six affected
local config values in `git-agent-signing-backup.json` inside the common Git
directory, then configures the private key path, SSH format, signing wrapper,
an email-specific allowed-signers file, and automatic commit/tag signing.
The local configuration is shared by a repository's linked worktrees.
Global Git settings and other repositories are untouched.

```sh
./scripts/git-agent-signing disable /path/to/repo
```

`disable` restores the previous local values, leaving inherited global
settings effective again. It refuses if those local signing values changed
after `enable`, so reconcile them with the backup first. Disabling keeps the
key and allowed-signers files for other repositories and future use.

An unencrypted key can be used by any process able to read it. Keep this key
separate from interactive identity or SSH authentication keys. Local signature
verification works immediately; recognition by a Git hosting account requires
separately registering the public key as a signing key. This helper performs
no account registration and does not change authentication or Home Manager.

Disposable integration tests:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tests -p 'test_git_agent_signing.py'
```
