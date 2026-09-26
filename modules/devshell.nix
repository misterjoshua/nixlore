_: {
  perSystem =
    { config, pkgs, ... }:
    {
      devShells.default = pkgs.mkShell {
        # pre-commit.devShell carries the shellHook that installs .git/hooks/pre-commit.
        inputsFrom = [ config.pre-commit.devShell ];

        packages = [
          config.treefmt.build.wrapper
        ]
        ++ config.pre-commit.settings.enabledPackages;
      };
    };
}
