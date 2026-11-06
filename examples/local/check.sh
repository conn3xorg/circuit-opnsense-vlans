#!/usr/bin/env bash
# Uses the VLANs from the client container, tagged on the firewall's
# vtnet2: gets a DHCP lease on each, looks up the host override through the
# firewall's resolver, and checks the trusted VLAN can reach the firewall's
# GUI while the internet_only ones can't.
set -euo pipefail
cd "$(dirname "$0")"
client=clab-${LAB_NAME:-opnsense}-c1
c() { docker exec "$client" sh -c "$1"; }

for tag in 10 20 30; do
  echo "VLAN $tag: a DHCP lease from Kea's pool"
  c "ip link show eth1.$tag >/dev/null 2>&1 || { ip link add link eth1 name eth1.$tag type vlan id $tag && ip link set eth1.$tag up; }"
  c "ip -4 addr flush dev eth1.$tag && udhcpc -i eth1.$tag -n -q -t 10 -T 3 >/dev/null 2>&1"
  c "ip -4 -o addr show dev eth1.$tag" | grep -Eq "inet 10\.$tag\.0\.1[0-9]{2}/24" || { echo "No lease from the pool on VLAN $tag." >&2; exit 1; }

  echo "VLAN $tag: the firewall's resolver answers nas.home.arpa"
  c "nslookup nas.home.arpa 10.$tag.0.1" | grep -q 10.10.0.10 || { echo "nas.home.arpa didn't resolve on VLAN $tag." >&2; exit 1; }
done

gui() { c "wget -q -T 5 --no-check-certificate -O /dev/null https://10.$1.0.1/"; }
echo "The trusted VLAN reaches the firewall's GUI"
gui 10
for tag in 20 30; do
  echo "VLAN $tag, internet_only, doesn't"
  if gui "$tag" 2>/dev/null; then echo "VLAN $tag reached the GUI." >&2; exit 1; fi
done
echo "All checks passed."
