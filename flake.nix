{
  description = "Neovim compiled to WebAssembly (WASI)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        nvimWasm = pkgs.callPackage ./nix/nvim-wasm.nix {};
      in {
        packages = {
          # Default: full build with both variants (nvim.wasm + nvim-asyncify.wasm)
          default = nvimWasm;
          nvim-wasm = nvimWasm;

          # Asyncify variant for browsers without SharedArrayBuffer
          # Uses Binaryen's asyncify transform for cooperative multitasking via JS event loop
          nvim-wasm-asyncify = pkgs.runCommand "nvim-wasm-asyncify" {} ''
            mkdir -p $out/bin $out/share
            cp ${nvimWasm}/bin/nvim-asyncify.wasm $out/bin/nvim.wasm
            cp -r ${nvimWasm}/share/nvim $out/share/
          '';
        };

        devShells.default = pkgs.mkShell {
          packages = with pkgs; [ lua5_1 curl gnutar git ];
        };
      }
    );
}
