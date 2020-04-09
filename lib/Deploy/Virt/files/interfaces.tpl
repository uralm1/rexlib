# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).

source /etc/network/interfaces.d/*

# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface
allow-hotplug <%= $iface->{dev} %>
#iface <%= $iface->{dev} %> inet static
#  address <%= $iface->{ip} %>
#  netmask <%= $iface->{netmask} %>
#  gateway <%= $iface->{gateway} %>

auto br0
iface br0 inet static
  address <%= $iface->{ip} %>
  netmask <%= $iface->{netmask} %>
  gateway <%= $iface->{gateway} %>
  bridge_ports <%= $iface->{dev} %>
  bridge_fd 0
