package Deploy::Owrt;

use Rex -feature=>['1.3'];
use Data::Dumper;
use File::Basename;
use DBI;
use NetAddr::IP;
use feature 'state';

my $def_net = "UWC66";

# params
my %hostparam = (
  host => '',
  gateway => '',
  dns => ['',],
  dns_suffix => '',
  log_ip => '',
  ntp_ip => '',
  ssh_icmp_from_wans_ips => ['',],
  wan_ip => '',
  wan_netmask => '',
  auto_wan_routes => [{name=>'',target=>'',netmask=>'',gateway=>''},],
  lan_ip => '',
  lan_netmask => '',
  lan_routes => [{name=>'',target=>'',netmask=>'',gateway=>''},],
  dhcp_on => 0,
  dhcp_start => 0,
  dhcp_limit => 0,
  dhcp_leasetime => '',
  dhcp_dns => '',
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


### Pre-installaion tasks for images
desc "Install perl for Rex, for images<1.9";
task "install_perl", sub {
  my $output = run "opkg install perl perlbase-bytes perlbase-data perlbase-digest perlbase essential perlbase-file perlbase-xsloader";
  say $output;
}, {dont_register => TRUE};

desc "Create openwrt_release, openwrt_version for Rex, for images<1.10";
task "fix_openwrt_detect", sub {
  my $output = run "touch /etc/openwrt_release /etc/openwrt_version";
  say $output;
}, {dont_register => TRUE};


desc "x86 primary configuration: enable login, disable startup failsafe prompt";
task "x86_preconf", sub {
  die "Unsupported operating system!\n" unless operating_system_is('OpenWrt');
  my $os_ver = operating_system_version();
  die "Unsupported firmware version!\n" if ($os_ver < 113 || $os_ver > 113);
  die "Unsupported system architecture!\n" unless is_x86();

  say "Primary x86 configuration started...";
  # enable login on consoles
  say "Activating login on consoles.";
  # check /bin/login
  die "Fatal error: /bin/login is not compiled.\n" unless (is_file("/bin/login"));
  # fix inittab
  sed qr/::askfirst:\/bin\/ash +--login$/, '::askfirst:/bin/login', '/etc/inittab';

  # disable failsafe mode prompt
  say "Disabling failsafe mode prompts.";
  file "/lib/preinit/30_failsafe_wait", ensure=>'absent';
  file "/lib/preinit/99_10_failsafe_login", ensure=>'absent';

  say "Primary x86 configuration finished. Reboot router to apply settings.";
};


##################################

### Helpers
my $dbh;

sub read_db {
  my ($_host, %args) = @_;
  die "Hostname is empty. Invalid task parameters.\n" unless $_host; 
  die "Erebus router must be configured by Deploy:Erebus:* tasks.\n" if (!$args{skip_erebus_check} && $_host =~ /^erebus$/); 

  $dbh = DBI->connect("DBI:mysql:database=".get(cmdb('dbname')).';host='.get(cmdb('dbhost')), get(cmdb('dbuser')), get(cmdb('dbpass'))) or 
    die "Connection to the database failed.\n";
  $dbh->do("SET NAMES 'UTF8'");

  my $hr = $dbh->selectrow_hashref("SELECT \
routers.host_name AS host, \
router_equipment.eq_name AS eq_name, \
router_equipment.manufacturer AS manufacturer, \
departments.dept_name AS dept_name, \
routers.gateway AS gateway, \
routers.dns_list AS dns_unparsed, \
routers.dns_suffix AS dns_suffix, \
routers.log_ip AS log_ip, \
routers.ntp_ip AS ntp_ip, \
routers.ssh_icmp_from_wans_ips AS ssh_icmp_from_wans_ips_unparsed, \
wans.ip AS wan_ip, \
wn.mask AS wan_netmask, \
lans.ip AS lan_ip, \
ln.mask AS lan_netmask, \
lans.routes AS lan_routes_unparsed, \
lans.dhcp_on AS dhcp_on, \
ln.dhcp_start_ip AS dhcp_start, \
ln.dhcp_limit AS dhcp_limit, \
ln.dhcp_leasetime AS dhcp_leasetime, \
ln.dhcp_dns AS dhcp_dns, \
ln.dhcp_dns_suffix AS dhcp_dns_suffix, \
ln.dhcp_wins AS dhcp_wins \
FROM routers \
INNER JOIN interfaces wans ON wans.router_id = routers.id AND wans.type = 1 \
INNER JOIN nets wn ON wn.id = wans.net_id \
INNER JOIN interfaces lans ON lans.router_id = routers.id AND lans.type = 2 \
INNER JOIN nets ln ON ln.id = lans.net_id \
LEFT OUTER JOIN router_equipment ON router_equipment.id = routers.equipment_id \
LEFT OUTER JOIN departments ON departments.id = routers.placement_dept_id \
WHERE host_name = ?", {}, $_host);
  die "There's no such host in the database, or database error.\n" unless $hr;
  #say Dumper $hr;

  %hostparam = %$hr;
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
  # parse dns_list
  $hostparam{dns} = [split /,/, $hostparam{dns_unparsed}];
  # parse dhcp_start
  if ($hostparam{dhcp_start} =~ /^(?:[0-9]{1,3}\.){3}([0-9]{1,3})$/) {
    $hostparam{dhcp_start} = $1;
  }
  # parse ssh_icmp_from_wans_ips
  $hostparam{ssh_icmp_from_wans_ips} = [split /,/, $hostparam{ssh_icmp_from_wans_ips_unparsed}];

  # read vpn parameters
  $hr = $dbh->selectrow_hashref("SELECT \
routers.host_name AS tun_node_name, \
ifs.ip AS tun_node_ip, \
nets.net_ip AS tun_subnet_ip, \
nets.mask AS tun_subnet_mask, \
tun_ip AS tun_int_ip, \
tun_netmask AS tun_int_netmask, \
pub_key AS tun_pub_key, \
priv_key AS tun_priv_key \
FROM vpns \
INNER JOIN routers ON routers.id = router_id \
INNER JOIN nets ON nets.id = subnet_id \
INNER JOIN interfaces ifs ON ifs.id = node_if_id \
WHERE routers.host_name = ?", {}, $_host);
  die "There's no such vpn in the database, or database error.\n" unless $hr;
  #say Dumper $hr;
  %hostparam = (%hostparam, %$hr);

  my $net = NetAddr::IP->new($hr->{tun_subnet_ip}, $hr->{tun_subnet_mask}) or
    die("Invalid vpn subnet address or mask!\n");
  $hostparam{tun_subnet} = $net->cidr;

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
wn.mask \
FROM routers \
INNER JOIN interfaces wans ON wans.router_id = routers.id AND wans.type = 1 \
INNER JOIN nets wn ON wn.id = wans.net_id");
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
    push @w_route_list, {name => $_r_name, target => $_r_target, netmask => $_r_netmask, gateway => $hostparam{gateway}};
  }
  $hostparam{auto_wan_routes} = \@w_route_list;
  #say Dumper $hostparam{auto_wan_routes};

  $dbh->disconnect;
  say "Host configuration has successfully been read from the database.";
  1;
}


sub remove_dups {
  my $aref = shift;
  my %seen;
  return [grep { ! $seen{ $_ }++ } @$aref];
}


sub read_tunnels_tinc {
  my $s = $dbh->prepare("SELECT \
t.id AS id, \
r1.host_name AS from_hostname, \
ifs1.ip AS from_ip, \
r2.host_name AS to_hostname, \
ifs2.ip AS to_ip \
FROM tunnels t \
INNER JOIN vpns v1 ON t.vpn_from_id = v1.id \
INNER JOIN routers r1 ON v1.router_id = r1.id \
INNER JOIN interfaces ifs1 ON v1.node_if_id = ifs1.id \
INNER JOIN vpns v2 ON t.vpn_to_id = v2.id \
INNER JOIN routers r2 ON v2.router_id = r2.id \
INNER JOIN interfaces ifs2 ON v2.node_if_id = ifs2.id \
WHERE t.vpn_type_id = 1");
  $s->execute;
  my @t_arr;
  while (my $hr = $s->fetchrow_hashref) {
    #say Dumper $hr;
    push @t_arr, $hr;
  }
  return \@t_arr;
}


sub recursive_search_by_from_hostname {
  my $listref = shift;
  my $hostname = shift;

  state $loop_control = 0;
  die "Wrong tunnels configuration (reqursive infinite loop found).\n" if $loop_control++ >= 30;

  my @tt1 = grep { $_->{from_hostname} eq $hostname } @{$hostparam{tun_array_ref}};
  foreach my $hh1 (@tt1) {
    unless ((grep { $_ eq $hh1->{to_ip} } @$listref) || ($hh1->{to_hostname} eq $hostparam{tun_node_name})) {
      push @$listref, $hh1->{to_ip};
      recursive_search_by_from_hostname($listref, $hh1->{to_hostname});
    }
  }
}


sub recursive_search_by_to_hostname {
  my $listref = shift;
  my $hostname = shift;

  state $loop_control = 0;
  die "Wrong tunnels configuration (reqursive infinite loop found).\n" if $loop_control++ >= 30;

  my @tt1 = grep { $_->{to_hostname} eq $hostname } @{$hostparam{tun_array_ref}};
  foreach my $hh1 (@tt1) {
    unless ((grep { $_ eq $hh1->{from_ip} } @$listref) || ($hh1->{from_hostname} eq $hostparam{tun_node_name})) {
      push @$listref, $hh1->{from_ip};
      recursive_search_by_to_hostname($listref, $hh1->{from_hostname});
    }
  }
}


sub check_par {
  die "Hostname parameter is empty. Configuration wasn't read.\n" unless $hostparam{host}; 
  die "Unsupported operating system!\n" unless operating_system_is('OpenWrt');
  #say "OS version: ".operating_system_version();
  #say "OS release: ".operating_system_release();
  my $os_ver = operating_system_version();
  die "Unsupported firmware version!\n" if ($os_ver < 113 || $os_ver > 399);
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


sub insert_autogen_comment {
  my $file = shift;
  my $autogen_comment = '# This file is autogenerated. All changes will be overwritten!';
  my $output = run "sed -i \'1i $autogen_comment\' $file", timeout=>10;
  say $output if $output;
}


sub is_x86 {
  # check kernel architecture
  my %i = get_system_information;
  return ($i{architecture} =~ /i\d86/);
};


desc "OWRT routers: Show router information";
task "show_router", sub {
  #dump_system_information;
  my %i = get_system_information;
  #say Dumper \%info;
  say "This is: $i{hostname}, $i{operating_system} system (arch: $i{architecture}), version: $i{operating_system_release}.";
  if (operating_system_is('OpenWrt')) {
    my $r = run "uci get system.\@system[0].hostname";
    say "Hostname configured as: $r, actual: $i{hostname}.";
  }
  my $r = run "uptime";
  say "Host up time is: $r.";
  say "Memory total/free/used: $i{memory_total}/$i{memory_free}/$i{memory_used}.";
  say "Network interfaces:";
  my $net_info = $i{Network}->{networkconfiguration};
  for my $dev (keys %$net_info) {
    say " $dev ip: ".$net_info->{$dev}->{ip}." netmask: ".$net_info->{$dev}->{netmask};
  }
};


#
### Configuration
#
desc "OWRT routers: DEPLOY ROUTER
  rex -H 10.0.1.1 deploy_router --confhost=gwtest1";
task "deploy_router", sub {
  my $ch = shift->{confhost};
  read_db $ch;
  check_par;

  say "Router deployment/OpenWRT/ started for $hostparam{host}";
  say "Router manufacturer from database: $hostparam{manufacturer}" if $hostparam{manufacturer};
  say "Router type from database: $hostparam{eq_name}" if $hostparam{eq_name};
  say "Department: $hostparam{dept_name}\n" if $hostparam{dept_name};
  Deploy::Owrt::conf_system();
  sleep 1;
  Deploy::Owrt::conf_net();
  sleep 1;
  Deploy::Owrt::conf_fw();
  sleep 1;
  Deploy::Owrt::conf_tun();
  say "Router deployment/OpenWRT/ finished for $hostparam{host}";
  say "!!! Reboot router manually to apply changes !!!";
};



desc "OWRT routers: Configure system parameters";
# if --confhost=host parameter is specified, host configuration is read
# from the database, otherwise uses current
task "conf_system", sub {
  my $ch = shift->{confhost};
  read_db $ch if $ch;
  check_par;

  say "System configuration started for $hostparam{host}";

  my $tpl_sys_file = is_x86() ? 'files/system.x86.tpl' : 'files/system.tp1043.tpl';
  file "/etc/config/system",
    owner => "ural",
    group => "root",
    mode => 644,
    content => template($tpl_sys_file),
    on_change => sub { say "/etc/config/system created." };

  file "/etc/banner",
    owner => "ural",
    group => "root",
    mode => 644,
    content => template("files/banner.0.tpl", _hostname=>$hostparam{host}),
    on_change => sub { say "banner updated." };

  uci "revert system";

  # system parameters
  uci "set system.\@system[0].hostname=\'$hostparam{host}\'";
  uci "set system.\@system[0].timezone=\'UTC-5\'";
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
  insert_autogen_comment '/etc/config/system';

  say "System configuration finished for $hostparam{host}";
};


desc "OWRT routers: Configure network";
# if --confhost=host parameter is specified, host configuration is read
# from the database, otherwise uses current
task "conf_net", sub {
  my $ch = shift->{confhost};
  read_db $ch if $ch;
  check_par;

  say "Network configuration started for $hostparam{host}";

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
  uci "set network.lan.ipaddr=\'$hostparam{lan_ip}\'";
  uci "set network.lan.netmask=\'$hostparam{lan_netmask}\'";
  uci "set network.lan.ipv6=0";

  uci "set network.wan.ifname=\'$wan_ifname\'";
  uci "set network.wan.proto=\'static\'";
  uci "set network.wan.ipaddr=\'$hostparam{wan_ip}\'";
  uci "set network.wan.netmask=\'$hostparam{wan_netmask}\'";
  uci "set network.wan.gateway=\'$hostparam{gateway}\'";
  uci "set network.wan.ipv6=0";

  quci "delete network.wan6";

  # lan routes
  foreach (@{$hostparam{lan_routes}}) {
    my $rname = $_->{'name'};
    uci "set network.$rname=\'route\'";
    uci "set network.$rname.interface=\'lan\'";
    uci "set network.$rname.target=\'$_->{target}\'";
    uci "set network.$rname.netmask=\'$_->{netmask}\'";
    uci "set network.$rname.gateway=\'$_->{gateway}\'";
  }

  # auto wan routes
  foreach (@{$hostparam{auto_wan_routes}}) {
    my $rname = $_->{'name'};
    uci "set network.$rname=\'route\'";
    uci "set network.$rname.interface=\'wan\'";
    uci "set network.$rname.target=\'$_->{target}\'";
    uci "set network.$rname.netmask=\'$_->{netmask}\'";
    uci "set network.$rname.gateway=\'$_->{gateway}\'";
  }
  say "Network routes configured.";

  # dns
  quci "delete network.lan.dns";
  foreach (@{$hostparam{dns}}) {
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
  uci "set dhcp.\@dnsmasq[0].domain=\'$hostparam{dns_suffix}\'";
  quci "delete dhcp.\@dnsmasq[0].local";
  uci "set dhcp.\@dnsmasq[0].logqueries=0";

  uci "set dhcp.lan.start=\'$hostparam{dhcp_start}\'";
  uci "set dhcp.lan.limit=\'$hostparam{dhcp_limit}\'";
  uci "set dhcp.lan.leasetime=\'$hostparam{dhcp_limit}\'";
  # disable dhcp at all
  uci "set dhcp.lan.ignore=".(($hostparam{dhcp_on} > 0)?0:1);
  # only allow static leases
  #uci "set dhcp.lan.dynamicdhcp=0";
  # dhcpv6
  uci "set dhcp.lan.dhcpv6=\'disabled\'";
  uci "set dhcp.lan.ra=\'disabled\'";

  quci "delete dhcp.lan.dhcp_option";
  #uci "add_list dhcp.lan.dhcp_option=\'3,192.168.33.81\'"; #router
  uci "add_list dhcp.lan.dhcp_option=\'6,$hostparam{dhcp_dns}\'" if $hostparam{dhcp_dns}; #dns
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
  insert_autogen_comment '/etc/config/network';
  insert_autogen_comment '/etc/config/dhcp';

  say "\nNetwork configuration finished for $hostparam{host}. Restarting the router will change the IP-s and enable DHCP server on LAN!!!.\n";
};


desc "OWRT routers: Configure firewall";
# if --confhost=host parameter is specified, host configuration is read
# from the database, otherwise uses current
task "conf_fw", sub {
  my $ch = shift->{confhost};
  read_db $ch if $ch;
  check_par;

  say "Firewall configuration started for $hostparam{host}";

  pkg "firewall", ensure => "present";

  file "/etc/config/firewall",
    owner => "ural",
    group => "root",
    mode => 644,
    content => template("files/firewall.0.tpl");

  uci "revert firewall";
  foreach (@{$hostparam{ssh_icmp_from_wans_ips}}) {
    # icmp-wan-in-xxx
    uci "add firewall rule";
    #uci "set firewall.\@rule[-1].name=\'icmp-wan-in-$_\'";
    uci "set firewall.\@rule[-1].src=wan";
    uci "set firewall.\@rule[-1].proto=icmp";
    uci "set firewall.\@rule[-1].src_ip=\'$_\'";
    uci "set firewall.\@rule[-1].target=ACCEPT";
    # ssh-wan-in-xxx
    uci "add firewall rule";
    #uci "set firewall.\@rule[-1].name=\'ssh-wan-in-$_\'";
    uci "set firewall.\@rule[-1].src=wan";
    uci "set firewall.\@rule[-1].proto=tcp";
    uci "set firewall.\@rule[-1].src_ip=\'$_\'";
    uci "set firewall.\@rule[-1].dest_port=22";
    uci "set firewall.\@rule[-1].target=ACCEPT";
    # ssh-wan-out-xxx
    uci "add firewall rule";
    #uci "set firewall.\@rule[-1].name=\'ssh-wan-out-$_\'";
    uci "set firewall.\@rule[-1].dest=wan";
    uci "set firewall.\@rule[-1].proto=tcp";
    uci "set firewall.\@rule[-1].dest_ip=\'$_\'";
    uci "set firewall.\@rule[-1].src_port=22";
    uci "set firewall.\@rule[-1].target=ACCEPT";
  }

  # icmp-wan-in-limit
  uci "add firewall rule";
  #uci "set firewall.\@rule[-1].name=icmp-wan-in-limit";
  uci "set firewall.\@rule[-1].src=wan";
  uci "set firewall.\@rule[-1].proto=icmp";
  uci "add_list firewall.\@rule[-1].icmp_type=$_" foreach (0,3,4,8,11,12);
  uci "set firewall.\@rule[-1].limit=\'20/sec\'";
  uci "set firewall.\@rule[-1].target=ACCEPT";

  # icmp-wan-out
  uci "add firewall rule";
  #uci "set firewall.\@rule[-1].name=icmp-wan-out";
  uci "set firewall.\@rule[-1].dest=wan";
  uci "set firewall.\@rule[-1].proto=icmp";
  uci "set firewall.\@rule[-1].target=ACCEPT";

  # syslog-wan-out
  uci "add firewall rule";
  #uci "set firewall.\@rule[-1].name=syslog-wan-out";
  uci "set firewall.\@rule[-1].dest=wan";
  uci "set firewall.\@rule[-1].proto=udp";
  uci "set firewall.\@rule[-1].dest_ip=\'$hostparam{log_ip}\'";
  uci "set firewall.\@rule[-1].dest_port=514";
  uci "set firewall.\@rule[-1].target=ACCEPT";

  #####
  my @outgoing_rules_ip_list;
  recursive_search_by_from_hostname(\@outgoing_rules_ip_list, $hostparam{tun_node_name});
  #say 'Outgoing: ', Dumper \@outgoing_rules_ip_list;

  my @incoming_rules_ip_list;
  recursive_search_by_to_hostname(\@incoming_rules_ip_list, $hostparam{tun_node_name});
  #say 'Incoming: ', Dumper \@incoming_rules_ip_list;

  # build outgoing tinc rules
  foreach (@outgoing_rules_ip_list) {
    # tinc-outgoing-wan-in-xxx
    uci "add firewall rule";
    #uci "set firewall.\@rule[-1].name=\'tinc-outgoing-wan-in-$_\'";
    uci "set firewall.\@rule[-1].src=wan";
    uci "set firewall.\@rule[-1].proto=tcpudp";
    uci "set firewall.\@rule[-1].src_ip=\'$_\'";
    uci "set firewall.\@rule[-1].src_port=655";
    uci "set firewall.\@rule[-1].target=ACCEPT";
    # tinc-outgoing-wan-out-xxx
    uci "add firewall rule";
    #uci "set firewall.\@rule[-1].name=\'tinc-outgoing-wan-out-$_\'";
    uci "set firewall.\@rule[-1].dest=wan";
    uci "set firewall.\@rule[-1].proto=tcpudp";
    uci "set firewall.\@rule[-1].dest_ip=\'$_\'";
    uci "set firewall.\@rule[-1].dest_port=655";
    uci "set firewall.\@rule[-1].target=ACCEPT";
  }
  # build incoming tinc rules
  foreach (@incoming_rules_ip_list) {
    # tinc-incoming-wan-in-xxx
    uci "add firewall rule";
    #uci "set firewall.\@rule[-1].name=\'tinc-incoming-wan-in-$_\'";
    uci "set firewall.\@rule[-1].src=wan";
    uci "set firewall.\@rule[-1].proto=tcpudp";
    uci "set firewall.\@rule[-1].src_ip=\'$_\'";
    uci "set firewall.\@rule[-1].dest_port=655";
    uci "set firewall.\@rule[-1].target=ACCEPT";
    # tinc-outgoing-wan-out-xxx
    uci "add firewall rule";
    #uci "set firewall.\@rule[-1].name=\'tinc-incoming-wan-out-$_\'";
    uci "set firewall.\@rule[-1].dest=wan";
    uci "set firewall.\@rule[-1].proto=tcpudp";
    uci "set firewall.\@rule[-1].dest_ip=\'$_\'";
    uci "set firewall.\@rule[-1].src_port=655";
    uci "set firewall.\@rule[-1].target=ACCEPT";
  }

  uci "add firewall include";
  uci "set firewall.\@include[-1].path=\'/etc/firewall.user\'";

  #uci "show firewall";
  uci "commit firewall";
  insert_autogen_comment '/etc/config/firewall';

  file "/etc/firewall.user",
    owner => "ural",
    group => "root",
    mode => 644,
    content => template("files/firewall.user.0.tpl");

  say "Firewall configuration finished for $hostparam{host}";
};


desc "OWRT routers: Configure tinc tunnel";
# if --confhost=host parameter is specified, host configuration is read
# from the database, otherwise uses current
task "conf_tun", sub {
  my $ch = shift->{confhost};
  read_db $ch if $ch;
  check_par;

  say "Tinc tunnel configuration started for $hostparam{host}";

  pkg "tinc", ensure => "present";

  file "/etc/config/tinc",
    owner => "ural",
    group => "root",
    mode => 644,
    content => template("files/tinc.0.tpl");
  quci "revert tinc";

  uci "set tinc.$def_net=tinc-net";
  uci "set tinc.\@tinc-net[-1].enabled=1";
  uci "set tinc.\@tinc-net[-1].debug=2";
  uci "set tinc.\@tinc-net[-1].AddressFamily=ipv4";
  uci "set tinc.\@tinc-net[-1].Interface=vpn1";
  uci "set tinc.\@tinc-net[-1].MaxTimeout=600";
  uci "set tinc.\@tinc-net[-1].Name=\'$hostparam{tun_node_name}\'";
  uci "add_list tinc.\@tinc-net[-1].ConnectTo=\'$_\'" foreach (@{$hostparam{tun_connect_nodes}});

  uci "set tinc.$hostparam{tun_node_name}=tinc-host";
  uci "set tinc.\@tinc-host[-1].enabled=1";
  uci "set tinc.\@tinc-host[-1].net=\'$def_net\'";
  uci "set tinc.\@tinc-host[-1].Cipher=blowfish";
  uci "set tinc.\@tinc-host[-1].Compression=0";
  uci "add_list tinc.\@tinc-host[-1].Address=\'$hostparam{tun_node_ip}\'";
  uci "set tinc.\@tinc-host[-1].Subnet=\'$hostparam{tun_subnet}\'";

  #uci "show tinc";
  uci "commit tinc";
  insert_autogen_comment '/etc/config/tinc';
  say "File /etc/config/tinc configured.";

  # configure tinc scripts
  file "/etc/tinc/$def_net",
    owner => "ural",
    group => "root",
    mode => 755,
    ensure => "directory";

  file "/etc/tinc/$def_net/tinc-up",
    owner => "ural",
    group => "root",
    mode => 755,
    content => template("files/tinc/$def_net/tinc-up.tpl",
      _tun_ip =>$hostparam{tun_int_ip},
      _tun_netmask=>$hostparam{tun_int_netmask});
  
  file "/etc/tinc/$def_net/tinc-down",
    owner => "ural",
    group => "root",
    mode => 755,
    content => template("files/tinc/$def_net/tinc-down.tpl");
  say "Scripts tinc-up/tinc-down are created.";

  unless ($hostparam{tun_pub_key} && $hostparam{tun_priv_key}) {
    say "No keypair found in the database, running gen_node for $hostparam{tun_node_name}...";
    run_task "Deploy:Owrt:gen_node", params=>{newnode=>$hostparam{tun_node_name}};
  } else {
    say "Keypair for $hostparam{tun_node_name} from the database is used.";
  }
    
  # configure tinc keys
  file "/etc/tinc/$def_net/rsa_key.priv",
    owner => "ural",
    group => "root",
    mode => 600,
    content => $hostparam{tun_priv_key};
  say "Tinc private key file for $hostparam{tun_node_name} is saved to rsa_key.priv";

  # generate all hosts files for this node
  sleep 1;
  Deploy::Owrt::dist_nodes();

  say "Tinc tunnel configuration finished for $hostparam{host}";
};


##################################
desc "Tinc net generate keys for node (run on *bikini* host only please)
  rex gen_node --newnode=gwtest1";
task "gen_node", sub {
  my $par = shift;
  my $_host = $par->{newnode};
  my $keysize = 2048;

  my %i = get_system_information;
  #say "Host: $i{hostname}";
  die "This task can be run only on bikini host.\n" unless $i{hostname} eq 'bikini';
  die "Invalid parameters, run as: rex gen_node --newnode=hostname.\n" unless $_host;

  # prepare database
  my $dbh = DBI->connect("DBI:mysql:database=".get(cmdb('dbname')).';host='.get(cmdb('dbhost')), get(cmdb('dbuser')), get(cmdb('dbpass'))) or 
    die "Connection to the database failed.\n";
  $dbh->do("SET NAMES 'UTF8'");

  my ($r_id) = $dbh->selectrow_array("SELECT id FROM routers WHERE host_name = ?", {}, $_host);
  die "There's no such host in the database, or database error.\n" unless $r_id;
  #say $r_id;

  say "Generating keys for node: $_host";
  #unless (is_installed("openssl")) {
  #  say "Openssl is required.";
  #  return 1;
  #}
  my $privkey = run "openssl genrsa $keysize", auto_die=>1;
  #say $privkey;
  say "Private key generated.";
  my $pubkey = run "openssl rsa -pubout -outform PEM << EOF123EOF\n$privkey\nEOF123EOF\n", auto_die=>1;
  #say $pubkey;
  say "Public key generated.";

  # save keys to database
  my $rows = $dbh->do("UPDATE vpns SET pub_key=?, priv_key=? WHERE router_id = ?", {}, $pubkey, $privkey, $r_id);
  die "Can't save keys to database.\n".$dbh->errstr."\n" unless $rows;

  $dbh->disconnect;
  say "Keys were successfully written to database.";
};


desc "Distribute tinc net hosts files to host (works on erebus too)";
# if --confhost=host parameter is specified, host configuration is read
# from the database, otherwise uses current
task "dist_nodes", sub {
  my $params = shift;
  my $ch = $params->{confhost};
  read_db($ch, skip_erebus_check=>1) if $ch;

  my $hostparam_ref = \%hostparam;
  $hostparam_ref = $params->{ext_hostparam} if ($params->{ext_hostparam});

  # like check_par() but we should run on erebus too...
  die "Hostname is empty. Configuration wasn't read" unless $hostparam_ref->{host}; 

  say "Tinc hostfiles distribution started for $hostparam_ref->{host}";

  file "/etc/tinc/$def_net/hosts",
    owner => "ural",
    group => "root",
    mode => 755,
    ensure => "directory";

  # build host files for all nodes in database
  my $dbh = DBI->connect("DBI:mysql:database=".get(cmdb('dbname')).';host='.get(cmdb('dbhost')), get(cmdb('dbuser')), get(cmdb('dbpass'))) or 
    die "Connection to the database failed.\n";
  $dbh->do("SET NAMES 'UTF8'");

  my $s = $dbh->prepare("SELECT \
routers.host_name AS tun_node_name, \
ifs.ip AS tun_node_ip, \
nets.net_ip AS tun_subnet_ip, \
nets.mask AS tun_subnet_mask, \
pub_key AS tun_pub_key \
FROM vpns \
INNER JOIN routers ON routers.id = router_id \
INNER JOIN nets ON nets.id = subnet_id \
INNER JOIN interfaces ifs ON ifs.id = node_if_id") or die $dbh->errstr;
  $s->execute or die $s->errstr;
  my @hosts_files;
  while (my $hr = $s->fetchrow_hashref) {
    #say Dumper $hr;

    unless ($hr->{tun_pub_key} && $hr->{tun_subnet_ip} && $hr->{tun_subnet_mask} && $hr->{tun_node_ip}) {
      say "Host file for node $hr->{tun_node_name} is not generated due incorrect configuration:";
      say "- No public key in database. Generate keys for this host and run distribution again." unless ($hr->{tun_pub_key});
      say "- No vpn subnet ip/mask in database. Check configuration." unless ($hr->{tun_subnet_ip} && $hr->{tun_subnet_mask});
      say "- No vpn ip in database. Check configuration." unless ($hr->{tun_node_ip});
      next;
    }

    my $net = NetAddr::IP->new($hr->{tun_subnet_ip}, $hr->{tun_subnet_mask}) or
      die("Invalid vpn subnet address or mask!\n");

    # now generate tinc host file with public key
    file "/etc/tinc/$def_net/hosts/$hr->{tun_node_name}",
      owner => "ural",
      group => "root",
      mode => 644,
      content => template("files/tinc/$def_net/hostfile.tpl",
	_address=>$hr->{tun_node_ip},
	_subnet=>$net->cidr,
        _pubkey=>$hr->{tun_pub_key});
    push @hosts_files, $hr->{tun_node_name};
    say "Host file for $hr->{tun_node_name} is generated.";
  }
  $dbh->disconnect;

  # check for hosts in connection list exist
  my @_con_list = @{$hostparam_ref->{tun_connect_nodes}};
  push @_con_list, $hostparam_ref->{tun_node_name}; # current host must be in list too
  foreach my $h (@_con_list) {
    my $f = 0;
    foreach (@hosts_files) {
      if ($h eq $_) { $f = 1; last; }
    }
    say "WARNING! Host $h is in tinc connection list, but not distributed." unless ($f);
  }

  say "Tinc hostfiles distribution finished for $hostparam_ref->{host}";
};


desc "Reload tinc daemon (useful after updating net hosts files, works on erebus too)";
task "reload_tinc", sub {
  my $pf = "/var/run/tinc.$def_net.pid";
  if (is_readable($pf)) {
    say "Reloading tinc daemon on host ".connection->server." ...";
    run "kill -HUP `cat $pf`";
    say "HUP signal is sent.";
  } else {
    say "Pid file $pf wasn't found. May be wrong host, or tinc is not running.";
  }
};


##################################
task "_t", sub {
  read_db 'gwsouth2';
  check_par;

  #my @outgoing_rules_ip_list;
  #recursive_search_by_from_hostname(\@outgoing_rules_ip_list, $hostparam{tun_node_name});
  #say 'Outgoing: ', Dumper \@outgoing_rules_ip_list;

  #my @incoming_rules_ip_list;
  #recursive_search_by_to_hostname(\@incoming_rules_ip_list, $hostparam{tun_node_name});
  #say 'Incoming: ', Dumper \@incoming_rules_ip_list;

  #check_par;
  say Dumper \%hostparam;
}, {dont_register => TRUE};

1;

=pod

=head1 NAME

$::module_name - {{ SHORT DESCRIPTION }}

=head1 DESCRIPTION

{{ LONG DESCRIPTION }}

=head1 USAGE

{{ USAGE DESCRIPTION }}

 include qw/Deploy::Owrt/;

 task yourtask => sub {
    Deploy::Owrt::example();
 };

=head1 TASKS

=over 4

=item example

This is an example Task. This task just output's the uptime of the system.

=back

=cut
