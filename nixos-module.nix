{ baseline, diagnostic }:
{ config, lib, pkgs, ... }:
let
  cfg = config.boot.xhciKernel;
  selected = if cfg.variant == "baseline" then baseline else diagnostic;
in
{
  options.boot.xhciKernel = {
    enable = lib.mkEnableOption "the cached xHCI diagnostic kernel pair";
    variant = lib.mkOption {
      type = lib.types.enum [ "baseline" "diagnostic" ];
      default = "baseline";
      description = "Use baseline first, then diagnostic for the paired experiment.";
    };
  };

  config = lib.mkIf cfg.enable {
    boot.kernelPackages = pkgs.linuxPackagesFor selected;

    nix.settings = {
      extra-substituters = [ "https://vertigo-red-xhci.cachix.org" ];
      extra-trusted-public-keys = [
        "vertigo-red-xhci.cachix.org-1:eBC+0A0EX9NrhBdKg57F67sDwAkjFyUS+p+uaQGcgw4="
      ];
    };

    assertions = [
      {
        assertion = config.nixpkgs.hostPlatform.system == "x86_64-linux";
        message = "The published xHCI kernels are built for x86_64-linux only.";
      }
      {
        assertion = config.boot.kernelPackages.kernel.drvPath == selected.drvPath;
        message = ''
          The host configuration changed the cached xHCI kernel derivation.
          Remove additional boot.kernelPatches, a custom randstructSeed, or
          conflicting kernel features; put shared kernel changes in this
          repository and rebuild both variants in CI instead.
        '';
      }
    ];
  };
}
