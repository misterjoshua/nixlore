# Identities are Nix files under ../keys. The directory says what kind, and
# who owns it; the file only carries what the path cannot.
#
#   keys/users/<user>/<label>.nix
#   keys/hosts/<host>.nix
#   keys/services/<service>/<label>.nix
#
# Consume from another flake via `inputs.nixlore.lib.identities`:
#
#   ids = nixlore.lib.identities;
#   users.users.josh.openssh.authorizedKeys.keys = ids.sshKeys (ids.by { user = "josh"; });
#   users.users.josh.openssh.authorizedKeys.keys = ids.sshKeys (ids.by { gesture = true; });
#   age.secrets.db.publicKeys = ids.sshKeys (ids.by { user = "josh"; host = config.networking.hostName; });
#   programs.ssh.knownHosts.nas.publicKey = ids.hosts.nas.sshHostKey;
#
# `by` ignores fields you leave out and matches null literally when you pass
# it. `.#lib.identities` itself is not JSON (it contains functions); use
# `.#lib.identities.all` or `.#lib.identities.users.<user>`.
#
# Adding an identity is adding a file. hosts/ and services/ may be absent.
{ lib, ... }:
let
  keysDir = ../keys;

  identRegex = "[A-Za-z_][A-Za-z0-9_']*";

  fail = where: msg: throw "keys/${where}: ${msg}";

  entries = dir: if builtins.pathExists dir then builtins.readDir dir else { };

  sorted = names: lib.sort builtins.lessThan names;

  assertIdent =
    where: name:
    if lib.match identRegex name == null then fail where "${name} is not a Nix identifier" else name;

  assertLowerIdent =
    where: name:
    let
      ident = assertIdent where name;
    in
    if ident != lib.toLower ident then fail where "${name} must be lowercase" else ident;

  nixFiles =
    dir:
    sorted (
      lib.mapAttrsToList (
        name: type:
        let
          base = lib.removeSuffix ".nix" name;
        in
        if type != "regular" || !lib.hasSuffix ".nix" name then
          fail dir "${name} is not an identity .nix file"
        else
          assertIdent dir base
      ) (entries (keysDir + "/${dir}"))
    );

  subdirs =
    dir:
    sorted (
      lib.mapAttrsToList (
        name: type:
        if type != "directory" then fail dir "${name} is not a directory" else assertIdent dir name
      ) (entries (keysDir + "/${dir}"))
    );

  singleLine =
    where: value:
    let
      trimmed = lib.trim value;
    in
    if trimmed == "" || lib.hasInfix "\n" trimmed then
      fail where "expected a single non-empty line"
    else
      trimmed;

  load =
    {
      display,
      kind,
      user,
      service,
      name,
      isHost,
    }:
    let
      raw' = import (keysDir + "/${display}");
      raw = if lib.isAttrs raw' then raw' else fail display "identity file must be an attribute set";
      allowed = [
        "host"
        "gesture"
        "githubKeyId"
        "ssh"
        "sshHostKey"
      ];
      unknown = lib.subtractLists allowed (lib.attrNames raw);

      hostFromFile =
        if !(raw ? host) then
          null
        else if !lib.isString raw.host || raw.host == "" || raw.host != lib.toLower raw.host then
          fail display "host must be a non-empty lowercase string"
        else
          raw.host;

      host = if isHost then name else hostFromFile;

      gesture = raw.gesture or false;

      githubKeyId = raw.githubKeyId or null;

      ssh = lib.mapAttrs (
        label: value:
        if !lib.isString value then
          fail display "ssh.${label} must be a string"
        else
          singleLine "${display} ssh.${label}" value
      ) (raw.ssh or { });

      sshHostKey =
        if !(raw ? sshHostKey) then
          null
        else if !lib.isString raw.sshHostKey then
          fail display "sshHostKey must be a string"
        else
          singleLine "${display} sshHostKey" raw.sshHostKey;
    in
    if unknown != [ ] then
      fail display "unknown field ${lib.concatStringsSep ", " unknown}"
    else if isHost && raw ? host then
      fail display "host is the filename; remove the host field"
    else if !isHost && sshHostKey != null then
      fail display "sshHostKey is only allowed on keys/hosts"
    else if !lib.isBool gesture then
      fail display "gesture must be a boolean"
    else if gesture && host != null then
      fail display "a gesture key cannot set host"
    else if githubKeyId != null && !lib.isInt githubKeyId then
      fail display "githubKeyId must be an integer"
    else if !lib.isAttrs (raw.ssh or { }) then
      fail display "ssh must be an attribute set"
    else if ssh == { } && sshHostKey == null then
      fail display "identity has no keys"
    else
      {
        inherit
          kind
          user
          service
          name
          host
          gesture
          githubKeyId
          ssh
          sshHostKey
          ;
      };

  userRecords = lib.concatMap (
    user:
    map (
      name:
      load {
        display = "users/${user}/${name}.nix";
        kind = "user";
        inherit user name;
        service = null;
        isHost = false;
      }
    ) (nixFiles "users/${user}")
  ) (subdirs "users");

  hostRecords = map (
    name:
    let
      hostName = assertLowerIdent "hosts" name;
    in
    load {
      display = "hosts/${hostName}.nix";
      kind = "host";
      user = null;
      service = null;
      name = hostName;
      isHost = true;
    }
  ) (nixFiles "hosts");

  serviceRecords = lib.concatMap (
    service:
    map (
      name:
      load {
        display = "services/${service}/${name}.nix";
        kind = "service";
        user = null;
        inherit service name;
        isHost = false;
      }
    ) (nixFiles "services/${service}")
  ) (subdirs "services");

  all = userRecords ++ hostRecords ++ serviceRecords;

  nest =
    kind: ownerField:
    lib.foldl' (
      acc: id:
      if id.kind != kind then
        acc
      else
        acc
        // {
          ${id.${ownerField}} = (acc.${id.${ownerField}} or { }) // {
            ${id.name} = id;
          };
        }
    ) { } all;

  hosts = lib.listToAttrs (
    map (id: lib.nameValuePair id.name id) (lib.filter (id: id.kind == "host") all)
  );

  queryFields = [
    "kind"
    "user"
    "service"
    "host"
    "gesture"
  ];

  by =
    query:
    let
      unknown = lib.subtractLists queryFields (lib.attrNames query);
      specified = name: builtins.hasAttr name query;
      hostQuery =
        if specified "host" && query.host != null then lib.toLower query.host else query.host or null;
      eq =
        name: value:
        if !specified name then
          true
        else if name == "host" then
          value == hostQuery
        else
          value == query.${name};
    in
    if unknown != [ ] then
      throw "identities.by: unknown field ${lib.concatStringsSep ", " unknown}"
    else if
      specified "kind"
      && query.kind != null
      && !lib.elem query.kind [
        "user"
        "host"
        "service"
      ]
    then
      throw "identities.by: kind must be \"user\", \"host\", or \"service\""
    else
      lib.filter (
        id:
        eq "kind" id.kind
        && eq "user" id.user
        && eq "service" id.service
        && eq "host" id.host
        && eq "gesture" id.gesture
      ) all;

  sshKeys = records: lib.concatMap (id: lib.attrValues id.ssh) records;

  sshMaterial = lib.concatMap (
    id:
    let
      who =
        if id.kind == "user" then
          id.user
        else if id.kind == "service" then
          id.service
        else
          id.host;
    in
    lib.mapAttrsToList (label: key: {
      inherit key;
      where = "${id.kind} ${who} ${id.name} ssh.${label}";
    }) id.ssh
    ++ lib.optional (id.sshHostKey != null) {
      key = id.sshHostKey;
      where = "${id.kind} ${who} ${id.name} sshHostKey";
    }
  ) all;
in
{
  # `lib` has no flake-parts type, so a later module can merge into it.
  options.flake.lib = lib.mkOption {
    type = lib.types.attrsOf lib.types.raw;
    default = { };
  };

  config = {
    flake.lib.identities = {
      users = nest "user" "user";
      inherit hosts;
      services = nest "service" "service";
      inherit
        all
        by
        sshKeys
        ;
    };

    # Fails `nix flake check` unless every SSH public key parses.
    # Schema checks throw while evaluating the identities above.
    perSystem =
      { pkgs, ... }:
      {
        checks.identities = pkgs.runCommand "check-identities" { nativeBuildInputs = [ pkgs.openssh ]; } ''
          set -eu
          ${lib.concatMapStrings ({ where, key }: ''
            echo ${lib.escapeShellArg "checking ${where}"}
            printf '%s\n' ${lib.escapeShellArg key} > key.pub
            ssh-keygen -l -f key.pub
          '') sshMaterial}
          touch "$out"
        '';
      };
  };
}
