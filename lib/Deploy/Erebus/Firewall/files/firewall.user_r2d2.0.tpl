*filter

# Firewall configuration for r2d2

<% if ($_r2d2_head_ip) { %># head access to lan
-A input_lan_rule -s <%= $_r2d2_head_ip %> -p tcp --sport 2271 -j ACCEPT
-A output_lan_rule -d <%= $_r2d2_head_ip %> -p tcp --dport 2271 -j ACCEPT

# rtsyn access from head
-A input_lan_rule -s <%= $_r2d2_head_net %> -p tcp --dport 2275 -j ACCEPT
-A output_lan_rule -d <%= $_r2d2_head_net %> -p tcp --sport 2275 -j ACCEPT<% } %>

COMMIT

*mangle
:pipe_out_inet_clients - [0:0]

-A PREROUTING -s <%= $_client_net %> -j pipe_out_inet_clients

COMMIT
