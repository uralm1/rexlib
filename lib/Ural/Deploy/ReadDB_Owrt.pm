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

use Exporter 'import';
our @EXPORT = qw(read_db);


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

  croak "Erebus router must be configured by Deploy:Erebus:* tasks.\n" if (!$self->{skip_erebus_check} && $host =~ /^erebus$/);
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
wans.ip AS wan_ip, \
wn.mask AS wan_netmask, \
lans.ip AS lan_ip, \
ln.mask AS lan_netmask, \
lans.net_id AS lan_net_id, \
ln.net_gw AS lan_net_gw, \
lans.dhcp_on AS dhcp_on, \
ln.dhcp_start_ip AS dhcp_start, \
ln.dhcp_limit AS dhcp_limit, \
ln.dhcp_leasetime AS dhcp_leasetime, \
ln.dhcp_dns AS dhcp_dns, \
ln.dhcp_dns_suffix AS dhcp_dns_suffix, \
ln.dhcp_wins AS dhcp_wins, \
ln.dhcp_static_leases AS dhcp_static_leases_unparsed, \
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
INNER JOIN interfaces wans ON wans.router_id = routers.id AND wans.type = 1 \
INNER JOIN nets wn ON wn.id = wans.net_id \
INNER JOIN interfaces lans ON lans.router_id = routers.id AND lans.type = 2 \
INNER JOIN nets ln ON ln.id = lans.net_id \
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

  # extract routes for lan interface
  my $ar1 = $dbh->selectall_arrayref("SELECT \
type AS type, \
nets.net_ip AS target, \
nets.mask AS netmask, \
r_table AS 'table' \
FROM routes \
INNER JOIN nets ON net_dst_id = nets.id \
WHERE net_src_id = ?", {Slice=>{}, MaxRows=>500}, $p->{lan_net_id});
  croak "Fetching routes database failure.\n" unless $ar1;
  #say Dumper $ar1;

  $p->{lan_routes} = [];
  my $routeid = 1;
  my $r_gateway = $p->{lan_net_gw};
  for (@$ar1) {
    my $r1 = {
      name => "lan_route$routeid",
      gateway => $r_gateway,
      target => $_->{target},
      netmask => $_->{netmask},
      table => $_->{table},
      type => $_->{type},
    };
    push @{$p->{lan_routes}}, $r1;
    $routeid++;
  }
  delete $p->{lan_net_id};
  delete $p->{lan_net_gw};

  # parse dns_list
  $p->{dns} = [split /,/, $p->{dns_unparsed}];
  delete $p->{dns_unparsed};
  # parse dhcp_start
  if ($p->{dhcp_start} =~ /^(?:[0-9]{1,3}\.){3}([0-9]{1,3})$/) {
    $p->{dhcp_start} = $1;
  }
  # parse ssh_icmp_from_wans_ips
  $p->{ssh_icmp_from_wans_ips} = [split /,/, $p->{ssh_icmp_from_wans_ips_unparsed}];
  delete $p->{ssh_icmp_from_wans_ips_unparsed};
  # parse dhcp_static_leases
  my @rres1;
  foreach (split /;/, $p->{dhcp_static_leases_unparsed}) {
    my @cr = split /,/, $_;
    if ($cr[0] and
      $cr[1] =~ /^(?:[0-9a-fA-F]{1,2}\:){5}[0-9a-fA-F]{1,2}$/ and
      $cr[2] =~ /^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$/) {
        push @rres1, {name => 'lan_'.lc($cr[0]), mac => $cr[1], ip => $cr[2]};
    } else {
      say "WARNING: invalid dhcp static lease: $cr[0] on lan interface ignored.";
    }
  }
  $p->{dhcp_static_leases} = \@rres1;
  delete $p->{dhcp_static_leases_unparsed};

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
  say "WARNING!!! NO destination VPN tunnels are configured for this node. ConnectTo list will be empty." unless @tmp_list;

  $p->{tun_connect_nodes} = remove_dups([map { $_->{to_hostname} } @tmp_list]);
  foreach (@{$p->{tun_connect_nodes}}) {
    croak "Invalid tunnel configuration! Source node connected to itself!\n" if $_ eq $node_name;
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


# my $hostparam = read_db('testhost1', [no_cache => 1]);
sub read_db {
  my ($host, %args) = @_;
  return Ural::Deploy::ReadDB_Owrt->new(skip_erebus_check => $args{skip_erebus_check})->read($host, %args);
}


1;
