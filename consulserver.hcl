node_name = "server"
data_dir = "serverdata"
bootstrap = true
server = true
log_level = "DEBUG"

acl {
  enabled = true
  enable_token_persistence = true
  default_policy = "deny"
  tokens {
    initial_management = "root"
  }
}

tls {
  defaults {
    ca_file   = "consul-agent-ca.pem"
    key_file  = "dc1-server-consul-0-key.pem"
    cert_file = "dc1-server-consul-0.pem"
    verify_incoming = true
    verify_outgoing = true
  }
  internal_rpc {
    verify_server_hostname = true
  }
}
ports {
  https = 8501
}
auto_encrypt {
  allow_tls = true
}

bind_addr   = "127.0.0.1"
client_addr = "127.0.0.1"