# The grove-infra service account, as it runs on trunk01. The private half
# is an agenix secret in grove-infra (secrets/grove-warden-ssh-key.age),
# decrypted onto that host alone.
{
  host = "trunk01";
  ssh.ed25519 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILAgvXZq0F9hFmjXXx4X2EEdNR6lO+rqnwv8xnRzn996 grove-warden@trunk01";
}
