<% if ($iface->{domain}) { %>domain <%= $iface->{domain} %>
search <%= $iface->{domain} %><% } %>
<% for my $s (@{ $iface->{dns_servers} }) { %>nameserver <%= $s %>
<% } %>
