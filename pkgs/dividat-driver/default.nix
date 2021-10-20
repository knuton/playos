{ stdenv, fetchFromGitHub, pkgs, buildGoModule }:

let

  channel = "develop";

  version = "2.2.0-rc2";

  releaseUrl = "https://dist.dividat.com/releases/driver2/";

in buildGoModule rec {

  pname = "dividat-driver";
  inherit version;

  src = fetchFromGitHub {
    owner = "dividat";
    repo = "driver";
    rev = "c4e2b1638828e8d274357418765584feded04226";
    sha256 = "1mv19hsrzzczakn5qih0sb6a877p3v4v722vnanwiyq2frqrzl49";
  };

  vendorSha256 = "0y6qwm0bia8h9pfchmp7nh33m1hawsp11y9w7n6463a856an75h3";

  nativeBuildInputs = with pkgs; [ pkgconfig pcsclite ];
  buildInputs = with pkgs; [ pcsclite ];

  ldflags = [
    "-X github.com/dividat/driver/src/dividat-driver/server.channel=${channel}"
    "-X github.com/dividat/driver/src/dividat-driver/server.version=${version}"
    "-X github.com/dividat/driver/src/dividat-driver/update.releaseUrl=${releaseUrl}"
  ];

}
