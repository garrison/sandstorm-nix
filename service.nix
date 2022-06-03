{ config, lib, pkgs, ... }:
with lib;
let
  cfg = config.services.sandstorm;
  sandstormConfigFile = pkgs.writeText "sandstorm.conf" ''
  SERVER_USER=sandstorm
  PORT=${builtins.toString cfg.httpPort}
  MONGO_PORT=${builtins.toString cfg.mongoPort}
  BIND_IP=127.0.0.1
  BASE_URL=${cfg.baseUrl}
  WILDCARD_HOST=${cfg.wildcardHost}
  UPDATE_CHANNEL=none
  ALLOW_DEV_ACCOUNTS=no
  SMTP_LISTEN_PORT=${builtins.toString cfg.smtpPort}

  '' + optionalString (cfg.httpsPort != 0) "HTTPS_PORT=${cfg.httpsPort}";

  sandstorm = (pkgs.callPackage ./default.nix {}).sandstormWithConfig sandstormConfigFile;
in
{
  options.services.sandstorm = {
    enable = mkEnableOption "Sandstorm application server";
    httpPort = mkOption {
      type = types.port;
      description = "HTTP port to listen on";
      default = 8180;
    };
    httpsPort = mkOption {
      type = types.port;
      description = "HTTPS port to listen on";
      default = 0;
    };
    mongoPort = mkOption {
      type = types.port;
      description = "port for MongoDB to listen on";
      default = 6081;
    };
    smtpPort = mkOption {
      type = types.port;
      description = "SMTP port to listen for mail to grains";
      default = 8125;
    };
    wildcardHost = mkOption {
      type = types.str;
      description = "Wildcard domain name, e.g. '*.example.org'.";
      default = "";
    };
    baseUrl = mkOption {
      type = types.str;
      description = "URL to the landing page for Sandstorm.";
      default = "http://localhost";
    };
  };
  config = mkIf cfg.enable {
    users.users.sandstorm =
      {
        isSystemUser = true;
        group = "sandstorm";
        description = "Sandstom App Server User";
      };
    users.groups.sandstorm = {};
    systemd.services.sandstorm = {
      description = "Sandstorm server";
      after = [ "local-fs.target" "remote-fs.target" "network-online.target" ];
      requires = [  "local-fs.target" "remote-fs.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      preStart = ''
        cd /var/lib/sandstorm
        mkdir -p var/sandstorm/{apps,grains,downloads} var/{log,pid,mongo}
        ln -fs ${sandstorm}/sandstorm.conf .
        rm -rf latest
        mkdir latest
        for dir in $(find ${sandstorm} -type d -empty); do
          mkdir latest/$(basename $dir)
        done
        cp ${sandstorm}/sandstorm latest
        ln -s ${sandstorm}/* latest || true
        ln -fs latest/sandstorm sandstorm
      '';
      serviceConfig = {
        Type = "forking";
        ExecStart = "/var/lib/sandstorm/latest/sandstorm start --verbose";
        ExecStop = "/var/lib/sandstorm/latest/sandstorm stop";
        StateDirectory = "sandstorm";
        WorkingDirectory = "/var/lib/sandstorm";
      };
    };
  };
}
