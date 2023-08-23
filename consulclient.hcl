node_name = "client"
data_dir = "clientdata"
log_level = "DEBUG"

acl {
  enabled = true
  enable_token_persistence = true
  default_policy = "deny"
  tokens {
    agent = "33e46602-3323-4da8-5546-ef16bab2e658"
  }
}

tls {
  defaults {
    ca_file = "consul-agent-ca.pem"
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
  tls = true
}
retry_join = ["127.0.0.1"]

bind_addr   = "127.0.0.2"
client_addr = "127.0.0.2"