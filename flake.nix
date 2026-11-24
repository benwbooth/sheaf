{
  description = "sheaf: a document and photo scanner, like macOS Image Capture (Rust + Qt Quick)";

  # The same nixpkgs revision as grove, so sheaf uses the Qt build the
  # desktop's style and platform plugins were made for.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/ab5c18fdedfc8f9bbc9d773f10a540790e2787a7";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAll = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
      qtFor = pkgs: with pkgs.qt6; [ qtbase qtdeclarative qtsvg qtwayland qtimageformats ];
      qtEnvFor = pkgs: pkgs.qt6.env "qt-sheaf-${pkgs.qt6.qtbase.version}" ((builtins.tail (qtFor pkgs)) ++ [ pkgs.libGL ]);
      # Text recognition for searchable PDFs: English, plus osd (which way
      # up a page is). More languages: add them here.
      tesseractFor = pkgs: pkgs.tesseract.override { enableLanguages = [ "eng" "osd" ]; };
      # Libraries sheaf links (it runs no scanner or OCR programs).
      linkedFor = pkgs: [ pkgs.sane-backends (tesseractFor pkgs) pkgs.leptonica ];
    in
    {
      packages = forAll (pkgs:
        let
          qtEnv = qtEnvFor pkgs;
          tesseract = tesseractFor pkgs;
          cargoDeps = pkgs.rustPlatform.importCargoLock { lockFile = ./Cargo.lock; };
          src = pkgs.lib.cleanSourceWith {
            src = ./.;
            filter = path: type: !(pkgs.lib.hasInfix "/target" path) && baseNameOf path != ".qt-env" && baseNameOf path != "result";
          };
          # Build in a persistent target directory (/var/tmp/cargo-nix, exposed
          # to the sandbox by the system flake) so rebuilds only recompile what
          # changed. Falls back to a throwaway directory when it isn't there.
          # kache stays out of these builds: CARGO_HOME is the build's own.
          persistentCargo = name: cargoArgs: ''
            runHook preBuild
            workDir=$TMPDIR/cargo-nix
            if [ -w /var/tmp/cargo-nix ]; then
              workDir=/var/tmp/cargo-nix/${name}
            fi
            # The store vendor copy only changes with Cargo.lock; the per-build
            # copy gets new mtimes, which would rebuild every dependency.
            sed -i "s|^directory = .*|directory = \"${cargoDeps}\"|" "$NIX_BUILD_TOP/.cargo/config.toml"
            (
              # Writable by everyone: each build may run as a different nixbld
              # user. Kept to this subshell so the outputs get normal modes.
              umask 000
              mkdir -p "$workDir/src" "$workDir/target"
              touch "$workDir"
              # Only rewrite files whose content changed (cargo checks mtimes).
              rsync -rc --no-times --no-perms --chmod=a+rwX --delete ./ "$workDir/src/"
              # The linker wrapper rejects output paths outside the build dir.
              export NIX_ENFORCE_PURITY=0
              cd "$workDir/src"
              # cxx-qt copies its QML exports with fs::copy, which also
              # chmods the destination: that fails on a file left by another
              # nixbld user. The exports are regenerated every build anyway.
              rm -rf "$workDir/target/cxxqt"
              CARGO_HOME="$NIX_BUILD_TOP/.cargo" CARGO_TARGET_DIR="$workDir/target" \
                cargo build ${cargoArgs} --offline --locked -j "$NIX_BUILD_CORES"
              find "$workDir/target" -mindepth 1 -user "$(id -u)" ! -perm -o+w -exec chmod a+rwX {} + 2>/dev/null || true
            )
            ln -sfn "$workDir/target" target
            runHook postBuild
          '';
          sheaf = pkgs.rustPlatform.buildRustPackage {
            pname = "sheaf";
            version = (pkgs.lib.importTOML ./Cargo.toml).package.version;
            inherit src cargoDeps;
            nativeBuildInputs = [ pkgs.pkg-config pkgs.qt6.wrapQtAppsHook pkgs.qt6.qtbase pkgs.rsync pkgs.makeWrapper ];
            buildInputs = qtFor pkgs ++ [ qtEnv pkgs.libGL ] ++ linkedFor pkgs;
            # cxx-qt wants every Qt module under one prefix.
            env.QMAKE = "${qtEnv}/bin/qmake";
            preBuild = ''
              # (Qt's setup hook sets QMAKE to qtbase's alone.)
              export QMAKE=${qtEnv}/bin/qmake
            '';
            buildPhase = persistentCargo "sheaf" "--release -p sheaf";
            installPhase = ''
              runHook preInstall
              install -Dm755 target/release/sheaf $out/bin/sheaf
              install -Dm644 icons/sheaf.svg $out/share/icons/hicolor/scalable/apps/sheaf.svg
              install -Dm644 data/sheaf.desktop $out/share/applications/sheaf.desktop
              runHook postInstall
            '';
            doCheck = false;
            dontWrapQtApps = true;
            # SANE's own settings (SANE_CONFIG_DIR, the system's backends in
            # LD_LIBRARY_PATH) come from the session, as for every SANE app.
            postFixup = ''
              wrapQtApp $out/bin/sheaf \
                --set-default SHEAF_FONT_DIR ${pkgs.inter}/share/fonts/truetype \
                --set-default SHEAF_TESSDATA ${tesseract}/share/tessdata \
                --suffix XDG_DATA_DIRS : ${pkgs.lib.concatMapStringsSep ":" (p: "${p}/share") [ pkgs.whitesur-icon-theme ]}
            '';
            meta = {
              description = "A document and photo scanner, like macOS Image Capture";
              homepage = "https://github.com/benwbooth/sheaf";
              license = pkgs.lib.licenses.mit;
              mainProgram = "sheaf";
              platforms = pkgs.lib.platforms.linux;
            };
          };
        in
        { default = sheaf; inherit sheaf; });

      apps = forAll (pkgs: {
        default = { type = "app"; program = "${self.packages.${pkgs.system}.default}/bin/sheaf"; };
      });

      # `nix develop`: Rust and the same Qt; plain `cargo` then uses the
      # host's kache setup (~/.cargo/config.toml).
      devShells = forAll (pkgs:
        let qtEnv = qtEnvFor pkgs; in
        {
          default = pkgs.mkShell {
            packages = [ pkgs.cargo pkgs.rustc pkgs.clippy pkgs.rustfmt pkgs.pkg-config qtEnv pkgs.libGL pkgs.git pkgs.imagemagick pkgs.xvfb-run pkgs.poppler-utils ];
            buildInputs = linkedFor pkgs;
            QMAKE = "${qtEnv}/bin/qmake";
            SHEAF_TESSDATA = "${tesseractFor pkgs}/share/tessdata";
            # Link with this shell's compiler (a system clang links against the
            # system glibc and the binary can't load this nixpkgs' Qt).
            "CARGO_TARGET_${pkgs.stdenv.hostPlatform.rust.cargoEnvVarTarget}_LINKER" = "cc";
            shellHook = ''
              ln -sfn ${qtEnv} .qt-env
              export NIX_LDFLAGS="''${NIX_LDFLAGS//"-rpath $out/lib"/}"
              export SHEAF_FONT_DIR=''${SHEAF_FONT_DIR:-${pkgs.inter}/share/fonts/truetype}
              export XDG_DATA_DIRS="${pkgs.whitesur-icon-theme}/share:''${XDG_DATA_DIRS:-}"
            '';
          };
        });
    };
}
