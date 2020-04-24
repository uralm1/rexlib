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
  gateway => '',
  dns => ['',],
  dns_suffix => '',
  log_ip => '',
  ntp_ip => '',
  ssh_icmp_from_wans_ips => ['',],
  wan_ifs => {ifname=>{ip=>'',netmask=>'',vlan=>'',alias=>0, 
    routes=>[{name=>'',gateway=>'',target=>'',netmask=>'',table=>''},],
    dhcp_on=>0,dhcp_start=>0,dhcp_limit=>0,dhcp_leasetime=>'',dhcp_dns=>'',dhcp_dns_suffix=>'',dhcp_wins=>'',
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
  hacks => {codename=>'content',},
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
=cut
  # parse dns_list
  $hostparam{dns} = [split /,/, $hostparam{dns_unparsed}];
  # parse ssh_icmp_from_wans_ips
  $hostparam{ssh_icmp_from_wans_ips} = [split /,/, $hostparam{ssh_icmp_from_wans_ips_unparsed}];

  # read hacks
  my $ar = $dbh->selectall_arrayref("SELECT \
codename, hack \
FROM hacks \
WHERE router_id = ?", {Slice=>{}, MaxRows=>100}, $hostparam{router_id});
  die "Getting hacks failure.\n" unless $ar;
  for (@$ar) {
    $_->{hack} =~ s/\r\n/\n/g; # dos2unix
    $hostparam{hacks}->{$_->{codename}} = "\n### BEGIN OF $_->{codename} HACK ###\n".$_->{hack}."\n### END OF $_->{codename} HACK ###\n";
  }


  say Dumper \%hostparam;

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
nets.dhcp_wins AS dhcp_wins \
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
        };
        push @{$ifs_href->{$if_name}{routes}}, $r1;
	$routeid++;
      }
      # parse dhcp_start
      if ($ifs_href->{$if_name}{dhcp_start} =~ /^(?:[0-9]{1,3}\.){3}([0-9]{1,3})$/) {
	$ifs_href->{$if_name}{dhcp_start} = $1;
      }
    } # for aliases
  } # for vlans
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

  # install packages
  say "Updating package database.";
  update_package_db;
  say "Installing / updating packages.";
  for (qw/ip-full tc iperf3 irqbalance ethtool lm-sensors lm-sensors-detect/) {
    pkg $_, ensure => latest, on_change => sub {
      say "package $_ was installed.";
    }
  }

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
  my $gw = ($hostparam{gateway}) ? NetAddr::IP->new($hostparam{gateway}) : undef;
  my $ifs_r = $hostparam{lan_ifs};
  for (sort keys %$ifs_r) {
    my $if_r = $ifs_r->{$_};
    my $part_vlan = ($if_r->{vlan}) ? ".$if_r->{vlan}" : '';
    uci "set network.$_=interface";
    uci "set network.$_.ifname=\'$lan_ifname$part_vlan\'";
    uci "set network.$_.proto=\'static\'";
    uci "set network.$_.ipaddr=\'$if_r->{ip}\'";
    uci "set network.$_.netmask=\'$if_r->{netmask}\'";
    my $net = NetAddr::IP->new($if_r->{ip}, $if_r->{netmask});
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
    my $net = NetAddr::IP->new($if_r->{ip}, $if_r->{netmask});
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
    source => "files/rt_tables";

  my $h = $hostparam{hacks}->{rt_tables_config};
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
	  my $n = $_->{name};
	  uci "set network.$n=route";
	  uci "set network.$n.interface=$r_interface";
	  uci "set network.$n.target=$_->{target}";
	  uci "set network.$n.netmask=$_->{netmask}";
	  uci "set network.$n.gateway=$_->{gateway}";
	  uci "set network.$n.table=$_->{table}" if $_->{table};
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
  # static leases TODO
  #uci "add dhcp host";
  #uci "set dhcp.\@host[-1].ip=\'192.168.33.82\'";
  #uci "set dhcp.\@host[-1].mac=\'00:11:22:33:44:55\'";
  #uci "set dhcp.\@host[-1].name=\'host1\'";

  say "DHCP and DNS configured.";

  #uci "show network";
  uci "show dhcp";
  uci "commit network";
  uci "commit dhcp";

  # append ip_rules_config hack to network
  $h = $hostparam{hacks}->{ip_rules_config};
  append_if_no_such_line($network_file,
    line => $h,
    on_change => sub {
      say "Hack ip_rules_config was added to /etc/config/network.";
    }
  ) if $h;

  say "\nNetwork configuration finished for $hostparam{host}. Restarting the router will change the IP-s!!!.\n";
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
