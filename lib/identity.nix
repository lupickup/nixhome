# mkIdentityProfile — build a Home Manager module for one git/SSH identity.
#
# An identity is data: an email, an SSH key name and, optionally, the
# literal public key an agent holds. The module this returns
#   - always writes ~/<name>.gitconfig, so per-gitdir includes can select
#     the identity on any host, and
#   - when `dotfiles.context.identity == name`, sets the top-level git
#     user, email and signing key.
#
# Private overlays call it with their own values; nothing here names an
# organisation.
#
#   (lib.mkIdentityProfile {
#     name = "work";
#     fullName = "Ada Lovelace";
#     email = "ada@example.com";
#     keyName = "work";                 # ~/.ssh/work or ~/.ssh/work.pub
#     publicKey = "ssh-ed25519 AAAA…";  # optional; used where an agent signs
#     description = "# Work repos (~/repos/work/)";
#   })
{ lib }:

{
  mkIdentityProfile =
    { name
    , email
    , fullName ? ""
    , keyName ? name
    , publicKey ? null
      # Signing key written inside ~/<name>.gitconfig on hosts with an SSH
      # agent: "path" (~/.ssh/<keyName>.pub) or "publicKey" (the literal key).
    , fileSigningKey ? "path"
    , description ? "# ${name} identity"
    , extraGitConfig ? ""
    }:
    assert lib.assertMsg (builtins.elem fileSigningKey [ "path" "publicKey" ])
      "mkIdentityProfile ${name}: fileSigningKey must be \"path\" or \"publicKey\"";
    { config, lib, ... }:
    let
      ctx = config.dotfiles.context;
      homeDir = config.home.homeDirectory;

      # 1Password / forwarded-agent hosts sign with a public key the agent
      # matches to a held private key; other hosts sign with a key file.
      hasSshAgent =
        ctx.platform == "darwin"
        || ctx.location == "remote"
        || ctx.credentialBackend == "windows-gcm-wsl";

      keyPath = "${homeDir}/.ssh/${keyName}${if hasSshAgent then ".pub" else ""}";
      agentKey = if hasSshAgent && publicKey != null then publicKey else keyPath;
      fileKey = if fileSigningKey == "publicKey" then agentKey else keyPath;

      body = ''
        ${description}
        [user]
            email = ${email}
            signingkey = ${fileKey}

        [gpg]
            format = ssh

        [commit]
            gpgsign = true
      '' + lib.optionalString (extraGitConfig != "") "\n${extraGitConfig}";
    in
    {
      config = lib.mkMerge [
        { modules.home.shell.git.identityFiles.${name} = body; }

        (lib.mkIf (ctx.identity == name) {
          modules.home.shell.git = {
            userName = fullName;
            userEmail = email;
            signing.key = agentKey;
            signing.signByDefault = true;
          };
        })
      ];
    };
}
