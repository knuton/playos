{ config, pkgs, ... }:

{

  # Kiosk runs as a non-privileged user
  users.users.play = {
    isNormalUser = true;
    home = "/home/play";
    extraGroups = [
      "dialout" # Access to serial ports for the Senso flex
    ];
  };

  # Note that setting up "/home" as persistent fails due to https://github.com/NixOS/nixpkgs/issues/6481
  volatileRoot.persistentFolders."/home/play" = {
    mode = "0700";
    user = "play";
    group = "users";
  };

  # System-wide packages
  environment.systemPackages = with pkgs; [
    breeze-contrast-cursor-theme
  ];

  # Kiosk session
  services.xserver = let sessionName = "kiosk-browser"; in {
    enable = true;

    desktopManager = {
      xterm.enable = false;
      session = [
        { name = sessionName;
          start = ''
            # Disable screen-saver control (screen blanking)
            xset s off
            xset s noblank
            xset -dpms

            # Localization for xsession
            if [ -f /var/lib/gui-localization/lang ]; then
              export LANG=$(cat /var/lib/gui-localization/lang)
            fi
            if [ -f /var/lib/gui-localization/keymap ]; then
              setxkbmap $(cat /var/lib/gui-localization/keymap) || true
            fi

            # force resolution
            scaling_pref=/var/lib/gui-localization/screen-scaling
            if [ -f "$scaling_pref" ] && [ $(cat "$scaling_pref") = "full-hd" ]; then
               xrandr --size 1920x1080
            fi

            # We want to avoid making the user configure audio outputs, but
            # instead route audio to both the standard output and any connected
            # displays. This looks for any "HDMI" device on ALSA card 0 and
            # tries to add a sink for it. Both HDMI and DisplayPort connectors
            # will count as "HDMI". We ignore failure from disconnected ports.
            for dev_num in $(aplay -l | grep "^card 0:" | grep "HDMI" | grep "device [0-9]\+" | sed "s/.*device \([0-9]\+\):.*/\1/"); do
              printf "Creating ALSA sink for device $dev_num: "
              pactl load-module module-alsa-sink device="hw:0,$dev_num" sink_name="hdmi$dev_num" sink_properties="device.description='HDMI-$dev_num'" || true
            done
            pactl load-module module-combine-sink sink_name=combined
            pactl set-default-sink combined

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

      defaultSession = sessionName;

      sessionCommands = ''
        ${pkgs.xorg.xrdb}/bin/xrdb -merge <<EOF
          Xcursor.theme: ${pkgs.breeze-contrast-cursor-theme.themeName}
        EOF
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

  # Audio
  sound.enable = true;
  hardware.pulseaudio = {
    enable = true;
  };

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

  services.udev.extraRules = ''
  # udev rules for deadzones on Teensy emulated joysticks
  SUBSYSTEM=="input", ENV{ID_VENDOR_ID}=="16c0", ACTION=="add", RUN+="${pkgs.linuxConsoleTools}/bin/jscal -s 7,1,0,512,512,1048544,1050595,1,0,512,512,1048544,1050595,1,0,512,512,1048544,1050595,1,0,512,512,1048544,1050595,1,0,512,512,1048544,1050595,1,0,0,0,536854528,536854528,1,0,0,0,536854528,536854528 /dev/input/js1"
'';

}
