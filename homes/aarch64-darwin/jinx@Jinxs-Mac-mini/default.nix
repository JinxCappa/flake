{lib, ...}:
let
  toml = lib.importTOML ../../../secrets/crypt.toml;
in
{
  imports = [
    ../../common/darwin/jinx/default.nix
  ];

  programs.zsh.oh-my-zsh.extraConfig = lib.mkAfter ''
    export BAO_ADDR=${toml.openbao.publicUrl}
  '';
}