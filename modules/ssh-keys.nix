# SSH public keys, sourced from ../keys/<user>/<name>.pub.
#
# Consume from another flake via `inputs.nixlore.lib.sshKeys`:
#
#   users.users.josh.openssh.authorizedKeys.keys = nixlore.lib.sshKeys.users.josh;
#   users.users.admin.openssh.authorizedKeys.keys = nixlore.lib.sshKeys.all;
#   age.secrets.foo.publicKeys = nixlore.lib.sshKeys.all;                      # agenix
#   users.users.josh.openssh.authorizedKeys.keyFiles =
#     builtins.attrValues nixlore.lib.sshKeys.files.josh;
#   environment.etc."my.pub".text = nixlore.lib.sshKeys.keys.josh.syl-ed25519;
#
# Add or rotate a key by dropping a `.pub` file into the user's directory; no
# Nix changes required.
{ lib, ... }:
let
  keysDir = ../keys;

  readKey = path: lib.removeSuffix "\n" (builtins.readFile path);

  pubFilesIn =
    dir:
    lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".pub" name) (builtins.readDir dir);

  userDirs = lib.filterAttrs (_: type: type == "directory") (builtins.readDir keysDir);

  # { <user> = { <name> = /path/to/keys/<user>/<name>.pub; }; }
  files = lib.mapAttrs (
    user: _:
    lib.mapAttrs' (
      file: _: lib.nameValuePair (lib.removeSuffix ".pub" file) (keysDir + "/${user}/${file}")
    ) (pubFilesIn (keysDir + "/${user}"))
  ) userDirs;
in
{
  flake.lib.sshKeys = rec {
    inherit files;

    # { <user> = { <name> = "ssh-ed25519 AAAA... comment"; }; }
    keys = lib.mapAttrs (_: lib.mapAttrs (_: readKey)) files;

    # { <user> = [ "ssh-ed25519 ..." ... ]; }
    users = lib.mapAttrs (_: lib.attrValues) keys;

    # [ "ssh-ed25519 ..." ... ] across every user
    all = lib.concatLists (lib.attrValues users);
  };

  # Fails `nix flake check` if any .pub file is not a parseable public key.
  perSystem =
    { pkgs, ... }:
    {
      checks.ssh-keys = pkgs.runCommand "check-ssh-keys" { nativeBuildInputs = [ pkgs.openssh ]; } ''
        for f in ${keysDir}/*/*.pub; do
          echo "checking $f"
          ssh-keygen -l -f "$f"
        done
        touch $out
      '';
    };
}
