package Deploy::Owrt::System;

use Rex -feature=>['1.4'];
#use Data::Dumper;

use Ural::Deploy::ReadDB_Owrt;
use Ural::Deploy::Utils qw(:DEFAULT is_x86);

require Deploy::Owrt::System::obsolete::pre117;


desc "OWRT routers: Configure system parameters";
# --confhost=host parameter is required
task "configure", sub {
  my $ch = shift->{confhost};

  # obsolete code begin
  if (operating_system_version() < 117) {
    Deploy::Owrt::System::obsolete::pre117::configure({confhost => $ch});
    exit 0;
  } # obsolete code end

  my $p = Ural::Deploy::ReadDB_Owrt->read_db($ch);
  check_dev $p;

  say 'System configuration started for '.$p->get_host;

  my $conntrack_max = 16384;

  my $router_os = router_os $p;
  if ($router_os =~ /^mips tp-link$/i) {
    $conntrack_max = 16384;
    
  } elsif ($router_os =~ /^mips mikrotik$/i) {
    $conntrack_max = 65536;

  } elsif ($router_os =~ /^x86$/i) {
    $conntrack_max = 131072;

  } else {
    die "Unsupported router_os!\n";
  }

  # we need /bin/config_generate
  my $config_generate = can_run('config_generate') or die "config_generate not found!\n";

  # recreate /etc/config/system
  file '/etc/config/system', ensure => 'absent';
  run $config_generate, auto_die=>1, timeout=>10;
  say "/etc/config/system created.";

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
  uci "set system.\@system[0].ttylogin=\'1\'" if is_x86();
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
  file "/etc/sysctl.conf",
    owner => "ural",
    group => "root",
    mode => 644,
    content => template('files/sysctl.conf.0.tpl', _conntrack_max => $conntrack_max),
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
