# This file describes the network interfaces available on your system
# and how to activate them. For more information, see interfaces(5).

source /etc/network/interfaces.d/*

# The loopback network interface
auto lo
iface lo inet loopback

# The primary network interface
allow-hotplug <%= $iface->{dev} %>
iface <%= $iface->{dev} %> inet static
  address <%= $iface->{ip} %>
  gateway <%= $iface->{gateway} %>

iface <%= $iface->{dev} %> inet6 static
  address <%= $iface->{ip6} %>
#  gateway <%= $iface->{gateway6} %>

