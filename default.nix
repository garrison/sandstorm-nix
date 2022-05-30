# Start with a version of nixpkgs that includes ekam
# https://github.com/NixOS/nixpkgs/pull/141064
{ pkgs ? (import <nixpkgs>) {} }:

with pkgs;
let
  meteor_version = "2.3.5";
  meteor-src = fetchurl {
    url = "https://s3.amazonaws.com/com.meteor.static/packages-bootstrap/${meteor_version}/meteor-bootstrap-os.linux.x86_64.tar.gz";
    hash = "sha256-4ZMj76AOHC2rDP9TfX2BdxtOhcgSFaWmxM4Q1/eV4Ug";
  };

  meteor-2_3_5 = meteor.overrideAttrs (old: {
    version = meteor_version;
    src = meteor-src;
    postFixup = old.postFixup + ''
    substituteInPlace  $out/dev_bundle/lib/node_modules/npm/node_modules/node-gyp/bin/node-gyp.js \
      --replace "/usr/bin/env node" "$out/dev_bundle/bin/node"

    substituteInPlace $out/dev_bundle/bin/npm \
      --replace "/usr/bin/env node" "$out/dev_bundle/bin/node"

    substituteInPlace $out/dev_bundle/bin/npx \
      --replace "/usr/bin/env node" "$out/dev_bundle/bin/node"
    '';
  });
  meteor-dev_bundle = "${meteor-2_3_5}/dev_bundle";
  meteor-nodejs = (runCommand "meteor-nodejs" {} ''
  mkdir -p $out/bin
  ln -sf ${meteor-dev_bundle}/bin/* ${meteor-dev_bundle}/lib/node_modules/.bin/* $out/bin
  '') // {
    src = fetchurl {
      url = "https://nodejs.org/dist/v14.17.5/node-v14.17.5.tar.xz";
      sha256 = "1a0zj505nhpfcj19qvjy2hvc5a7gadykv51y0rc6032qhzzsgca2";
    };
  };
  meteor-1_8_2 = fetchurl {
    url = "https://s3.amazonaws.com/com.meteor.static/packages-bootstrap/1.8.2/meteor-bootstrap-os.linux.x86_64.tar.gz";
    hash = "sha256-t6Z0RRanJE96OG5rtZcAY484qODNHuwwKXxJHzqvzd8=";
  };
  meteor-dev_bundle-icons = "${meteor-1_8_2}/packages/meteor-tool/1.8.2/mt-os.linux.x86_64/dev_bundle";
  version = "0.297";
  sandstorm-src = fetchgit {
    url = "https://github.com/sandstorm-io/sandstorm.git";
    rev = "v${version}";
    hash = "sha256-yt8eQ4T94OgxtZ7iHzvV0PjEBzrUuZ1qabJdN/PvQiM=";
    fetchSubmodules = true;
    leaveDotGit = true;
  };
  shell-node-env-deps = (callPackage ./shell-node-env {
    nodejs = meteor-nodejs;
    sandstorm-source = sandstorm-src + "/shell";
  }).nodeDependencies;
  icons-node-env-deps = (callPackage ./icons-node-env {}).nodeDependencies.override ({
    src = sandstorm-src + "/icons";
  });
  server-node-env-deps = (callPackage ./server-node-env { nodejs = meteor-nodejs; }).nodeDependencies.override ({
    src = meteor-dev_bundle + "/etc";
  });
  shell-meteor-deps = stdenv.mkDerivation {
    name = "sandstorm-shell-meteor-deps";
    src = builtins.path {
      path = sandstorm-src;
      name = "sandstorm-shell-src";
      filter = (name: type: lib.hasPrefix ((builtins.toString sandstorm-src) + "/shell") name);
    };
    buildPhase = ''
    mkdir meteor-home
    mkdir meteor-build
    cp -r --no-preserve=ownership,mode ${shell-node-env-deps}/lib/node_modules shell/node_modules
    export HOME=$PWD/meteor-home
    cp ${./dummy-_icons.scss} shell/client/styles/_icons.scss
    (cd shell; ${meteor-2_3_5}/bin/meteor lint)
    '';
    installPhase = ''
    mkdir $out
    cp -r meteor-home $out
    cp -r shell/.meteor/local $out
    '';
    dontFixup = true;
    outputHashAlgo = "sha256";
    outputHashMode = "recursive";
    outputHash =  "sha256-z2G28evNzEkTwB3lptMwEpBtsdYRva8XrRdQYspgMiY=";
  };
  old-sandstorm = fetchurl {
    url = "https://dl.sandstorm.io/sandstorm-171.tar.xz";
    sha256 = "ebffd643dffeba349f139bee34e4ce33fd9b1298fafc1d6a31eb35a191059a99";
  };
in

stdenv.mkDerivation rec {
  pname = "sandstorm";
  version = "0.297";

  # leaveDotGit is not completely deterministic; the sha256 below *seems*
  # to change when a commit is added to the master branch of sandstorm
  # :-/
  # https://github.com/NixOS/nixpkgs/issues/8567
  src = sandstorm-src;

  nativeBuildInputs = [ git which ekam strace bison flex ];

  buildInputs = [
    xz zip unzip
    curl python3 gnupg zlib
    discount
    boringssl clang libcap libseccomp libsodium
    zlib.static pkgsStatic.libsodium
    stdenv.glibc.out stdenv.glibc.static
  ];

  patches = [
    ./0001-use-system-llvm.patch
    ./0002-use-system-libsodium.patch
    ./0003-use-system-boringssl.patch
    ./0004-copy-node-deps.patch
  ];

  postPatch = ''
    # A single capnproto test file expects to be able to write to
    # /var/tmp.  We change it to use /tmp because /var is not available
    # under nix-build.
    substituteInPlace deps/capnproto/c++/src/kj/filesystem-disk-test.c++ \
      --replace "/var/tmp" "/tmp"

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
    # filenames seems to be the only way to avoid some 'undefined
    # reference' errors.
    substituteInPlace Makefile --replace "-lssl -lcrypto" \
      "${boringssl}/lib/libssl.a ${boringssl}/lib/libcrypto.a"

    # Use the node2nix-built node env
    substituteInPlace Makefile --replace "@SHELL_NODE_MODULES@" "${shell-node-env-deps}/lib/node_modules"
    substituteInPlace Makefile --replace "@ICONS_NODE_MODULES@" "${icons-node-env-deps}/lib/node_modules"
    substituteInPlace Makefile --replace "&& meteor" "&& ${meteor-2_3_5}/bin/meteor"
    # Use the system-provided ekam
    substituteInPlace Makefile --replace "tmp/ekam-bin -j" "${ekam}/bin/ekam -j"

    patchShebangs make-bundle.sh
    substituteInPlace make-bundle.sh --replace "@SERVER_NODE_MODULES@" "${server-node-env-deps}/lib/node_modules"

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

    cp -r --no-preserve=mode,ownership ${shell-meteor-deps}/local shell/.meteor/local
    cp ${old-sandstorm} hack/sandstorm-171.tar.xz
    export HOME=${shell-meteor-deps}/meteor-home USER=nixos HOSTNAME=nixos
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
