# Auto-Encrypt TLS Tech-mech


The article explains how Auto-encrypt works, Whats are pros and cons. Read up.

:blue_book: What's in :

* Lab setup/Configs
* Working of Auto-encryption
* Demo 
* Summary

 

### Lab Setup : 
Its a local lab on macos, built on loopback. Refer config as below: 

### Configs : 

#### Consul Server : 
```
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
``` 

#### Consul client : 
```
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
``` 

#### Create the CA and the server certs : 
```
consul tls ca create
==> Saved consul-agent-ca.pem
==> Saved consul-agent-ca-key.pem


consul tls cert create -server -dc dc1
==> WARNING: Server Certificates grants authority to become a
    server and access all state in the cluster including root keys
    and all ACL tokens. Do not distribute them to production hosts
    that are not server nodes. Store them as securely as CA keys.
==> Using consul-agent-ca.pem and consul-agent-ca-key.pem
==> Saved dc1-server-consul-0.pem
==> Saved dc1-server-consul-0-key.pem
``` 

#### Run the server and client agents : 
```
./consul agent -config-file consulserver.hcl
./consul agent -config-file consulclient.hcl
``` 

You’ll start to notice multiple ACL auto-encrypt related logs on client like below : 

```
2023-08-10T22:22:18.870+1000 [DEBUG] agent.auto_config: making AutoEncrypt.Sign RPC: addr=127.0.0.1:8300
2023-08-10T22:22:18.887+1000 [ERROR] agent.auto_config: AutoEncrypt.Sign RPC failed: addr=127.0.0.1:8300 error="rpcinsecure error making call: ACL not found"
2023-08-10T22:22:18.887+1000 [ERROR] agent.auto_config: No servers successfully responded to the auto-encrypt request
```

Note: the errors are related to “AutoEncrypt.sign” rpc being failed, and “ACL not found” errors.

 

Consul members show only server as output, and does not show any client joining the cluster : 

#### On consul server:
```
./consul members
Node    Address         Status  Type    Build   Protocol  DC   Partition  Segment
server  127.0.0.1:8301  alive   server  1.13.3  2         dc1  default    <all>

** consul server(127.0.0.1) listening on port 8500
repro_119092 netstat -ant|grep 8500
tcp4       0      0  127.0.0.1.8500         *.*                    LISTEN
```

#### On consul client:
```
./consul members
Error retrieving members: Get "http://127.0.0.2:8500/v1/agent/members?segment=_all": dial tcp 127.0.0.2:8500: connect: connection refused

** consul client(127.0.0.2) not listening on port 8500, despite of client agent running.
```

### Reasoning for above behaviour:
Consul client is not able to get AutoEncrypt.sign rpc through because the agent token on client is wrong(on purpose for demo), and not able to get server sign its CSR. This was to show that its important to have an agent token with node:write permission, set as an agent/default token on clients to be able to talk to server in Auto-encrypt setting. During an initial clients auto-encrypt.sign RPC to server, it also sends its agent token, which should be a valid token.

 

### Okay, How Auto-encrypt works? 

#### With ACLs:
When server and clients are configured with ACLs and Auto-encrypt, and client boots up, the first thing it does it, look for a server to join. Once it knows which server to join, it is supposed to send AutoEncrypt.sign rpc along with its agent acl token to the consul server, to get the signed cert from server, and also to passively supply its identity in the form of ACL token, because thats the only way to certify a consul client’s identity, as consul knows the token being used by client was created by operator and its present in consul records. 

Also, the token used by client needs to have node:write permission, as it needs to register its status in consul, else the Cluster join will fail, and we’ll keep getting the above Autoencrypt errors. Refer error : 


2023-08-10T22:56:01.465+1000 [ERROR] agent.auto_config: AutoEncrypt.Sign RPC failed: addr=127.0.0.1:8300 error="rpcinsecure error making call: Permission denied: token with AccessorID 'ebbce4e7-316e-8a0d-9e9d-463b1b5bef8a' lacks permission 'node:write' on "client""
2023-08-10T22:56:01.465+1000 [ERROR] agent.auto_config: No servers successfully responded to the auto-encrypt request
If the token has node:write permissions, and agent token is configured correctly on client, it will manage to get signed certs from servers.

*Question*: But how the client gets a CSR signed by a server which is TLS enabled and verify_incoming = true . How is client getting authenticated in this TLS communication ?

The Answer to this question is, TLS/ACL enabled Consul cluster goes easy on client(only during TLS initializing duration), booting up first time with auto-encrypt settings. When client boots up, and send the CSR sign request to server, the server doesnt strictly follow verify_incoming = true for clients, as they have no way to prove their TLS identity at the first attempt to initialize. So the server allows the client to get the CSR signed. The servers run insecureRPCServer which runs with configuration: IncomingInsecureRPCconfig , whose purpose is to allow new clients to send autoencrypt.sign rpcs to get initial signed certificate.

 

#### Without ACLs:
Without ACLs, Auto-encrypt is a security glitch. Servers have no way to certify consul clients.

Its recommended to have ACLs enabled Auto-encrypt configured for production environemnts.

 

### Demo:
Now lets create a policy with node:write permissions:

#### Policy that works: (node = write)
```
node "client" {
  policy = "write"
}

service_prefix "" {
  policy = "read"
}
``` 

#### Create Policy in consul with node:write : 
```
./consul acl policy create \
  -name consul-clients \
  -rules @working-policy.hcl
``` 

#### Create token : 
```
./consul acl token create -policy-name consul-clients

AccessorID:       6b8a2377-65ab-7e65-d3fd-dee56dbdb28d
SecretID:         89447493-b1aa-40c0-ef67-03fc6b851110
Description:
Local:            false
Create Time:      2023-08-10 20:57:56.026585 +1000 AEST
Policies:
   9316bb01-8700-8307-44dc-26dbfa86e8b7 - consul-clients
``` 

#### Set agent token on server and client : 
```
consul acl set-agent-token agent 89447493-b1aa-40c0-ef67-03fc6b851110

OR

acl {
  enabled = true
  enable_token_persistence = true
  default_policy = "deny"
  tokens {
    agent = "89447493-b1aa-40c0-ef67-03fc6b851110"
  }
}
``` 

Now Check consul members command, which should return the consul server and clients:
```
./consul members
Node    Address         Status  Type    Build   Protocol  DC   Partition  Segment
server  127.0.0.1:8301  alive   server  1.13.3  2         dc1  default    <all>
client  127.0.0.2:8301  alive   client  1.13.3  2         dc1  default    <default>
``` 

### Summary:
So, we now know how Auto-encrypt works, and importance of ACLs with it. ACLs play an important role to present clients' credibility and building trust with servers.