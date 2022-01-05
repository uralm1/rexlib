*filter

# Firewall configuration for r2d2
:clients_in - [0:0]
:clients_out - [0:0]
:pipe_in_inet_clients - [0:0]
:pipe_out_inet_clients - [0:0]

<% if ($_r2d2_head_ip) { %># head access to wan
-A input_wan_rule -s <%= $_r2d2_head_ip %> -p tcp --sport 2271 -j ACCEPT
-A output_wan_rule -d <%= $_r2d2_head_ip %> -p tcp --dport 2271 -j ACCEPT

# gwsyn access from head
-A input_wan_rule -s <%= $_r2d2_head_ip %> -p tcp --dport 2275 -j ACCEPT
-A output_wan_rule -d <%= $_r2d2_head_ip %> -p tcp --sport 2275 -j ACCEPT<% } %>

# pass localnets
-A clients_in -s 10.0.0.0/8 -j ACCEPT
-A clients_out -d 10.0.0.0/8 -j ACCEPT
-A clients_in -s 192.168.0.0/16 -j ACCEPT
-A clients_out -d 192.168.0.0/16 -j ACCEPT
-A clients_in -s 172.16.0.0/12 -j ACCEPT
-A clients_out -d 172.16.0.0/12 -j ACCEPT
# internet access
-A clients_in -j pipe_in_inet_clients
-A clients_out -j pipe_out_inet_clients
# log and drop
-A clients_in -m limit --limit 3/min --limit-burst 3 -j LOG --log-level 6 --log-prefix "DROP inet in:"
-A clients_in -j DROP
-A clients_out -m limit --limit 3/min --limit-burst 3 -j LOG --log-level 6 --log-prefix "DROP inet out:"
-A clients_out -j DROP

-A forwarding_rule -s <%= $_client_net %> -j clients_out
-A forwarding_rule -d <%= $_client_net %> -j clients_in
COMMIT

*mangle
:pipe_in_inet_clients - [0:0]
:pipe_out_inet_clients - [0:0]

-A FORWARD -s <%= $_client_net %> -j pipe_out_inet_clients
-A FORWARD -d <%= $_client_net %> -j pipe_in_inet_clients
COMMIT
