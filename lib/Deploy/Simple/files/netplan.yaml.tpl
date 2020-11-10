#network:
#  ethernets:
#    <%= $iface->{dev} %>:
#      addresses:
#      - <%= $iface->{ip} %>
<% if ($iface->{ip6}) { %>#      - "<%= $iface->{ip6} %>"<% } %>
<% if ($iface->{gateway}) { %>#     gateway4: <%= $iface->{gateway} %><% } %>
<% if ($iface->{gateway6}) { %>#     gateway6: "<%= $iface->{gateway6} %>"<% } %>
#     nameservers:
#       addresses:
<% for my $s (@{ $iface->{dns_servers} }) { %>#       - "<%= $s %>"
<% } %>
<% if ($iface->{domain}) { %>#       search:
#       - <%= $iface->{domain} %><% } %>
#  version: 2
