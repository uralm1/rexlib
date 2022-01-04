package Deploy::Owrt::Net;

use Rex -feature=>['1.4'];
use Data::Dumper;
use NetAddr::IP::Lite;

use Ural::Deploy::ReadDB_Owrt;
use Ural::Deploy::Utils qw(:DEFAULT is_x86);


desc "OWRT routers: Configure network";
# --confhost=host parameter is required
task "configure", sub {
  my $ch = shift->{confhost};

  # obsolete code begin
  if (operating_system_version() < 117) {
    Deploy::Owrt::Net::obsolete::pre117::configure({confhost => $ch});
    exit 0;
  } # obsolete code end

  my $p = Ural::Deploy::ReadDB_Owrt->read_db($ch);
  check_dev $p;

  say 'Network configuration started for '.$p->get_host;

  my $router_os = router_os $p;
  if ($router_os =~ /^mips tp-link$/i) {
  } elsif ($router_os =~ /^mips mikrotik$/i) {
  } elsif ($router_os =~ /^x86$/i) {
  } else {
    die "Unsupported router_os!\n";
  }

  # we need /bin/config_generate
  my $config_generate = can_run('config_generate') or die "config_generate not found!\n";

  # recreate /etc/config/network
  file '/etc/config/network', ensure => 'absent';
  run $config_generate, auto_die=>1, timeout=>10;
  say "/etc/config/network created.";

  uci "revert network";
  uci "set network.globals.packet_steering=1"; # mikrotik only? FIXME

  # create new ula on first re-boot
  file "/etc/uci-defaults/12_network-generate-ula",
    source => "files/12_network-generate-ula";

  # cleanup interfaces
  quci "delete network.lan";
  quci "delete network.wan";
  quci "delete network.wan6";

  # lan
  my $gw = $p->{gateway} ? NetAddr::IP::Lite->new($p->{gateway}) : undef;
  my $ifs = $p->{lan_ifs};
  for (sort keys %$ifs) {
    my $if = $ifs->{$_};
    #my $part_vlan = $if->{vlan} ? ".$if->{vlan}" : '';
    if ($if->{vlan}) {
      say "WARNING: vlans not supported, interface $_ ignored!";
      next;
    }
    uci "set network.$_=interface";
    uci "set network.$_.device=\'br-lan\'";
    uci "set network.$_.proto=\'static\'";
    uci "set network.$_.ipaddr=\'$if->{ip}\'";
    uci "set network.$_.netmask=\'$if->{netmask}\'";
    my $net = NetAddr::IP::Lite->new($if->{ip}, $if->{netmask});
    uci "set network.$_.gateway=\'$p->{gateway}\'" if $gw && $net && $gw->within($net);
    uci "set network.$_.ipv6=0";
  }

  # wan
  $ifs = $p->{wan_ifs};
  for (sort keys %$ifs) {
    my $if = $ifs->{$_};
    #my $part_vlan = $if->{vlan} ? ".$if->{vlan}" : '';
    if ($if->{vlan}) {
      say "WARNING: vlans not supported, interface $_ ignored!";
      next;
    }
    uci "set network.$_=interface";
    uci "set network.$_.device=\'wan\'";
    uci "set network.$_.proto=\'static\'";
    uci "set network.$_.ipaddr=\'$if->{ip}\'";
    uci "set network.$_.netmask=\'$if->{netmask}\'";
    my $net = NetAddr::IP::Lite->new($if->{ip}, $if->{netmask});
    uci "set network.$_.gateway=\'$p->{gateway}\'" if $gw && $net && $gw->within($net);
    uci "set network.$_.ipv6=0";
  }

  # routes
  for my $ifs ($p->{lan_ifs}, $p->{wan_ifs}) {
    for (sort keys %$ifs) {
      my $r_interface = $_;
      if (my $r = $ifs->{$_}{routes}) {
	for (@$r) {
	  my $t = $_->{type};
	  my $n = $_->{name};
	  if ($t == 1) { # 1 UNICAST
	    uci "set network.$n.interface=$r_interface";
	    uci "set network.$n.target=$_->{target}";
	    uci "set network.$n.netmask=$_->{netmask}";
	    uci "set network.$n.gateway=$_->{gateway}";
	    #uci "set network.$n.table=$_->{table}" if $_->{table};
	    say "WARNING: table not supported and ignored in route $n!" if $_->{table};
	  } else {
	    die  "Unsupported route type: $t";
	  }
	}
      }
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

  say "/etc/config/network created and configured.";

  # dhcp FIXME
  file "/etc/config/dhcp",
    owner => "ural",
    group => "root",
    mode => 644,
    content => template('files/dhcp.117.tpl');
  uci "revert dhcp";

  uci "set dhcp.\@dnsmasq[0].domainneeded=0";
  uci "set dhcp.\@dnsmasq[0].boguspriv=0";
  uci "set dhcp.\@dnsmasq[0].rebind_protection=0";
  uci "set dhcp.\@dnsmasq[0].domain=\'$p->{dns_suffix}\'";
  quci "delete dhcp.\@dnsmasq[0].local";
  uci "set dhcp.\@dnsmasq[0].logqueries=0";
  # add dhcphostfile option to /etc/config/dhcp
  uci "set dhcp.\@dnsmasq[0].dhcphostsfile=\'/etc/r2d2/dhcphosts.clients\'";

  uci "set dhcp.lan.start=\'$p->{dhcp_start}\'";
  uci "set dhcp.lan.limit=\'$p->{dhcp_limit}\'";
  uci "set dhcp.lan.leasetime=\'$p->{dhcp_leasetime}\'";
  # disable dhcp at all
  if ($p->{dhcp_on} > 0) {
    uci "set dhcp.lan.ignore=0";
    uci "set dhcp.lan.dhcpv4=\'server\'";
  } else {
    uci "set dhcp.lan.ignore=1";
    uci "set dhcp.lan.dhcpv4=\'disabled\'";
  }
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

  file "/etc/r2d2",
    owner => "ural",
    group => "root",
    mode => 755,
    ensure => "directory";

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
