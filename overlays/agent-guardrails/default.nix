# Tool builds that keep agents from rewriting shared history.
#
# Apply on standalone Home Manager hosts with
# `modules.home.dev.agent-guardrails.enable = true;`, or add
# `nixhome.overlays.agentGuardrails` to any nixpkgs instance.
#
# Every package that asks for `git` gets the patched build. nixpkgs derives
# `gitMinimal` from the final `git`, and compiler toolchains use it at build
# time, so it is rebuilt here from the unpatched `git` with the arguments
# nixpkgs uses. That keeps those toolchains identical to upstream and served
# from the binary cache; the `agent-guardrails-gitMinimal` check enforces it.
final: prev: {
  git = prev.git.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ ./git-refuse-forced-updates.patch ];
    # git's own test suite exercises forced pushes.
    doCheck = false;
    doInstallCheck = false;
  });

  gitMinimal = prev.git.override {
    withManual = false;
    osxkeychainSupport = false;
    pythonSupport = false;
    perlSupport = false;
    rustSupport = false;
    withpcre2 = false;
    curl = if prev.stdenv.hostPlatform.isFreeBSD then prev.curlMinimal else prev.curl;
  };
}
