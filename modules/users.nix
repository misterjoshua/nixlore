# One OpenSSH authorized_keys file per person, exposed as data:
#
#   users/<user>/authorized_keys  ->  lib.users.<user> = {
#     sshKeys = [ ... ];            # the key lines, in file order
#     authorizedKeysFile = <path>;  # the file itself, for openssh.authorizedKeys.keyFiles
#   }
#
# The file is the source of truth: sshd, curl and `keyFiles` read it as
# it is, and this module only parses it. `#` lines and blank lines are
# prose. A key line is `<type> <base64> [comment]` with no options
# prefix. Nothing in the result is a function, so
# `nix eval --json .#lib.users` works from any shell.
#
# Order is kept. Consumers put these lines into files whose hash is part
# of a system closure, so a new key is appended at the end.
#
# A new file must be git-added before the flake can see it.
{ lib, ... }:
let
  usersDir = ../users;

  keyTypes = [
    "ssh-ed25519"
    "ssh-rsa"
    "ecdsa-sha2-nistp256"
    "ecdsa-sha2-nistp384"
    "ecdsa-sha2-nistp521"
    "sk-ssh-ed25519@openssh\\.com"
    "sk-ecdsa-sha2-nistp256@openssh\\.com"
  ];
  keyLine = "(${lib.concatStringsSep "|" keyTypes})[ \t]+([A-Za-z0-9+/]+={0,2})([ \t]+.*)?";

  readUser =
    user:
    let
      rel = "users/${user}/authorized_keys";
      file = usersDir + "/${user}/authorized_keys";
      fail = n: msg: throw "${rel}:${toString n}: ${msg}";

      # Numbered before filtering, so an error cites the real line.
      lines = lib.imap1 (n: text: {
        inherit n;
        line = lib.trim text;
      }) (lib.splitString "\n" (builtins.readFile file));
      keys = lib.filter ({ line, ... }: line != "" && !lib.hasPrefix "#" line) lines;
      parsed = map (
        { n, line }:
        let
          m = lib.match keyLine line;
        in
        if m == null then
          fail n "not an OpenSSH public key line"
        else
          {
            inherit n line;
            id = "${lib.head m} ${lib.elemAt m 1}";
          }
      ) keys;

      # The same type and blob is the same key, whatever the comment says.
      # foldl' forces every step, so forcing `seen` validates every line.
      seen = lib.foldl' (
        acc: k:
        if acc ? ${k.id} then
          fail k.n "duplicate of line ${toString acc.${k.id}}"
        else
          acc // { ${k.id} = k.n; }
      ) { } parsed;
    in
    if lib.match "[a-z_][a-z0-9_-]*" user == null then
      throw "users/${user}: directory name must be a lowercase identifier"
    else if !builtins.pathExists file then
      throw "${rel}: missing"
    else if parsed == [ ] then
      throw "${rel}: no keys"
    else
      builtins.seq seen {
        sshKeys = map (k: k.line) parsed;
        authorizedKeysFile = file;
      };

  users = lib.mapAttrs (
    user: type: if type == "directory" then readUser user else throw "users/${user}: not a directory"
  ) (builtins.readDir usersDir);
in
{
  # `lib` has no flake-parts type. attrsOf raw: one definition per name, so
  # another module can add lib.<other> beside users.
  options.flake.lib = lib.mkOption {
    type = lib.types.attrsOf lib.types.raw;
    default = { };
  };

  config = {
    flake.lib.users = users;

    # `nix flake check` does not evaluate `lib`; interpolating every key
    # here is what makes the throws above fail the check. ssh-keygen -l on
    # a whole authorized_keys file exits 0 if any line parses, so keys go
    # one at a time.
    perSystem =
      { pkgs, ... }:
      {
        checks.users = pkgs.runCommand "check-users" { nativeBuildInputs = [ pkgs.openssh ]; } ''
          set -eu
          ${lib.concatStrings (
            lib.mapAttrsToList (
              user:
              { sshKeys, ... }:
              lib.concatMapStrings (key: ''
                echo ${lib.escapeShellArg "users/${user}: ${key}"}
                printf '%s\n' ${lib.escapeShellArg key} | ssh-keygen -l -f -
              '') sshKeys
            ) users
          )}
          touch "$out"
        '';
      };
  };
}
