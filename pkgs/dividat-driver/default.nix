{stdenv, fetchurl}:
stdenv.mkDerivation rec {
  name = "dividat-driver-${version}";
  version = "2.2.0-rc1-17-g33093cb";
  channel = "master";

  src = ./dividat-driver-linux-amd64-2.2.0-rc1-17-g33093cb;

  buildCommand = ''
    mkdir -p $out/bin
    cp $src $out/bin/dividat-driver
    chmod +x $out/bin/dividat-driver
  '';

}
