{
  lib,
  inputs,
  ...
}:

final: prev:
{
  inherit inputs;

  oh-my-zsh = prev.callPackage ../../packages/oh-my-zsh { };
}