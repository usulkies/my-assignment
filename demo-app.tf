# Demo App
resource "kubernetes_deployment_v1" "demo-app" {
  metadata {
    name = "demo-app"
    labels = {
      app = "demo-app"
    }
  }
  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "demo-app"
      }
    }
    template {
      metadata {
        labels = {
          app = "demo-app"
        }
      }
      spec {
        container {
          name  = "demo-app"
          image = "nginx:latest"
          port {
            container_port = 80
          }
        }
      }
    }
  }
}