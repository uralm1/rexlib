package Deploy::Erebus::Software;

use Rex -feature=>['1.4'];
#use Data::Dumper;

use Ural::Deploy::ReadDB_Erebus;
use Ural::Deploy::Utils;


desc "Erebus router: Configure software";
# --confhost=erebus required
task "configure", sub {
  my $ch = shift->{confhost};
  my $p = read_db($ch);
  check_par;

  say 'Software configuration started for '.$p->get_host;

  # disable failsafe mode prompt (erebus is always x64)
  say "Disabling failsafe mode prompts.";
  file "/lib/preinit/30_failsafe_wait", ensure=>'absent';
  file "/lib/preinit/99_10_failsafe_login", ensure=>'absent';

  # install packages
  say "Updating package database.";
  update_package_db;
  say "Installing / updating packages.";
  for (qw/ip-full tc conntrack kmod-sched
    iperf3 irqbalance ethtool lm-sensors lm-sensors-detect
    strongswan-default tinc snmpd snmp-utils
    perl perlbase-encode perlbase-findbin perl-dbi perl-dbd-mysql perl-netaddr-ip perl-sys-runalone
    libmariadb openssh-client/) {
    pkg $_, ensure => latest,
      on_change => sub { say "package $_ was installed." };
  }
  say 'Software configuration finished for '.$p->get_host;
};


1;

=pod

=head1 NAME

$::module_name - {{ SHORT DESCRIPTION }}

=head1 DESCRIPTION

{{ LONG DESCRIPTION }}

=head1 USAGE

{{ USAGE DESCRIPTION }}

 include qw/Deploy::Erebus::Software/;

 task yourtask => sub {
    Deploy::Erebus::Software::example();
 };

=head1 TASKS

=over 4

=item example

This is an example Task. This task just output's the uptime of the system.

=back

=cut
