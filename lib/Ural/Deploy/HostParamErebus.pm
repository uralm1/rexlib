package Ural::Deploy::HostParamErebus;

use strict;
use warnings;
use v5.12;
#use utf8;

use Carp;
use parent 'Ural::Deploy::HostParam';

# $p = Ural::Deploy::HostParamErebus->new(
#   host => 'testhost1',
# );
sub new {
  my ($class, %args) = @_;
  my $self = $class->SUPER::new(host => $args{host});

  # example structure
  #{ host => '',
  #  router_id, equipment_name, manufacturer, router_os_id, router_os_name, dept_name,
  #  gateway => '',
  #  dns => ['',],
  #  dns_suffix => '',
  #  log_ip => '',
  #  ntp_ip => '',
  #  ssh_icmp_from_wans_ips => ['',],
  #  wan_ifs => {ifname=>{ip=>'',netmask=>'',vlan=>'',alias=>0, 
  #    routes=>[{name=>'',type=>1,gateway=>'',target=>'',netmask=>'',table=>''},],
  #    dhcp_on=>0,dhcp_start=>0,dhcp_limit=>0,dhcp_leasetime=>'',dhcp_dns=>'',dhcp_dns_suffix=>'',dhcp_wins=>'',
  #    dhcp_static_leases=>[{name=>'',mac=>'',ip=>''},],
  #  },},
  #  lan_ifs => {},
  #  tun_node_name => '',
  #  tun_node_ip => '',
  #  tun_subnet => '',
  #  tun_connect_nodes => [],
  #  tun_int_ip => '',
  #  tun_int_netmask => '',
  #  tun_pub_key => '',
  #  tun_priv_key => '',
  #  tun_array_ref => [],
  #  hacks => {codename=>'content',},
  #};

  return $self;
}


1;
