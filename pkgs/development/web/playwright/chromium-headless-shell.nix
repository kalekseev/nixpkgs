{
  fetchzip,
  revision,
  suffix,
  system,
  throwSystem,
  stdenv,
  autoPatchelfHook,
  patchelfUnstable,

  alsa-lib,
  at-spi2-atk,
  glib,
  libgbm,
  libgcc,
  libxkbcommon,
  nspr,
  nss,
  xorg,
  ...
}:
let
  linux = stdenv.mkDerivation {
    name = "playwright-webkit";
    src = fetchzip {
      url = "https://playwright.azureedge.net/builds/chromium/${revision}/chromium-headless-shell-${suffix}.zip";
      stripRoot = false;
      hash =
        {
          x86_64-linux = "sha256-tzYJeO+FxnbhFXBJhHT9Daz0MawDmCgMW2duYVHpeAw=";
          aarch64-linux = "sha256-Qq5K+kMDmyhoZEMTGJeGG5XFDC3aT5JtOouDMkWSTFc=";
        }
        .${system} or throwSystem;
    };

    nativeBuildInputs = [
      autoPatchelfHook
      patchelfUnstable
    ];

    buildInputs = [
      alsa-lib
      at-spi2-atk
      glib
      libgbm
      libgcc.lib
      libxkbcommon
      nspr
      nss
      xorg.libXcomposite
      xorg.libXdamage
      xorg.libXfixes
      xorg.libXrandr
    ];

    buildPhase = ''
      cp -R . $out
    '';
  };

  darwin = fetchzip {
    url = "https://playwright.azureedge.net/builds/chromium/${revision}/chromium-headless-shell-${suffix}.zip";
    stripRoot = false;
    hash =
      {
        x86_64-darwin = "sha256-IiIeEzOv7nQnO3ld1RVZ1zNDym24RNk6ztGW8whJKk4=";
        aarch64-darwin = "sha256-2TvYvK67hOOTxhUIYUkpyfQ42dqaW03+LoVHsCXsJHk=";
      }
      .${system} or throwSystem;
  };
in
{
  x86_64-linux = linux;
  aarch64-linux = linux;
  x86_64-darwin = darwin;
  aarch64-darwin = darwin;
}
.${system} or throwSystem
