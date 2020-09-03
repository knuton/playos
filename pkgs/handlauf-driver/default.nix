{ buildGoModule, fetchFromGitHub }:

buildGoModule rec {
  pname = "handlauf";
  version = "0.1.2";

  src = fetchFromGitHub {
    owner = "256dpi";
    repo = "handlauf";
    rev = "v${version}";
    sha256 = "0lvbydcy2rckqf2qk5cizibvvmah790zicji9d60rzlrf68xg7sf";
  };

  modSha256 = "1jrpcd51vgyrgs42jqn1iyvgf8bqmmhmjjp8zai89na2k7pzy0vk";

}
