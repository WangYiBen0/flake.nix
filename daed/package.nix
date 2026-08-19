{
  pnpm,
  fetchPnpmDeps,
  pnpmConfigHook,
  nodejs,
  stdenv,
  clang,
  buildGoModule,
  fetchFromGitHub,
  lib,
}:

let
  metadata = (builtins.fromJSON (builtins.readFile ../metadata.json)).daed.release;
  pname = "daed";
  inherit (metadata) version;
  src = fetchFromGitHub {
    owner = "daeuniverse";
    repo = "daed";
    inherit (metadata) rev hash;
    fetchSubmodules = true;
  };

  web = stdenv.mkDerivation {
    inherit pname version src;

    pnpmDeps = fetchPnpmDeps {
      inherit
        pname
        version
        src
        pnpm
        ;
      fetcherVersion = 4;
      hash = metadata.pnpmDepsHash;
    };

    nativeBuildInputs = [
      nodejs
      pnpm
      pnpmConfigHook
    ];

    prePatch = ''
      # pnpm 11's `pmOnFail` defaults to `download`: when running `pnpm run`,
      # pnpm re-spawns itself using the pnpm version declared in the root
      # `packageManager` field (pnpm@10.24.0), fetched from the registry via
      # a hardcoded bootstrap registry. The sandbox has no network, so tell it
      # to keep the nixpkgs-provided pnpm instead. (the old
      # `manage-package-manager-versions` key is ignored by pnpm 11)
      sed -i '1i pmOnFail: ignore' pnpm-workspace.yaml
    '';

    buildPhase = ''
      runHook preBuild
      pnpm build
      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out
      cp -R apps/web/dist/* $out/
      runHook postInstall
    '';
  };
in
buildGoModule rec {
  inherit pname version src;
  sourceRoot = "${src.name}/wing";

  inherit (metadata) vendorHash;
  proxyVendor = true;

  nativeBuildInputs = [ clang ];

  hardeningDisable = [ "zerocallusedregs" ];

  prePatch = ''
    substituteInPlace Makefile \
      --replace-fail /bin/bash /bin/sh

    # ${web} does not have write permission
    mkdir dist
    cp -r ${web}/* dist
    chmod -R 755 dist
  '';

  buildPhase = ''
    runHook preBuild

    make CFLAGS="-D__REMOVE_BPF_PRINTK -fno-stack-protector -Wno-unused-command-line-argument" \
      NOSTRIP=y \
      WEB_DIST=dist \
      AppName=${pname} \
      VERSION=${version} \
      OUTPUT=$out/bin/daed \
      bundle

    runHook postBuild
  '';

  postInstall = ''
    install -Dm444 $src/install/daed.service -t $out/lib/systemd/system
    substituteInPlace $out/lib/systemd/system/daed.service \
      --replace-fail /usr/bin $out/bin
  '';

  meta = {
    description = "Modern dashboard with dae";
    homepage = "https://github.com/daeuniverse/daed";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ oluceps ];
    platforms = lib.platforms.linux;
    mainProgram = "daed";
  };
}
