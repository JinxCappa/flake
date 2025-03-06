{
  lib,
  inputs,
  ...
}:

final: prev:
{
  inherit inputs;

  vector = prev.callPackage ../../packages/vector { };
}