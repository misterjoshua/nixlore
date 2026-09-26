{ inputs, ... }:
{
  imports = [ inputs.treefmt-nix.flakeModule ];

  # Provides `nix fmt` (formatter.<system>) and checks.treefmt for `nix flake check`.
  perSystem = _: {
    treefmt = {
      projectRootFile = "flake.nix";

      programs = {
        nixfmt.enable = true;
        deadnix.enable = true;
        statix.enable = true;
        prettier.enable = true;
      };

      settings.formatter.prettier.includes = [
        "*.md"
        "*.yaml"
        "*.yml"
        "*.json"
      ];
    };
  };
}
