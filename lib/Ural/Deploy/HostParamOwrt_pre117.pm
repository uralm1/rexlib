package Ural::Deploy::HostParamOwrt_pre117;

use strict;
use warnings;
use v5.12;
#use utf8;

use Carp;
use parent 'Ural::Deploy::HostParam';

# $p = Ural::Deploy::HostParamOwrt_pre117->new(
#   host => 'testhost1',
# );
sub new {
  my ($class, %args) = @_;
  my $self = $class->SUPER::new(host => $args{host});

  # example stucture
  #{ host => '',
  #  router_id, equipment_name, manufacturer, router_os_id, router_os_name, dept_name,
  #  gateway => '',
  #  dns => ['',],
  #  dns_suffix => '',
  #  log_ip => '',
  #  ntp_ip => '',
  #  ssh_icmp_from_wans_ips => ['',],
  #  wan_ip => '',
  #  wan_netmask => '',
  #  auto_wan_routes => [{name=>'',target=>'',netmask=>'',gateway=>''},],
  #  lan_ip => '',
  #  lan_netmask => '',
  #  lan_routes => [{name=>'',type=>1,target=>'',netmask=>'',gateway=>'',table=>''},],
  #  dhcp_on => 0,
  #  dhcp_start => 0,
  #  dhcp_limit => 0,
  #  dhcp_leasetime => '',
  #  dhcp_dns => '',
  #  dhcp_dns_suffix => '',
  #  dhcp_wins => '',
  #  dhcp_static_leases => [{name=>'',mac=>'',ip=>''},],
  #  tun_node_name => '',
  #  tun_node_ip => '',
  #  tun_subnet => '',
  #  tun_connect_nodes => [],
  #  tun_int_ip => '',
  #  tun_int_netmask => '',
  #  tun_pub_key => '',
  #  tun_priv_key => '',
  #  tun_array_ref => [],
  #  r2d2_head_ip => '',
  #  r2d2_speed_name => '',
  #  r2d2_glob_speed_in => '',
  #  r2d2_glob_speed_out => '',
  #  r2d2_loc_speed_in => '',
  #  r2d2_loc_speed_out => '',
  #  r2d2_inet_speed_in => '',
  #  r2d2_inet_speed_out => '',
  #  r2d2_limited_speed_in => '',
  #  r2d2_limited_speed_out => '',
  #};

  return $self;
}


1;
