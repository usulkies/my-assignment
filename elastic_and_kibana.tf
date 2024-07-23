locals {
  elasticsearch_version = "7.17.22"
}

resource "random_password" "elasticsearch_password" {
  length  = 16
  special = true
}

resource "random_password" "kibana_encryptionkey" {
  length  = 32
  special = false
}

resource "kubernetes_secret_v1" "elasticsearch_credentials" {
  metadata {
    name = "elasticsearch-credentials"
  }

  data = {
    username = "elastic"
    password = random_password.elasticsearch_password.result
  }
}

resource "kubernetes_stateful_set_v1" "elasticsearch" {
  metadata {
    name = "elasticsearch"
  }

  spec {
    replicas              = 3
    pod_management_policy = "Parallel"
    update_strategy {
      type = "RollingUpdate"
    }
    service_name = "elasticsearch"
    selector {
      match_labels = {
        app = "elasticsearch"
      }
    }

    template {
      metadata {
        labels = {
          app = "elasticsearch"
        }
      }

      spec {
        security_context {
          fs_group = 1000
        }
        init_container {
          name    = "fix-permissions"
          image   = "busybox"
          command = ["sh", "-c", "chown -R 1000:1000 /usr/share/elasticsearch/data"]
          volume_mount {
            name       = "elasticsearch-data"
            mount_path = "/usr/share/elasticsearch/data"
          }
        }
        container {
          image = "docker.elastic.co/elasticsearch/elasticsearch:${local.elasticsearch_version}"
          name  = "elasticsearch"

          env {
            name  = "discovery.type"
            value = "single-node"
          }
          env {
            name  = "ingest.geoip.downloader.enabled"
            value = "false"
          }
          env {
            name  = "ES_JAVA_OPTS"
            value = "-Xms1g -Xmx2g"
          }
          env {
            name  = "ELASTIC_USERNAME"
            value = "elastic"
          }
          env {
            name = "ELASTIC_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.elasticsearch_credentials.metadata[0].name
                key  = "password"
              }
            }
          }
          security_context {
            run_as_user  = 1000
            run_as_group = 1000
          }
          port {
            container_port = 9200
          }
          volume_mount {
            mount_path = "/usr/share/elasticsearch/config/elasticsearch.yml"
            sub_path   = "elasticsearch.yml"
            name       = "elasticsearch-config"
          }
          volume_mount {
            mount_path = "/usr/share/elasticsearch/data"
            name       = "elasticsearch-data"
          }
          resources {
            requests = {
              cpu    = "1"
              memory = "2Gi"
            }
            limits = {}
          }
          readiness_probe {
            tcp_socket {
              port = 9200
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }
          liveness_probe {
            tcp_socket {
              port = 9200
            }
            initial_delay_seconds = 60
            period_seconds        = 30
          }
        }
        volume {
          name = "elasticsearch-config"
          config_map {
            name = kubernetes_config_map_v1.elastic.metadata[0].name
          }
        }
      }
    }
    volume_claim_template {
      metadata {
        name = "elasticsearch-data"
      }
      spec {
        storage_class_name = "gp3"
        access_modes       = ["ReadWriteOnce"]
        resources {
          requests = {
            storage = "30Gi"
          }
        }
      }
    }
  }
}

resource "kubernetes_config_map_v1" "elastic" {
  metadata {
    name = "elastic"
  }

  data = {
    "elasticsearch.yml" = <<-EOF
    cluster.name: "my-assignment"
    node.name: node-1
    path.data: /usr/share/elasticsearch/data
    http:
      host: 0.0.0.0
      port: 9200
    bootstrap.memory_lock: true
    transport.host: 127.0.0.1
    ingest.geoip.downloader.enabled: false
    xpack.license.self_generated.type: basic
    xpack.security.enabled: true
    xpack.monitoring.enabled: false
    xpack.graph.enabled: false
    xpack.watcher.enabled: false
    xpack.ml.enabled: false
    EOF
  }
}


resource "kubernetes_service_v1" "elasticsearch" {
  metadata {
    name = kubernetes_stateful_set_v1.elasticsearch.metadata[0].name
  }

  spec {
    selector = {
      app = "elasticsearch"
    }
    type = "NodePort"
    port {
      port        = 9200
      target_port = 9200
    }
  }
}


# Kibana
resource "kubernetes_config_map_v1" "kibana-config" {
  metadata {
    name = "kibana-config"
  }

  data = {
    "kibana.yml" = <<-EOF
      server.host: "0.0.0.0"
      elasticsearch.hosts: ["http://elasticsearch:9200"]
      elasticsearch.username: "elastic"
      elasticsearch.password: "${random_password.elasticsearch_password.result}"
      xpack.security.enabled: true
      xpack.security.encryptionKey: "${random_password.kibana_encryptionkey.result}"
      logging.verbose: true
    EOF
  }
}

resource "kubernetes_deployment_v1" "kibana" {
  metadata {
    name = "kibana"
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "kibana"
      }
    }

    template {
      metadata {
        labels = {
          app = "kibana"
        }
      }

      spec {
        container {
          image = "docker.elastic.co/kibana/kibana:${local.elasticsearch_version}"
          name  = "kibana"

          env {
            name  = "ELASTICSEARCH_URL"
            value = "http://elasticsearch:9200"
          }
          env {
            name  = "ELASTICSEARCH_HOSTS"
            value = "http://elasticsearch:9200"
          }
          env {
            name  = "XPACK_SECURITY_ENABLED"
            value = "true"
          }
          env {
            name = "ELASTICSEARCH_USERNAME"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.elasticsearch_credentials.metadata[0].name
                key  = "username"
              }
            }
          }
          env {
            name = "ELASTICSEARCH_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.elasticsearch_credentials.metadata[0].name
                key  = "password"
              }
            }
          }
          env {
            name  = "SERVER_HOST"
            value = "0.0.0.0"
          }
          port {
            container_port = 5601
            name           = "http"
          }
          resources {
            requests = {
              cpu    = "1"
              memory = "2Gi"
            }
            limits = {}
          }
          liveness_probe {
            tcp_socket {
              port = "http"
            }
            initial_delay_seconds = 60
            period_seconds        = 30
          }

          readiness_probe {
            tcp_socket {
              port = "http"
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }

          volume_mount {
            name       = "kibana-tokens"
            mount_path = "/usr/share/kibana/config/tokens"
          }
        }
        volume {
          name = "kibana-tokens"
          empty_dir {}
        }
        volume {
          name = "kibanaconfig"
          config_map {
            name = kubernetes_config_map_v1.kibana-config.metadata[0].name
          }
        }
      }
    }
  }
  depends_on = [kubernetes_service_v1.elasticsearch]
}

resource "kubernetes_service_v1" "kibana" {
  metadata {
    name = "kibana"
  }

  spec {
    selector = {
      app = "kibana"
    }
    type = "NodePort"
    port {
      port        = 5601
      target_port = 5601
    }
  }
}

