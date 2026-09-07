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

  # LibreLane nixpkgs'i dogrudan bir girdi olarak disari acmiyor;
  # nix-eda uzerinden tasiyor. Bu yuzden
  #     nixpkgs.follows = "librelane/nixpkgs"
  # yazilamaz - "input 'nixpkgs' follows a non-existent input" hatasi verir.
  # Dogru yol nix-eda zincirini takip etmektir; boylece LibreLane'in
  # kendi araclarini derledigi nixpkgs ile BIREBIR AYNI surum kullanilir.
  inputs = {
    # SURUM SABITLENDI: 3.0.6
    #
    # Sartname s.7 referans surumu 3.0.6 olarak belirliyor. Farkli bir surum
    # ancak DDK'nin ONCEDEN ONAYIYLA kullanilabilir. Onay surecine girmemek
    # icin referans surumde kaliyoruz.
    #
    # Gelistirme sirasinda bir sure 3.0.10 kullanildi; teslim edilecek butun
    # ciktilar 3.0.6 ile uretilmistir.
    librelane.url = "github:librelane/librelane/3.0.6";
    nixpkgs.follows = "librelane/nix-eda/nixpkgs";
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
