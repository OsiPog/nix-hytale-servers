{
  lib,
  config,
  pkgs,
  flake,
  ...
}: let
  inherit (builtins) concatStringsSep;
  inherit (lib) mkIf mkOption mkEnableOption types optionals;

  cfg = config.services.hytale-server;
in {
  options.services.hytale-server = {
    enable = mkEnableOption "Hytale game server";
    user = mkOption {
      description = "The user the server will be run as.";
      type = types.str;
      default = "hytale";
    };
    group = mkOption {
      description = "The group under which the server will be run.";
      type = types.str;
      default = "hytale";
    };
    stateDir = mkOption {
      description = "The directory where the server files will be created.";
      type = types.pathWith {absolute = true;};
      default = "/var/lib/hytale-server";
    };
    port = mkOption {
      description = "The UDP port the server will be bound to";
      type = types.port;
      default = 5520;
    };
    hytaleDownloaderCredentialsFile = mkOption {
      description = "Path to the JSON file created by the hytale-downloader program. Required to download the server files. Make sure that the configured user can see the file.";
      type = types.pathWith {absolute = true;};
    };
    extraJvmOpts = mkOption {
      description = "Additional options passed to the java command that runs the server.";
      type = with types; listOf str;
      default = [];
      example = ["-Xms6G" "-Xmx6G"];
    };
    useRecommendedJvmOpts = mkEnableOption "using the recommended JVM options from https://github.com/RVSkeLe/Hytale-SelfHosted";
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [
      (pkgs.writeShellApplication {
        name = "hytale-server-cmd";
        text = ''
          echo "$@" > /run/hytale.stdin
        '';
      })
    ];

    users = {
      users.hytale = mkIf (cfg.user == "hytale") {
        group = cfg.group;
        home = cfg.stateDir;
        createHome = true;
        homeMode = "0770";
        isSystemUser = true;
      };
      groups.hytale = mkIf (cfg.user == "hytale") {};
    };

    systemd = {
      services.hytale-server = {
        wantedBy = ["multi-user.target"];
        requires = ["hytale-server.socket"];
        partOf = ["hytale-server.socket"];
        after = ["network.target" "hytale-server.socket"];
        path = with pkgs; [
          javaPackages.compiler.openjdk25
          unzip
        ];
        script = ''
          cd ${cfg.stateDir}
          ${lib.getExe flake.packages.${pkgs.system}.hytale-downloader} \
            -skip-update-check \
            -download-path download.zip \
            -credentials-path ${cfg.hytaleDownloaderCredentialsFile}

          unzip download.zip
          rm download.zip

          java \
            -XX:AOTCache=HytaleServer.aot \
            ${concatStringsSep " " (cfg.extraJvmOpts
            ++ (optionals cfg.useRecommendedJvmOpts [
              "-XX:AOTCache=HytaleServer.aot"
              "-XX:+UseCompactObjectHeaders"
              "-Xms6G -Xmx6G"
              "-XX:+UseG1GC"
              "-XX:+ParallelRefProcEnabled"
              "-XX:MaxGCPauseMillis=200"
              "-XX:+UnlockExperimentalVMOptions"
              "-XX:+DisableExplicitGC"
              "-XX:+AlwaysPreTouch"
              "-XX:G1HeapWastePercent=5"
              "-XX:G1MixedGCCountTarget=4"
              "-XX:InitiatingHeapOccupancyPercent=15"
              "-XX:G1MixedGCLiveThresholdPercent=90"
              "-XX:G1RSetUpdatingPauseTimePercent=5"
              "-XX:SurvivorRatio=32"
              "-XX:+PerfDisableSharedMem"
              "-XX:MaxTenuringThreshold=1"
              "-Dusing.aikars.flags=https://mcflags.emc.gs"
              "-Daikars.new.flags=true -XX:G1NewSizePercent=30"
              "-XX:G1MaxNewSizePercent=40"
              "-XX:G1HeapRegionSize=8M"
              "-XX:G1ReservePercent=20"
            ]))}
            -jar HytaleServer.jar \
            --assets Assets.zip \
            --bind 0.0.0.0:${toString cfg.port} \
        '';
        serviceConfig = {
          Type = "simple";
          User = cfg.user;
          Group = cfg.group;
          StandardInput = "socket";
          StandardOutput = "journal";
          StandardError = "journal";
        };
      };
      sockets.hytale-server = {
        requires = ["hytale-server.service"];
        partOf = ["hytale-server.service"];
        socketConfig = {
          ListenFIFO = "/run/hytale-server.stdin";
          SocketMode = "0660";
          SocketUser = cfg.user;
          SocketGroup = cfg.group;
          RemoveOnStop = true;
          FlushPending = true;
        };
      };
    };
  };
}
