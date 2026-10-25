# Server packages for the Debian Nidrew server: Harmonia and Skopeo from one
# pinned nixpkgs revision, recorded in the committed flake.lock. Agent images
# keep their own pins. Update the lock only with update-server-lock.sh.
{
  description = "Nidrew server packages";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

  outputs =
    { nixpkgs, ... }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
    in
    {
      packages.x86_64-linux = {
        inherit (pkgs) harmonia skopeo;
        # Installed by apply-nix-config.sh as the nidrew-server system profile.
        default = pkgs.buildEnv {
          name = "nidrew-server";
          paths = [
            pkgs.harmonia
            pkgs.skopeo
          ];
        };
      };
    };
}
