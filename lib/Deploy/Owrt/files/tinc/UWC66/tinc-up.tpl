ifconfig $INTERFACE <%= $_tun_ip %> netmask <%= $_tun_netmask %>
ip route add 0.0.0.0/1 dev $INTERFACE
ip route add 128.0.0.0/1 dev $INTERFACE
