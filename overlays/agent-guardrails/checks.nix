# Checks for the agent guardrails overlay and its Home Manager module.
{ nixpkgs, home-manager, system, overlay, module }:

let
  inherit (nixpkgs) lib;
  upstream = nixpkgs.legacyPackages.${system};
  pkgs = import nixpkgs { inherit system; overlays = [ overlay ]; };

  isPatched = drv:
    lib.any (p: baseNameOf (toString p) == "git-refuse-forced-updates.patch") (drv.patches or [ ]);

  homeWith = enable: home-manager.lib.homeManagerConfiguration {
    pkgs = upstream;
    modules = [
      module
      {
        home.username = "check";
        home.homeDirectory = "/home/check";
        home.stateVersion = "24.05";
        modules.home.dev.agent-guardrails.enable = enable;
      }
    ];
  };

  pass = name: pkgs.runCommand name { } "touch $out";
in
{
  agent-guardrails-git = pkgs.runCommand "agent-guardrails-git" { nativeBuildInputs = [ pkgs.git ]; } ''
    bash ${./git-refuse-forced-updates-test.sh}
    touch $out
  '';

  agent-guardrails-gitMinimal =
    assert lib.assertMsg (pkgs.gitMinimal.drvPath == upstream.gitMinimal.drvPath)
      "agent-guardrails: gitMinimal must match upstream so toolchains stay cached";
    pass "agent-guardrails-gitMinimal";

  agent-guardrails-module =
    assert lib.assertMsg (isPatched (homeWith true).pkgs.git && isPatched (homeWith true).pkgs.gitFull)
      "agent-guardrails: enabling the module should patch git and gitFull";
    assert lib.assertMsg (!isPatched (homeWith false).pkgs.git)
      "agent-guardrails: the disabled module must leave git unchanged";
    pass "agent-guardrails-module";
}
