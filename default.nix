# Start with a version of nixpkgs that includes ekam
# https://github.com/NixOS/nixpkgs/pull/141064
{ pkgs ? import (builtins.fetchTarball {
  name = "nixpkgs-unstable-2021-10-22";
  url = "https://github.com/NixOS/nixpkgs/archive/1cab3e231b41f38f2d2cbf5617eb7b88e433428a.tar.gz";
  sha256 = "18h0csq9180yb9v5k713cq645pfwpx2fs21vj2nb3img3y9xr149";
}) {} }:

with pkgs;
let
  meteor_version = "2.3.5";
  meteor-unpacked = fetchTarball {
    url = "https://s3.amazonaws.com/com.meteor.static/packages-bootstrap/${meteor_version}/meteor-bootstrap-os.linux.x86_64.tar.gz";
    sha256 = "0kcwq3d8s3c5i2kd85y9m8nb4632j7wqvfjh8xlsp6097n2h6c7v";
  };
  meteor-dev_bundle = "${meteor-unpacked}/packages/meteor-tool/${meteor_version}/mt-os.linux.x86_64/dev_bundle";
  meteor-1_8_2 = fetchTarball {
    url = "https://s3.amazonaws.com/com.meteor.static/packages-bootstrap/1.8.2/meteor-bootstrap-os.linux.x86_64.tar.gz";
    sha256 = "02ic6h9xl69d8b8ydh30dvrxcjgn73yx4h438y8gab9v5g9annjc";
  };
  meteor-dev_bundle-icons = "${meteor-1_8_2}/packages/meteor-tool/1.8.2/mt-os.linux.x86_64/dev_bundle";
in
stdenv.mkDerivation rec {
  pname = "sandstorm";
  version = "0.290";

  # leaveDotGit is not completely deterministic; the sha256 below *seems*
  # to change when a commit is added to the master branch of sandstorm
  # :-/
  # https://github.com/NixOS/nixpkgs/issues/8567
  src = fetchgit {
    url = "https://github.com/sandstorm-io/sandstorm.git";
    rev = "v${version}";
    sha256 = "1bxf1b1af0yzp9hxa20wbag3p984f8kala275zcwcirmwr98vwcy";
    fetchSubmodules = true;
    leaveDotGit = true;
  };

  nativeBuildInputs = [ git which ekam strace bison flex ];

  buildInputs = [
    xz zip unzip
    curl python3 zlib
    discount
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

    # Remove one test file, which currently fails under nix
    # https://github.com/garrison/sandstorm-nix/issues/1
    rm deps/node-capnp/src/node-capnp/capnp-test.js

    # A sandstorm test expects /bin/true to exist
    substituteInPlace src/sandstorm/util-test.c++ \
      --replace "/bin/true" "${coreutils}/bin/true"

    # Lots of files expect /usr/bin/env
    substituteInPlace src/bpf_asm/lex-yacc.ekam-rule \
      --replace "/usr/bin/env bash" "${bash}/bin/bash"
    substituteInPlace src/sandstorm/seccomp-bpf/bpf_asm.ekam-rule \
      --replace "/usr/bin/env bash" "${bash}/bin/bash"
    substituteInPlace src/sandstorm/seccomp-bpf/clean-header.ekam-rule \
      --replace "/usr/bin/env bash" "${bash}/bin/bash"
    substituteInPlace deps/node-capnp/build.js \
      --replace "/usr/bin/env node" "${meteor-dev_bundle}/bin/node"

    # Providing the boringssl static libraries explicitly by their
    # filenames seems to be the only way to avoid some "undefined
    # reference" errors.
    substituteInPlace Makefile --replace "-lssl -lcrypto" \
      "${boringssl}/lib/libssl.a ${boringssl}/lib/libcrypto.a"

    # Use the system-provided ekam
    substituteInPlace Makefile --replace "tmp/ekam-bin -j" "ekam -j"
  '';

  makeFlags = [
    "PARALLEL=$(NIX_BUILD_CORES)"
  ];

  preBuild = ''
    cat >find-meteor-dev-bundle.sh <<-EOF
      #!${bash}/bin/bash
      echo ${meteor-dev_bundle}
    EOF
    makeFlagsArray+=(METEOR_DEV_BUNDLE_ICONS="${meteor-dev_bundle-icons}")

    makeFlagsArray+=(CFLAGS="-O2 -Wall -g -I${meteor-dev_bundle}/include/node")
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
