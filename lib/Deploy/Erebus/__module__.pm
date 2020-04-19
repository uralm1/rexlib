package Deploy::Erebus;

use Rex -feature=>['1.4'];
use Data::Dumper;
use File::Basename;
use DBI;
use NetAddr::IP;
use feature 'state';

# params
my %hostparam = (
  host => '',
  log_ip => '',
  ntp_ip => '',
  ssh_icmp_from_wans_ips => ['',],
  wans => [{wan_ip=>'',wan_netmask=>'',wan_gw=>'',wan_vlan=>''},],
  auto_wan_routes => [{name=>'',target=>'',netmask=>'',gateway=>''},],
  lan_ip => '',
  lan_netmask => '',
  lan_routes => [{name=>'',target=>'',netmask=>'',gateway=>''},],
  lan_dns => ['',],
  dhcp_on => 0,
  dhcp_start => 0,
  dhcp_limit => 0,
  dhcp_dns_suffix => '',
  dhcp_wins => '',
  tun_node_name => '',
  tun_node_ip => '',
  tun_subnet => '',
  tun_connect_nodes => [],
  tun_int_ip => '',
  tun_int_netmask => '',
  tun_pub_key => '',
  tun_priv_key => '',
  tun_array_ref => [],
);

##################################

### Helpers
my $dbh;

sub read_db {
  my $_host = shift;
  die "Hostname is empty. Invalid task parameters.\n" unless $_host; 
  die "Only *erebus* router is supported by this task.\n" unless $_host =~ /^erebus$/;

  $dbh = DBI->connect("DBI:mysql:database=".get(cmdb('dbname')).';host='.get(cmdb('dbhost')), get(cmdb('dbuser')), get(cmdb('dbpass'))) or 
    die "Connection to the database failed.\n";
  $dbh->do("SET NAMES 'UTF8'");

  my $hr = $dbh->selectrow_hashref("SELECT \
routers.id AS router_id, \
routers.host_name AS host, \
router_equipment.eq_name AS eq_name, \
router_equipment.manufacturer AS manufacturer, \
departments.dept_name AS dept_name, \
routers.log_ip AS log_ip, \
routers.ntp_ip AS ntp_ip, \
routers.ssh_icmp_from_wans_ips AS ssh_icmp_from_wans_ips_unparsed, \
lans.ip AS lan_ip, \
lans.mask AS lan_netmask, \
lans.routes AS lan_routes_unparsed, \
lans.dns_list AS lan_dns_unparsed, \
lans.dhcp_on AS dhcp_on, \
lans.dhcp_start_ip AS dhcp_start_ip_unparsed, \
lans.dhcp_limit AS dhcp_limit, \
lans.dhcp_dns_suffix AS dhcp_dns_suffix, \
lans.dhcp_wins AS dhcp_wins \
FROM routers \
INNER JOIN lans ON lans.router_id = routers.id \
LEFT OUTER JOIN router_equipment ON router_equipment.id = routers.equipment_id LEFT OUTER JOIN departments ON departments.id = routers.placement_dept_id \
WHERE host_name = ?", {}, $_host);
  die "There's no such host in the database, or database error.\n" unless $hr;
  #say Dumper $hr;

  %hostparam = %$hr;

  # read wans
  my $ar = $dbh->selectall_arrayref("SELECT \
ip AS wan_ip, \
mask AS wan_netmask, \
gw AS wan_gw, \
vlan AS wan_vlan \
FROM wans \
WHERE router_id = ?", {Slice=>{}, MaxRows=>10}, $hostparam{router_id});
  die "Fetching wans database failure.\n" unless $ar;
  #say Dumper $ar;

  push(@{$hostparam{wans}}, { %$_ }) for (@$ar);

=for comment
  # parse routes
  my @ra = split /;/, $hostparam{lan_routes_unparsed};
  my @rres;
  my $i = 1;
  foreach (@ra) {
    my @cr = split /,/, $_;
    push @rres, {name => 'l_'.$i, target => $cr[0], netmask => $cr[1], gateway => $cr[2]};
    $i++;
  }
  $hostparam{lan_routes} = \@rres;
=cut
  # parse dns_list
  $hostparam{lan_dns} = [split /,/, $hostparam{lan_dns_unparsed}];
  # parse dhcp_start
  if ($hostparam{dhcp_start_ip_unparsed} =~ /^(?:[0-9]{1,3}\.){3}([0-9]{1,3})$/) {
    $hostparam{dhcp_start} = $1;
  }
  # parse ssh_icmp_from_wans_ips
  $hostparam{ssh_icmp_from_wans_ips} = [split /,/, $hostparam{ssh_icmp_from_wans_ips_unparsed}];

=for comment
  # read vpn parameters
  $hr = $dbh->selectrow_hashref("SELECT \
routers.host_name AS tun_node_name, \
node_ip AS tun_node_ip, \
subnet AS tun_subnet, \
tun_ip AS tun_int_ip, \
tun_netmask AS tun_int_netmask, \
pub_key AS tun_pub_key, \
priv_key AS tun_priv_key \
FROM vpns \
INNER JOIN routers ON routers.id = router_id \
WHERE routers.host_name = ?", {}, $_host);
  die "There's no such vpn in the database, or database error.\n" unless $hr;
  #say Dumper $hr;
  %hostparam = (%hostparam, %$hr);

  $hostparam{tun_array_ref} = read_tunnels_tinc();
  #say Dumper $hostparam{tun_array_ref};

  # build tinc connect_to list of nodes
  my @tmp_list = grep { $_->{from_hostname} eq $hostparam{tun_node_name} } @{$hostparam{tun_array_ref}};
  #say Dumper \@tmp_list;
  say "WARNING!!! NO destination VPN tunnels are configured for this node. ConnectTo list will be empty." unless @tmp_list;

  $hostparam{tun_connect_nodes} = remove_dups([map { $_->{to_hostname} } @tmp_list]);
  foreach (@{$hostparam{tun_connect_nodes}}) {
    die "Invalid tunnel configuration! Source node connected to itself!\n" if $_ eq $hostparam{tun_node_name};
  }
  ### TODO: check if we can run without vpn configuration records

  # build route list
  my $sth = $dbh->prepare("SELECT \
host_name, \
wans.ip, \
wans.mask \
FROM routers \
INNER JOIN wans ON wans.router_id = routers.id");
  $sth->execute;
  my @w_route_list;
  RLIST: while (my $data = $sth->fetchrow_arrayref) {
    next RLIST if $data->[0] eq $_host; # skip self
    #say Dumper $data;
    my $dst_ip = NetAddr::IP->new($data->[1], $data->[2]);
    die "Invalid wan ip address while building route list" unless $dst_ip;
    my $_r_name = 'w_'.lc($data->[0]);
    my $_r_target = $dst_ip->network->addr; #say "Network ip: ".$_r_target;
    my $_r_netmask = $data->[2];
    # remove route target+netmask duplications
    RCHECK1: foreach (@w_route_list) {
      if ($_r_target eq $_->{target} && $_r_netmask eq $_->{netmask}) {
	say "NOTE: No route to $data->[0] will be build because the same route for $_->{name} has already been built.";
	next RLIST;
      }
    }
    # fix route name duplications
    my $i = 1;
    my $_prev_r_name = $_r_name;
    RCHECK2: foreach (@w_route_list) {
      if ($_r_name eq $_->{name}) {
	$_r_name = $_prev_r_name.'_'.$i;
	$i++;
        redo RCHECK2;
      }
    }
    push @w_route_list, {name => $_r_name, target => $_r_target, netmask => $_r_netmask, gateway => $hostparam{wan_gateway}};
  }
  $sth->finish;
  $hostparam{auto_wan_routes} = \@w_route_list;
  #say Dumper $hostparam{auto_wan_routes};
=cut
  say Dumper \%hostparam;

  $dbh->disconnect;
  say "Erebus configuration has successfully been read from the database.";
  1;
}


sub check_par {
  die "Hostname parameter is empty. Configuration wasn't read.\n" unless $hostparam{host}; 
  die "Unsupported operating system!\n" unless operating_system_is('OpenWrt');
  #say "OS version: ".operating_system_version();
  #say "OS release: ".operating_system_release();
  my $os_ver = operating_system_version();
  die "Unsupported firmware version!\n" if ($os_ver < 114 || $os_ver > 399);
  1;
}


sub uci {
  my $cmd = shift;
  my $output = run "uci $cmd", auto_die=>1, timeout=>10;
  say $output if $output;
};

sub quci {
  my $cmd = shift;
  my $output = run "uci -q $cmd", timeout=>10;
  say $output if $output;
};


#
### Configuration
#
desc "Erebus router: DEPLOY ROUTER
  rex -H 10.0.1.1 Deploy:Erebus:deploy_router [--confhost=erebus]";
task "deploy_router", sub {
  my $ch = shift->{confhost} || 'erebus';
  read_db $ch;
  check_par;

  say "Router deployment/Erebus/ started for $hostparam{host}";
  say "Router manufacturer from database: $hostparam{manufacturer}" if $hostparam{manufacturer};
  say "Router type from database: $hostparam{eq_name}" if $hostparam{eq_name};
  say "Department: $hostparam{dept_name}\n" if $hostparam{dept_name};
  #Deploy::Erebus::conf_system();
  #sleep 1;
  Deploy::Erebus::conf_net();
  sleep 1;
  #run_task "Deploy:Owrt:conf_fw", on=>connection->server;
  #sleep 1;
  #run_task "Deploy:Owrt:conf_tun", on=>connection->server;
  say "Router deployment/Erebus/ finished for $hostparam{host}";
  say "!!! Reboot router manually to apply changes !!!";
};


desc "Erebus router: Configure system parameters";
# if --confhost=erebus parameter is specified, host configuration is read
# from the database, otherwise uses current
task "conf_system", sub {
  my $ch = shift->{confhost};
  read_db $ch if $ch;
  check_par;

  say "System configuration started for $hostparam{host}";

  # disable failsafe mode prompt
  say "Disabling failsafe mode prompts.";
  file "/lib/preinit/30_failsafe_wait", ensure=>'absent';
  file "/lib/preinit/99_10_failsafe_login", ensure=>'absent';

  my $tpl_sys_file = 'files/system.x86.tpl';
  file "/etc/config/system",
    owner => "ural",
    group => "root",
    mode => 644,
    content => template($tpl_sys_file);
  say "/etc/config/system created.";

  file "/etc/banner",
    owner => "ural",
    group => "root",
    mode => 644,
    content => template("files/banner.0.tpl", _hostname=>$hostparam{host});
  say "banner updated.";

  uci "revert system";

  # system parameters
  uci "set system.\@system[0].hostname=\'$hostparam{host}\'";
  uci "set system.\@system[0].timezone=\'UTC-5\'";
  uci "set system.\@system[0].ttylogin=\'1\'";
  if (defined $hostparam{log_ip} && $hostparam{log_ip} ne '') {
    uci "set system.\@system[0].log_ip=\'$hostparam{log_ip}\'";
    uci "set system.\@system[0].log_port=\'514\'";
  }
  say "/etc/config/system configured.";

  # ntp
  uci "set system.ntp.enable_server=0";
  if (defined $hostparam{ntp_ip} && $hostparam{ntp_ip} ne '') {
    uci "set system.ntp.enabled=1";
    uci "delete system.ntp.server";
    uci "add_list system.ntp.server=\'$hostparam{ntp_ip}\'";
  } else {
    uci "set system.ntp.enabled=0";
  }
  say "NTP server configured.";

  #uci "show system";
  uci "commit system";

  say "System configuration finished for $hostparam{host}";
};


desc "Erebus router: Configure network";
# if --confhost=erebus parameter is specified, host configuration is read
# from the database, otherwise uses current
task "conf_net", sub {
  my $ch = shift->{confhost};
  read_db $ch if $ch;
  check_par;

  say "Network configuration started for $hostparam{host}";

  my $tpl_net_file = 'files/network.x86.tpl';
  my $lan_ifname = 'eth0';
  my $wan_ifname = 'eth1';
  my @extif_list;

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
  #uci "set network.lan.ipaddr=\'$hostparam{lan_ip}\'";
  #uci "set network.lan.netmask=\'$hostparam{lan_netmask}\'";
  uci "set network.lan.ipaddr=\'10.0.1.1\'"; #FIXME
  uci "set network.lan.netmask=\'255.192.0.0\'"; #FIXME
  uci "set network.lan.ipv6=0";
  uci "delete network.lan.type";

  # reorganize wans array to hash for aliasing support
  my %vif;
  push(@{$vif{$_->{wan_vlan}}}, $_) for (@{$hostparam{wans}});
  #say Dumper \%vif;

  for (sort keys %vif) {
    my $vid = $_;
    my $val = $vif{$_}; # aref
    my $aliasid = 0;
    # sort aliases by ip to keep things persistent
    for (sort {$a->{wan_ip} cmp $b->{wan_ip}} @$val) {
      uci "set network.wan_vlan${vid}_$aliasid=interface";
      uci "set network.wan_vlan${vid}_$aliasid.ifname=\'$wan_ifname.$vid\'";
      uci "set network.wan_vlan${vid}_$aliasid.proto=\'static\'";
      uci "set network.wan_vlan${vid}_$aliasid.ipaddr=\'$_->{wan_ip}\'";
      uci "set network.wan_vlan${vid}_$aliasid.netmask=\'$_->{wan_netmask}\'";
      uci "set network.wan_vlan${vid}_$aliasid.ipv6=0";
      push @extif_list, "wan_vlan${vid}_$aliasid";
      $aliasid++;
    }
  }

  quci "delete network.wan";
  quci "delete network.wan6";

  # rt_tables
  my $rt_file = '/etc/iproute2/rt_tables';
  append_or_amend_line $rt_file,
    line => '90	r_uwc',
    regexp => qr/^90\s+r_uwc$/;
  append_or_amend_line $rt_file,
    line => '100	r_beeline',
    regexp => qr/^100\s+r_beeline$/,
    on_change => sub {
      say "Routing tables r_uwc and r_beeline were added to rt_tables.";
    };

  # dns
  quci "delete network.lan.dns";
  foreach (@{$hostparam{lan_dns}}) {
    uci "add_list network.lan.dns=\'$_\'";
  }
  quci "delete network.lan.dns_search";
  #uci "add_list network.lan.dns_search=\'$hostparam{dhcp_dns_suffix}\'";
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
  uci "set dhcp.\@dnsmasq[0].domain=\'$hostparam{dhcp_dns_suffix}\'";
  quci "delete dhcp.\@dnsmasq[0].local";
  uci "set dhcp.\@dnsmasq[0].logqueries=0";

  quci "delete dhcp.\@dnsmasq[0].interface";
  uci "add_list dhcp.\@dnsmasq[0].interface=\'lan\'"; # dnsmasq listen only lan

  # wan is not used
  quci "delete dhcp.wan";
  # disable dhcp on external interfaces
  for (@extif_list) {
    uci "set dhcp.$_=dhcp";
    uci "set dhcp.$_.interface=\'$_\'";
    uci "set dhcp.$_.ignore=1";
  }
  # configure dhcp on lan
  uci "set dhcp.lan.start=\'$hostparam{dhcp_start}\'";
  uci "set dhcp.lan.limit=\'$hostparam{dhcp_limit}\'";
  uci "set dhcp.lan.leasetime=\'24h\'";
  # disable dhcp at all
  uci "set dhcp.lan.ignore=".(($hostparam{dhcp_on} > 0)?0:1);
  # only allow static leases
  #uci "set dhcp.lan.dynamicdhcp=0";
  # dhcpv6
  uci "set dhcp.lan.dhcpv6=\'disabled\'";
  uci "set dhcp.lan.ra=\'disabled\'";

  quci "delete dhcp.lan.dhcp_option";
  #uci "add_list dhcp.lan.dhcp_option=\'3,192.168.33.81\'"; #router
  #uci "add_list dhcp.lan.dhcp_option=\'6,10.14.0.2,10.14.0.1\'"; #dns
  uci "add_list dhcp.lan.dhcp_option=\'15,$hostparam{dhcp_dns_suffix}\'";
  uci "add_list dhcp.lan.dhcp_option=\'44,$hostparam{dhcp_wins}\'"; #wins
  uci "add_list dhcp.lan.dhcp_option=\'46,8\'";

  quci "delete dhcp.\@host[-1]" foreach 0..9;
  # static leases TODO
  #uci "add dhcp host";
  #uci "set dhcp.\@host[-1].ip=\'192.168.33.82\'";
  #uci "set dhcp.\@host[-1].mac=\'00:11:22:33:44:55\'";
  #uci "set dhcp.\@host[-1].name=\'host1\'";
  say "DHCP and DNS configured.";

  #uci "show network";
  #uci "show dhcp";
  uci "commit network";
  uci "commit dhcp";

  say "\nNetwork configuration finished for $hostparam{host}. Restarting the router will change the IP-s!!!.\n";
};


##################################
task "_t", sub {
  read_db 'gwtest2';
  check_par;

  #check_par;
  #say Dumper \%hostparam;
}, {dont_register => TRUE};

1;

=pod

=head1 NAME

$::module_name - {{ SHORT DESCRIPTION }}

=head1 DESCRIPTION

{{ LONG DESCRIPTION }}

=head1 USAGE

{{ USAGE DESCRIPTION }}

 include qw/Deploy::Erebus/;

 task yourtask => sub {
    Deploy::Erebus::example();
 };

=head1 TASKS

=over 4

=item example

This is an example Task. This task just output's the uptime of the system.

=back

=cut
