{ inputs, ... }:
{
  imports = [ inputs.git-hooks.flakeModule ];

  # Provides checks.pre-commit and config.pre-commit.{devShell,installationScript}.
  perSystem =
    { config, ... }:
    {
      pre-commit.settings.hooks = {
        # Formatting and linting are delegated to treefmt so there is a single
        # source of truth shared by `nix fmt`, `nix flake check`, and the hook.
        treefmt = {
          enable = true;
          package = config.treefmt.build.wrapper;
        };

        check-merge-conflicts.enable = true;
        end-of-file-fixer.enable = true;
        trim-trailing-whitespace.enable = true;
        check-added-large-files.enable = true;

        flake-checker.enable = true;
      };
    };
}
