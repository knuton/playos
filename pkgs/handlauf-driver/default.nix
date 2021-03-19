{ buildGoModule, fetchFromGitHub }:

buildGoModule rec {
  pname = "handlauf";
  version = "0.1.2";

  src = fetchFromGitHub {
    owner = "256dpi";
    repo = "handlauf";
    rev = "de894641b2d7cb30c93204a91b156394da91427d";
    sha256 = "19bhx59rc3k920hc33vjkw85nj2b8csw20wgj6x0b1m2lvzm56a6";
  };

  vendorSha256 = "0zsf3mg9rv8mgxajw6k96hdpjqn4prb04qnnjvkv4vxv3npah31r";

}
