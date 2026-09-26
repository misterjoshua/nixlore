# age public keys, sourced from ../keys/<user>/<name>.age.
#
# Consume from another flake via `inputs.nixlore.lib.ageKeys`:
#
#   age -r ${nixlore.lib.ageKeys.keys.josh.syl} -o secret.age secret.txt
#   recipients = nixlore.lib.ageKeys.all;
#   environment.etc."syl.age".source = nixlore.lib.ageKeys.files.josh.syl;
#
# Add or rotate a key by dropping a `.age` file into the user's directory; no
# Nix changes required.
{ lib, ... }:
let
  keysDir = ../keys;

  readKey = path: lib.removeSuffix "\n" (builtins.readFile path);

  ageFilesIn =
    dir:
    lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".age" name) (builtins.readDir dir);

  userDirs = lib.filterAttrs (_: type: type == "directory") (builtins.readDir keysDir);

  # { <user> = { <name> = /path/to/keys/<user>/<name>.age; }; }
  files = lib.mapAttrs (
    user: _:
    lib.mapAttrs' (
      file: _: lib.nameValuePair (lib.removeSuffix ".age" file) (keysDir + "/${user}/${file}")
    ) (ageFilesIn (keysDir + "/${user}"))
  ) userDirs;
in
{
  # `lib` has no flake-parts type, so a second assignment is rejected.
  # Declaring it lets sshKeys and ageKeys merge.
  options.flake.lib = lib.mkOption {
    type = lib.types.attrsOf lib.types.raw;
    default = { };
  };

  config = {
    flake.lib.ageKeys = rec {
      inherit files;

      # { <user> = { <name> = "age1..."; }; }
      keys = lib.mapAttrs (_: lib.mapAttrs (_: readKey)) files;

      # { <user> = [ "age1..." ... ]; }
      users = lib.mapAttrs (_: lib.attrValues) keys;

      # [ "age1..." ... ] across every user
      all = lib.concatLists (lib.attrValues users);
    };

    # Fails `nix flake check` unless every .age file is a single age1 recipient.
    perSystem =
      { pkgs, ... }:
      {
        checks.age-keys = pkgs.runCommand "check-age-keys" { } ''
          for f in ${keysDir}/*/*.age; do
            echo "checking $f"
            if ! grep -Exq 'age1[0-9a-z]+' "$f" || [ "$(wc -l < "$f")" -ne 1 ]; then
              echo "$f is not an age public key" >&2
              exit 1
            fi
          done
          touch $out
        '';
      };
  };
}
