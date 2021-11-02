{ config, lib, pkgs, ...}:
with lib;
let
  cfg = config.services.hadoop;
  hadoopConf = "${import ./conf.nix { inherit cfg pkgs lib; }}/";
  restartIfChanged  = mkOption {
    type = types.bool;
    description = ''
      Automatically restart the service on config change.
      This can be set to false to defer restarts on clusters running critical applications.
      Please consider the security implications of inadvertently running an older version,
      and the possibility of unexpected behavior caused by inconsistent versions across a cluster when disabling this option.
    '';
    default = false;
  };
in
{
  options.services.hadoop.hdfs = {
    namenode = {
      enabled = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether to run the HDFS NameNode
        '';
      };
      formatOnInit = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Format HDFS namenode on first start. This is useful for quickly spinning up ephemeral HDFS clusters with a single namenode.
          For HA clusters, initialization involves multiple steps across multiple nodes. Follow [this guide](https://hadoop.apache.org/docs/stable/hadoop-project-dist/hadoop-hdfs/HDFSHighAvailabilityWithQJM.html)
          to initialize an HA cluster manually.
        '';
      };
      inherit restartIfChanged;
      openFirewall = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Open firewall ports for namenode
        '';
      };
    };
    datanode = {
      enabled = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether to run the HDFS DataNode
        '';
      };
      inherit restartIfChanged;
      openFirewall = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Open firewall ports for datanode
        '';
      };
    };
    journalnode = {
      enabled = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether to run the HDFS JournalNode
        '';
      };
      inherit restartIfChanged;
      openFirewall = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Open firewall ports for journalnode
        '';
      };
    };
    zkfc = {
      enabled = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Whether to run the HDFS ZooKeeper failover controller
        '';
      };
      inherit restartIfChanged;
    };
  };

  config = mkMerge [
    (mkIf cfg.hdfs.namenode.enabled {
      systemd.services.hdfs-namenode = {
        description = "Hadoop HDFS NameNode";
        wantedBy = [ "multi-user.target" ];
        inherit (cfg.hdfs.namenode) restartIfChanged;

        preStart = (mkIf cfg.hdfs.namenode.formatOnInit ''
          ${cfg.package}/bin/hdfs --config ${hadoopConf} namenode -format -nonInteractive || true
        '');

        serviceConfig = {
          User = "hdfs";
          SyslogIdentifier = "hdfs-namenode";
          ExecStart = "${cfg.package}/bin/hdfs --config ${hadoopConf} namenode";
          Restart = "always";
        };
      };

      networking.firewall.allowedTCPPorts = (mkIf cfg.hdfs.namenode.openFirewall [
        9870 # namenode.http-address
        8020 # namenode.rpc-address
        8022 # namenode. servicerpc-address
      ]);
    })
    (mkIf cfg.hdfs.datanode.enabled {
      systemd.services.hdfs-datanode = {
        description = "Hadoop HDFS DataNode";
        wantedBy = [ "multi-user.target" ];
        inherit (cfg.hdfs.datanode) restartIfChanged;

        serviceConfig = {
          User = "hdfs";
          SyslogIdentifier = "hdfs-datanode";
          ExecStart = "${cfg.package}/bin/hdfs --config ${hadoopConf} datanode";
          Restart = "always";
        };
      };

      networking.firewall.allowedTCPPorts = (mkIf cfg.hdfs.datanode.openFirewall [
        9864 # datanode.http.address
        9866 # datanode.address
        9867 # datanode.ipc.address
      ]);
    })
    (mkIf cfg.hdfs.journalnode.enabled {
      systemd.services.hdfs-journalnode = {
        description = "Hadoop HDFS JournalNode";
        wantedBy = [ "multi-user.target" ];
        inherit (cfg.hdfs.journalnode) restartIfChanged;

        serviceConfig = {
          User = "hdfs";
          SyslogIdentifier = "hdfs-journalnode";
          ExecStart = "${cfg.package}/bin/hdfs --config ${hadoopConf} journalnode";
          Restart = "always";
        };
      };

      networking.firewall.allowedTCPPorts = (mkIf cfg.hdfs.datanode.openFirewall [
        8480 # dfs.journalnode.http-address
        8485 # dfs.journalnode.rpc-address
      ]);
    })
    (mkIf cfg.hdfs.zkfc.enabled {
      systemd.services.hdfs-zkfc = {
        description = "Hadoop HDFS ZooKeeper failover controller";
        wantedBy = [ "multi-user.target" ];
        inherit (cfg.hdfs.zkfc) restartIfChanged;

        serviceConfig = {
          User = "hdfs";
          SyslogIdentifier = "hdfs-zkfc";
          ExecStart = "${cfg.package}/bin/hdfs --config ${hadoopConf} zkfc";
          Restart = "always";
        };
      };
    })
    (mkIf (
        cfg.hdfs.namenode.enabled || cfg.hdfs.datanode.enabled || cfg.hdfs.journalnode.enabled || cfg.hdfs.zkfc.enabled
    ) {
      users.users.hdfs = {
        description = "Hadoop HDFS user";
        group = "hadoop";
        uid = config.ids.uids.hdfs;
      };
    })

  ];
}
