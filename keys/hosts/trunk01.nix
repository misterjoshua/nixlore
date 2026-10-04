# trunk01's sshd host key (ssh-keyscan -t ed25519 trunk01.lan). grove-infra
# encrypts its agenix secrets to this, so the host decrypts them with
# /etc/ssh/ssh_host_ed25519_key. A reinstall regenerates the key: update
# this file and re-key the secrets.
{
  sshHostKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMg3O/SBquc0gnZTCWP3cFp6HOKVyXJR9r8tyG4D4kh6";
}
