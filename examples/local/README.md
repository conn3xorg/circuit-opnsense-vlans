# Local example

Applies circuit-opnsense-vlans to a throwaway OPNsense firewall in [containerlab](https://containerlab.dev), with an Alpine container plugged into its `vtnet2` as a client on all three VLANs. You need an x86_64 Linux machine with KVM, Docker, containerlab, Conn3x, `git`, `make`, `bunzip2`, `qemu-img`, `sshpass` and `curl`, and about 10 GB of free disk for the image build.

```sh
./up.sh
conn3x init
conn3x apply
./assign.sh
conn3x apply -var assigned=true
conn3x plan -var assigned=true
./check.sh
```

The first apply makes the VLANs. `assign.sh` then does what the circuit's README has you do in the GUI: assigns them to `opt1`, `opt2` and `opt3` with their addresses and turns Kea DHCPv4 on for them. The second apply adds the rules and DHCP subnets, the plan after it says `No changes.`, and `check.sh` ends with `All checks passed.` It gets a DHCP lease on each VLAN from the client, looks up `nas.home.arpa` through the firewall, and checks only the trusted VLAN reaches the GUI.

`up.sh` downloads the OPNsense 26.7 nano image once, checks it against the SHA-256 written in the script (from OPNsense's checksum file), and builds a local Docker image from it with vrnetlab at a pinned commit. Both stay in `~/.cache/circuit-opnsense-vlans` and in Docker for the next run; the image is never pushed anywhere. It then deploys the lab with `sudo containerlab deploy`, waits for vrnetlab's first-boot setup and one reboot (about two minutes), makes an API key for root with a short PHP script over SSH, the same call the GUI's key button makes, and writes the GUI address and the key to `lab.auto.tfvars`, which Conn3x reads by itself. The firewall keeps the image's root password, `opnsense`, since it's only reachable from your machine. Set `LAB_NAME` to run a second lab beside the first.

`./down.sh` destroys the lab and removes the key and the state.
