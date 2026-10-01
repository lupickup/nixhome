# Keep the XDG configuration root separate from editable source checkouts.
{ config, lib, pkgs, ... }:

let
  cfg = config.modules.home.platform.config-root;
  configHome = toString (builtins.toPath config.xdg.configHome);
  replacesConfigHome = file:
    let
      target = toString (builtins.toPath (
        if lib.hasPrefix "/" file.target then file.target
        else "${config.home.homeDirectory}/${file.target}"
      ));
    in file.enable && (target == configHome || lib.hasPrefix "${target}/" configHome);
in
{
  options.modules.home.platform.config-root = {
    enable = lib.mkEnableOption "protecting the XDG configuration root";
    forbiddenRoots = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Absolute source directories that must not contain the live XDG config root.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !lib.any replacesConfigHome (lib.attrValues config.home.file);
        message = "The XDG config root (or its parent) must not be managed as a home.file entry. Link individual app configs instead.";
      }
    ];
    home.activation.checkConfigRoot = lib.hm.dag.entryBefore [
      "checkLinkTargets" "cleanupLegacySkillInstalls" "writeBoundary"
    ] ''
      ${pkgs.bash}/bin/bash ${../../../scripts/check-config-home} \
        ${lib.escapeShellArgs ([ config.xdg.configHome ] ++ cfg.forbiddenRoots)}
    '';
  };
}
