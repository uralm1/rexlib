# This file is interpreted as shell script.
# Put your custom tc rules here, they will
# be executed with each firewall (re-)start.

tc qdisc del dev vpn1 root 2>/dev/null
tc qdisc add dev vpn1 root handle 1: pfifo

