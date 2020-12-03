{ stdenv
, lib
, fetchFromGitHub
, rustPlatform
, Security
, openssl
}:

rustPlatform.buildRustPackage rec {
  pname = "volta";
  version = "0.9.2";

  src = fetchFromGitHub {
    owner = "volta-cli";
    repo = pname;
    rev = "v${version}";
    sha256 = "sha256-0OBaR1dZXAngwR8ZziEPvyp5XbBux8TVXDWPW4eYTM8=";
  };

  cargoSha256 = "sha256-QzWl3fvd6ukPvgf74Yk/xTAuSzTDy/Lt44UFvtSV7s8=";

  buildInputs = [ openssl ]
    ++ stdenv.lib.optionals stdenv.isDarwin [ Security ];

  meta = with lib; {
    homepage = "https://github.com/volta-cli/volta";
    description = "Volta is a hassle-free way to manage your JavaScript command-line tools.";
    changelog = "https://github.com/volta-cli/volta/blob/v${version}/RELEASES.md";
    license = licenses.bsd2;
    maintainers = with maintainers; [ kalekseev ];
  };
}
