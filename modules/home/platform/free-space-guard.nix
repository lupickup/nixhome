# modules/home/platform/free-space-guard.nix — keep writable disk space above a
# floor on macOS.
#
# A launchd agent runs scripts/free-space-guard every 15 minutes. It measures
# writable space as `df` does (statfs's f_bavail). Finder and menu-bar monitors
# count purgeable space as free, including Time Machine's local snapshots,
# which keep every file deleted after they were taken on disk: a disk they
# show with hundreds of gigabytes free can be nearly full. Time Machine takes
# a local snapshot every hour and keeps them for a day, more while its backup
# disk is away, and macOS thins them only when the disk is nearly full.
#
# Below `thinBelow` GiB the guard deletes local Time Machine snapshots, oldest
# first, keeping the newest unless the volume is under `floor` GiB, then runs
# `mbx gc` when `mbx` is set. If the volume is still under the floor it posts a
# notification naming the largest volumes and the size of mbx's cache, at most
# once per `notifyEvery` seconds. It deletes nothing else and needs no root:
# tmutil deletes local snapshots for an administrator.
#
#   modules.home.platform.free-space-guard.enable = true;
#
# It logs to ~/Library/Logs/free-space-guard.log when it acts. Its notifications
# come from osascript, which macOS shows as Script Editor's; allow those in
# System Settings > Notifications. To preview a run without changing anything,
# raise the threshold for one dry run:
#
#   free-space-guard --dry-run --thin-below 2000 --mbx "$(command -v mbx)"

{ config, lib, pkgs, ... }:

let
  cfg = config.modules.home.platform.free-space-guard;
  mbxCfg = config.modules.home.dev.mbx;
  logFile = "${config.home.homeDirectory}/Library/Logs/free-space-guard.log";

  guard = pkgs.runCommandLocal "free-space-guard" { } ''
    install -Dm755 ${../../../scripts/free-space-guard} $out/bin/free-space-guard
  '';

  arguments = [
    "--volume" cfg.volume
    "--thin-below" (toString cfg.thinBelow)
    "--floor" (toString cfg.floor)
    "--notify-every" (toString cfg.notifyEvery)
    "--log" logFile
  ]
  ++ lib.optionals (cfg.mbx != null) [ "--mbx" (lib.getExe' cfg.mbx "mbx") ]
  ++ lib.optional cfg.dryRun "--dry-run";
in
{
  options.modules.home.platform.free-space-guard = {
    enable = lib.mkEnableOption "a launchd agent that keeps writable disk space above a floor on macOS";

    volume = lib.mkOption {
      type = lib.types.str;
      default = "/System/Volumes/Data";
      description = "Mount point of the volume to guard.";
    };

    thinBelow = lib.mkOption {
      type = lib.types.ints.positive;
      default = 120;
      description = "Writable GiB below which the guard deletes local snapshots and runs `mbx gc`.";
    };

    floor = lib.mkOption {
      type = lib.types.ints.positive;
      default = 100;
      description = ''
        Writable GiB to keep. Under it the newest local snapshot goes too, and
        the guard notifies when it cannot get back above it.
      '';
    };

    interval = lib.mkOption {
      type = lib.types.ints.positive;
      default = 900;
      description = "Seconds between runs.";
    };

    notifyEvery = lib.mkOption {
      type = lib.types.ints.unsigned;
      default = 3600;
      description = "Least number of seconds between notifications while the volume stays under the floor.";
    };

    mbx = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = if mbxCfg.enable then mbxCfg.package else null;
      defaultText = lib.literalExpression
        "config.modules.home.dev.mbx.package, when modules.home.dev.mbx is enabled";
      description = "mbx package whose `mbx gc` the guard runs, or null to skip it.";
    };

    dryRun = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Log what each run would do without deleting anything or notifying.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = pkgs.stdenv.hostPlatform.isDarwin;
        message = "modules.home.platform.free-space-guard runs only on macOS.";
      }
      {
        assertion = cfg.floor <= cfg.thinBelow;
        message = "modules.home.platform.free-space-guard.floor must not exceed thinBelow.";
      }
    ];

    home.packages = [ guard ];

    launchd.agents.free-space-guard = {
      enable = true;
      config = {
        ProgramArguments = [ "${guard}/bin/free-space-guard" ] ++ arguments;
        StartInterval = cfg.interval;
        RunAtLoad = true;
        ProcessType = "Background";
        EnvironmentVariables = {
          HOME = config.home.homeDirectory;
          PATH = "/usr/bin:/bin:/usr/sbin:/sbin";
        };
        StandardOutPath = logFile;
        StandardErrorPath = logFile;
      };
    };
  };
}
