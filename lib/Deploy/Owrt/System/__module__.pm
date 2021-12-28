package Deploy::Owrt::System;

use Rex -feature=>['1.4'];
#use Data::Dumper;

use Ural::Deploy::ReadDB_Owrt;
use Ural::Deploy::Utils qw(:DEFAULT is_x86);


desc "OWRT routers: Configure system parameters";
# --confhost=host parameter is required
task "configure", sub {
  my $ch = shift->{confhost};
  my $p = read_db($ch);
  check_dev $p;

  my $tpl_sys_file;
  my $conntrack_max = 16384;

  my $router_os = router_os $p;
  if ($router_os =~ /^mips tp-link$/i) {
    $tpl_sys_file = 'files/system.tp1043.tpl';
    $conntrack_max = 16384;
    
  } elsif ($router_os =~ /^mips mikrotik$/i) {
    $tpl_sys_file = 'files/system.rb750gr3.117.tpl';
    $conntrack_max = 65536;

  } elsif ($router_os =~ /^x86$/i) {
    $tpl_sys_file = 'files/system.x86.tpl';
    $conntrack_max = 131072;

  } else {
    die "Unsupported router_os!\n";
  }

  say 'System configuration started for '.$p->get_host;

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
    content => template("files/banner.0.tpl", _hostname=>$p->get_host),
    on_change => sub { say "banner updated." };

  uci "revert system";

  # system parameters
  uci "set system.\@system[0].hostname=\'$p->{host}\'";
  uci "set system.\@system[0].timezone=\'UTC-5\'";
  uci "set system.\@system[0].ttylogin=\'1\'" if is_x86() and operating_system_version() > 114;
  if (defined $p->{log_ip} && $p->{log_ip} ne '') {
    uci "set system.\@system[0].log_ip=\'$p->{log_ip}\'";
    uci "set system.\@system[0].log_port=\'514\'";
  }
  say "/etc/config/system configured.";

  # ntp
  uci "set system.ntp.enable_server=0";
  if (defined $p->{ntp_ip} && $p->{ntp_ip} ne '') {
    uci "set system.ntp.enabled=1";
    uci "delete system.ntp.server";
    uci "add_list system.ntp.server=\'$p->{ntp_ip}\'";
  } else {
    uci "set system.ntp.enabled=0";
  }
  say "NTP server configured.";

  #uci "show system";
  uci "commit system";
  insert_autogen_comment '/etc/config/system';

  # tune sysctl
  my $tpl_sysctl_file = (operating_system_version() > 113) ? 'files/sysctl.conf.0.tpl' : 'files/sysctl.conf.113.tpl';
  file "/etc/sysctl.conf",
    owner => "ural",
    group => "root",
    mode => 644,
    content => template($tpl_sysctl_file, _conntrack_max => $conntrack_max),
    on_change => sub { say "sysctl parameters configured." };

  say 'System configuration finished for '.$p->get_host;
};


1;

=pod

=head1 NAME

$::Deploy::Owrt::System - Configure system parameters on Owrt routers.

=head1 DESCRIPTION

Configure system parameters on Owrt routers.

=head1 USAGE

rex -H 192.168.34.1 Deploy::Owrt::System::configure --confhost=gwtest1

but better use full configuration task:

rex -H 192.168.34.1 Deploy::Owrt::deploy_router --confhost=gwtest1

=head1 TASKS

=over 4

=item configure --confhost=gwtest1

Configure system parameters on Owrt routers task.

=back

=cut
