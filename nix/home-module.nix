# home-manager module: azoo-key-skkserv as a systemd user service.
#
#   services.azoo-key-skkserv.enable = true;
#
# then point the SKK client at 127.0.0.1:1178. The server always answers in UTF-8, so a client
# that uses one encoding for both directions (libskk / fcitx5-skk) wants incomingCharset = "UTF-8"
# and its server encoding set to UTF-8 as well; macSKK-style clients that send EUC-JP keep the
# EUC-JP default of the other skkservs.
self:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.azoo-key-skkserv;
in
{
  options.services.azoo-key-skkserv = {
    enable = lib.mkEnableOption "azoo-key-skkserv, an skkserv backed by AzooKeyKanaKanjiConverter";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
      defaultText = lib.literalExpression "azoo-key-skkserv.packages.\${system}.default";
      description = "The azoo-key-skkserv package to run.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 1178;
      description = "TCP port to listen on. The server binds 127.0.0.1 only.";
    };

    incomingCharset = lib.mkOption {
      type = lib.types.enum [
        "UTF-8"
        "EUC-JP"
      ];
      default = "UTF-8";
      description = "Encoding the clients send their requests in.";
    };

    inferenceLimit = lib.mkOption {
      type = lib.types.ints.positive;
      default = 3;
      description = "Maximum number of Zenzai (neural) inferences per request.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.user.services.azoo-key-skkserv = {
      Unit.Description = "azoo-key-skkserv (skkserv on 127.0.0.1:${toString cfg.port})";
      Service = {
        ExecStart = lib.escapeShellArgs [
          (lib.getExe cfg.package)
          "--port"
          (toString cfg.port)
          "--incoming-charset"
          cfg.incomingCharset
          "--inference-limit"
          (toString cfg.inferenceLimit)
        ];
        Restart = "on-failure";
        RestartSec = 5;
        # Conversion is interactive, but loading the model is a burst of CPU at login.
        Nice = 5;
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
      };
      Install.WantedBy = [ "default.target" ];
    };
  };
}
