# Start with a version of nixpkgs that includes ekam
# https://github.com/NixOS/nixpkgs/pull/141064
{ pkgs ? import (builtins.fetchTarball {
  name = "nixpkgs-unstable-2021-10-22";
  url = "https://github.com/NixOS/nixpkgs/archive/1cab3e231b41f38f2d2cbf5617eb7b88e433428a.tar.gz";
  sha256 = "18h0csq9180yb9v5k713cq645pfwpx2fs21vj2nb3img3y9xr149";
}) {} }:

with pkgs;
stdenv.mkDerivation rec {
  pname = "sandstorm";
  version = "0.289";

  # leaveDotGit is not completely deterministic; the sha256 below *seems*
  # to change when a commit is added to the master branch of sandstorm
  # :-/
  # https://github.com/NixOS/nixpkgs/issues/8567
  src = fetchgit {
    url = "https://github.com/sandstorm-io/sandstorm.git";
    rev = "v${version}";
    sha256 = "08az9yz0h69ry620skkh4wqr35fkym730ki8an6iw9qhj2z04s8q";
    fetchSubmodules = true;
    leaveDotGit = true;
  };

  nativeBuildInputs = [ git which ekam strace ];

  buildInputs = [
    xz zip unzip
    curl python3 zlib
    meteor discount
    boringssl clang libcap libseccomp libsodium
    zlib.static pkgsStatic.libsodium
    stdenv.glibc.out stdenv.glibc.static
  ];

  patches = [
    ./0001-use-system-llvm.patch
    ./0002-use-system-libsodium.patch
    ./0003-use-system-boringssl.patch
  ];

  postPatch = ''
    # A single capnproto test file expects to be able to write to
    # /var/tmp.  We change it to use /tmp because /var is not available
    # under nix-build.
    substituteInPlace deps/capnproto/c++/src/kj/filesystem-disk-test.c++ \
      --replace "/var/tmp" "/tmp"

    # Use the system-provided ekam
    substituteInPlace Makefile --replace "tmp/ekam-bin -j" "ekam -j"
  '';

  makeFlags = [
    "PARALLEL=$(NIX_BUILD_CORES)"
  ];

  preBuild = ''
    makeFlagsArray+=(LIBS="$NIX_LDFLAGS")

    # NIX_ENFORCE_PURITY prevents ld from linking against anything
    # outside of the nix store -- but ekam builds capnp locally and
    # links against it, so that causes the build to fail. So, we turn
    # this off.
    #
    # See: https://nixos.wiki/wiki/Development_environment_with_nix-shell#Troubleshooting
    unset NIX_ENFORCE_PURITY
  '';

  buildFlags = [ "fast" ];

  installPhase = ''
    mkdir $out
    cp sandstorm-*.tar.xz $out
  '';

  meta = with lib; {
    description = "A self-hostable web productivity suite";
    longDescription = ''
      Sandstorm is an open source project built by a community of
      volunteers with the goal of making it really easy to run open
      source web applications.
    '';
    license = licenses.asl20;
    platforms = [ "x86_64-linux" ];
    maintainers = [ maintainers.evils ];
  };

}
