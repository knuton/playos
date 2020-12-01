{stdenv, fetchurl}:
stdenv.mkDerivation rec {
  name = "dividat-driver-${version}";
  version = "2.2.0-rc1-19-g7c7c59f";
  channel = "master";

  src = ./dividat-driver-linux-amd64-2.2.0-rc1-19-g7c7c59f;

  buildCommand = ''
    mkdir -p $out/bin
    cp $src $out/bin/dividat-driver
    chmod +x $out/bin/dividat-driver
  '';

}
