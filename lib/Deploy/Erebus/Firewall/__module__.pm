package Deploy::Erebus::Firewall;

use Rex -feature=>['1.4'];
use Data::Dumper;

use Ural::Deploy::ReadDB_Erebus;
use Ural::Deploy::Utils qw(:DEFAULT recursive_search_by_from_hostname recursive_search_by_to_hostname);
use NetAddr::IP::Lite;


desc "Erebus router: Configure firewall";
# --confhost=erebus is required
task "configure", sub {
  my $ch = shift->{confhost};
  my $p = read_db($ch);
  check_par;

  say 'Firewall configuration started for '.$p->get_host;

  pkg "firewall", ensure => "present";

  my @lan_ifs = sort keys %{$p->{lan_ifs}};
  my @wan_ifs = sort keys %{$p->{wan_ifs}};
  file "/etc/config/firewall",
    owner => "ural",
    group => "root",
    mode => 644,
    content => template("files/firewall.0.tpl",
      _lan_interfaces => \@lan_ifs,
      _wan_interfaces => \@wan_ifs,
    );

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
  }

  # icmp-wan-in-limit
  uci "add firewall rule";
  #uci "set firewall.\@rule[-1].name=icmp-wan-in-limit";
  uci "set firewall.\@rule[-1].src=wan";
  uci "set firewall.\@rule[-1].proto=icmp";
  uci "add_list firewall.\@rule[-1].icmp_type=$_" foreach (0,3,4,8,11,12);
  uci "set firewall.\@rule[-1].limit=\'10/sec\'";
  uci "set firewall.\@rule[-1].target=ACCEPT";

  # icmp-wan-out
  uci "add firewall rule";
  #uci "set firewall.\@rule[-1].name=icmp-wan-out";
  uci "set firewall.\@rule[-1].dest=wan";
  uci "set firewall.\@rule[-1].proto=icmp";
  uci "set firewall.\@rule[-1].target=ACCEPT";

  # ssh-wan-out
  uci "add firewall rule";
  #uci "set firewall.\@rule[-1].name=ssh-wan-out";
  uci "set firewall.\@rule[-1].dest=wan";
  uci "set firewall.\@rule[-1].proto=tcp";
  uci "set firewall.\@rule[-1].dest_port=22";
  uci "set firewall.\@rule[-1].target=ACCEPT";

  # syslog-wan/lan-out
  for (qw/wan lan/) {
    uci "add firewall rule";
    #uci "set firewall.\@rule[-1].name=syslog-$_-out";
    uci "set firewall.\@rule[-1].dest=\'$_\'";
    uci "set firewall.\@rule[-1].proto=udp";
    uci "set firewall.\@rule[-1].dest_ip=\'$p->{log_ip}\'";
    uci "set firewall.\@rule[-1].dest_port=514";
    uci "set firewall.\@rule[-1].target=ACCEPT";
  }

  # ntp-lan-out
  uci "add firewall rule";
  #uci "set firewall.\@rule[-1].name=ntp-lan-out";
  uci "set firewall.\@rule[-1].dest=lan";
  uci "set firewall.\@rule[-1].proto=udp";
  uci "set firewall.\@rule[-1].dest_ip=\'$p->{ntp_ip}\'";
  uci "set firewall.\@rule[-1].dest_port=123";
  uci "set firewall.\@rule[-1].target=ACCEPT";

  # snmp-lan-in
  uci "add firewall rule";
  #uci "set firewall.\@rule[-1].name=snmp-lan-in";
  uci "set firewall.\@rule[-1].src=lan";
  uci "set firewall.\@rule[-1].proto=udp";
  uci "set firewall.\@rule[-1].dest_port=161";
  uci "set firewall.\@rule[-1].target=ACCEPT";

  # opkg-lan-out
  uci "add firewall rule";
  #uci "set firewall.\@rule[-1].name=opkg-lan-out";
  uci "set firewall.\@rule[-1].dest=lan";
  uci "set firewall.\@rule[-1].dest_ip=\'10.15.0.3\'";
  uci "set firewall.\@rule[-1].proto=tcp";
  uci "set firewall.\@rule[-1].dest_port=80";
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

  my @hacks_restore_list = qw/pf_input_ipsec pf_rsyslog_forwarding pf_admin_access_des
    pf_clients_forwarding/;

  for (@hacks_restore_list) {
    uci "add firewall include";
    uci "set firewall.\@include[-1].type=restore";
    uci "set firewall.\@include[-1].path=\'/etc/firewall.user_${_}\'";
    uci "set firewall.\@include[-1].family=ipv4";
  }

  # include r2d2 configuration file
  uci "add firewall include";
  uci "set firewall.\@include[-1].type=restore";
  uci "set firewall.\@include[-1].path=\'/etc/firewall.user_r2d2\'";
  uci "set firewall.\@include[-1].family=ipv4";


  uci "add firewall include";
  uci "set firewall.\@include[-1].path=\'/etc/firewall.user\'";

  uci "add firewall include";
  uci "set firewall.\@include[-1].path=\'/etc/tc.user\'";

  #uci "show firewall";
  uci "commit firewall";
  insert_autogen_comment '/etc/config/firewall';

  # R2d2 iptables_restore firewall.user_r2d2 file
  my $r2d2_head_ip = '10.14.72.5';
  my $__ipn = NetAddr::IP::Lite->new($r2d2_head_ip, 24) or die 'Bad head ip address';
  file '/etc/firewall.user_r2d2',
    owner => "ural",
    group => "root",
    mode => 644,
    content => template("files/firewall.user_r2d2.0.tpl",
      _client_net => '10.0.0.0/8',
      _r2d2_head_ip => $r2d2_head_ip,
      _r2d2_head_net => $__ipn->network
    ),
    on_change => sub {
      say "R2d2 configuration was added to /etc/firewall.user_r2d2.";
      say "HEAD access granted to $r2d2_head_ip.";
    };

  # save iptables_restore hacks to firewall.user_xxx files
  for (@hacks_restore_list) {
    my $h = $p->{hacks}{$_};
    file("/etc/firewall.user_$_",
      owner => "ural",
      group => "root",
      mode => 644,
      content => $h,
      on_change => sub {
	say "Hack $_ was added to /etc/firewall.user_$_.";
      }
    ) if $h;
  }

  my $firewall_user_file = '/etc/firewall.user';
  file $firewall_user_file,
    owner => "ural",
    group => "root",
    mode => 644,
    content => template("files/firewall.user.0.tpl");

  # append hacks to firewall.user
  for (qw/pf_interfaces_names 
    pf_snat_config pf_dnat_config pf_internet_forwarding pf_ban_in_logs/) {
    my $h = $p->{hacks}{$_};
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
    my $h = $p->{hacks}{$_};
    append_if_no_such_line($tc_user_file,
      line => $h,
      on_change => sub {
	say "Hack $_ was added to /etc/tc.user.";
      }
    ) if $h;
  }


  say 'Firewall configuration finished for '.$p->get_host;
};


##################################
desc "Erebus router: Test firewall hacks";
task "test_hacks", sub {
  my $p = read_db 'erebus';
  check_par;

  say 'Firewall hacks test started for '.$p->get_host;
  my $err = undef;

  my @hacks_restore_list = qw/pf_input_ipsec pf_rsyslog_forwarding pf_admin_access_des
    pf_clients_forwarding/;

  for (@hacks_restore_list) {
    say "* Testing hack: $_";
    my $h = $p->{hacks}{$_};
    if ($h) {
      my $fn = '/tmp/testhack.tmp';
      my $f = undef;
      file($fn,
	content => $h, 
	on_change => sub { $f = 1 }
      );
      say "ERROR! Temporary file is not created! This is subject for detailed investigation." unless $f;

      my $output = run "/usr/sbin/iptables-restore --noflush --test < $fn", timeout => 100;
      say $output if $output;
      if ($? > 0) { $err = 1 }
      if ($? == 0) {
	say "OK, result: $?.";
      } elsif ($? == 1) {
	say "ERROR, result: $?, hack contents format error.";
      } elsif ($? == 2) {
	say "ERROR, result: $?, iptables rule or chain error.";
      } else {
	say "ERROR, result: $?, unspecified error.";
      }

      unlink($fn);
    } else {
      say "WARNING! Hack contents is empty. It will be simply ignored.";
    }
    say;
  }

  say 'Firewall hacks test finished for '.$p->get_host;
  die "\nERRORS found!!! Fix it before applying firewall configuration.\n" if $err;
  0;
};


##################################
desc "Erebus router: restart firewall (useful after updating firewall hacks)";
task "restart", sub {
  say "Restarting firewall on host ".connection->server." ...";
  #service firewall => 'restart';
  my $output = run "/etc/init.d/firewall restart 2>&1", timeout => 100;
  say $output if $output;
  return (($? > 0) ? 255:0);
};


1;

=pod

=head1 NAME

$::Deploy::Erebus::Firewall - Configure firewall on Erebus router.

=head1 DESCRIPTION

Configures firewall on Erebus Router.

=head1 USAGE

rex -H 192.168.12.3 Deploy::Erebus::Firewall::configure --confhost=erebus

=head1 TASKS

=over 4

=item configure --confhost=erebus

Configures firewall on Erebus Router.

=back

=cut
