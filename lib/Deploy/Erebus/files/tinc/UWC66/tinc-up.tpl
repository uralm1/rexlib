ifconfig $INTERFACE <%= $_tun_ip %> netmask <%= $_tun_netmask %>
ip route add <%= $_tun_route_addr %> dev $INTERFACE src <%= $_tun_ip %> table r_beeline
