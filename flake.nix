{
  # Based on https://github.com/bobvanderlinden/templates/blob/master/ruby/flake.nix
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs { inherit system; };

        ruby = pkgs.ruby_3_3;
        python = pkgs.python313.withPackages (ps: [ ps.rdkit ]);

        gems = pkgs.bundlerEnv {
          name = "anodyne-chrp-gems";
          gemdir = ./.;
          inherit ruby;
        };

        anodyne-chrp =
          pkgs.runCommand "anodyne-chrp-0.1.0"
            {
              nativeBuildInputs = [ pkgs.makeWrapper ];
              meta.mainProgram = "chrp";
            }
            ''
              makeWrapper ${gems.wrappedRuby}/bin/ruby $out/bin/chrp \
                --add-flags ${self}/exe/chrp \
                --prefix PATH : ${
                  pkgs.lib.makeBinPath [
                    pkgs.svgo
                    python
                  ]
                }
            '';
      in
      {
        formatter = pkgs.nixfmt-tree;

        packages = {
          default = anodyne-chrp;
          anodyne-chrp = anodyne-chrp;
        };

        apps.default = flake-utils.lib.mkApp {
          drv = anodyne-chrp;
          exePath = "/bin/chrp";
        };
        devShells.default = pkgs.mkShell {
          packages = (
            ([ anodyne-chrp ])
            ++ (with pkgs; [
              svgo
              ruby_3_3
              python313
              bundler
              bundix
              python313Packages.rdkit
              python313Packages.requests
              python313Packages.beautifulsoup4
            ])
          );
          buildInputs = [
            pkgs.ruby_3_3
            pkgs.bundix
          ];
        };
      }
    ) // { hydraJobs = {
          inherit (self) packages;
        };
};
}
