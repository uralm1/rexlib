config interface 'loopback'
	option ifname 'lo'
	option proto 'static'
	option ipaddr '127.0.0.1'
	option netmask '255.0.0.0'

config globals 'globals'
	option ula_prefix 'auto'

config interface 'lan'
	option ifname 'eth1'
	option force_link '1'
	option type 'bridge'
	option proto 'static'
	option ipaddr '10.0.1.1'
	option netmask '255.192.0.0'
	option ip6assign '60'

config interface 'wan'
	option ifname 'eth0'
	option proto 'dhcp'

config interface 'wan6'
	option ifname 'eth0'
	option proto 'dhcpv6'

config switch
	option name 'switch0'
	option reset '1'
	option enable_vlan '1'

config switch_vlan
	option device 'switch0'
	option vlan '1'
	option ports '0 1 2 3 4'

config switch_vlan
	option device 'switch0'
	option vlan '2'
	option ports '5 6'

