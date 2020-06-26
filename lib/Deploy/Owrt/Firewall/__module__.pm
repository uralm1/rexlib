package Deploy::Owrt::Firewall;

use Rex -feature=>['1.4'];
use Data::Dumper;

use Ural::Deploy::ReadDB_Owrt;
use Ural::Deploy::Utils qw(:DEFAULT recursive_search_by_from_hostname recursive_search_by_to_hostname);


desc "OWRT routers: Configure firewall";
# --confhost=host parameter is required
task "configure", sub {
  my $ch = shift->{confhost};
  my $p = read_db($ch);
  check_par_old;

  say 'Firewall configuration started for '.$p->get_host;

  pkg "firewall", ensure => "present";

  file "/etc/config/firewall",
    owner => "ural",
    group => "root",
    mode => 644,
    content => template("files/firewall.0.tpl");

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

  #uci "show firewall";
  uci "commit firewall";
  insert_autogen_comment '/etc/config/firewall';

  file "/etc/firewall.user",
    owner => "ural",
    group => "root",
    mode => 644,
    content => template("files/firewall.user.0.tpl");

  say 'Firewall configuration finished for '.$p->get_host;
};


1;

=pod

=head1 NAME

$::module_name - {{ SHORT DESCRIPTION }}

=head1 DESCRIPTION

{{ LONG DESCRIPTION }}

=head1 USAGE

{{ USAGE DESCRIPTION }}

 include qw/Deploy::Owrt::Firewall/;

 task yourtask => sub {
    Deploy::Owrt::Firewall::example();
 };

=head1 TASKS

=over 4

=item example

This is an example Task. This task just output's the uptime of the system.

=back

=cut
