# Client VPN — how to turn it on if you want it

**Disabled by default**, because you asked to skip ACM and a Client VPN endpoint cannot exist
without a server certificate in ACM. The module is written and ready; it needs two certificate
ARNs.

Dev has this: `cvpn-endpoint-0b6417adc90c36a53`, OpenVPN, split-tunnel, mutual certificate
auth, client CIDR `10.100.0.0/16`, using two imported ACM certs.

## Do you need it?

With everything on private subnets, you need *some* way in. The options:

| Option | Reaches | Cost | Effort |
| --- | --- | --- | --- |
| SSM Session Manager | the EC2 tools host, plus port-forwards through it | free | none, already working |
| Client VPN | the whole VPC — RDS, Redis, EKS API, everything, natively | ~$72/month + $0.05/hr per connection | 15 min |
| Public EKS endpoint, IP-restricted | the Kubernetes API only | free | one line |

Start with SSM. Add the VPN when port-forwarding through a bastion gets annoying, which for most
teams is about two weeks in.

## Generating the certificates

Mutual (certificate) authentication needs your own small certificate authority. AWS documents
this with `easy-rsa`.

```bash
git clone https://github.com/OpenVPN/easy-rsa.git
cd easy-rsa/easyrsa3

./easyrsa init-pki
./easyrsa build-ca nopass                          # prompts for a CA name; anything is fine
./easyrsa --san=DNS:server build-server-full server nopass
./easyrsa build-client-full client1.domain.tld nopass

mkdir -p ~/vpn-certs
cp pki/ca.crt                              ~/vpn-certs/
cp pki/issued/server.crt                   ~/vpn-certs/
cp pki/private/server.key                  ~/vpn-certs/
cp pki/issued/client1.domain.tld.crt       ~/vpn-certs/
cp pki/private/client1.domain.tld.key      ~/vpn-certs/
cd ~/vpn-certs
```

Import both into ACM in the same region as the VPC:

```bash
SERVER_ARN=$(aws acm import-certificate \
  --certificate fileb://server.crt \
  --private-key fileb://server.key \
  --certificate-chain fileb://ca.crt \
  --region us-east-1 --query CertificateArn --output text)

CLIENT_ARN=$(aws acm import-certificate \
  --certificate fileb://client1.domain.tld.crt \
  --private-key fileb://client1.domain.tld.key \
  --certificate-chain fileb://ca.crt \
  --region us-east-1 --query CertificateArn --output text)

echo "server: $SERVER_ARN"
echo "client: $CLIENT_ARN"
```

Store `ca.crt` and `ca.key` somewhere safe and offline. They are how you issue certificates for
new team members and revoke them for departing ones.

## Choosing the client CIDR — read this before you pick one

This is the setting people get wrong, and it cannot be fixed without destroying the endpoint.

**AWS requires a block size between /12 and /22.** A `/24` is rejected outright:

```
InvalidParameterValue: The client CIDR block size must be at least /22 and no more than /12
```

**It must not overlap** the associated VPC's CIDR or any route on the endpoint. Stage's VPC is
`10.20.0.0/16`, prod's is `10.30.0.0/16`.

**It cannot be changed after creation.** `aws_ec2_client_vpn_endpoint` marks
`client_cidr_block` as ForceNew, so editing it destroys and recreates the endpoint — new DNS
name, and every distributed `.ovpn` file stops working.

The repo ships `10.100.0.0/22` for stage and `10.110.0.0/22` for prod, set in
`config/main.tf`. A /22 gives roughly 1000 usable client addresses; AWS reserves part of the
range for the endpoint's own availability model, so you never get the full 1024.

### On using 172.31.x

`172.31.0.0/16` is the range AWS gives every default VPC in every region, and it is what the
dev account (`021914193398`) runs on. AWS will not *reject* a client CIDR inside it — the API
only checks the VPC you associate the endpoint with, which for us is `10.20.0.0/16` — but it
is still a poor choice:

- The stage account almost certainly has its own untouched default VPC on `172.31.0.0/16`. Any
  future peering, or a workload someone spins up in the default VPC, collides.
- A VPN client on `172.31.1.x` cannot reach the dev account over any peering or Transit
  Gateway, because dev's own VPC owns that range.
- Plenty of home routers hand out `172.31.x` addresses, and a client whose LAN overlaps the
  VPN range gets unpredictable routing.

If you must stay in that family, `172.31.252.0/22` is the least-bad option: still inside the
default VPC range, but at the far end where AWS's default subnets (which start at
`172.31.0.0/20`) do not reach. I would still use `10.100.0.0/22`.

The repo validates the prefix length at **plan** time, so a bad value fails in seconds rather
than after ten minutes of endpoint creation:

```
Error: Invalid value for variable
AWS requires the Client VPN CIDR to be between /12 and /22. A /24 (or anything
smaller than /22) is rejected by the API.
```

## Enabling it

`config/main.tf`, stage block:

```hcl
  enable_client_vpn                     = true
  vpn_client_cidr_block                 = "10.100.0.0/22"
  vpn_server_certificate_arn            = "arn:aws:acm:us-east-1:419717495525:certificate/..."
  vpn_client_root_certificate_chain_arn = "arn:aws:acm:us-east-1:419717495525:certificate/..."
```

Commit, PR, merge. CI applies it. Creating the endpoint and associating it with three subnets
takes about 10 minutes.

Note that the certificate ARNs go in plain text in a `.tf` file. That is fine — an ARN is an
identifier, not a secret. The private keys stay on your machine and in ACM.

## Handing out the client config

```bash
ENDPOINT=$(cd live/stage && terraform output -json environment | python3 -c \
  'import sys,json; print(json.load(sys.stdin))' 2>/dev/null || echo "get it from the console")

aws ec2 export-client-vpn-client-configuration \
  --client-vpn-endpoint-id <ENDPOINT_ID> \
  --output text > scribl-stage.ovpn
```

Then append the client certificate and key to that file:

```bash
cat >> scribl-stage.ovpn << EOF
<cert>
$(cat ~/vpn-certs/client1.domain.tld.crt)
</cert>
<key>
$(cat ~/vpn-certs/client1.domain.tld.key)
</key>
EOF
```

Import `scribl-stage.ovpn` into AWS VPN Client, Tunnelblick, or OpenVPN Connect.

Give each person their own client certificate — `./easyrsa build-client-full alice nopass` —
so you can revoke one without reissuing everyone's.

## Cost warning

The endpoint charges per *subnet association* per hour, not per endpoint. Three associations is
roughly $72/month before anyone connects. To halve it, associate fewer subnets:

```hcl
subnet_ids = slice(data.terraform_remote_state.network.outputs.private_subnet_ids, 0, 1)
```

in `stacks/90-vpn/main.tf`. You lose AZ redundancy for VPN access, which for a development
VPN is usually an acceptable trade.
