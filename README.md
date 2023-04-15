# lnd-baremetal-docker
Dockerized Version of Baremetal Noderunning

## Pre-requisites
An Ubuntu 20.04 or higher server with at least 4GB of RAM and 50GB of disk space.
This can be deployed in cloud like AWS or on a local machine like a Raspberry Pi 4.

### Install docker
[Install Docker](https://docs.docker.com/engine/install/)

### Install docker-compose
[Install docker-compose](https://docs.docker.com/compose/install/linux/)


### Setup local firewall
```bash
# Check if UFW is installed
which ufw
sudo ufw logging on
sudo ufw enable
# PRESS Y
# Allow access to 9735 the P2P port and 10009 the gRPC port
sudo ufw status
sudo ufw allow OpenSSH
sudo ufw allow 9735
sudo ufw allow 10009
```

### Setup network flood protection
```bash
sudo iptables -N syn_flood
sudo iptables -A INPUT -p tcp --syn -j syn_flood
sudo iptables -A syn_flood -m limit --limit 1/s --limit-burst 3 -j RETURN
sudo iptables -A syn_flood -j DROP
sudo iptables -A INPUT -p icmp -m limit --limit 1/s --limit-burst 1 -j ACCEPT
sudo iptables -A INPUT -p icmp -m limit --limit 1/s --limit-burst 1 -j LOG --log-prefix PING-DROP:
sudo iptables -A INPUT -p icmp -j DROP
sudo iptables -A OUTPUT -p icmp -j ACCEPT
```

### Download and use the Bitcoin Core auth script to generate credentials:
```bash
wget https://raw.githubusercontent.com/bitcoin/bitcoin/master/share/rpcauth/rpcauth.py

python3 ./rpcauth.py bitcoinrpc
# This will output the authentication string to add to bitcoin.conf
# Save the password, this will be used for LND configuration
```


## Bitcoin Core

Setup Bitcoin Core Data Directory
```bash
mkdir ~/.bitcoin
```

Create bitcoin.conf
```bash
nano ~/.bitcoin/bitcoin.conf
```

Add the following to the bitcoin.conf file
```ini
# Set the best block hash here:
assumevalid=

# Set the number of megabytes of RAM to use, set to like 50% of available memory
dbcache=3000

# Add visibility into mempool and RPC calls for potential LND debugging
debug=mempool
debug=rpc

# Turn off the wallet, it won't be used
disablewallet=1

# Don't bother listening for peers
listen=0

# Constrain the mempool to the number of megabytes needed:
maxmempool=100

# Limit uploading to peers
maxuploadtarget=1000

# Turn off serving SPV nodes
nopeerbloomfilters=1
peerbloomfilters=0

# Don't accept deprecated multi-sig style
permitbaremultisig=0

# Turn on pruned mode (remove this if you want to run a full node)
prune=550

# Set the RPC auth to what was set above
rpcauth=

# Turn on the RPC server
server=1

# Reduce the log file size on restarts
shrinkdebuglog=1

# Turn on transaction lookup index (turn off pruned mode if this is enabled)
txindex=1

# Turn on ZMQ publishing
zmqpubrawblock=tcp://0.0.0.0:28332
zmqpubrawtx=tcp://0.0.0.0:28333

# Rpc server settings
rpcbind=0.0.0.0
rpcallowip=0.0.0.0/0
rpcport=8332
```


## Lnd

Setup Lnd Data Directory
```bash
mkdir ~/.lnd
```

Create lnd.conf
```bash
nano ~/.lnd/lnd.conf
```

Add the following to the lnd.conf file
```ini
[Application Options]
# Allow push payments
accept-keysend=1

# Public network name
alias=YourNodeName

# Allow gift routes
allow-circular-route=1

# Public hex color
color=#000000

# Reduce the cooperative close chain fee
coop-close-target-confs=1000

# Log levels
debuglevel=CNCT=debug,CRTR=debug,HSWC=debug,NTFN=debug,RPCS=debug

# Public P2P IP (remove this if using Tor)
externalip=EXTERNAL_IP

# Mark unpayable, unpaid invoices as deleted
gc-canceled-invoices-on-startup=1
gc-canceled-invoices-on-the-fly=1

# Avoid historical graph data sync
ignore-historical-gossip-filters=1

# Set the maximum amount of commit fees in a channel
max-channel-fee-allocation=1.0

# Set the max timeout blocks of a payment
max-cltv-expiry=5000

# Allow commitment fee to rise on anchor channels
max-commit-fee-rate-anchors=100

# Pending channel limit
maxpendingchannels=10

# Min inbound channel limit
minchansize=5000000

# gRPC socket binding
rpclisten=0.0.0.0:10009

# Avoid high startup overhead
stagger-initial-reconnect=1

# Delete and recreate RPC TLS certificate when details change or cert expires
tlsautorefresh=1

# Do not include IPs in the RPC TLS certificate
tlsdisableautofill=1

# Add DNS to the RPC TLS certificate
tlsextraip=EXTERNAL_IP

# The full path to a file (or pipe/device) that contains the password for unlocking the wallet
# Add this to the config file after you have created a wallet
wallet-unlock-password-file=/root/.lnd/wallet_password

[Bitcoin]
# Turn on Bitcoin mode
bitcoin.active=1

# Set the channel confs to wait for channels
bitcoin.defaultchanconfs=2

# Forward fee rate in parts per million
bitcoin.feerate=1000

# Set bitcoin.testnet=1 or bitcoin.mainnet=1 as appropriate
bitcoin.mainnet=1

# Set the lower bound for HTLCs
bitcoin.minhtlc=1

# Set backing node, bitcoin.node=neutrino or bitcoin.node=bitcoind
bitcoin.node=bitcoind

# Set CLTV forwarding delta time
bitcoin.timelockdelta=144

[bitcoind]
# Configuration for using Bitcoin Core backend

# Set the rpc host
bitcoind.rpchost="bitcoin-core:8332"

# Set the password to what the auth script said
bitcoind.rpcpass=

# Set the username
bitcoind.rpcuser=bitcoinrpc

# Set the ZMQ listeners
bitcoind.zmqpubrawblock="tcp://bitcoin-core:28332"
bitcoind.zmqpubrawtx="tcp://bitcoin-core:28333"

[bolt]
# Enable database compaction when restarting
db.bolt.auto-compact=true

[protocol]
# Enable large channels support
protocol.wumbo-channels=1

# Enable channel id hiding
protocol.option-scid-alias=true

[routerrpc]
# Set default chance of a hop success
routerrpc.apriori.hopprob=0.5

# Start to ignore nodes if they return many failures (set to 1 to turn off)
routerrpc.apriori.weight=0.75

# Set minimum desired savings of trying a cheaper path
routerrpc.attemptcost=10
routerrpc.attemptcostppm=10

# Set the number of historical routing records
routerrpc.maxmchistory=10000

# Set the min confidence in a path worth trying
routerrpc.minrtprob=0.005

# Set the time to forget past routing failures
routerrpc.apriori.penaltyhalflife=6h0m0s
```

Create a wallet password
```bash
openssl rand -base64 32 > ~/.lnd/wallet_password

cat ~/.lnd/wallet_password
# Copy and save this password
```

### Create a docker-network
```bash
docker network create baremetal
```

### Start Bitcoin Core and LND
```bash
# Go to the home directory
cd ~

# Clone the repo
git clone https://github.com/niteshbalusu11/lnd-baremetal-docker.git

# Change directory
cd lnd-baremetal-docker

# Start the containers
docker compose up -d

# Add alias for bitcoin-cli
echo "alias bitcoin-cli='docker exec -it bitcoin-core bitcoin-cli -rpccookiefile=/home/bitcoin/.bitcoin/.cookie'" >> ~/.profile

# Add alias for lncli
echo "alias lncli='docker exec -it lnd lncli'" >> ~/.profile

# Execute the profile
source ~/.profile

# Create a wallet
lncli create

# Enter the wallet password from above and save the seed securely
```

## Apps to control LND:


### Start Bos and Lndboss
```bash
# Go to the home directory
cd ~

# Change directory
cd lnd-baremetal-docker

# Start the containers
docker compose -f apps-docker-compose.yml up -d
```

### Add Alias for BalanceOfSatoshis
```bash
echo "alias bos='docker exec -it bos bos peers'" >> ~/.profile

# Execute the profile
source ~/.profile
```


### To view Logs
```bash
# Bitcoin core logs
docker logs -f bitcoin-core

# LND logs
docker logs -f lnd
```
