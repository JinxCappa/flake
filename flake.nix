{
  description = "Jinx Flakes";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";

    vscode-server = {
      url = "github:nix-community/nixos-vscode-server";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    snowfall-lib = {
      url = "github:snowfallorg/lib";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    darwin = {
      url = "github:lnl7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-anywhere = {
      url = "github:numtide/nixos-anywhere";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.disko.follows = "disko";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nix-rage = {
      url = "github:renesat/nix-rage";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs: 
    let
      lib = inputs.snowfall-lib.mkLib {
        inherit inputs;

        src = ./.;

        snowfall = {
          root = ./.;

          namespace = "aulogix";

          meta = {
            name = "jinx-flake";

            title = "Jinx Flake";
          };
        };
      };
    in
      lib.mkFlake {
        overlays = with inputs; [
          # my-inputs.overlays.my-overlay
        ];
        
        systems.modules.nixos = with inputs; [
          disko.nixosModules.disko
          home-manager.nixosModules.home-manager
          vscode-server.nixosModules.default
          sops-nix.nixosModules.sops
        ];

        homes.modules = with inputs; [
          sops-nix.homeManagerModules.sops
        ];

        deploy = lib.mkDeploy {inherit (inputs) self;};

        checks =
          builtins.mapAttrs
          (system: deploy-lib:
            deploy-lib.deployChecks inputs.self.deploy)
          inputs.deploy-rs.lib;
      };
}
