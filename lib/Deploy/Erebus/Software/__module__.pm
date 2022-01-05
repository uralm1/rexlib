package Deploy::Erebus::Software;

use Rex -feature=>['1.4'];
#use Data::Dumper;

use Ural::Deploy::ReadDB_Erebus;
use Ural::Deploy::Utils;


desc "Erebus router: Configure software";
# --confhost=erebus required
task "configure", sub {
  my $ch = shift->{confhost};
  my $p = Ural::Deploy::ReadDB_Erebus->read_db($ch);
  check_dev_erebus $p;

  say 'Software configuration started for '.$p->get_host;

  # disable failsafe mode prompt (erebus is always x64)
  say "Disabling failsafe mode prompts.";
  file "/lib/preinit/30_failsafe_wait", ensure=>'absent';
  file "/lib/preinit/99_10_failsafe_login", ensure=>'absent';

  # install packages
  say "Updating package database.";
  update_package_db;
  say "Installing / updating packages.";
  my $tc_package = operating_system_version() < 117 ? 'tc' : 'tc-full';
  for (qq/ip-full $tc_package conntrack kmod-sched
iperf3 irqbalance ethtool lm-sensors lm-sensors-detect
strongswan-default tinc snmpd snmp-utils
openssh-client/) {
    pkg $_, ensure => latest,
      on_change => sub { say "package $_ was installed." };
  }
  say 'Software configuration finished for '.$p->get_host;
};


1;

=pod

=head1 NAME

$::Deploy::Erebus::Software - Install base software packages on Erebus router.

=head1 DESCRIPTION

Installs base software packages on Erebus router not including perl for R2d2.

=head1 USAGE

<network repository should be online>

rex -H 192.168.12.3 Deploy::Erebus::Software::configure --confhost=erebus

=head1 TASKS

=over 4

=item configure --confhost=erebus

Installs base software.

=back

=cut
