variable "vlans" {
  type = map(object({
    parent      = string
    tag         = number
    address     = string
    device      = optional(string)
    interface   = optional(string)
    policy      = optional(string, "trusted")
    description = optional(string)
    dhcp = optional(object({
      pools       = list(string)
      domain_name = optional(string, "")
    }))
  }))
  default     = {}
  description = "VLANs, by name, such as { iot = { parent = \"igc1\", tag = 20, address = \"10.20.0.1/24\", interface = \"opt2\", policy = \"internet_only\", dhcp = { pools = [\"10.20.0.100-10.20.0.200\"] } } }. address is the firewall's own address on the VLAN, as you set it on the interface. Rules and DHCP need the interface the VLAN is assigned to (see the README), so they're only made once interface is set."

  validation {
    condition     = alltrue([for v in var.vlans : v.tag >= 1 && v.tag <= 4094 && floor(v.tag) == v.tag])
    error_message = "Each tag must be a whole number from 1 to 4094."
  }

  validation {
    condition     = alltrue([for v in var.vlans : can(cidrhost(v.address, 0)) && can(regex("^[0-9.]+/[0-9]+$", v.address))])
    error_message = "Each address must be an IPv4 address with its prefix length, such as \"10.20.0.1/24\"."
  }

  validation {
    condition     = alltrue([for v in var.vlans : contains(["trusted", "internet_only"], v.policy)])
    error_message = "policy must be trusted (anywhere) or internet_only (DNS on the firewall, then anywhere but private networks)."
  }

  validation {
    condition     = alltrue([for v in var.vlans : v.device == null || can(regex("^vlan0\\.[0-9.]+$", coalesce(v.device, "x")))])
    error_message = "device must start with vlan0. followed by digits and dots, such as \"vlan0.20\"."
  }

  validation {
    condition     = length(distinct([for v in var.vlans : coalesce(v.device, "vlan0.${v.tag}")])) == length(var.vlans)
    error_message = "Each VLAN needs its own device name. Two VLANs with the same tag on different parents need device set on one of them."
  }
}

variable "host_overrides" {
  type        = map(string)
  default     = {}
  description = "Names Unbound answers with your own address, as full name to IPv4 address, such as { \"nas.home.arpa\" = \"10.20.0.10\" }."

  validation {
    condition     = alltrue([for name in keys(var.host_overrides) : can(regex("^[A-Za-z0-9*][A-Za-z0-9-]*\\.[A-Za-z0-9.-]+$", name))])
    error_message = "Each key must be a full name with at least one dot, such as \"nas.home.arpa\"."
  }
}

variable "private_networks" {
  type        = list(string)
  default     = ["10.0.0.0/8", "172.16.0.0/12", "192.168.0.0/16", "100.64.0.0/10", "169.254.0.0/16"]
  description = "Networks an internet_only VLAN can't reach, besides the firewall itself. Each gets its own block rule."
}

variable "rule_sequence" {
  type        = number
  default     = 10000
  description = "Sequence number the circuit's firewall rules start from. Rules run in sequence order, lowest first, so pick a range clear of your own rules."
}
