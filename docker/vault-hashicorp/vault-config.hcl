storage "raft" {
  path    = "/vault/file"
  # node_id akan di-set via Environment Variable di Docker agar dinamis
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  cluster_address = "0.0.0.0:8201"
  tls_disable = "true"
}

# Alamat API yang bisa diakses publik/internal
api_addr     = "http://{{ GetPrivateIP }}:8200"
cluster_addr = "http://{{ GetPrivateIP }}:8201"
ui = true
