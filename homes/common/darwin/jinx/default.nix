{
  # Snowfall Lib provides a customized `lib` instance with access to your flake's library
  # as well as the libraries available from your flake's inputs.
  lib,
  # An instance of `pkgs` with your overlays and packages applied is also available.
  pkgs,
  # You also have access to your flake's inputs.
  inputs,

  # Additional metadata is provided by Snowfall Lib.
  home, # The home architecture for this host (eg. `x86_64-linux`).
  target, # The Snowfall Lib target for this home (eg. `x86_64-home`).
  format, # A normalized name for the home target (eg. `home`).
  virtual, # A boolean to determine whether this home is a virtual target using nixos-generators.
  host, # The host name for this home.

  # All other arguments come from the home home.
  config,
  ...
}:
{
  # Home Manager needs a bit of information about you and the
  # paths it should manage.
  home.username = "jinx";
  home.homeDirectory = "/Users/jinx";

  home.stateVersion = "24.11";

  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  home.file.".oh-my-zsh/custom/custom.zsh".text = ''
    export SOPS_AGE_KEY_FILE=$HOME/.config/sops/age/keys.txt
  '';

  programs.gpg = {
    enable = true;
    settings.pinentry-mode = "loopback";
  };

  home.file.".gnupg/gpg-agent.conf".text = ''
    default-cache-ttl 28800
    max-cache-ttl 86400
    allow-loopback-pinentry
  '';

  home.file.".git-hooks-global/pre-push" = {
    executable = true;
    text = ''
      #!/bin/sh
      # %G? values: G=good, U=good-untrusted, others=missing/bad
      zero=0000000000000000000000000000000000000000
      status=0
      while read local_ref local_sha remote_ref remote_sha; do
          [ "$local_sha" = "$zero" ] && continue
          if [ "$remote_sha" = "$zero" ]; then
              range="$local_sha --not --remotes"
          else
              range="$remote_sha..$local_sha"
          fi
          bad=$(git log --pretty='%H %G?' $range | awk '$2 != "G" && $2 != "U" { print $1 }')
          if [ -n "$bad" ]; then
              echo "pre-push: refusing — unsigned commits on $local_ref:" >&2
              echo "$bad" | sed 's/^/  /' >&2
              echo "fix: git rebase --exec 'git commit --amend --no-edit -S' <base> && git push --force-with-lease" >&2
              status=1
          fi
      done
      exit $status
    '';
  };

  programs.zsh = {
    enable = true;
    autocd = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    oh-my-zsh = {
      enable = true;
      package = pkgs.oh-my-zsh;
      plugins = [
        "git"
        "sudo"
        "starship"
      ];
      theme = "lukerandall";
      extraConfig = ''
        zstyle ':omz:update' mode reminder
        eval "$(starship init zsh)"
        export PNPM_HOME="$HOME/Library/pnpm"
        export PATH="/Users/jinx/.git-ai/bin:$PNPM_HOME:$HOME/.local/bin:$HOME/.npm-global/bin:$HOME/.krew/bin:$PATH:/Library/Frameworks/Python.framework/Versions/Current/bin"
        export ZSH_CUSTOM=~/.oh-my-zsh/custom
        eval "$(direnv hook zsh)"
        source "$HOME/.cargo/env"
        export GPG_TTY=$(tty)
        gpgconf --launch gpg-agent 2>/dev/null
      '';
    };
  };
}
