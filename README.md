# NixOS xHCI diagnostic kernels

[![Build kernels](https://github.com/vertigo-red/nixos-xhci-kernel/actions/workflows/build-kernels.yml/badge.svg)](https://github.com/vertigo-red/nixos-xhci-kernel/actions/workflows/build-kernels.yml)

GitHub Actions builds a controlled kernel pair for the Intel Cannon Point-LP
USB controller (`8086:9ded`) and publishes the image, modules and development
output to the public [vertigo-red-xhci cache](https://vertigo-red-xhci.cachix.org).
Diagnostics must run on native NixOS with the physical controller; WSL can build
the packages but cannot reproduce this hardware setup.

| Variant | Kernel release | xHCI changes |
| --- | --- | --- |
| `baseline` | `7.2.9-xhci-baseline` | Mathias Nyman's dequeue fix, plus the fixes already in upstream 7.2.9 |
| `diagnostic` | `7.2.9-xhci-diagnostic` | Baseline plus Michal Pecio's Missed Service Error length experiment |

Nixpkgs is pinned to `151fa4e8ddfdd8dd25d945ad94ed54a13de9f6e4` and
`flake.lock` records the source hash. Both builds use the same toolchain and
identical generated kernel `.config`. Only the diagnostic source change and
`LOCALVERSION` make flag differ. The different releases make the booted variant
visible in `uname -r`.

## Patch provenance and limits

The original Fedora tests used Linux 7.1.8 with two backports. This is a new paired
experiment on Linux 7.2.9, not an exact reproduction of those Fedora builds.

* [7c0c31c66a7f](https://github.com/torvalds/linux/commit/7c0c31c66a7f9daace156bac427aafb2f4bbb5fc)
  moves dequeue to the next valid TD. It is not in the pinned upstream 7.2.9
  source, so `0001` includes it in **both** variants.
* [3d9eeb336131](https://github.com/torvalds/linux/commit/3d9eeb336131bc5a174367c384fa00c15c8744fd)
  is already present in 7.2.9 and is not applied twice.
* [Michal's reply, 2026-08-31](https://marc.info/?l=linux-usb&m=178816199087777&w=2),
  Message-ID `<20260831093914.7e8a45d6.michal.pecio@gmail.com>`, proposes replacing
  `sum_trbs_for_length = true` with `requested = 0` in the
  `COMP_MISSED_SERVICE_ERROR` case. `0002` implements exactly that change and
  keeps `-EXDEV` reporting. It is a **diagnostic proposal**, not a confirmed fix
  for missed service intervals or low frame rate.

The recipes retain Nixpkgs' standard configuration, including xHCI, UVC, Intel
IOMMU, tracepoints and dynamic debugging. CI checks these features and compares
the configs. It does not disable IOMMU or power management, set permanent UVC
quirks, or change exposure controls. Keep those settings equal during A/B tests.

## First GitHub Actions run

1. In this repository open **Settings → Secrets and variables → Actions**.
2. Add a repository secret named **`CACHIX_AUTH_TOKEN`**, containing a Cachix token
   with **Read and Write access to `vertigo-red-xhci`**. A read-only token or a
   token for another cache will fail with `403 Forbidden`. Do not commit or paste
   the token into source files.
3. Open **Actions → Build and publish xHCI kernels → Run workflow**. Code changes
   on `main` also trigger it. Both variants build in separate jobs after checks
   and a small test publication that verifies cache write access.

A successful run means the kernel image, modules and development output were
built, pushed and their public `.narinfo` entries retrieved. Each job saves small
metadata artifacts with the release, commit, derivation and output paths, config
hash and lock file. The kernel binaries live in Cachix, not in expiring GitHub
artifacts. Hardware correctness is assessed separately on the laptop.

The first builds can take hours. Each build job has a 350-minute limit. Subsequent
runs reuse unchanged published outputs. If a build exceeds the hosted-runner
limit, run the same workflow on a suitably sized self-hosted runner or build the
same pinned recipe locally and push it to the same cache.

## Use the published kernel on NixOS

In your existing system flake add the input and module:

```nix
inputs.xhci-kernel.url = "github:vertigo-red/nixos-xhci-kernel";

# Within your existing nixosSystem modules list:
modules = [
  inputs.xhci-kernel.nixosModules.default
  ./configuration.nix
];
```

Keep the kernel input's own pinned Nixpkgs. Do **not** set
`inputs.xhci-kernel.inputs.nixpkgs.follows = "nixpkgs"`: changing its dependencies
would select a different derivation from the one CI published. Commit your system
`flake.lock` too. In `configuration.nix`:

```nix
boot.xhciKernel = {
  enable = true;
  variant = "baseline";
};
```

Remove the earlier standalone `boot.kernelPatches` entry for Michal's patch;
this module already includes it when `variant = "diagnostic"`. Additional kernel
patches, seeds or kernel features can change the derivation and cause local
compilation. The module rejects such an accidental mismatch with an assertion.
External modules such as NVIDIA or ZFS may still require their own builds.

The module installs the cache settings for future rebuilds. Bootstrap the first
rebuild by passing them on the command line (replace `YOUR_HOST` with your actual
NixOS configuration name):

```bash
sudo nixos-rebuild boot --flake /etc/nixos#YOUR_HOST \
  --option extra-substituters https://vertigo-red-xhci.cachix.org \
  --option extra-trusted-public-keys \
  'vertigo-red-xhci.cachix.org-1:eBC+0A0EX9NrhBdKg57F67sDwAkjFyUS+p+uaQGcgw4='
sudo reboot
uname -r
```

Expect `7.2.9-xhci-baseline`. Keep the previous generation available in your boot
menu. After the baseline measurement, change only the variant to `diagnostic`,
rebuild with `boot`, reboot and expect `7.2.9-xhci-diagnostic`. `nixos-rebuild
switch` cannot replace the currently running kernel; a reboot is required.

For a cache-only check before installing (use the same repository commit pinned
in your system lock file):

```bash
nix build github:vertigo-red/nixos-xhci-kernel#diagnostic --max-jobs 0 \
  --option extra-substituters https://vertigo-red-xhci.cachix.org \
  --option extra-trusted-public-keys \
  'vertigo-red-xhci.cachix.org-1:eBC+0A0EX9NrhBdKg57F67sDwAkjFyUS+p+uaQGcgw4='
```

`--max-jobs 0` makes that check fail if the package needs a local build. It is not
needed for an ordinary full NixOS rebuild, which may build unrelated packages.

## Local recipe checks and intentional updates

```bash
nix flake check --no-build
nix eval --json .#lib.integration
nix build .#checks.x86_64-linux.kernel-config
nix build .#baseline .#baseline-modules .#baseline-dev
nix build .#diagnostic .#diagnostic-modules .#diagnostic-dev
```

To update, change the explicit Nixpkgs revision in `flake.nix`, regenerate the
lock file and inspect whether the upstream fixes or diagnostic change are now
included. Recheck patch applicability and rebuild **both** variants before
starting a new comparison. Do not mix results from different revisions.
