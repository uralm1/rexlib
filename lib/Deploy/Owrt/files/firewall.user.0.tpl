# This file is interpreted as shell script.
# Put your custom iptables rules here, they will
# be executed with each firewall (re-)start.

# Internal uci firewall chains are flushed and recreated on reload, so
# put custom rules into the root chains e.g. INPUT or FORWARD or into the
# special user chains, e.g. input_wan_rule or postrouting_lan_rule.

### DONT LOG before DROP rules ###
# lan zone
# annoying netbios broadcasts on lan
iptables -A input_lan_rule -p udp --dport 137:139 -j DROP
# igmp on lan
iptables -A input_lan_rule -d 224.0.0.1 -p igmp -j DROP

# wan zone
# very annoying microtik broadcasts on wan
iptables -A input_wan_rule -p udp --dport 5678 -j DROP 
# very annoying dhcp broadcasts
iptables -A input_wan_rule -d 255.255.255.255 -p udp --dport 67 -j DROP
# annoying netbios broadcasts on wan
iptables -A input_wan_rule -p udp --dport 137:139 -j DROP 
# igmp on wan
iptables -A input_wan_rule -d 224.0.0.1 -p igmp -j DROP
# misc
iptables -A input_wan_rule -d 255.255.255.255 -p udp --dport 54320 -j DROP
iptables -A input_wan_rule -d 255.255.255.255 -p udp --dport 1947 -j DROP

