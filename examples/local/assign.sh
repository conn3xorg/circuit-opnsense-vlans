#!/usr/bin/env sh
# Does by script what you'd do in the GUI after the first apply, and what
# the provider can't: assigns the three lab VLANs to opt1, opt2 and opt3
# with their addresses, then turns Dnsmasq's DHCP off and Kea DHCPv4 on for
# them. Then apply again with -var assigned=true.
set -eu
cd "$(dirname "$0")"
val() { sed -n "s/^$1 *= \"\(.*\)\"$/\1/p" lab.auto.tfvars; }
uri=$(val uri)
ip=${uri#https://}
fw() { sshpass -p opnsense ssh -q -o UserKnownHostsFile=known_hosts "root@$ip" "$@"; }

fw 'cat > /tmp/conn3x-assign.php' < assign.php
for spec in "opt1 vlan0.10 TRUSTED 10.10.0.1" "opt2 vlan0.20 IOT 10.20.0.1" "opt3 vlan0.30 GUEST 10.30.0.1"; do
  set -- $spec
  fw "php /tmp/conn3x-assign.php $1 $2 $3 $4 24 && configctl interface reconfigure $1 >/dev/null"
done
fw 'rm -f /tmp/conn3x-assign.php'

# The key goes to curl on stdin, not its command line.
api() {
  printf 'user = "%s:%s"\n' "$(val api_key)" "$(val api_secret)" |
    curl -ksSf -K - -H 'Content-Type: application/json' -d "$2" "$uri/api/$1" >/dev/null
}
# A fresh OPNsense hands out addresses with Dnsmasq, which holds port 67,
# so it goes off before Kea comes on.
api dnsmasq/settings/set '{"dnsmasq":{"enable":"0"}}'
api dnsmasq/service/reconfigure '{}'
api kea/dhcpv4/set '{"dhcpv4":{"general":{"enabled":"1","interfaces":"opt1,opt2,opt3"}}}'
api kea/service/reconfigure '{}'
# Unbound builds its access list from the interfaces it saw at start.
fw 'configctl unbound restart >/dev/null && configctl filter reload >/dev/null'
echo "Assigned. Now run: conn3x apply -var assigned=true"
