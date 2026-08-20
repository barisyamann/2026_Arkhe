#
# flake.nix - Arkhe SoC ASIC akisi Nix ortami
# TEKNOFEST 2026 - Takim ARKHE
#
# Final ciktilar belgesi, LibreLane ve gerekli araclari tanimlayan bir
# flake.nix ile bagimliliklari sabitleyen bir flake.lock istiyor.
#
# flake.lock BU DOSYADAN URETILIR, elle yazilmaz:
#
#     cd asic/environment
#     nix flake lock
#
# Bu komut kullanilan LibreLane ve nixpkgs surumlerini commit hash
# duzeyinde sabitler; boylece akis baska bir makinede birebir ayni
# araclarla tekrar kosulabilir.
#
# Ortama girmek icin:
#     nix develop ./environment
#
{
  description = "Arkhe SoC - ASIC fiziksel tasarim ortami (LibreLane + sky130A)";

  inputs = {
    librelane.url = "github:librelane/librelane";
    nixpkgs.follows = "librelane/nixpkgs";
  };

  outputs = { self, librelane, nixpkgs }:
    let
      # Akisin kosuldugu platformlar
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    in
    {
      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        {
          default = pkgs.mkShell {
            name = "arkhe-asic";

            packages = [
              librelane.packages.${system}.librelane
              pkgs.gnumake
              pkgs.python3
            ];

            shellHook = ''
              echo "Arkhe SoC ASIC ortami"
              echo "  librelane : $(librelane --version 2>/dev/null || echo bulunamadi)"
              echo "  PDK_ROOT  : ''${PDK_ROOT:-tanimsiz}"
              echo ""
              echo "  asic/ dizininden:  make asic_run"
            '';
          };
        });
    };
}
