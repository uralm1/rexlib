package Deploy::Owrt::Firewall::obsolete::pre117;

use Rex -feature=>['1.4'];
#use Data::Dumper;

use Ural::Deploy::ReadDB_Owrt_pre117;
use Ural::Deploy::Utils qw(:DEFAULT recursive_search_by_from_hostname recursive_search_by_to_hostname);
use NetAddr::IP::Lite;


# --confhost=host parameter is required
sub configure {
  my $ch = shift->{confhost};
  my $p = Ural::Deploy::ReadDB_Owrt_pre117->read_db($ch);
  check_dev $p;

  say 'Firewall configuration started for '.$p->get_host;

  pkg "firewall", ensure => "present";

  file "/etc/config/firewall",
    owner => "ural",
    group => "root",
    mode => 644,
    content => template("files/firewall.pre117.tpl");

  uci "revert firewall";
  foreach (@{$p->{ssh_icmp_from_wans_ips}}) {
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
  uci "set firewall.\@rule[-1].dest_ip=\'$p->{log_ip}\'";
  uci "set firewall.\@rule[-1].dest_port=514";
  uci "set firewall.\@rule[-1].target=ACCEPT";

  #####
  my @outgoing_rules_ip_list;
  recursive_search_by_from_hostname(\@outgoing_rules_ip_list, $p->{tun_node_name},
    $p->{tun_array_ref}, $p->{tun_node_name});
  #say 'Outgoing: ', Dumper \@outgoing_rules_ip_list;

  my @incoming_rules_ip_list;
  recursive_search_by_to_hostname(\@incoming_rules_ip_list, $p->{tun_node_name},
    $p->{tun_array_ref}, $p->{tun_node_name});
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

  # include r2d2 configuration file
  uci "add firewall include";
  uci "set firewall.\@include[-1].type=restore";
  uci "set firewall.\@include[-1].path=\'/etc/firewall.user_r2d2\'";
  uci "set firewall.\@include[-1].family=ipv4";

  # include r2d2 client file
  uci "add firewall include";
  uci "set firewall.\@include[-1].type=restore";
  uci "set firewall.\@include[-1].path=\'/var/r2d2/firewall.clients\'";
  uci "set firewall.\@include[-1].family=ipv4";

  uci "add firewall include";
  uci "set firewall.\@include[-1].path=\'/etc/tc.user\'";

  # include r2d2 shaper configuration file
  uci "add firewall include";
  uci "set firewall.\@include[-1].path=\'/etc/tc.user_r2d2\'";

  #uci "show firewall";
  uci "commit firewall";
  insert_autogen_comment '/etc/config/firewall';

  my $lan_addr = NetAddr::IP::Lite->new($p->{lan_ip}, $p->{lan_netmask}) or die 'Lan net address calculation failure';
  #say "CIDR: ".$lan_addr->network->cidr;

  # R2d2 iptables_restore firewall.user_r2d2 file
  file '/etc/firewall.user_r2d2',
    owner => "ural",
    group => "root",
    mode => 644,
    content => template('files/firewall.user_r2d2.pre117.tpl',
      _client_net => $lan_addr->network->cidr,
      _r2d2_head_ip => $p->{r2d2_head_ip}
    ),
    on_change => sub {
      say "R2d2 configuration was added to /etc/firewall.user_r2d2.";
      say "HEAD access granted to $p->{r2d2_head_ip}." if $p->{r2d2_head_ip};
    };
 
  # R2d2 traffic shaper tc.user_r2d2 file
  file '/etc/tc.user_r2d2',
    owner => "ural",
    group => "root",
    mode => 644,
    content => template("files/tc.user_r2d2.0.tpl",
      _lan_interface => 'br-lan',
      _vpn_interface => 'vpn1',
      _r2d2_glob_speed_in => $p->{r2d2_glob_speed_in},
      _r2d2_glob_speed_out => $p->{r2d2_glob_speed_out},
      _r2d2_loc_speed_in => $p->{r2d2_loc_speed_in},
      _r2d2_loc_speed_out => $p->{r2d2_loc_speed_out},
      _r2d2_inet_speed_in => $p->{r2d2_inet_speed_in},
      _r2d2_inet_speed_out => $p->{r2d2_inet_speed_out},
      _r2d2_limited_speed_in => $p->{r2d2_limited_speed_in},
      _r2d2_limited_speed_out => $p->{r2d2_limited_speed_out},
    ),
    on_change => sub {
      say "R2d2 shaper configuration was added to /etc/tc.user_r2d2.";
      say "Traffic speed group: $p->{r2d2_speed_name}" if $p->{r2d2_speed_name};
    };
 
  my $firewall_user_file = '/etc/firewall.user';
  file $firewall_user_file,
    owner => "ural",
    group => "root",
    mode => 644,
    content => template("files/firewall.user.0.tpl");

  my $tc_user_file = '/etc/tc.user';
  file $tc_user_file,
    owner => "ural",
    group => "root",
    mode => 644,
    content => template("files/tc.user.0.tpl");

  say 'Firewall configuration finished for '.$p->get_host;
}


1;

=pod

=head1 NAME

$::Deploy::Owrt::Firewall - Configure firewall on Owrt router.

=head1 DESCRIPTION

Configures firewall on Owrt Router and installs r2d2 adapter module for gwsyn integration.

=head1 USAGE

rex -H 192.168.34.1 Deploy::Owrt::Firewall::configure --confhost=gwtest1

=head1 TASKS

=over 4

=item configure --confhost=gwtest1

Configures firewall on Owrt Router and installs r2d2 adapter module for gwsyn integration.

=back

=cut
