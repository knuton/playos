{stdenv, fetchurl}:
stdenv.mkDerivation rec {
  name = "dividat-driver-${version}";
  version = "2.2.0-rc1-14-g84c93ab";
  channel = "master";

  src = ./dividat-driver-linux-amd64-2.2.0-rc1-14-g84c93ab;

  buildCommand = ''
    mkdir -p $out/bin
    cp $src $out/bin/dividat-driver
    chmod +x $out/bin/dividat-driver
  '';

}
