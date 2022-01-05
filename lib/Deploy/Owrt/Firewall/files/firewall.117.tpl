config defaults
	option syn_flood	1
	option input		DROP
	option output		DROP
	option forward		DROP
# Uncomment this line to disable ipv6 rules
###	option disable_ipv6	1

config zone
	option name		lan
<% for my $if (@$_lan_interfaces) { %>
	list network	'<%= $if %>'
<% } %>
	option input		REJECT
	option output		DROP
	option forward		DROP
	option log 1
        # comment to debug
	option log_limit '10/minute'

config zone
	option name		wan
<% for my $if (@$_wan_interfaces) { %>
	list network	'<%= $if %>'
<% } %>
	option input		DROP
	option output		DROP
	option forward		DROP
	#option masq		1
	#option mtu_fix		1
	option log 1
        # comment to debug
	option log_limit '5/minute'

config zone
	option name vpn
	#list network 'vpn1'
	option device 'vpn+'
	option input		DROP
	option output		DROP
	option forward		DROP
	option log 1
        # comment to debug
	option log_limit '10/minute'


### LAN ###
config rule
	option name icmp-lan-in
	option src lan
	option proto icmp
        option target ACCEPT

config rule
	option name icmp-lan-out
	option dest lan
	option proto icmp
        option target ACCEPT

config rule
	option name ssh-lan-in
	option src lan
	option proto tcp
	option dest_port 22
	option target ACCEPT

config rule
	option name ssh-lan-out
	option dest lan
	option proto tcp
	option src_port 22
	option target ACCEPT

config rule
	option name dns-lan-in
	option src lan
	option proto tcpudp
	option dest_port 53
	option target ACCEPT

config rule
	option name dns-lan-out
	option dest lan
	option proto tcpudp
	option src_port 53
	option target ACCEPT

config rule
	option name dhcp-lan-in
	option src lan
	option proto udp
	option src_port '67:68'
	option dest_port '67:68'
	option target ACCEPT

config rule
	option name dhcp-lan-out
	option dest lan
	option proto udp
	option src_port '67:68'
	option dest_port '67:68'
	option target ACCEPT

# don't send REJECTS on some requests
config rule
	option name netbios-lan-drop
	option src lan
	option proto tcpudp
	option dest_port '137:139'
	option target DROP

config rule
	option name igmp-lan-drop
	option src lan
	option proto igmp
	option target DROP
###################

### WAN ###
###################


### VPN ###
config rule
	option name tunnel-to-router
	option src vpn
	option proto all
	option target ACCEPT

config rule
	option name router-to-tunnel
	option dest vpn
	option proto all
	option target ACCEPT

###################

