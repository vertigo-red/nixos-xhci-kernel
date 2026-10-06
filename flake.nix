{
  description = "Paired NixOS kernels for Intel Cannon Point-LP xHCI/UVC diagnostics";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/151fa4e8ddfdd8dd25d945ad94ed54a13de9f6e4";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
      stock = pkgs.linuxKernel.kernels.linux_7_2;
      commonPatches = [
        {
          name = "xhci-move-dequeue-to-next-valid-td";
          patch = ./patches/0001-xhci-move-dequeue-to-next-valid-td.patch;
        }
      ];
      mkKernel = variant: stock.override (args: {
        pname = "linux-xhci-${variant}";
        modDirVersion = "${stock.modDirVersion}-xhci-${variant}";
        extraMakeFlags = (args.extraMakeFlags or [ ]) ++ [ "LOCALVERSION=-xhci-${variant}" ];
        kernelPatches = (args.kernelPatches or [ ]) ++ commonPatches
          ++ pkgs.lib.optional (variant == "diagnostic") {
            name = "xhci-missed-service-diagnostic";
            patch = ./patches/0002-xhci-missed-service-diagnostic.patch;
          };
      });
      baseline = mkKernel "baseline";
      diagnostic = mkKernel "diagnostic";
    in
    {
      packages.${system} = {
        inherit baseline diagnostic;
        baseline-dev = baseline.dev;
        baseline-modules = baseline.modules;
        diagnostic-dev = diagnostic.dev;
        diagnostic-modules = diagnostic.modules;
        default = diagnostic;
      };

      checks.${system}.kernel-config = pkgs.runCommand "xhci-kernel-config-check" { } ''
        bash ${./scripts/check-configs.sh} ${baseline.configfile} ${diagnostic.configfile}
        touch "$out"
      '';

      nixosModules.default = import ./nixos-module.nix {
        inherit baseline diagnostic;
      };

      # Evaluation checks that a NixOS import selects the same derivations
      # as CI, rather than silently creating an uncached kernel override.
      lib.integration = pkgs.lib.genAttrs [ "baseline" "diagnostic" ] (variant:
        let
          evaluated = nixpkgs.lib.nixosSystem {
            inherit system;
            modules = [
              self.nixosModules.default
              {
                boot.xhciKernel.enable = true;
                boot.xhciKernel.variant = variant;
                system.stateVersion = "26.05";
              }
            ];
          };
        in
        {
          kernelDrvPath = evaluated.config.boot.kernelPackages.kernel.drvPath;
          expectedDrvPath = self.packages.${system}.${variant}.drvPath;
          matchesPublished = evaluated.config.boot.kernelPackages.kernel.drvPath
            == self.packages.${system}.${variant}.drvPath;
        });
    };
}
