package Deploy::Owrt::Net;

use Rex -feature=>['1.4'];
#use Data::Dumper;

use Ural::Deploy::ReadDB_Owrt;
use Ural::Deploy::Utils qw(:DEFAULT is_x86);


desc "OWRT routers: Configure network";
# --confhost=host parameter is required
task "configure", sub {
  my $ch = shift->{confhost};
  my $p = read_db($ch);
  check_par_old;

  say 'Network configuration started for '.$p->get_host;

  my $tpl_net_file;
  my $lan_ifname;
  my $wan_ifname;
  if (is_x86()) {
    $tpl_net_file = 'files/network.x86.tpl';
    $lan_ifname = 'eth0';
    $wan_ifname = 'eth1';
  } else {
    $tpl_net_file = 'files/network.tp1043.tpl';
    $lan_ifname = 'eth1';
    $wan_ifname = 'eth0';
  }
  file "/etc/config/network",
    owner => "ural",
    group => "root",
    mode => 644,
    content => template($tpl_net_file);
  uci "revert network";

  # create new ula on first re-boot
  file "/etc/uci-defaults/12_network-generate-ula",
    source => "files/12_network-generate-ula";

  uci "set network.lan.ifname=\'$lan_ifname\'";
  uci "set network.lan.proto=\'static\'";
  uci "set network.lan.ipaddr=\'$p->{lan_ip}\'";
  uci "set network.lan.netmask=\'$p->{lan_netmask}\'";
  uci "set network.lan.ipv6=0";

  uci "set network.wan.ifname=\'$wan_ifname\'";
  uci "set network.wan.proto=\'static\'";
  uci "set network.wan.ipaddr=\'$p->{wan_ip}\'";
  uci "set network.wan.netmask=\'$p->{wan_netmask}\'";
  uci "set network.wan.gateway=\'$p->{gateway}\'";
  uci "set network.wan.ipv6=0";

  quci "delete network.wan6";

  # lan routes
  foreach (@{$p->{lan_routes}}) {
    my $t = $_->{'type'};
    my $n = $_->{'name'};
    if ($t == 1) { # 1 UNICAST
      uci "set network.$n=route";
      uci "set network.$n.interface=lan";
      uci "set network.$n.target=\'$_->{target}\'";
      uci "set network.$n.netmask=\'$_->{netmask}\'";
      uci "set network.$n.gateway=\'$_->{gateway}\'";
      #uci "set network.$n.table=$_->{table}" if $_->{table};
    } else {
      die "Unsupported route type: $t";
    }
  }

  # auto wan routes
  foreach (@{$p->{auto_wan_routes}}) {
    my $n = $_->{'name'};
    uci "set network.$n=route";
    uci "set network.$n.interface=wan";
    uci "set network.$n.target=\'$_->{target}\'";
    uci "set network.$n.netmask=\'$_->{netmask}\'";
    uci "set network.$n.gateway=\'$_->{gateway}\'";
  }
  say "Network routes configured.";

  # dns
  quci "delete network.lan.dns";
  foreach (@{$p->{dns}}) {
    uci "add_list network.lan.dns=\'$_\'";
  }
  quci "delete network.lan.dns_search";
  #uci "add_list network.lan.dns_search=\'$p->{dhcp_dns_suffix}\'";
  say "/etc/config/network created and configured.";

  # dhcp
  file "/etc/config/dhcp",
    owner => "ural",
    group => "root",
    mode => 644,
    content => template("files/dhcp.0.tpl");
  uci "revert dhcp";

  uci "set dhcp.\@dnsmasq[0].domainneeded=0";
  uci "set dhcp.\@dnsmasq[0].boguspriv=0";
  uci "set dhcp.\@dnsmasq[0].rebind_protection=0";
  uci "set dhcp.\@dnsmasq[0].domain=\'$p->{dns_suffix}\'";
  quci "delete dhcp.\@dnsmasq[0].local";
  uci "set dhcp.\@dnsmasq[0].logqueries=0";
  # add dhcphostfile option to /etc/config/dhcp
  uci "set dhcp.\@dnsmasq[0].dhcphostsfile=\'/var/r2d2/dhcphosts.clients\'";

  uci "set dhcp.lan.start=\'$p->{dhcp_start}\'";
  uci "set dhcp.lan.limit=\'$p->{dhcp_limit}\'";
  uci "set dhcp.lan.leasetime=\'$p->{dhcp_leasetime}\'";
  # disable dhcp at all
  uci "set dhcp.lan.ignore=".(($p->{dhcp_on} > 0)?0:1);
  # only allow static leases
  #uci "set dhcp.lan.dynamicdhcp=0";
  # dhcpv6
  uci "set dhcp.lan.dhcpv6=\'disabled\'";
  uci "set dhcp.lan.ra=\'disabled\'";

  quci "delete dhcp.lan.dhcp_option";
  #uci "add_list dhcp.lan.dhcp_option=\'3,192.168.33.81\'"; #router
  uci "add_list dhcp.lan.dhcp_option=\'6,$p->{dhcp_dns}\'" if $p->{dhcp_dns}; #dns
  uci "add_list dhcp.lan.dhcp_option=\'15,$p->{dhcp_dns_suffix}\'" if $p->{dhcp_dns_suffix};
  uci "add_list dhcp.lan.dhcp_option=\'44,$p->{dhcp_wins}\'" if $p->{dhcp_wins}; #wins
  uci "add_list dhcp.lan.dhcp_option=\'46,8\'";

  quci "delete dhcp.\@host[-1]" foreach 0..9;
  # static leases
  for (@{$p->{dhcp_static_leases}}) {
    uci "add dhcp host";
    uci "set dhcp.\@host[-1].ip=\'$_->{ip}\'";
    uci "set dhcp.\@host[-1].mac=\'$_->{mac}\'";
    uci "set dhcp.\@host[-1].name=\'$_->{name}\'";
  }
  say "DHCP and DNS configured.";

  #uci "show network";
  #uci "show dhcp";
  uci "commit network";
  uci "commit dhcp";
  insert_autogen_comment '/etc/config/network';
  insert_autogen_comment '/etc/config/dhcp';

  # patch /etc/init.d/dnsmasq to set --dhcphostsfile option always
  sed qr{\[\s+-e\s+\"\$hostsfile\"\s+\]\s+&&\s+xappend},
    'xappend',
    '/etc/init.d/dnsmasq',
    on_change => sub {
      say '/etc/init.d/dnsmasq: dhcphostsfile processing is patched to set always.';
    };

  say "\nNetwork configuration finished for $p->{host}. Restarting the router will change the IP-s and enable DHCP server on LAN!!!.\n";
};


1;

=pod

=head1 NAME

$::module_name - {{ SHORT DESCRIPTION }}

=head1 DESCRIPTION

{{ LONG DESCRIPTION }}

=head1 USAGE

{{ USAGE DESCRIPTION }}

 include qw/Deploy::Owrt::Net/;

 task yourtask => sub {
    Deploy::Owrt::Net::example();
 };

=head1 TASKS

=over 4

=item example

This is an example Task. This task just output's the uptime of the system.

=back

=cut
