{ config, pkgs, ... }:

{

  # Kiosk runs as a non-privileged user
  users.users.play = {
    isNormalUser = true;
    home = "/home/play";
    extraGroups = [
      "audio" # Play audio
      "dialout" # Access to serial ports for the Senso flex
    ];
  };

  # Note that setting up "/home" as persistent fails due to https://github.com/NixOS/nixpkgs/issues/6481
  volatileRoot.persistentFolders."/home/play" = {
    mode = "0700";
    user = "play";
    group = "users";
  };


  # Kiosk session
  services.xserver = {
    enable = true;

    desktopManager = {
      xterm.enable = false;
      session = [
        { name = "kiosk-browser";
          start = ''
            # Disable screen-saver control (screen blanking)
            xset s off
            xset s noblank
            xset -dpms

            # Enable Qt WebEngine Developer Tools (https://doc.qt.io/qt-5/qtwebengine-debugging.html)
            export QTWEBENGINE_REMOTE_DEBUGGING="127.0.0.1:3355"

            ${pkgs.playos-kiosk-browser}/bin/kiosk-browser \
              ${config.playos.kioskUrl} \
              http://localhost:3333/

            waitPID=$!
          '';
        }
      ];
    };

    displayManager = {
      # Always automatically log in play user
      lightdm = {
        enable = true;
        greeter.enable = false;
        autoLogin.timeout = 0;
      };

      autoLogin = {
        enable = true;
        user = "play";
      };

      defaultSession = "kiosk-browser";
      sessionCommands = ''
        ${pkgs.xorg.xrdb}/bin/xrdb -merge <<EOF
          Xcursor.theme: ${pkgs.breeze-contrast-cursor-theme.themeName}
        EOF

        # Localization for xsession
        if [ -f /var/lib/gui-localization/lang ]; then
          export LANG=$(cat /var/lib/gui-localization/lang)
        fi
        if [ -f /var/lib/gui-localization/keymap ]; then
          setxkbmap $(cat /var/lib/gui-localization/keymap) || true
        fi

        # Disable virtual terminal switching with Ctrl-Alt-F12
        # Users tend to press this instead of Ctrl-Shift-F12 and get scared by the black screen
        ${pkgs.xorg.xkbcomp}/bin/xkbcomp $DISPLAY keymap.xkb
        sed -i 's/SwitchScreen(screen=12.\+)/NoAction()/' keymap.xkb
        ${pkgs.xorg.xkbcomp}/bin/xkbcomp keymap.xkb $DISPLAY
        rm keymap.xkb
      '';
    };
  };

  # Driver service
  systemd.services."dividat-driver" = {
    description = "Dividat Driver";
    serviceConfig.ExecStart = "${pkgs.dividat-driver}/bin/dividat-driver";
    serviceConfig.User = "play";
    wantedBy = [ "multi-user.target" ];
  };

  # Enable audio
  hardware.pulseaudio.enable = true;

  # Run PulseAudio as System-Wide daemon. See [1] for why this is in general a bad idea, but ok for our case.
  # [1] https://www.freedesktop.org/wiki/Software/PulseAudio/Documentation/User/WhatIsWrongWithSystemWide/
  hardware.pulseaudio.systemWide = true;

  environment.systemPackages = with pkgs; [
    breeze-contrast-cursor-theme

    # Install a command line mixer
    pamix
    pamixer
  ];

  # Enable avahi for Senso discovery
  services.avahi.enable = true;

  # Enable pcscd for smart card identification
  services.pcscd.enable = true;
  # Blacklist NFC modules conflicting with CCID (https://ludovicrousseau.blogspot.com/2013/11/linux-nfc-driver-conflicts-with-ccid.html)
  boot.blacklistedKernelModules = [ "pn533_usb" "pn533" "nfc" ];
  # Allow play user to access pcsc
  security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        if (subject.user == "play" && (action.id == "org.debian.pcsc-lite.access_pcsc" || action.id == "org.debian.pcsc-lite.access_card")) {
          return polkit.Result.YES;
        }
      });
  '';

}
