package Deploy::Erebus;

use Rex -feature=>['1.4'];
use Rex::Commands::Cron;
use Data::Dumper;
use File::Basename;
use DBI;
use NetAddr::IP::Lite;
use feature 'state';

my $def_net = 'UWC66';

# params: usage $hostparam{key}
my %hostparam = (
  host => '',
  gateway => '',
  dns => ['',],
  dns_suffix => '',
  log_ip => '',
  ntp_ip => '',
  ssh_icmp_from_wans_ips => ['',],
  wan_ifs => {ifname=>{ip=>'',netmask=>'',vlan=>'',alias=>0, 
    routes=>[{name=>'',type=>1,gateway=>'',target=>'',netmask=>'',table=>''},],
    dhcp_on=>0,dhcp_start=>0,dhcp_limit=>0,dhcp_leasetime=>'',dhcp_dns=>'',dhcp_dns_suffix=>'',dhcp_wins=>'',
    dhcp_static_leases=>[{name=>'',mac=>'',ip=>''},],
  },},
  lan_ifs => {},
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

# hacks: usage $hosthacks{codename}
my %hosthacks = (
  #codename => 'content',
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
routers.gateway AS gateway, \
routers.dns_list AS dns_unparsed, \
routers.dns_suffix AS dns_suffix, \
routers.log_ip AS log_ip, \
routers.ntp_ip AS ntp_ip, \
routers.ssh_icmp_from_wans_ips AS ssh_icmp_from_wans_ips_unparsed \
FROM routers \
LEFT OUTER JOIN router_equipment ON router_equipment.id = routers.equipment_id \
LEFT OUTER JOIN departments ON departments.id = routers.placement_dept_id \
WHERE host_name = ?", {}, $_host);
  die "There's no such host in the database, or database error.\n" unless $hr;
  #say Dumper $hr;

  %hostparam = %$hr;

  # read wans and lans
  $hostparam{wan_ifs} = {};
  populate_interfaces($hostparam{wan_ifs}, 1, $hostparam{router_id});
  $hostparam{lan_ifs} = {};
  populate_interfaces($hostparam{lan_ifs}, 2, $hostparam{router_id});

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
  delete $hostparam{lan_routes_unparsed};
=cut
  # parse dns_list
  $hostparam{dns} = [split /,/, $hostparam{dns_unparsed}];
  delete $hostparam{dns_unparsed};
  # parse ssh_icmp_from_wans_ips
  $hostparam{ssh_icmp_from_wans_ips} = [split /,/, $hostparam{ssh_icmp_from_wans_ips_unparsed}];
  delete $hostparam{ssh_icmp_from_wans_ips_unparsed};

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

  my $net = NetAddr::IP::Lite->new($hr->{tun_subnet_ip}, $hr->{tun_subnet_mask}) or
    die("Invalid vpn subnet address or mask!\n");
  $hostparam{tun_subnet} = $net->cidr;

  $hostparam{tun_array_ref} = read_tunnels_tinc();
  #say Dumper $hostparam{tun_array_ref};

  # build tinc connect_to list of nodes
  my @tmp_list = grep { $_->{from_hostname} eq $hostparam{tun_node_name} } @{$hostparam{tun_array_ref}};
  #say Dumper \@tmp_list;
  say "INFORMATION! NO destination VPN tunnels are configured for this node. ConnectTo list will be empty." unless @tmp_list;

  $hostparam{tun_connect_nodes} = remove_dups([map { $_->{to_hostname} } @tmp_list]);
  foreach (@{$hostparam{tun_connect_nodes}}) {
    die "Invalid tunnel configuration! Source node connected to itself!\n" if $_ eq $hostparam{tun_node_name};
  }
  ### TODO: check if we can run without vpn configuration records


  # read hacks
  my $ar = $dbh->selectall_arrayref("SELECT \
codename, hack, add_comment \
FROM hacks \
WHERE router_id = ?", {Slice=>{}, MaxRows=>100}, $hostparam{router_id});
  die "Getting hacks failure.\n" unless $ar;
  for (@$ar) {
    my $pre_comm = '';
    my $post_comm = '';
    if ($_->{add_comment}) {
      $pre_comm = "\n### BEGIN OF $_->{codename} HACK ###\n";
      $post_comm = "\n### END OF $_->{codename} HACK ###\n";
    }
    $_->{hack} =~ s/\r\n/\n/g; # dos2unix
    $hosthacks{$_->{codename}} = $pre_comm.$_->{hack}.$post_comm;
  }
  #say Dumper \%hosthacks;

  #say Dumper \%hostparam;

  $dbh->disconnect;
  say "Erebus configuration has successfully been read from the database.";
  1;
}


# $hostparam{wan_ifs} = {};
# populate_interfaces($hostparam{wan_ifs} /to fill in/, $if_type /1 or 2/, $router_id);
sub populate_interfaces {
  my ($ifs_href, $if_type, $router_id) = @_;
  die "Unsupported interface type $if_type\n" unless $if_type == 1 || $if_type == 2;

  my $ar = $dbh->selectall_arrayref("SELECT \
i.ip AS ip, \
nets.mask AS netmask, \
i.vlan AS vlan, \
i.net_id AS net_src_id, \
nets.net_gw AS net_src_gw, \
i.dhcp_on AS dhcp_on, \
nets.dhcp_start_ip AS dhcp_start, \
nets.dhcp_limit AS dhcp_limit, \
nets.dhcp_leasetime AS dhcp_leasetime, \
nets.dhcp_dns AS dhcp_dns, \
nets.dhcp_dns_suffix AS dhcp_dns_suffix, \
nets.dhcp_wins AS dhcp_wins, \
nets.dhcp_static_leases AS dhcp_static_leases_unparsed \
FROM interfaces i \
INNER JOIN nets ON net_id = nets.id \
WHERE type = ? AND router_id = ?", {Slice=>{}, MaxRows=>10}, $if_type, $router_id);
  die "Fetching interfaces database failure.\n" unless $ar;
  #say Dumper $ar;

  # reorganize wans array to hash for aliasing support
  my %vif;
  push(@{$vif{ ($_->{vlan}) ? $_->{vlan} : '0' }}, $_) for (@$ar); # group by vlan
  #say Dumper \%vif;

  my $part_if = ($if_type == 1) ? 'wan' : 'lan';
  for (sort keys %vif) {
    my $vid = $_;
    my $val = $vif{$_}; # aref
    my $aliasid = 0;
    my $routeid = 1;
    my $part_vlan = ($vid) ? "_vlan$vid" : '';
    # sort aliases by ip to keep things persistent
    for (sort {$a->{ip} cmp $b->{ip}} @$val) {
      my $part_alias = ($aliasid) ? "_alias$aliasid" : '';
      my $if_name = $part_if.$part_vlan.$part_alias;
      $ifs_href->{$if_name} = { %$_ };
      $ifs_href->{$if_name}{alias} = $aliasid++;

      # extract routes for each interface
      my $ar1 = $dbh->selectall_arrayref("SELECT \
type AS type, \
nets.net_ip AS target, \
nets.mask AS netmask, \
r_table AS 'table' \
FROM routes \
INNER JOIN nets ON net_dst_id = nets.id \
WHERE net_src_id = ?", {Slice=>{}, MaxRows=>500}, $_->{net_src_id});
      die "Fetching routes database failure.\n" unless $ar1;
      #say Dumper $ar1;

      my $r_gateway = $_->{net_src_gw};
      for (@$ar1) {
	my $r1 = {
	  name => "${if_name}_route$routeid",
	  gateway => $r_gateway,
	  target => $_->{target},
	  netmask => $_->{netmask},
	  table => $_->{table},
	  type => $_->{type},
        };
        push @{$ifs_href->{$if_name}{routes}}, $r1;
	$routeid++;
      }
      # parse dhcp_start
      if ($ifs_href->{$if_name}{dhcp_start} =~ /^(?:[0-9]{1,3}\.){3}([0-9]{1,3})$/) {
	$ifs_href->{$if_name}{dhcp_start} = $1;
      }
      # parse dhcp_static_leases
      my @rres;
      foreach (split /;/, $ifs_href->{$if_name}{dhcp_static_leases_unparsed}) {
	my @cr = split /,/, $_;
	if ($cr[0] and
	  $cr[1] =~ /^(?:[0-9a-fA-F]{1,2}\:){5}[0-9a-fA-F]{1,2}$/ and
	  $cr[2] =~ /^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$/) {
	    push @rres, {name => "${if_name}_".lc($cr[0]), mac => $cr[1], ip => $cr[2]};
	} else {
	  say "WARNING: invalid dhcp static lease: $cr[0] on interface $if_name ignored.";
	}
      }
      $ifs_href->{$if_name}{dhcp_static_leases} = \@rres;
      delete $ifs_href->{$if_name}{dhcp_static_leases_unparsed};
    } # for aliases
  } # for vlans
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


sub insert_autogen_comment {
  my $file = shift;
  my $autogen_comment = '# This file is autogenerated. All changes will be overwritten!';
  my $output = run "sed -i \'1i $autogen_comment\' $file", timeout=>10;
  say $output if $output;
}


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
  Deploy::Erebus::conf_software();
  sleep 1;
  Deploy::Erebus::conf_system();
  sleep 1;
  Deploy::Erebus::conf_net();
  sleep 1;
  Deploy::Erebus::conf_fw();
  sleep 1;
  Deploy::Erebus::conf_ipsec();
  sleep 1;
  Deploy::Erebus::conf_tinc();
  sleep 1;
  Deploy::Erebus::conf_r2d2();
  sleep 1;
  Deploy::Erebus::conf_snmp();
  say "Router deployment/Erebus/ finished for $hostparam{host}";
  say "!!! Reboot router manually to apply changes !!!";
};


desc "Erebus router: Configure software";
# if --confhost=erebus parameter is specified, host configuration is read
# from the database, otherwise uses current
task "conf_software", sub {
  my $ch = shift->{confhost};
  read_db $ch if $ch;
  check_par;

  say "Software configuration started for $hostparam{host}";

  # disable failsafe mode prompt (erebus is always x64)
  say "Disabling failsafe mode prompts.";
  file "/lib/preinit/30_failsafe_wait", ensure=>'absent';
  file "/lib/preinit/99_10_failsafe_login", ensure=>'absent';

  # install packages
  say "Updating package database.";
  update_package_db;
  say "Installing / updating packages.";
  for (qw/ip-full tc conntrack kmod-sched
    iperf3 irqbalance ethtool lm-sensors lm-sensors-detect
    strongswan-default tinc snmpd snmp-utils
    perl perlbase-encode perlbase-findbin perl-dbi perl-dbd-mysql perl-netaddr-ip perl-sys-runalone
    libmariadb openssh-client/) {
    pkg $_, ensure => latest,
      on_change => sub { say "package $_ was installed." };
  }
  say "Software configuration finished for $hostparam{host}";
};


desc "Erebus router: Configure system parameters";
# if --confhost=erebus parameter is specified, host configuration is read
# from the database, otherwise uses current
task "conf_system", sub {
  my $ch = shift->{confhost};
  read_db $ch if $ch;
  check_par;

  say "System configuration started for $hostparam{host}";

  my $tpl_sys_file = 'files/system.x86.tpl';
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
  insert_autogen_comment '/etc/config/system';

  # tune sysctl
  file "/etc/sysctl.conf",
    owner => "ural",
    group => "root",
    mode => 644,
    content => template('files/sysctl.conf.0.tpl'),
    on_change => sub { say "sysctl parameters configured." };

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
  my $gw = ($hostparam{gateway}) ? NetAddr::IP::Lite->new($hostparam{gateway}) : undef;
  my $ifs_r = $hostparam{lan_ifs};
  for (sort keys %$ifs_r) {
    my $if_r = $ifs_r->{$_};
    my $part_vlan = ($if_r->{vlan}) ? ".$if_r->{vlan}" : '';
    uci "set network.$_=interface";
    uci "set network.$_.ifname=\'$lan_ifname$part_vlan\'";
    uci "set network.$_.proto=\'static\'";
    uci "set network.$_.ipaddr=\'$if_r->{ip}\'";
    uci "set network.$_.netmask=\'$if_r->{netmask}\'";
    my $net = NetAddr::IP::Lite->new($if_r->{ip}, $if_r->{netmask});
    uci "set network.$_.gateway=\'$hostparam{gateway}\'" if ($gw && $net && $gw->within($net));
    uci "set network.$_.ipv6=0";
  }
  # wan
  $ifs_r = $hostparam{wan_ifs};
  for (sort keys %$ifs_r) {
    my $if_r = $ifs_r->{$_};
    my $part_vlan = ($if_r->{vlan}) ? ".$if_r->{vlan}" : '';
    uci "set network.$_=interface";
    uci "set network.$_.ifname=\'$wan_ifname$part_vlan\'";
    uci "set network.$_.proto=\'static\'";
    uci "set network.$_.ipaddr=\'$if_r->{ip}\'";
    uci "set network.$_.netmask=\'$if_r->{netmask}\'";
    my $net = NetAddr::IP::Lite->new($if_r->{ip}, $if_r->{netmask});
    uci "set network.$_.gateway=\'$hostparam{gateway}\'" if ($gw && $net && $gw->within($net));
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

  my $h = $hosthacks{rt_tables_config};
  append_if_no_such_line($rt_file,
    line => $h,
    on_change => sub {
      say "Hack rt_tables_config was added to rt_tables.";
    }
  ) if $h;

  # routes
  for my $ifs_r ($hostparam{lan_ifs}, $hostparam{wan_ifs}) {
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
  uci "set dhcp.\@dnsmasq[0].domain=\'$hostparam{dns_suffix}\'";
  quci "delete dhcp.\@dnsmasq[0].local";
  quci "delete dhcp.\@dnsmasq[0].server";
  foreach (@{$hostparam{dns}}) {
    uci "add_list dhcp.\@dnsmasq[0].server=\'$_\'";
  }

  uci "set dhcp.\@dnsmasq[0].logqueries=0";

  #quci "delete dhcp.\@dnsmasq[0].interface";
  #uci "add_list dhcp.\@dnsmasq[0].interface=\'lan\'"; # dnsmasq listen only lan

  # lan, wan is not used
  quci "delete dhcp.lan";
  quci "delete dhcp.wan";

  # dhcp configuration for interfaces
  for my $ifs_r ($hostparam{lan_ifs}, $hostparam{wan_ifs}) {
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
  for my $ifs_r ($hostparam{lan_ifs}, $hostparam{wan_ifs}) {
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
  $h = $hosthacks{ip_rules_config};
  append_if_no_such_line($network_file,
    line => $h,
    on_change => sub {
      say "Hack ip_rules_config was added to /etc/config/network.";
    }
  ) if $h;

  say "\nNetwork configuration finished for $hostparam{host}. Restarting the router will change the IP-s!!!.\n";
};


desc "Erebus router: Configure IPsec";
# if --confhost=erebus parameter is specified, host configuration is read
# from the database, otherwise uses current
task "conf_ipsec", sub {
  my $ch = shift->{confhost};
  read_db $ch if $ch;
  check_par;

  say "IPsec configuration started for $hostparam{host}";

  pkg "strongswan-default", ensure => "present";

  # strongswan init
  file '/etc/init.d/ipsec',
    owner => "ural",
    group => "root",
    mode => 755,
    source => "files/ipsec.init",
    on_change => sub { say "Strongswan init file created." };
  
  # strongswan config
  my $ipsec_file = '/etc/config/ipsec';
  file $ipsec_file,
    owner => "ural",
    group => "root",
    mode => 644,
    content => template('files/ipsec.0.tpl'),
    on_change => sub { say "/etc/config/ipsec created." };

  my $h = $hosthacks{strongswan_config};
  append_if_no_such_line($ipsec_file,
    line => $h,
    on_change => sub {
      say "Hack strongswan_config was added to /etc/config/ipsec.";
    }
  ) if $h;

  say "IPsec configuration finished for $hostparam{host}";
};


desc "Erebus router: Configure tinc";
# if --confhost=erebus parameter is specified, host configuration is read
# from the database, otherwise uses current
task "conf_tinc", sub {
  my $ch = shift->{confhost};
  read_db $ch if $ch;
  check_par;

  say "Tinc configuration started for $hostparam{host}";

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
  uci "set tinc.\@tinc-net[-1].BindToAddress=\'$hostparam{tun_node_ip}\'";
  uci "set tinc.\@tinc-net[-1].MaxTimeout=600";
  uci "set tinc.\@tinc-net[-1].Name=\'$hostparam{tun_node_name}\'";
  uci "add_list tinc.\@tinc-net[-1].ConnectTo=\'$_\'" for (@{$hostparam{tun_connect_nodes}});

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

  my $int_addr = NetAddr::IP::Lite->new($hostparam{tun_int_ip}, $hostparam{tun_int_netmask}) or
    die "Invalid vpn tunnel interface address or mask!\n";
  file "/etc/tinc/$def_net/tinc-up",
    owner => "ural",
    group => "root",
    mode => 755,
    content => template("files/tinc/$def_net/tinc-up.tpl",
      _tun_ip =>$int_addr->addr,
      _tun_netmask=>$int_addr->mask,
      _tun_route_addr=>$int_addr->network->cidr,
    );
  
  file "/etc/tinc/$def_net/tinc-down",
    owner => "ural",
    group => "root",
    mode => 755,
    content => template("files/tinc/$def_net/tinc-down.tpl",
      _tun_route_addr=>$int_addr->network->cidr,
    );
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
    content => $hostparam{tun_priv_key},
    on_change => sub {
      say "Tinc private key file for $hostparam{tun_node_name} is saved to rsa_key.priv";
    };

  # generate all hosts files for this node
  sleep 1;
  Deploy::Owrt::dist_nodes({ext_hostparam=>\%hostparam});

  say "Tinc configuration finished for $hostparam{host}";
};


desc "Erebus router: Configure firewall";
# if --confhost=erebus parameter is specified, host configuration is read
# from the database, otherwise uses current
task "conf_fw", sub {
  my $ch = shift->{confhost};
  read_db $ch if $ch;
  check_par;

  say "Firewall configuration started for $hostparam{host}";

  pkg "firewall", ensure => "present";

  my @lan_ifs = sort keys %{$hostparam{lan_ifs}};
  my @wan_ifs = sort keys %{$hostparam{wan_ifs}};
  file "/etc/config/firewall",
    owner => "ural",
    group => "root",
    mode => 644,
    content => template("files/firewall.0.tpl",
      _lan_interfaces => \@lan_ifs,
      _wan_interfaces => \@wan_ifs,
    );

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

  # syslog-wan/lan-out
  for (qw/wan lan/) {
    uci "add firewall rule";
    #uci "set firewall.\@rule[-1].name=syslog-$_-out";
    uci "set firewall.\@rule[-1].dest=\'$_\'";
    uci "set firewall.\@rule[-1].proto=udp";
    uci "set firewall.\@rule[-1].dest_ip=\'$hostparam{log_ip}\'";
    uci "set firewall.\@rule[-1].dest_port=514";
    uci "set firewall.\@rule[-1].target=ACCEPT";
  }

  # ntp-lan-in
  uci "add firewall rule";
  #uci "set firewall.\@rule[-1].name=ntp-lan-in";
  uci "set firewall.\@rule[-1].src=lan";
  uci "set firewall.\@rule[-1].proto=udp";
  uci "set firewall.\@rule[-1].src_ip=\'$hostparam{ntp_ip}\'";
  uci "set firewall.\@rule[-1].src_port=123";
  uci "set firewall.\@rule[-1].target=ACCEPT";

  # ntp-lan-out
  uci "add firewall rule";
  #uci "set firewall.\@rule[-1].name=ntp-lan-out";
  uci "set firewall.\@rule[-1].dest=lan";
  uci "set firewall.\@rule[-1].proto=udp";
  uci "set firewall.\@rule[-1].dest_ip=\'$hostparam{ntp_ip}\'";
  uci "set firewall.\@rule[-1].dest_port=123";
  uci "set firewall.\@rule[-1].target=ACCEPT";

  # snmp-lan-in
  uci "add firewall rule";
  #uci "set firewall.\@rule[-1].name=snmp-lan-in";
  uci "set firewall.\@rule[-1].src=lan";
  uci "set firewall.\@rule[-1].proto=udp";
  uci "set firewall.\@rule[-1].dest_port=161";
  uci "set firewall.\@rule[-1].target=ACCEPT";

  # snmp-lan-out
  uci "add firewall rule";
  #uci "set firewall.\@rule[-1].name=snmp-lan-out";
  uci "set firewall.\@rule[-1].dest=lan";
  uci "set firewall.\@rule[-1].proto=udp";
  uci "set firewall.\@rule[-1].src_port=161";
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
    uci "set firewall.\@rule[-1].family=ipv4";
    uci "set firewall.\@rule[-1].target=ACCEPT";
    # tinc-outgoing-wan-out-xxx
    uci "add firewall rule";
    #uci "set firewall.\@rule[-1].name=\'tinc-outgoing-wan-out-$_\'";
    uci "set firewall.\@rule[-1].dest=wan";
    uci "set firewall.\@rule[-1].proto=tcpudp";
    uci "set firewall.\@rule[-1].dest_ip=\'$_\'";
    uci "set firewall.\@rule[-1].dest_port=655";
    uci "set firewall.\@rule[-1].family=ipv4";
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
    uci "set firewall.\@rule[-1].family=ipv4";
    uci "set firewall.\@rule[-1].target=ACCEPT";
    # tinc-incoming-wan-out-xxx
    uci "add firewall rule";
    #uci "set firewall.\@rule[-1].name=\'tinc-incoming-wan-out-$_\'";
    uci "set firewall.\@rule[-1].dest=wan";
    uci "set firewall.\@rule[-1].proto=tcpudp";
    uci "set firewall.\@rule[-1].dest_ip=\'$_\'";
    uci "set firewall.\@rule[-1].src_port=655";
    uci "set firewall.\@rule[-1].family=ipv4";
    uci "set firewall.\@rule[-1].target=ACCEPT";
  }

  uci "add firewall include";
  uci "set firewall.\@include[-1].path=\'/etc/firewall.user\'";

  uci "add firewall include";
  uci "set firewall.\@include[-1].path=\'/etc/tc.user\'";

  #uci "show firewall";
  uci "commit firewall";
  insert_autogen_comment '/etc/config/firewall';

  my $firewall_user_file = '/etc/firewall.user';
  file $firewall_user_file,
    owner => "ural",
    group => "root",
    mode => 644,
    content => template("files/firewall.user.0.tpl");

  # append hacks to firewall.user
  for (qw/pf_interfaces_names pf_input_ipsec pf_rsyslog_forwarding pf_clients_forwarding pf_internet_r2d2 pf_snat_config pf_dnat_config pf_internet_forwarding/) {
    my $h = $hosthacks{$_};
    append_if_no_such_line($firewall_user_file,
      line => $h,
      on_change => sub {
	say "Hack $_ was added to /etc/firewall.user.";
      }
    ) if $h;
  }

  my $tc_user_file = '/etc/tc.user';
  file $tc_user_file,
    owner => "ural",
    group => "root",
    mode => 644,
    content => template("files/tc.user.0.tpl");

  # append hacks to tc.user
  for (qw/tc_lan_config tc_wan_config/) {
    my $h = $hosthacks{$_};
    append_if_no_such_line($tc_user_file,
      line => $h,
      on_change => sub {
	say "Hack $_ was added to /etc/tc.user.";
      }
    ) if $h;
  }

  say "Firewall configuration finished for $hostparam{host}";
};


desc "Erebus router: Configure r2d2";
# if --confhost=erebus parameter is specified, host configuration is read
# from the database, otherwise uses current
task "conf_r2d2", sub {
  my $ch = shift->{confhost};
  read_db $ch if $ch;
  check_par;

  say "R2d2 configuration started for $hostparam{host}";

  for (qw/perl perlbase-encode perlbase-findbin perl-dbi perl-dbd-mysql perl-netaddr-ip perl-sys-runalone libmariadb/) {
    pkg $_, ensure => "present";
  }

  file "/etc/r2d2",
    owner => "ural",
    group => "root",
    mode => 755,
    ensure => "directory";

  for (qw/rtsyn print_rules/) {
    file "/etc/r2d2/$_",
      owner => "ural",
      group => "root",
      mode => 755,
      source => "files/r2d2/$_",
      on_change => sub { say "$_ installed." };
  }

  file '/etc/r2d2/r2d2.conf',
    owner => "ural",
    group => "root",
    mode => 644,
    source => "files/r2d2/r2d2.conf",
    on_change => sub { say "r2d2.conf installed." };

  host_entry 'bikini.uwc.local',
    ensure => 'present',
    ip => '10.15.0.3',
    on_change => sub { say "Control server address added to /etc/hosts." };

  cron_entry 'rtsyn',
    ensure => 'present',
    command => "/etc/r2d2/rtsyn 1> /dev/null",
    user => 'ural',
    minute => '1,31',
    hour => '*',
    on_change => sub { say "cron entry for rtsyn created." };

  #my @crons = cron list => "ural"; say Dumper(\@crons);

  # run rtsyn after every reboot
  delete_lines_matching '/etc/rc.local', 'exit 0';
  append_if_no_such_line '/etc/rc.local',
    "(sleep 10 && logger 'Starting rtsyn ater reboot' && /etc/r2d2/rtsyn >/dev/null)&",
    on_change => sub { say "rc.local line to run rtsyn on reboot added." };
  append_if_no_such_line '/etc/rc.local', 'exit 0';

  say "R2d2 configuration finished for $hostparam{host}";
};


desc "Erebus router: Configure snmp";
# if --confhost=erebus parameter is specified, host configuration is read
# from the database, otherwise uses current
task "conf_snmp", sub {
  my $ch = shift->{confhost};
  read_db $ch if $ch;
  check_par;

  say "Snmp configuration started for $hostparam{host}";

  pkg 'snmpd', ensure => 'present';

  file "/etc/config/snmpd",
    owner => "ural",
    group => "root",
    mode => 644,
    content => template('files/snmpd.0.tpl', _hostname=>$hostparam{host}),
    on_change => sub { say "/etc/config/snmpd installed." };

  say "Snmp configuration finished for $hostparam{host}";
};


##################################
task "_t", sub {
  read_db 'erebus';
  check_par;
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
