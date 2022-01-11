package Ural::Deploy::ReadDB_Owrt;

use strict;
use warnings;
use v5.12;
#use utf8;

use Rex;
use Rex::Commands;
use Rex::CMDB;

use DBI;
use NetAddr::IP::Lite;

use Carp;
use Ural::Deploy::HostParamOwrt;
use Ural::Deploy::Utils qw(remove_dups);
use parent 'Ural::Deploy::ReadDB_base';


# my $r = Ural::Deploy::ReadDB_Owrt->new();
# my $r = Ural::Deploy::ReadDB_Owrt->new(skip_erebus_check => 1);
sub new {
  my ($class, %args) = @_;
  my $self = $class->SUPER::new();
  $self->{result_type} = 'Ural::Deploy::HostParamOwrt';
  #$self->{dbh};

  for (qw/skip_erebus_check/) {
    $self->{$_} = $args{$_} if defined $args{$_};
  }

  return $self;
}


sub _read_uncached {
  my ($self, $host) = @_;
  #say "Reading uncached owrt: $host";

  croak "Erebus router must be configured by Deploy:Erebus:* tasks.\n" if !$self->{skip_erebus_check} && $host =~ /^erebus$/;
  my $dbname = get cmdb('dbname');
  my $dbhost = get cmdb('dbhost');
  croak "CMDB failure. Possible CMDB is not initialized.\n" unless $dbname and $dbhost;

  my $p = Ural::Deploy::HostParamOwrt->new(host => $host);

  my $dbh = DBI->connect("DBI:mysql:database=$dbname;host=$dbhost", get(cmdb('dbuser')), get(cmdb('dbpass'))) or 
    croak "Connection to the database failed.\n";
  $dbh->do("SET NAMES 'UTF8'");
  $self->{dbh} = $dbh;

  my $hr = $dbh->selectrow_hashref("SELECT \
routers.id AS router_id, \
router_equipment.eq_name AS equipment_name, \
router_equipment.manufacturer AS manufacturer, \
os_types.id AS router_os_id, \
os_types.os_type AS router_os_name, \
departments.dept_name AS dept_name, \
routers.gateway AS gateway, \
routers.dns_list AS dns_unparsed, \
routers.dns_suffix AS dns_suffix, \
routers.log_ip AS log_ip, \
routers.ntp_ip AS ntp_ip, \
routers.ssh_icmp_from_wans_ips AS ssh_icmp_from_wans_ips_unparsed, \
routers.r2d2_head_ip AS r2d2_head_ip, \
rs.name AS r2d2_speed_name, \
rs.glob_speed_in AS r2d2_glob_speed_in, \
rs.glob_speed_out AS r2d2_glob_speed_out, \
rs.loc_speed_in AS r2d2_loc_speed_in, \
rs.loc_speed_out AS r2d2_loc_speed_out, \
rs.inet_speed_in AS r2d2_inet_speed_in, \
rs.inet_speed_out AS r2d2_inet_speed_out, \
rs.limited_speed_in AS r2d2_limited_speed_in, \
rs.limited_speed_out AS r2d2_limited_speed_out \
FROM routers \
LEFT OUTER JOIN router_equipment ON router_equipment.id = routers.equipment_id \
LEFT OUTER JOIN os_types ON os_types.id = router_equipment.os_type_id \
LEFT OUTER JOIN departments ON departments.id = routers.placement_dept_id \
LEFT OUTER JOIN r2d2_speeds rs ON rs.id = routers.r2d2_speed_id \
WHERE host_name = ?", {}, $host);
  croak "There's no such host in the database, or database error.\n" unless $hr;
  #say Dumper $hr;

  while (my ($key, $value) = each %$hr) {
    $p->{$key} = $value;
  }

  # read wans and lans
  $p->{wan_ifs} = {};
  $self->populate_interfaces($p->{wan_ifs}, 1, $p->{router_id});
  $p->{lan_ifs} = {};
  $self->populate_interfaces($p->{lan_ifs}, 2, $p->{router_id});

  # parse dns_list
  $p->{dns} = [split /,/, $p->{dns_unparsed}];
  delete $p->{dns_unparsed};

  # parse ssh_icmp_from_wans_ips
  $p->{ssh_icmp_from_wans_ips} = [split /,/, $p->{ssh_icmp_from_wans_ips_unparsed}];
  delete $p->{ssh_icmp_from_wans_ips_unparsed};

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
WHERE routers.host_name = ?", {}, $host);
  croak "There's no such vpn in the database, or database error.\n" unless $hr;
  #say Dumper $hr;

  while (my ($key, $value) = each %$hr) {
    $p->{$key} = $value;
  }

  my $net = NetAddr::IP::Lite->new($hr->{tun_subnet_ip}, $hr->{tun_subnet_mask}) or
    croak("Invalid vpn subnet address or mask!\n");
  $p->{tun_subnet} = $net->cidr;

  $p->{tun_array_ref} = $self->read_tunnels_tinc();
  #say Dumper $p->{tun_array_ref};

  # build tinc connect_to list of nodes
  my $node_name = $p->{tun_node_name};
  my @tmp_list = grep { $_->{from_hostname} eq $node_name } @{$p->{tun_array_ref}};
  #say Dumper \@tmp_list;
  say "INFORMATION! NO destination VPN tunnels are configured for this node. ConnectTo list will be empty." unless @tmp_list;

  $p->{tun_connect_nodes} = remove_dups([map { $_->{to_hostname} } @tmp_list]);
  foreach (@{$p->{tun_connect_nodes}}) {
    croak "Invalid tunnel configuration! Source node connected to itself!\n" if $_ eq $node_name;
  }
  ### TODO: check if we can run without vpn configuration records

  # build wan route list (auto_wan_routes)
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
    next RLIST if $data->[0] eq $host; # skip self
    #say Dumper $data;
    my $dst_ip = NetAddr::IP::Lite->new($data->[1], $data->[2]);
    croak "Invalid wan ip address while building route list" unless $dst_ip;
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
    push @w_route_list, {name => $_r_name, target => $_r_target, netmask => $_r_netmask, gateway => $p->{gateway}};
  }
  $p->{auto_wan_routes} = \@w_route_list;
  #say Dumper $p->{auto_wan_routes};

  $dbh->disconnect;
  $self->{dbh} = undef;

  return $self->set_cache($host, $p);
}


# $p->{wan_ifs} = {};
# $self->populate_interfaces($p->{wan_ifs} /to fill in/, $if_type /1 or 2/, $router_id);
sub populate_interfaces {
  my ($self, $ifs_href, $if_type, $router_id) = @_;
  croak "Unsupported interface type $if_type\n" unless $if_type == 1 || $if_type == 2;

  my $ar = $self->{dbh}->selectall_arrayref("SELECT \
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
  croak "Fetching interfaces database failure.\n" unless $ar;
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
      my $ar1 = $self->{dbh}->selectall_arrayref("SELECT \
type AS type, \
nets.net_ip AS target, \
nets.mask AS netmask, \
r_table AS 'table' \
FROM routes \
INNER JOIN nets ON net_dst_id = nets.id \
WHERE router_id = ? AND net_src_id = ?", {Slice=>{}, MaxRows=>500}, $router_id, $_->{net_src_id});
      croak "Fetching routes database failure.\n" unless $ar1;
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


sub read_tunnels_tinc {
  my $self = shift;
  my $s = $self->{dbh}->prepare("SELECT \
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


# my $hostparam = Ural::Deploy::ReadDB_Owrt->read_db('testhost1', [no_cache => 1]);
sub read_db {
  my ($class, $host, %args) = @_;
  return $class->new(skip_erebus_check => $args{skip_erebus_check})->read($host, %args);
}


1;
