output "vlan_devices" {
  description = "The device for each VLAN, by VLAN name, such as { iot = \"vlan0.20\" }. Assign these under Interfaces > Assignments."
  value       = { for name, v in opnsense_interfaces_vlan.this : name => v.device }
}

output "unassigned" {
  description = "VLANs with no interface set yet, which have no rules or DHCP."
  value       = sort([for name, v in var.vlans : name if v.interface == null])
}
