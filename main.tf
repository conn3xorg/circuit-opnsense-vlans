locals {
  # VLANs assigned to an interface, sorted so rule sequence numbers stay put
  # when a VLAN is added.
  assigned = { for name, v in var.vlans : name => merge(v, {
    ip      = split("/", v.address)[0]
    network = cidrsubnet(v.address, 0, 0)
    seq     = var.rule_sequence + 10 * index(sort([for n, x in var.vlans : n if x.interface != null]), name)
  }) if v.interface != null }

  restricted = { for name, v in local.assigned : name => v if v.policy == "internet_only" }
}

resource "opnsense_interfaces_vlan" "this" {
  for_each    = var.vlans
  parent      = each.value.parent
  tag         = each.value.tag
  device      = coalesce(each.value.device, "vlan0.${each.value.tag}")
  description = coalesce(each.value.description, each.key)
}

resource "opnsense_firewall_alias" "private" {
  count       = length(local.restricted) > 0 ? 1 : 0
  name        = "private_networks"
  type        = "network"
  content     = var.private_networks
  description = "Networks internet_only VLANs can't reach"
}

# trusted: anything from the VLAN's network.
resource "opnsense_firewall_filter" "trusted" {
  for_each    = { for name, v in local.assigned : name => v if v.policy == "trusted" }
  sequence    = each.value.seq
  description = "${each.key}: allow from the VLAN"
  interface   = { interface = [each.value.interface] }
  filter = {
    quick     = true
    action    = "pass"
    direction = "in"
    protocol  = "any"
    source    = { net = each.value.network }
  }
}

# internet_only, in sequence: DNS to the firewall, nothing to private
# networks (the firewall's own addresses included), then anything else.
resource "opnsense_firewall_filter" "dns" {
  for_each    = local.restricted
  sequence    = each.value.seq
  description = "${each.key}: allow DNS to the firewall"
  interface   = { interface = [each.value.interface] }
  filter = {
    quick       = true
    action      = "pass"
    direction   = "in"
    protocol    = "TCP/UDP"
    source      = { net = each.value.network }
    destination = { net = each.value.ip, port = "53" }
  }
}

resource "opnsense_firewall_filter" "block_private" {
  for_each    = local.restricted
  sequence    = each.value.seq + 1
  description = "${each.key}: block private networks"
  interface   = { interface = [each.value.interface] }
  filter = {
    quick       = true
    action      = "block"
    direction   = "in"
    protocol    = "any"
    source      = { net = each.value.network }
    destination = { net = opnsense_firewall_alias.private[0].name }
  }
}

resource "opnsense_firewall_filter" "internet" {
  for_each    = local.restricted
  sequence    = each.value.seq + 2
  description = "${each.key}: allow the internet"
  interface   = { interface = [each.value.interface] }
  filter = {
    quick     = true
    action    = "pass"
    direction = "in"
    protocol  = "any"
    source    = { net = each.value.network }
  }
}

resource "opnsense_kea_dhcpv4_subnet" "this" {
  for_each     = { for name, v in local.assigned : name => v if v.dhcp != null }
  subnet       = each.value.network
  pools        = each.value.dhcp.pools
  auto_collect = false
  routers      = [each.value.ip]
  dns_servers  = [each.value.ip]
  domain_name  = each.value.dhcp.domain_name
  description  = each.key
}

resource "opnsense_unbound_host_override" "this" {
  for_each = var.host_overrides
  hostname = split(".", each.key)[0]
  domain   = join(".", slice(split(".", each.key), 1, length(split(".", each.key))))
  server   = each.value
}
