package Deploy::Erebus::Net;

use Rex -feature=>['1.4'];
use Data::Dumper;
use NetAddr::IP::Lite;

use Ural::Deploy::ReadDB_Erebus;
use Ural::Deploy::Utils;


desc "Erebus router: Configure network";
# --confhost=erebus is required
task "configure", sub {
  my $ch = shift->{confhost};
  my $p = read_db($ch);
  check_par;

  say 'Network configuration started for '.$p->get_host;

  my $network_file = '/etc/config/network';
  file $network_file,
    owner => "ural",
    group => "root",
    mode => 644,
    content => template('files/network.x86.tpl');
  uci "revert network";

  # create new ula on first re-boot
  file "/etc/uci-defaults/12_network-generate-ula",
    source => "files/12_network-generate-ula";

  quci "delete network.lan";
  quci "delete network.wan";
  quci "delete network.wan6";

  my $lan_ifname = 'eth0';
  my $wan_ifname = 'eth1';

  # lan
  my $gw = ($p->{gateway}) ? NetAddr::IP::Lite->new($p->{gateway}) : undef;
  my $ifs_r = $p->{lan_ifs};
  for (sort keys %$ifs_r) {
    my $if_r = $ifs_r->{$_};
    my $part_vlan = ($if_r->{vlan}) ? ".$if_r->{vlan}" : '';
    uci "set network.$_=interface";
    uci "set network.$_.ifname=\'$lan_ifname$part_vlan\'";
    uci "set network.$_.proto=\'static\'";
    uci "set network.$_.ipaddr=\'$if_r->{ip}\'";
    uci "set network.$_.netmask=\'$if_r->{netmask}\'";
    my $net = NetAddr::IP::Lite->new($if_r->{ip}, $if_r->{netmask});
    uci "set network.$_.gateway=\'$p->{gateway}\'" if ($gw && $net && $gw->within($net));
    uci "set network.$_.ipv6=0";
  }
  # wan
  $ifs_r = $p->{wan_ifs};
  for (sort keys %$ifs_r) {
    my $if_r = $ifs_r->{$_};
    my $part_vlan = ($if_r->{vlan}) ? ".$if_r->{vlan}" : '';
    uci "set network.$_=interface";
    uci "set network.$_.ifname=\'$wan_ifname$part_vlan\'";
    uci "set network.$_.proto=\'static\'";
    uci "set network.$_.ipaddr=\'$if_r->{ip}\'";
    uci "set network.$_.netmask=\'$if_r->{netmask}\'";
    my $net = NetAddr::IP::Lite->new($if_r->{ip}, $if_r->{netmask});
    uci "set network.$_.gateway=\'$p->{gateway}\'" if ($gw && $net && $gw->within($net));
    uci "set network.$_.ipv6=0";
  }
  #uci "set network.lan.ipaddr=\'10.0.1.1\'"; #FIXME
  #uci "set network.lan.netmask=\'255.192.0.0\'"; #FIXME

  # rt_tables
  my $rt_file = '/etc/iproute2/rt_tables';
  file $rt_file,
    owner => "ural",
    group => "root",
    mode => 644,
    source => "files/rt_tables",
    on_change => sub { say "/etc/iproute2/rt_tables created." };

  my $h = $p->{hacks}{rt_tables_config};
  append_if_no_such_line($rt_file,
    line => $h,
    on_change => sub {
      say "Hack rt_tables_config was added to rt_tables.";
    }
  ) if $h;

  # routes
  for my $ifs_r ($p->{lan_ifs}, $p->{wan_ifs}) {
    for (sort keys %$ifs_r) {
      my $r_interface = $_;
      my $r = $ifs_r->{$_}{routes};
      if ($r) {
	for (@$r) {
	  my $t = $_->{type};
	  my $n = $_->{name};
	  if ($t == 1 || $t == 9) { # 1 UNICAST / 9 surrogate IPSEC
	    uci "set network.$n=route";
	    uci "set network.$n.interface=$r_interface";
	    uci "set network.$n.target=$_->{target}";
	    uci "set network.$n.netmask=$_->{netmask}";
	    uci "set network.$n.gateway=$_->{gateway}";
	    uci "set network.$n.table=$_->{table}" if $_->{table};
	  } else {
	    die "Unsupported route type: $t";
	  }
	}
      }
    }
  }

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
  # dns
  uci "set dhcp.\@dnsmasq[0].domain=\'$p->{dns_suffix}\'";
  quci "delete dhcp.\@dnsmasq[0].local";
  quci "delete dhcp.\@dnsmasq[0].server";
  foreach (@{$p->{dns}}) {
    uci "add_list dhcp.\@dnsmasq[0].server=\'$_\'";
  }

  uci "set dhcp.\@dnsmasq[0].logqueries=0";

  #quci "delete dhcp.\@dnsmasq[0].interface";
  #uci "add_list dhcp.\@dnsmasq[0].interface=\'lan\'"; # dnsmasq listen only lan

  # lan, wan is not used
  quci "delete dhcp.lan";
  quci "delete dhcp.wan";

  # dhcp configuration for interfaces
  for my $ifs_r ($p->{lan_ifs}, $p->{wan_ifs}) {
    for (sort keys %$ifs_r) {
      uci "set dhcp.$_=dhcp"; # $_ interface
      uci "set dhcp.$_.interface=\'$_\'";
      if ($ifs_r->{$_}{dhcp_on} > 0) {
	uci "set dhcp.$_.ignore=0";
	uci "set dhcp.$_.start=\'$ifs_r->{$_}{dhcp_start}\'";
	uci "set dhcp.$_.limit=\'$ifs_r->{$_}{dhcp_limit}\'";
	uci "set dhcp.$_.leasetime=\'$ifs_r->{$_}{dhcp_leasetime}\'";
	# only allow static leases
	#uci "set dhcp.$_.dynamicdhcp=0";
	# dhcpv6
	uci "set dhcp.$_.dhcpv6=\'disabled\'";
	uci "set dhcp.$_.ra=\'disabled\'";

	quci "delete dhcp.$_.dhcp_option";
	#uci "add_list dhcp.$_.dhcp_option=\'3,192.168.33.81\'"; #router
	uci "add_list dhcp.$_.dhcp_option=\'6,$ifs_r->{$_}{dhcp_dns}\'" if $ifs_r->{$_}{dhcp_dns}; #dns
	uci "add_list dhcp.$_.dhcp_option=\'15,$ifs_r->{$_}{dhcp_dns_suffix}\'";
	uci "add_list dhcp.$_.dhcp_option=\'44,$ifs_r->{$_}{dhcp_wins}\'"; #wins
	uci "add_list dhcp.$_.dhcp_option=\'46,8\'";
      } else {
        # disable dhcp at all
        uci "set dhcp.$_.ignore=1";
      }
    }
  }
  quci "delete dhcp.\@host[-1]" foreach 0..9;
  # static leases
  for my $ifs_r ($p->{lan_ifs}, $p->{wan_ifs}) {
    for (sort keys %$ifs_r) {
      if ($ifs_r->{$_}{dhcp_on} > 0) {
        for my $l (@{$ifs_r->{$_}{dhcp_static_leases}}) {
	  uci "add dhcp host";
	  uci "set dhcp.\@host[-1].ip=\'$l->{ip}\'";
	  uci "set dhcp.\@host[-1].mac=\'$l->{mac}\'";
	  uci "set dhcp.\@host[-1].name=\'$l->{name}\'";
        }
      }
    }
  }

  say "DHCP and DNS configured.";

  #uci "show network";
  #uci "show dhcp";
  uci "commit network";
  uci "commit dhcp";
  insert_autogen_comment $network_file;
  insert_autogen_comment '/etc/config/dhcp';

  # append ip_rules_config hack to network
  $h = $p->{hacks}{ip_rules_config};
  append_if_no_such_line($network_file,
    line => $h,
    on_change => sub {
      say "Hack ip_rules_config was added to /etc/config/network.";
    }
  ) if $h;

  say "\nNetwork configuration finished for $p->{host}. Restarting the router will change the IP-s!!!.\n";
};


##################################
desc "Erebus router: reload network (useful after updating routes or dhcp)";
task "reload", sub {
  say "Reloading network configuration on host ".connection->server." ...";
  #service network => 'reload';
  my $output = run "/etc/init.d/network reload 2>&1", timeout => 100;
  say $output if $output;
  return (($? > 0) ? 255:0);
};


1;

=pod

=head1 NAME

$::module_name - {{ SHORT DESCRIPTION }}

=head1 DESCRIPTION

{{ LONG DESCRIPTION }}

=head1 USAGE

{{ USAGE DESCRIPTION }}

 include qw/Deploy::Erebus::Net/;

 task yourtask => sub {
    Deploy::Erebus::Net::example();
 };

=head1 TASKS

=over 4

=item example

This is an example Task. This task just output's the uptime of the system.

=back

=cut
