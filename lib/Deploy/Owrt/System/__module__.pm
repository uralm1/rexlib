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
  check_par_old;

  say 'System configuration started for '.$p->get_host;

  my $tpl_sys_file = is_x86() ? 'files/system.x86.tpl' : 'files/system.tp1043.tpl';
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
    content => template('files/sysctl.conf.0.tpl'),
    on_change => sub { say "sysctl parameters configured." };

  say 'System configuration finished for '.$p->get_host;
};


1;

=pod

=head1 NAME

$::module_name - {{ SHORT DESCRIPTION }}

=head1 DESCRIPTION

{{ LONG DESCRIPTION }}

=head1 USAGE

{{ USAGE DESCRIPTION }}

 include qw/Deploy::Owrt::System/;

 task yourtask => sub {
    Deploy::Owrt::System::example();
 };

=head1 TASKS

=over 4

=item example

This is an example Task. This task just output's the uptime of the system.

=back

=cut
