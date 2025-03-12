# ObservabilityCommands.md Guide for Command to run scripts

## Commands

## setup_loki_grafana
- sudo bash setup_loki_grafana.sh install/uninstall

## setup_vector
- ./setup_vector.sh install processor-logs vector_loki_grafana.toml

## setup_elastic_kibana
- sudo ./setup_vector.sh install vector_elastic_kibana.toml

## check transmissibility between servers
- For Loki-Grafana : curl -v http://<Server-Ip>:<Loki_port>/ready
               o/p : Ready/wait 15 secs


- For Elastic-Kibana : curl -XGET http://<Server-Ip>:<Elastic-Port>
                 o/p : 
{
  "name" : "Dev-plugin-common-server-2",
  "cluster_name" : "elasticsearch",
  "cluster_uuid" : "DIwvclO9Sy65tkF9VXBpiw",
  "version" : {
    "number" : "8.17.3",
    "build_flavor" : "default",
    "build_type" : "rpm",
    "build_hash" : "a091390de485bd4b127884f7e565c0cad59b10d2",
    "build_date" : "2025-02-28T10:07:26.089129809Z",
    "build_snapshot" : false,
    "lucene_version" : "9.12.0",
    "minimum_wire_compatibility_version" : "7.17.0",
    "minimum_index_compatibility_version" : "7.0.0"
  },
  "tagline" : "You Know, for Search"
}

## check connectivity between servers

- telnet <Server-Ip> <Port-No>