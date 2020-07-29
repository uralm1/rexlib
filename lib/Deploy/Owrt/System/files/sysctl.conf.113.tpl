# This file is autogenerated. All changes will be overwritten!
kernel.panic=3
net.ipv4.conf.default.arp_ignore=1
net.ipv4.conf.all.arp_ignore=1
net.ipv4.ip_forward=1
net.ipv4.icmp_echo_ignore_broadcasts=1
net.ipv4.icmp_ignore_bogus_error_responses=1
net.ipv4.igmp_max_memberships=100
net.ipv4.tcp_ecn=0
net.ipv4.tcp_fin_timeout=30
net.ipv4.tcp_keepalive_time=120
net.ipv4.tcp_syncookies=1
net.ipv4.tcp_timestamps=1
net.ipv4.tcp_sack=1
net.ipv4.tcp_dsack=1

net.ipv6.conf.default.forwarding=1
net.ipv6.conf.all.forwarding=1

net.netfilter.nf_conntrack_acct=1

# disable bridge firewalling by default
net.bridge.bridge-nf-call-arptables=0
net.bridge.bridge-nf-call-ip6tables=0
net.bridge.bridge-nf-call-iptables=0

net.ipv4.ip_local_port_range=8192 65535
net.netfilter.nf_conntrack_max=262144
net.netfilter.nf_conntrack_generic_timeout=300
net.netfilter.nf_conntrack_tcp_timeout_syn_sent=60
net.netfilter.nf_conntrack_tcp_timeout_syn_recv=60
net.netfilter.nf_conntrack_tcp_timeout_established=1200
net.netfilter.nf_conntrack_tcp_timeout_fin_wait=60
net.netfilter.nf_conntrack_tcp_timeout_close_wait=60
net.netfilter.nf_conntrack_tcp_timeout_last_ack=30
net.netfilter.nf_conntrack_tcp_timeout_time_wait=120
net.netfilter.nf_conntrack_tcp_timeout_close=10
net.netfilter.nf_conntrack_tcp_timeout_max_retrans=300
net.netfilter.nf_conntrack_tcp_timeout_unacknowledged=300
net.netfilter.nf_conntrack_udp_timeout=30
net.netfilter.nf_conntrack_udp_timeout_stream=60
net.netfilter.nf_conntrack_icmp_timeout=30
net.netfilter.nf_conntrack_icmpv6_timeout=30
net.netfilter.nf_conntrack_checksum=0
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.all.accept_redirects=0
