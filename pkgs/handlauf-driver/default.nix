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

  vendorSha256 = "0y4vcw47kpxi1301qc80hvrbdzf0hfkyvhxj0iv6n7yh13b7x66s";

}
