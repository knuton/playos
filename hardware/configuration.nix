{ config, lib, pkgs, ... }:

{
  # Include drivers for common boot devices
  boot.initrd.availableKernelModules = [ "ahci" "nvme" "sd_mod" "sdhci_pci" "usb_storage" "xhci_pci" ];
}
