#!/usr/bin/env sh
# Starts a throwaway OPNsense firewall in containerlab, with an Alpine client
# container wired to its vtnet2, makes an API key on it, and writes
# lab.auto.tfvars with the GUI address and the key. Needs Docker,
# containerlab, KVM, git, make, bunzip2, qemu-img and curl, about 10 GB of
# free disk for the image build, and runs containerlab with sudo unless
# you're root. The image is downloaded from OPNsense and built locally with
# vrnetlab; it's never pushed anywhere. The firewall keeps the image's
# default root password, opnsense: it's only reachable from this machine.
set -eu
cd "$(dirname "$0")"
lab=${LAB_NAME:-opnsense}
# One OPNsense release, checked against the SHA-256 in OPNsense's own
# checksum file for it, recorded here so moving on is a reviewed change.
release=26.7
sha256=28d5e2f37e40d87468a924e3006ef10e2ddc6de485b85333d9e3958c84d0cb9d
vrnetlab=0b0e3a179b96245907101cad64eb5be690a9bde6
client=alpine:3.24.4@sha256:93b41ef40b1677fce8fcc64ff4af09daddfacf5040afde618bc46c1e2d1cc7d4
# vrnetlab wants x.y.z, so 26.7 is tagged 26.7.0.
image=vrnetlab/opnsense:$release.0
cache=${XDG_CACHE_HOME:-$HOME/.cache}/circuit-opnsense-vlans
sudo=sudo
[ "$(id -u)" -ne 0 ] || sudo=

if [ ! -r /dev/kvm ] || [ ! -w /dev/kvm ]; then
  echo "No access to /dev/kvm. Add yourself to the kvm group, or run this where KVM is available." >&2
  exit 1
fi

if ! docker image inspect "$image" >/dev/null 2>&1; then
  mkdir -p "$cache"
  img=OPNsense-$release-nano-amd64.img
  if ! (cd "$cache" && echo "$sha256  $img.bz2" | sha256sum -c --status - 2>/dev/null); then
    curl -fsSL -o "$cache/$img.bz2" "https://pkg.opnsense.org/releases/$release/$img.bz2"
    (cd "$cache" && echo "$sha256  $img.bz2" | sha256sum -c --quiet -) || { rm -f "$cache/$img.bz2"; exit 1; }
  fi
  [ -d "$cache/vrnetlab" ] || git clone -q https://github.com/srl-labs/vrnetlab "$cache/vrnetlab"
  git -C "$cache/vrnetlab" checkout -q "$vrnetlab"
  dir=$cache/vrnetlab/opnsense
  rm -f "$dir"/*.qcow2
  bunzip2 -kc "$cache/$img.bz2" > "$dir/$img"
  qemu-img convert -f raw -O qcow2 "$dir/$img" "$dir/OPNsense-$release.0.qcow2"
  rm -f "$dir/$img"
  (cd "$dir" && make >/dev/null)
  rm -f "$dir"/*.qcow2
fi

cat > lab.clab.yml <<YML
name: $lab
topology:
  nodes:
    fw:
      kind: generic_vm
      image: $image
    c1:
      kind: linux
      image: $client
  links:
    # eth1 is the WAN, vtnet1, left unplugged. eth2 is vtnet2.
    - endpoints: ["fw:eth2", "c1:eth1"]
YML
$sudo containerlab deploy -t lab.clab.yml --reconfigure >/dev/null
node=clab-$lab-fw
# vrnetlab sets up the console, turns on SSH and reboots once: about two
# minutes on a 2-CPU runner.
for _ in $(seq 1 240); do
  [ "$(docker inspect -f '{{.State.Health.Status}}' "$node")" = healthy ] && break
  sleep 5
done
ip=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$node")
for _ in $(seq 1 60); do
  curl -ksf -o /dev/null "https://$ip/" && break
  sleep 3
done
curl -ksf -o /dev/null "https://$ip/" || {
  echo "The firewall started, but its GUI didn't answer on https://$ip. See: docker logs $node" >&2
  exit 1
}

ssh-keyscan -T 5 "$ip" 2>/dev/null > known_hosts
fw() { sshpass -p opnsense ssh -q -o UserKnownHostsFile=known_hosts "root@$ip" "$@"; }
fw 'cat > /tmp/conn3x-apikey.php' < apikey.php
pair=$(fw 'php /tmp/conn3x-apikey.php; rm -f /tmp/conn3x-apikey.php' | tail -1)
# PHP's JSON escapes each / as \/.
key=$(printf '%s' "$pair" | sed -n 's/.*"key":"\([^"]*\)".*/\1/p' | sed 's#\\/#/#g')
secret=$(printf '%s' "$pair" | sed -n 's/.*"secret":"\([^"]*\)".*/\1/p' | sed 's#\\/#/#g')
[ -n "$key" ] && [ -n "$secret" ] || { echo "Couldn't make an API key on the firewall." >&2; exit 1; }

umask 077
cat > lab.auto.tfvars <<VARS
uri        = "https://$ip"
api_key    = "$key"
api_secret = "$secret"
VARS
echo "Ready: OPNsense $release at https://$ip. Now run: conn3x init && conn3x apply"
