package Deploy::Erebus::R2d2;

use Rex -feature=>['1.4'];
use Rex::Commands::Cron;
use Data::Dumper;

use Ural::Deploy::ReadDB_Erebus;
use Ural::Deploy::Utils;


desc "Erebus router: Configure r2d2";
# --confhost=erebus is required
task "configure", sub {
  my $ch = shift->{confhost};
  my $p = read_db($ch);
  check_par;

  say 'R2d2 configuration started for '.$p->get_host;

  for (qw/perl perlbase-encode perlbase-findbin perl-dbi perl-dbd-mysql perl-netaddr-ip perl-sys-runalone libmariadb/) {
    pkg $_, ensure => "present";
  }

  file "/etc/r2d2",
    owner => "ural",
    group => "root",
    mode => 755,
    ensure => "directory";

  for (qw/rtsyn print_rules/) {
    file "/etc/r2d2/$_",
      owner => "ural",
      group => "root",
      mode => 755,
      source => "files/$_",
      on_change => sub { say "$_ installed." };
  }

  file '/etc/r2d2/r2d2.conf',
    owner => "ural",
    group => "root",
    mode => 644,
    source => "files/r2d2.conf",
    on_change => sub { say "r2d2.conf installed." };

  host_entry 'bikini.uwc.local',
    ensure => 'present',
    ip => '10.15.0.3',
    on_change => sub { say "Control server address added to /etc/hosts." };

  cron_entry 'rtsyn',
    ensure => 'present',
    command => "/etc/r2d2/rtsyn 1> /dev/null",
    user => 'ural',
    minute => '1,31',
    hour => '*',
    on_change => sub { say "cron entry for rtsyn created." };

  #my @crons = cron list => "ural"; say Dumper(\@crons);

  # run rtsyn after every reboot
  delete_lines_matching '/etc/rc.local', 'exit 0';
  append_if_no_such_line '/etc/rc.local',
    "(sleep 10 && logger 'Starting rtsyn ater reboot' && /etc/r2d2/rtsyn >/dev/null)&",
    on_change => sub { say "rc.local line to run rtsyn on reboot added." };
  append_if_no_such_line '/etc/rc.local', 'exit 0';

  say 'R2d2 configuration finished for '.$p->get_host;
};


1;

=pod

=head1 NAME

$::module_name - {{ SHORT DESCRIPTION }}

=head1 DESCRIPTION

{{ LONG DESCRIPTION }}

=head1 USAGE

{{ USAGE DESCRIPTION }}

 include qw/Deploy::Erebus::R2d2/;

 task yourtask => sub {
    Deploy::Erebus::R2d2::example();
 };

=head1 TASKS

=over 4

=item example

This is an example Task. This task just output's the uptime of the system.

=back

=cut
