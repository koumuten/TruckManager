# To learn more about how to use Nix to configure your environment
# see: https://developers.google.com/idx/guides/customize-idx-env
{ pkgs, ... }: {
  # Which nixpkgs channel to use.
  channel = "stable-23.11"; # or "unstable"

  # Use https://search.nixos.org/packages to find packages
  packages = [
    pkgs.nodePackages.firebase-tools
    pkgs.jdk17
    pkgs.unzip
    pkgs.dart
    pkgs.flutter
    pkgs.poppler_utils
    pkgs.nodejs_20
    pkgs.curl
    pkgs.zip
  ];

  # Sets environment variables in the workspace
  env = {};

  idx = {
    # Search for the extensions you want on https://open-vsx.org/ and use "publisher.id"
    extensions = [
      "Dart-Code.dart-code"
      "Dart-Code.flutter"
    ];


    # Workspace lifecycle hooks
    workspace = {
      # Runs when a workspace is first created
onCreate = {
    };
      # Runs when the workspace is (re)started
      onStart = {
        # Example: start a continuous build process
        # build-flutter = "flutter build web";
      };
    };
  };
}