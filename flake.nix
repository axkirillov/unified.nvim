{
  description = "unified.nvim — dev tooling (pinned stylua for formatting)";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      # Pinned stylua used by `make format` / `make lint` and the pre-commit hook:
      #   nix run .#stylua -- --check lua/ test/ example/
      packages = forAllSystems (pkgs: {
        stylua = pkgs.stylua;
        default = pkgs.stylua;
      });

      # `nix fmt` formats the tree with the same pinned stylua (honours .stylua.toml).
      formatter = forAllSystems (pkgs: pkgs.stylua);

      # `nix develop` drops you into a shell with the dev tools on PATH.
      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = [
            pkgs.stylua
            pkgs.git
          ];
        };
      });

      # `nix flake check` fails if lua/ test/ example/ are not stylua-clean.
      checks = forAllSystems (pkgs: {
        stylua = pkgs.runCommand "stylua-check" { nativeBuildInputs = [ pkgs.stylua ]; } ''
          cd ${self}
          stylua --check lua test example
          touch $out
        '';
      });
    };
}
