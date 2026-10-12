# nixlore

josh's SSH public keys, as plain OpenSSH `authorized_keys` files that a Nix
flake also exposes as data. Nothing in this repository is secret: every key
is a public half, and the private halves live in a vault, not on any
machine's disk.

## Layout

```
users/<user>/authorized_keys   one key per line; `#` lines are prose
modules/users.nix              reads users/, exposes lib.users, defines checks.users
modules/*.nix                  the rest is tooling: devshell, formatter, git hooks
```

The file is the source of truth and its order is kept everywhere.
Consumers put these lines into files whose hash is part of a system
closure, so a new key is appended at the end and existing lines are not
reordered.

## Consuming

### From Nix

```nix
inputs.nixlore.url = "github:misterjoshua/nixlore";

# in a NixOS module
users.users.josh.openssh.authorizedKeys.keys = inputs.nixlore.lib.users.josh.sshKeys;
# or as a file
users.users.josh.openssh.authorizedKeys.keyFiles = [ inputs.nixlore.lib.users.josh.authorizedKeysFile ];
```

`lib.users` is data only:

```nix
lib.users.<user> = {
  sshKeys = [ "ssh-rsa AAAA... comment" ]; # the key lines, in file order
  authorizedKeysFile = <path>; # the file itself
};
```

### From a shell

```sh
nix eval --json github:misterjoshua/nixlore/<commit>#lib.users.josh.sshKeys
```

### With curl

```sh
curl -fsSL https://raw.githubusercontent.com/misterjoshua/nixlore/<commit>/users/josh/authorized_keys
```

## Trust

A public key repository is a trust anchor for whoever reads it. Pin a
commit: a flake lock does this for you, and a URL should carry the full
commit SHA. Nothing should authorize keys from a moving ref such as
`main`, or a compromise of this repository's hosting becomes a login
everywhere it is read live.

Check fingerprints out of band with:

```sh
ssh-keygen -lf users/josh/authorized_keys
```

A key change is a commit here; consumers pick it up by moving their pin
(`nix flake update nixlore`).

## Adding a key

Append the `.pub` line to `users/<user>/authorized_keys` with a comment
that says what it is, then:

```sh
git add -A
nix flake check
```

The check rejects a line with an options prefix, a blob that does not
parse, the same key twice (same type and blob, whatever the comment), and
a user directory that is not a lowercase identifier. A new user is a new
directory with an `authorized_keys` file.

## Why no age recipients

agenix encrypts to SSH public keys directly, RSA and ed25519 alike, so it
needs nothing beyond this file. sops-nix wants age recipients, which
`ssh-to-age` derives from ed25519 keys only; the keys here are RSA today,
so none would yield one.

## Development

```sh
nix develop     # or `direnv allow`; installs the pre-commit hook
nix fmt
nix flake check # treefmt, pre-commit, checks.users
```
