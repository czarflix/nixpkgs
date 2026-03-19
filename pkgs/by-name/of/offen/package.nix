{
  lib,
  stdenvNoCC,
  buildGoModule,
  fetchFromGitHub,
  fetchPnpmDeps,
  nodejs_22,
  pnpm_10,
  pnpmConfigHook,
  runCommand,
}:
let
  rev = "ec99082a37ffb5855bd84debfef227d41c7b403c";
  version = "unstable-2026-03-04";

  src = fetchFromGitHub {
    owner = "offen";
    repo = "offen";
    inherit rev;
    hash = "sha256-EGlqD3611sG3YTVe74H49PB8Hj1NsKYhLANg5VAQ0wg=";
  };

  pnpm = pnpm_10.override { nodejs = nodejs_22; };

  clientEnv = {
    ADBLOCK = true;
    DISABLE_OPENCOLLECTIVE = true;
    NODE_OPTIONS = "--no-experimental-fetch";
    PUPPETEER_SKIP_CHROMIUM_DOWNLOAD = true;
  };

  mkClient =
    {
      name,
      directory,
    }:
    stdenvNoCC.mkDerivation (finalAttrs: {
      pname = "offen-${name}";
      inherit version src;
      sourceRoot = "${finalAttrs.src.name}/${directory}";

      env = clientEnv;

      pnpmDeps = fetchPnpmDeps {
        inherit (finalAttrs)
          pname
          version
          src
          sourceRoot
          ;
        inherit pnpm;
        fetcherVersion = 3;
        hash =
          {
            auditorium = "sha256-xpdFlgHBUcHgL16hruFg6Spv1IlBEc7PB/UqpKnv5Oo=";
            script = "sha256-Vmv4aESpAvE9Dg28WpSPhtEEBr8q/BfqrJl5EXC0nl4=";
            vault = "sha256-vAXHm85rlsG0pAeRmqzmmI+Ztw0CmkzgVg9f67m3S3g=";
          }
          .${name};
      };

      nativeBuildInputs = [
        nodejs_22
        pnpm
        pnpmConfigHook
      ];

      postPatch = ''
        cp -R ../locales ./locales
      '';

      buildPhase = ''
        runHook preBuild

        export NODE_ENV=production
        pnpm run build

        runHook postBuild
      '';

      installPhase = ''
        runHook preInstall

        mkdir -p $out
        cp -R dist/. $out/

        runHook postInstall
      '';
    });

  auditorium = mkClient {
    name = "auditorium";
    directory = "auditorium";
  };

  script = mkClient {
    name = "script";
    directory = "script";
  };

  vault = mkClient {
    name = "vault";
    directory = "vault";
  };
in
buildGoModule (finalAttrs: {
  pname = "offen";
  inherit version src;

  modRoot = "server";
  subPackages = [ "cmd/offen" ];

  vendorHash = "sha256-AeQa5oaOEB/50aPCRq702vMEtEctwP+jU5C6zB+3XR0=";

  tags = [ "sqlite_omit_load_extension" ];

  ldflags = [
    "-s"
    "-w"
    "-X github.com/offen/offen/server/config.Revision=${rev}"
  ];

  preConfigure = ''
    chmod -R u+w server/public/static
    rm -rf server/public/static/locales
    mkdir -p server/public/static/locales

    cp -r --no-preserve=mode ${script}/. server/public/static/
    cp -r --no-preserve=mode ${vault}/. server/public/static/
    cp -r --no-preserve=mode ${auditorium}/. server/public/static/
    cp -r --no-preserve=mode server/locales/. server/public/static/locales/
    cp NOTICE server/public/static/NOTICE.txt
  '';

  passthru = {
    inherit
      auditorium
      script
      vault
      ;

    tests.smoke = runCommand "${finalAttrs.pname}-smoke" { } ''
      tmpdir="$(mktemp -d)"

      cat > "$tmpdir/offen.env" <<EOF
      OFFEN_DATABASE_DIALECT=sqlite3
      OFFEN_DATABASE_CONNECTIONSTRING=$tmpdir/offen.db
      OFFEN_SERVER_PORT=0
      EOF

      ${lib.getExe finalAttrs.finalPackage} version > "$tmpdir/version.log" 2>&1
      grep -F 'revision' "$tmpdir/version.log"

      ${lib.getExe finalAttrs.finalPackage} setup \
        -envfile "$tmpdir/offen.env" \
        -populate \
        -force \
        -name "Smoke Account" \
        -email smoke@example.com \
        -password smoketest123

      test -f "$tmpdir/offen.db"

      touch $out
    '';
  };

  meta = {
    description = "Self-hosted web analytics tool that keeps data private";
    homepage = "https://www.offen.dev";
    downloadPage = "https://github.com/offen/offen";
    changelog = "https://github.com/offen/offen/commit/${rev}";
    license = with lib.licenses; [
      asl20
      cc-by-nc-nd-40
    ];
    mainProgram = "offen";
    maintainers = with lib.maintainers; [ czarflix ];
    platforms = lib.platforms.unix;
    teams = with lib.teams; [ ngi ];
  };
})
