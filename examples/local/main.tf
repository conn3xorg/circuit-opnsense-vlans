terraform {
  required_providers {
    # The version comes from the circuit's own pin.
    opnsense = {
      source = "browningluke/opnsense"
    }
  }
}

# up.sh writes lab.auto.tfvars with these.
variable "uri" {
  type = string
}

variable "api_key" {
  type      = string
  ephemeral = true
  sensitive = true
}

variable "api_secret" {
  type      = string
  ephemeral = true
  sensitive = true
}

# The first apply makes the VLANs. Once they're assigned to interfaces
# (assign.sh does what you'd do in the GUI), apply again with
# -var assigned=true for the rules and DHCP.
variable "assigned" {
  type    = bool
  default = false
}

provider "opnsense" {
  uri        = var.uri
  api_key    = var.api_key
  api_secret = var.api_secret
  # The lab firewall serves its GUI with a self-signed certificate.
  allow_insecure = true
}

module "vlans" {
  source = "../.."

  # vtnet2 is the lab's link to the client container.
  vlans = {
    trusted = {
      parent    = "vtnet2"
      tag       = 10
      address   = "10.10.0.1/24"
      interface = var.assigned ? "opt1" : null
      dhcp      = { pools = ["10.10.0.100-10.10.0.199"] }
    }
    iot = {
      parent    = "vtnet2"
      tag       = 20
      address   = "10.20.0.1/24"
      interface = var.assigned ? "opt2" : null
      policy    = "internet_only"
      dhcp      = { pools = ["10.20.0.100-10.20.0.199"] }
    }
    guest = {
      parent    = "vtnet2"
      tag       = 30
      address   = "10.30.0.1/24"
      interface = var.assigned ? "opt3" : null
      policy    = "internet_only"
      dhcp      = { pools = ["10.30.0.100-10.30.0.199"], domain_name = "guest.home.arpa" }
    }
  }

  host_overrides = {
    "nas.home.arpa" = "10.10.0.10"
  }
}

output "vlan_devices" {
  value = module.vlans.vlan_devices
}
