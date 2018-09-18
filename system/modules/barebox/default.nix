{config, lib, pkgs, ...}:

let

  cfg = config.boot.loader.barebox;

  efi = config.boot.loader.efi;

  barebox = (import ./barebox-efi.nix) {
    inherit (pkgs) stdenv binutils fetchurl;
    inherit (cfg) defaultEnv;
  };

in

with lib;

{ 

  options = {
    boot.loader.barebox = {
      enable = mkOption {
        default = false;
        type = types.bool;
        description = ''
          Whether to enable the barebox boot loader.
        '';
      };

      defaultEnv = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''
          Default environment that is compiled into barebox.
        '';
      };

    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = (config.boot.kernelPackages.kernel.features or { efiBootStub = true; }) ? efiBootStub;

        message = "This kernel does not support the EFI boot stub";
      }
    ];

    boot.loader.grub.enable = mkDefault false;

    boot.loader.supportsInitrdSecrets = true;

    system = {
      build.installBootLoader = pkgs.writeScript "install-barebox.sh"
        ''
          # Install barebox
          mkdir -p ${efi.efiSysMountPoint}/EFI/BOOT
          cp ${barebox} ${efi.efiSysMountPoint}/EFI/BOOT/BOOTX64.EFI
        '';

      boot.loader.id = "barebox";

      requiredKernelConfig = with config.lib.kernelConfig; [
        (isYes "EFI_STUB")
      ];
    };
  };

}
