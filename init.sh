#!/bin/bash

# Function to print header
print_header() {
    echo "===================================="
    echo $1
    echo "===================================="
}

# Function to print message
print_message() {
    echo "* $1"
}


# Check if UFW is installed
if ! command -v ufw &> /dev/null
then
    echo "UFW is not installed. Please install it and run the script again."
    exit
fi

# ====================================================================================================

print_header "Setting up UFW firewall"
# Enable logging
sudo ufw logging on

# Enable UFW
sudo ufw enable

# Allow access to P2P and gRPC ports
echo "Do you want to allow access to P2P and gRPC ports? [Y/n]"
read answer
if [[ ${answer,,} == "y" ]]
then
    sudo ufw allow 9735/tcp
    sudo ufw allow 10009/tcp
fi

# Check UFW status
sudo ufw status

# Allow OpenSSH
sudo ufw allow OpenSSH

# ====================================================================================================

print_header "Setting up IPTables"
# Set up iptables rules
sudo iptables -N syn_flood
sudo iptables -A INPUT -p tcp --syn -j syn_flood
sudo iptables -A syn_flood -m limit --limit 1/s --limit-burst 3 -j RETURN
sudo iptables -A syn_flood -j DROP
sudo iptables -A INPUT -p icmp -m limit --limit 1/s --limit-burst 1 -j ACCEPT
sudo iptables -A INPUT -p icmp -m limit --limit 1/s --limit-burst 1 -j LOG --log-prefix PING-DROP:
sudo iptables -A INPUT -p icmp -j DROP
sudo iptables -A OUTPUT -p icmp -j ACCEPT

# ====================================================================================================

print_header "Creating bitcoin.conf and lnd.conf files inside ~/.bitcoin and ~/.lnd directories"

# Create bitcoin directory and copy configuration file
mkdir -p ~/.bitcoin
cp -n ~/lnd-baremetal-docker/bitcoin.conf ~/.bitcoin/bitcoin.conf

# Create lnd directory and copy configuration file
mkdir -p ~/.lnd
cp -n ~/lnd-baremetal-docker/lnd.conf ~/.lnd/lnd.conf

# ====================================================================================================
# Add alias for bitcoin-cli
print_header "Configuring aliases"
print_message "Adding alias for bitcoin-cli"
echo "alias bitcoin-cli='docker exec -it bitcoin-core bitcoin-cli -rpccookiefile=/home/bitcoin/.bitcoin/.cookie'" >> ~/.profile

# Add alias for lncli
print_message "Adding alias for lncli"
echo "alias lncli='docker exec -it lnd lncli'" >> ~/.profile

# Add alias for bos
echo "alias bos='docker exec -it bos bos'" >> ~/.profile

# Execute the profile
print_message "Executing the profile"
source ~/.profile

# ====================================================================================================
# Install Docker
print_header "Installing Docker"

# Remove existing Docker installations
print_message "Removing existing Docker installations"
sudo apt-get remove docker docker-engine docker.io containerd runc

# Install dependencies
print_message "Installing dependencies"
sudo apt-get update
sudo apt-get install -y \
    ca-certificates \
    curl \
    gnupg

# Install Docker GPG key
print_message "Installing Docker GPG key"
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Add Docker repository
print_message "Adding Docker repository"
echo \
  "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker
print_message "Installing Docker"
sudo apt-get update
sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Verify Docker installation
print_message "Verifying Docker installation"
docker_run_output=$(sudo docker run hello-world 2>&1)
if [[ "$docker_run_output" == *"Hello from Docker!"* ]]
then
    print_message "Docker installation completed successfully"
else
    echo "ERROR: Docker installation failed. Please check logs for more information."
fi

# ====================================================================================================

# Create Docker network
print_header "Setting up Docker network"
print_message "Creating Docker network"
docker network create baremetal

# ====================================================================================================
# Generate wallet password
echo ""
print_message "Press y to enter a password for LND wallet encryption, or any other key to generate a random password"
read answer
if [[ ${answer,,} == "y" ]]
then
    while true
    do
        print_message "Enter a password for LND wallet encryption:"
        read -s password
        print_message "Confirm the password:"
        read -s password2

        if [[ $password == $password2 ]]
        then
            echo $password > ~/.lnd/wallet_password
            print_message "LND wallet encryption password set"
            break
        else
            print_message "Passwords do not match. Please try again."
        fi
    done
else
    print_message "Generating LND wallet password"
    openssl rand -base64 32 > ~/.lnd/wallet_password
    print_message "Wallet password:"
    cat ~/.lnd/wallet_password
fi

# ====================================================================================================
echo ""
print_header "Downloading and executing bitcoin auth script, make sure to save the output of this"
# Download and execute rpcauth.py script
cd ~
wget https://raw.githubusercontent.com/bitcoin/bitcoin/master/share/rpcauth/rpcauth.py
python3 ./rpcauth.py bitcoinrpc