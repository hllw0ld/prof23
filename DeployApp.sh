#!/bin/bash

# change permissions on ssh private key file
chmod 600 privkey.pem

# configure openstack vars
source cloud.conf
export OS_AUTH_URL="https://infra.mail.ru:35357/v3/"
export OS_PROJECT_ID="$PROJECT_ID"
export OS_REGION_NAME="RegionOne"
export OS_USERNAME="$USER_NAME"
export OS_USER_DOMAIN_NAME="users"
export OS_PASSWORD="$PASSWORD"
export OS_INTERFACE=public
export OS_IDENTITY_API_VERSION=3

# raw info about vms
export raw_srvs=$(openstack server list | head -n -1 | tail -n -2)
# all servers ips
export srv_ips="$(echo "$raw_srvs" | cut -d"|" -f5 | cut -d= -f 2 | tr "," "\n" | tr -d " " | grep -v 192.168.5)"

# nginx conf
export original_nginx_conf="$(cat nginx.conf)"
export lb_address="$(openstack floating ip list | head -n -1 | tail -n -3 | grep -v 192.168.5.101 | grep -v 192.168.5.102 | cut -d"|" -f3 | xargs)"
export nginx_fixed="${original_nginx_conf/LB_IP/"$lb_address"}"

for srv in $srv_ips; do
    echo "Setting up Docker repository on $srv"
    ssh -o StrictHostKeyChecking=no -i privkey.pem -l ubuntu $srv -- /bin/bash << EOF
        sudo apt update
        sudo apt install -y ca-certificates curl gnupg
        sudo mkdir -m 0755 -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu focal stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
EOF

    echo "Installing Docker on $srv"
    ssh -i privkey.pem -l ubuntu $srv -- /bin/bash << EOF
        sudo apt update
        sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
EOF

    echo "Run App1 in Docker($srv)"
    ssh -i privkey.pem -l ubuntu $srv -- /bin/bash << EOF
        sudo docker pull ghcr.io/vobbla16/prof23pointless:latest
        sudo docker run --name app1 -p 8000:80 -d ghcr.io/vobbla16/prof23pointless:latest
EOF

    echo "Setting up Nginx for http->https redirect on $srv"
    echo "$nginx_fixed" | ssh -i privkey.pem -l ubuntu -T $srv "cat > /tmp/nginx.conf"
    ssh -i privkey.pem -l ubuntu $srv -- /bin/bash << EOF
        sudo docker run --name nginx-redir -p 8001:80 -d --mount type=bind,source=/tmp/nginx.conf,target=/etc/nginx/nginx.conf nginx:alpine
EOF
done
