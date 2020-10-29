{ stdenv, lib, fetchurl, autoPatchelfHook, dpkg, awscli, unzip }:
stdenv.mkDerivation rec {
  pname = "ssm-session-manager-plugin";
  version = "1.2.7.0";

  src = if stdenv.isDarwin then fetchurl {
    url =
      "https://s3.amazonaws.com/session-manager-downloads/plugin/${version}/mac/sessionmanager-bundle.zip";
    sha256 = "sha256-HP+opNjS53zR9eUxpNUHGD9rZN1z7lDc6+nONR8fa/s=";
  } else fetchurl {
    url =
      "https://s3.amazonaws.com/session-manager-downloads/plugin/${version}/ubuntu_64bit/session-manager-plugin.deb";
    sha256 = "sha256-EZ9ncj1YYlod1RLfXOpZFijnKjLYWYVBb+C6yd42l34=";
  };

  nativeBuildInputs = [ autoPatchelfHook dpkg ] ++ stdenv.lib.optional stdenv.isDarwin [unzip];

  buildInputs = [ awscli ];

  unpackPhase = if stdenv.isDarwin then "unzip $src" else "dpkg-deb -x $src .";

  installPhase = if stdenv.isDarwin then
    "install -m755 -D sessionmanager-bundle/bin/session-manager-plugin $out/bin/session-manager-plugin"
    else
    "install -m755 -D usr/local/sessionmanagerplugin/bin/session-manager-plugin $out/bin/session-manager-plugin";

  meta = with lib; {
    homepage =
      "https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html";
    description = "Amazon SSM Session Manager Plugin";
    platforms = [ "x86_64-linux" "x86_64-darwin"];
    license = licenses.unfree;
    maintainers = with maintainers; [ mbaillie ];
  };
}
