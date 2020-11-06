#network:
#  ethernets:
#    <%= $iface->{dev} %>:
#      addresses:
#      - <%= $iface->{ip} %>
#      - "<%= $iface->{ip6} %>"
#     gateway4: <%= $iface->{gateway} %>
#     gateway6: "<%= $iface->{gateway6} %>"
#     nameservers:
#       addresses:
#       - 10.14.0.1
#       - 10.14.0.2
#       - "fc00:10:10::14:0:2"
#       search:
#       - uwc.local
#  version: 2
