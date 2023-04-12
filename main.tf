variable "PROJECT_ID" {
	type = string
}

variable "USER_NAME" {
	type = string
}

variable "PASSWORD" {
	type = string
}

terraform {
  required_providers {
    vkcs = {
      source = "vk-cs/vkcs"
    }
  }
}

provider "vkcs" {
  username   = var.USER_NAME
  password   = var.PASSWORD
  project_id = var.PROJECT_ID
  region     = "RegionOne"
}

data "vkcs_networking_network" "extnet" {
  name = "ext-net"
}

resource "vkcs_networking_network" "local-net" {
  name = "local-net"
}

resource "vkcs_networking_subnet" "local-net-sn" {
  name       = "local-net-sn"
  network_id = vkcs_networking_network.local-net.id
  cidr       = "192.168.5.0/24"
}

resource "vkcs_networking_router" "router" {
  name                = "router"
  admin_state_up      = true
  external_network_id = data.vkcs_networking_network.extnet.id
}

resource "vkcs_networking_router_interface" "db" {
  router_id = vkcs_networking_router.router.id
  subnet_id = vkcs_networking_subnet.local-net-sn.id
}

resource "vkcs_networking_secgroup" "lb-fw" {
   name = "lb-fw"
   description = "Firewall group for lb"
}

resource "vkcs_networking_secgroup_rule" "lb-fw-in1" {
   direction = "ingress"
   ethertype = "IPv4"
   port_range_max = 8000
   port_range_min = 8000
   protocol = "tcp"
   remote_ip_prefix = "192.168.5.0/24"
   security_group_id = vkcs_networking_secgroup.lb-fw.id
   description = "allow ingress for ips from localnet"
}

resource "vkcs_networking_secgroup_rule" "lb-fw-in2" {
	direction = "ingress"
	ethertype = "IPv4"
	port_range_max = 22
	port_range_min = 22
	protocol = "tcp"
	remote_ip_prefix = "0.0.0.0/0"
   security_group_id = vkcs_networking_secgroup.lb-fw.id
   description = "allow ingress for ssh from all networks"
}

resource "vkcs_networking_secgroup_rule" "lb-fw-in3" {
	direction = "ingress"
	ethertype = "IPv4"
	protocol = "icmp"
	remote_ip_prefix = "0.0.0.0/0"
   security_group_id = vkcs_networking_secgroup.lb-fw.id
   description = "allow icmp from all networks"
}

resource "vkcs_networking_secgroup_rule" "lb-fw-in4" {
   direction = "ingress"
   ethertype = "IPv4"
   port_range_max = 8001
   port_range_min = 8001
   protocol = "tcp"
   remote_ip_prefix = "192.168.5.0/24"
   security_group_id = vkcs_networking_secgroup.lb-fw.id
   description = "allow ingress for ips from localnet"
}



data "vkcs_compute_flavor" "compute" {
  name = "Basic-1-1-10"
}

data "vkcs_images_image" "compute" {
  name = "Ubuntu-20.04.1-202008"
}

resource "vkcs_compute_keypair" "ssh-kp" {
  name = "ssh-kp"
}

resource "vkcs_networking_floatingip" "vm1-fip" {
  description = "vm1 fip"
  pool = "ext-net"
}
resource "vkcs_networking_floatingip" "vm2-fip" {
  description = "vm2 fip"
  pool = "ext-net"
}
resource "vkcs_networking_floatingip" "lb-fip" {
  description = "lb fip"
  pool = "ext-net"
}


resource "vkcs_compute_instance" "vm1" {
  name              = "vm1"
  flavor_id         = data.vkcs_compute_flavor.compute.id
  availability_zone = "GZ1"
  key_pair = resource.vkcs_compute_keypair.ssh-kp.id

  block_device {
    uuid                  = data.vkcs_images_image.compute.id
    source_type           = "image"
    destination_type      = "volume"
    volume_type           = "ceph-hdd"
    volume_size           = 5
    boot_index            = 0
    delete_on_termination = true
  }

  network {
    uuid = vkcs_networking_network.local-net.id
	  fixed_ip_v4 = "192.168.5.101"
  }

  security_groups = [
    vkcs_networking_secgroup.lb-fw.id
  ]

  depends_on = [
    vkcs_networking_network.local-net,
    vkcs_networking_subnet.local-net-sn
  ]
}

resource "vkcs_compute_floatingip_associate" "vm1-fip-associate" {
  floating_ip = resource.vkcs_networking_floatingip.vm1-fip.address
  instance_id = vkcs_compute_instance.vm1.id
}

resource "vkcs_compute_instance" "vm2" {
  name              = "vm2"
  flavor_id         = data.vkcs_compute_flavor.compute.id
  availability_zone = "MS1"
  key_pair = resource.vkcs_compute_keypair.ssh-kp.id

  block_device {
    uuid                  = data.vkcs_images_image.compute.id
    source_type           = "image"
    destination_type      = "volume"
    volume_type           = "ceph-hdd"
    volume_size           = 5
    boot_index            = 0
    delete_on_termination = true
  }

  security_groups = [
    vkcs_networking_secgroup.lb-fw.id
  ]
  
  network {
    uuid = vkcs_networking_network.local-net.id
	  fixed_ip_v4 = "192.168.5.102"
  }

  depends_on = [
    vkcs_networking_network.local-net,
    vkcs_networking_subnet.local-net-sn
  ]
}
resource "vkcs_compute_floatingip_associate" "vm2-fip-associate" {
  floating_ip = resource.vkcs_networking_floatingip.vm2-fip.address
  instance_id = vkcs_compute_instance.vm2.id
}


# cert
resource "vkcs_keymanager_secret" "certificate_1" {
  name                 = "certificate"
  payload              = "${file("${path.module}/sitecrt.pem")}"
  secret_type          = "certificate"
  payload_content_type = "text/plain"
}

resource "vkcs_keymanager_secret" "private_key_1" {
  name                 = "private_key"
  payload              = "${file("${path.module}/sitekey.pem")}"
  secret_type          = "private"
  payload_content_type = "text/plain"
}

resource "vkcs_keymanager_container" "tls_1" {
  name = "tls"
  type = "certificate"

  secret_refs {
    name       = "certificate"
    secret_ref = "${vkcs_keymanager_secret.certificate_1.secret_ref}"
  }

  secret_refs {
    name       = "private_key"
    secret_ref = "${vkcs_keymanager_secret.private_key_1.secret_ref}"
  }
}



# lb itself
resource "vkcs_lb_loadbalancer" "lb" {
  name = "loadbalancer"
  vip_subnet_id = "${vkcs_networking_subnet.local-net-sn.id}"
  tags = ["tag1"]
}

# listeners
resource "vkcs_lb_listener" "listener" {
  name = "listener"
  protocol = "HTTP"
  protocol_port = 80
  loadbalancer_id = "${vkcs_lb_loadbalancer.lb.id}"
}
resource "vkcs_lb_listener" "listener-https" {
  name = "listener"
  protocol = "TERMINATED_HTTPS"
  protocol_port = 443
  loadbalancer_id = "${vkcs_lb_loadbalancer.lb.id}"
  default_tls_container_ref = "${vkcs_keymanager_container.tls_1.container_ref}"
}

# pools
resource "vkcs_lb_pool" "lb-pool" {
  name = "lb-pool"
  protocol = "HTTP"
  lb_method = "ROUND_ROBIN"
  listener_id = "${vkcs_lb_listener.listener.id}"
}
resource "vkcs_lb_pool" "lb-pool-https" {
  name = "lb-pool"
  protocol = "HTTP"
  lb_method = "ROUND_ROBIN"
  listener_id = "${vkcs_lb_listener.listener-https.id}"
}

# redir members
resource "vkcs_lb_member" "member_1_redir" {
  address = "192.168.5.101"
  protocol_port = 8001
  pool_id = "${vkcs_lb_pool.lb-pool.id}"
  subnet_id = "${vkcs_networking_subnet.local-net-sn.id}"
}
resource "vkcs_lb_member" "member_2_redir" {
  address = "192.168.5.102"
  protocol_port = 8001
  pool_id = "${vkcs_lb_pool.lb-pool.id}"
  subnet_id = "${vkcs_networking_subnet.local-net-sn.id}"
}

# https members
resource "vkcs_lb_member" "member_1_https" {
  address = "192.168.5.101"
  protocol_port = 8000
  pool_id = "${vkcs_lb_pool.lb-pool-https.id}"
  subnet_id = "${vkcs_networking_subnet.local-net-sn.id}"
}
resource "vkcs_lb_member" "member_2_https" {
  address = "192.168.5.102"
  protocol_port = 8000
  pool_id = "${vkcs_lb_pool.lb-pool-https.id}"
  subnet_id = "${vkcs_networking_subnet.local-net-sn.id}"
}

resource "vkcs_networking_floatingip_associate" "lb-fip-associate" {
  floating_ip = resource.vkcs_networking_floatingip.lb-fip.address
  port_id = resource.vkcs_lb_loadbalancer.lb.vip_port_id
}


output "keypair" {
  value = resource.vkcs_compute_keypair.ssh-kp.private_key
}