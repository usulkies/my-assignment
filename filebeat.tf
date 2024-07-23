resource "kubernetes_service_account_v1" "filebeat" {
  metadata {
    name      = "filebeat"
    namespace = "kube-system"
    labels = {
      k8s-app = "filebeat"
    }
  }
}

resource "kubernetes_cluster_role_v1" "filebeat" {
  metadata {
    name = "filebeat"
    labels = {
      k8s-app = "filebeat"
    }
  }
  rule {
    api_groups = [""]
    resources  = ["namespaces", "pods", "nodes"]
    verbs      = ["get", "watch", "list"]
  }
  rule {
    api_groups = ["apps"]
    resources  = ["replicasets"]
    verbs      = ["get", "list", "watch"]
  }
  rule {
    api_groups = ["batch"]
    resources  = ["jobs"]
    verbs      = ["get", "list", "watch"]
  }
}
resource "kubernetes_role_v1" "filebeat" {
  metadata {
    name      = "filebeat"
    namespace = "kube-system"
    labels = {
      k8s-app = "filebeat"
    }
  }
  rule {
    api_groups = ["coordination.k8s.io"]
    resources  = ["leases"]
    verbs      = ["get", "create", "update"]
  }
}
resource "kubernetes_role_v1" "filebeat-kubeadm-config" {
  metadata {
    name      = "filebeat-kubeadm-config"
    namespace = "kube-system"
    labels = {
      k8s-app = "filebeat"
    }
  }
  rule {
    api_groups     = [""]
    resources      = ["configmaps"]
    resource_names = ["kubeadm-config"]
    verbs          = ["get"]
  }
}
resource "kubernetes_cluster_role_binding_v1" "filebeat" {
  metadata {
    name = "filebeat"
  }
  subject {
    kind      = "ServiceAccount"
    name      = "filebeat"
    namespace = "kube-system"
  }
  role_ref {
    kind      = "ClusterRole"
    name      = "filebeat"
    api_group = "rbac.authorization.k8s.io"
  }
}
resource "kubernetes_role_binding_v1" "filebeat" {
  metadata {
    name      = "filebeat"
    namespace = "kube-system"
  }
  subject {
    kind      = "ServiceAccount"
    name      = "filebeat"
    namespace = "kube-system"
  }
  role_ref {
    kind      = "Role"
    name      = "filebeat"
    api_group = "rbac.authorization.k8s.io"
  }
}
resource "kubernetes_role_binding_v1" "filebeat-kubeadm-config" {
  metadata {
    name      = "filebeat-kubeadm-config"
    namespace = "kube-system"
  }
  subject {
    kind      = "ServiceAccount"
    name      = "filebeat"
    namespace = "kube-system"
  }
  role_ref {
    kind      = "Role"
    name      = "filebeat-kubeadm-config"
    api_group = "rbac.authorization.k8s.io"
  }
}
resource "kubernetes_config_map_v1" "filebeat-config" {
  metadata {
    name      = "filebeat-config"
    namespace = "kube-system"
    labels = {
      k8s-app = "filebeat"
    }
  }
  data = {
    "filebeat.yml" = <<-EOF
      filebeat.inputs:
      - type: filestream
        id: kubernetes-container-logs
        paths:
          - /var/log/containers/*.log
        parsers:
          - container: ~
        prospector:
          scanner:
            fingerprint.enabled: true
            symlinks: true
        file_identity.fingerprint: ~
        close_inactive: 5m
        close_renamed: true
        close_removed: true
        processors:
          - add_kubernetes_metadata:
              host: $${NODE_NAME}
              default_indexers.enabled: true
              default_matchers.enabled: true

      processors:
        - add_host_metadata:

      output.elasticsearch:
        hosts: ['$${ELASTICSEARCH_HOST:elasticsearch}:$${ELASTICSEARCH_PORT:9200}']
        username: $${ELASTICSEARCH_USERNAME}
        password: $${ELASTICSEARCH_PASSWORD}

      logging:
        level: debug
  EOF
  }
}
resource "kubernetes_daemon_set_v1" "filebeat" {
  metadata {
    name      = "filebeat"
    namespace = "kube-system"
    labels = {
      k8s-app = "filebeat"
    }
  }
  spec {
    selector {
      match_labels = {
        k8s-app = "filebeat"
      }
    }
    template {
      metadata {
        labels = {
          k8s-app = "filebeat"
        }
      }
      spec {
        service_account_name             = "filebeat"
        termination_grace_period_seconds = 30
        host_network                     = true
        dns_policy                       = "ClusterFirstWithHostNet"
        container {
          name  = "filebeat"
          image = "docker.elastic.co/beats/filebeat:8.14.3"
          args  = ["-c", "/etc/filebeat.yml", "-e"]
          env {
            name  = "ELASTICSEARCH_HOST"
            value = "elasticsearch.default.svc"
          }
          env {
            name  = "ELASTICSEARCH_PORT"
            value = "9200"
          }
          env {
            name  = "ELASTICSEARCH_USERNAME"
            value = "elastic"
          }
          env {
            name  = "ELASTICSEARCH_PASSWORD"
            value = random_password.elasticsearch_password.result
          }
          env {
            name  = "ELASTIC_CLOUD_ID"
            value = ""
          }
          env {
            name  = "ELASTIC_CLOUD_AUTH"
            value = ""
          }
          env {
            name = "NODE_NAME"
            value_from {
              field_ref {
                field_path = "spec.nodeName"
              }
            }
          }
          security_context {
            run_as_user = 0
          }
          resources {
            limits = {}
            requests = {
              cpu    = "200m"
              memory = "200Mi"
            }
          }
          volume_mount {
            name       = "config"
            mount_path = "/etc/filebeat.yml"
            read_only  = true
            sub_path   = "filebeat.yml"
          }
          volume_mount {
            name       = "data"
            mount_path = "/usr/share/filebeat/data"
          }
          volume_mount {
            name       = "varlibdockercontainers"
            mount_path = "/var/lib/docker/containers"
            read_only  = true
          }
          volume_mount {
            name       = "varlog"
            mount_path = "/var/log"
            read_only  = true
          }
        }
        volume {
          name = "config"
          config_map {
            name = kubernetes_config_map_v1.filebeat-config.metadata[0].name
          }
        }
        volume {
          name = "varlibdockercontainers"
          host_path {
            path = "/var/lib/docker/containers"
          }
        }
        volume {
          name = "varlog"
          host_path {
            path = "/var/log"
          }
        }
        volume {
          name = "data"
          host_path {
            path = "/var/lib/filebeat-data"
            type = "DirectoryOrCreate"
          }
        }
      }
    }
  }
}
