# Exercises a git build with forced pushes disabled, against a local bare
# repository in the current directory. `git` must be the patched build.
set -euo pipefail

export HOME="$PWD/home"
mkdir -p "$HOME"

g() { git -c user.name=check -c user.email=check@example.invalid -c init.defaultBranch=main "$@"; }

refuse() {
  local expect=$1 out
  shift
  if out=$(g "$@" 2>&1); then
    echo "FAIL: git $* succeeded" >&2
    exit 1
  fi
  if ! grep -q -- "$expect" <<<"$out"; then
    printf 'FAIL: git %s: unexpected output:\n%s\n' "$*" "$out" >&2
    exit 1
  fi
  echo "ok: git $* refused"
}

g init -q --bare remote.git
g clone -q remote.git work 2>/dev/null
cd work
echo one > file && g add file && g commit -qm one
g push -q origin HEAD:main
published=$(g -C ../remote.git rev-parse main)

echo two > file && g commit -qa --amend -m rewritten
refuse "force push" push --force origin HEAD:main
refuse "force push" push -f origin HEAD:main
refuse "force push" push --force-with-lease origin HEAD:main
refuse "force push" push --mirror origin
refuse "force push" push origin +HEAD:main
refuse "rejected" -c remote.origin.push=+HEAD:refs/heads/main push origin
refuse "rejected" send-pack --force ../remote.git HEAD:refs/heads/main
if [ "$(g -C ../remote.git rev-parse main)" != "$published" ]; then
  echo "FAIL: remote main moved" >&2
  exit 1
fi
echo "ok: remote main unchanged"

g reset -q --hard origin/main
echo three > file && g commit -qam three
g push -q origin HEAD:main
g push -q origin HEAD:refs/heads/topic
g push -q origin --delete topic
echo "ok: fast-forward push and branch deletion still work"
