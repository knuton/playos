{ stdenv, makeFontsConf, pandoc, python39Packages, ibm-plex, version }:
let
  fontsConf = makeFontsConf {
    fontDirectories = [ ibm-plex ];
  };
in
stdenv.mkDerivation {
  name = "playos-docs-${version}";

  src = ./.;

  buildInputs = [ pandoc python39Packages.weasyprint ];

  installPhase = ''
    DATE=$(date -I)
    export FONTCONFIG_FILE="${fontsConf}"

    mkdir -p $out

    cd arch
    pandoc \
      --template ../templates/default.html \
      --toc --number-sections \
      -V version=${version} -M date=$DATE \
      -t html5 \
      --standalone --self-contained -o $out/arch.html \
      Readme.org
    weasyprint $out/arch.html $out/arch.pdf

    cd ../user-manual
    pandoc \
        --template ../templates/default.html \
        --toc --number-sections \
        -V version=${version} -M date=$DATE \
        -t html5 \
        --standalone --self-contained -o $out/user-manual.html \
        Readme.org
    weasyprint $out/user-manual.html $out/user-manual.pdf
  '';
}
