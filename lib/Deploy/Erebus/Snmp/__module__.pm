package Deploy::Erebus::Snmp;

use Rex -feature=>['1.4'];
#use Data::Dumper;

use Ural::Deploy::ReadDB_Erebus;
use Ural::Deploy::Utils;


desc "Erebus router: Configure snmp";
# --confhost=erebus is required
task "configure", sub {
  my $ch = shift->{confhost};
  my $p = Ural::Deploy::ReadDB_Erebus->read_db($ch);
  check_dev_erebus $p;

  say 'Snmp configuration started for '.$p->get_host;

  pkg 'snmpd', ensure => 'present';

  file "/etc/config/snmpd",
    owner => "ural",
    group => "root",
    mode => 644,
    content => template('files/snmpd.0.tpl', _hostname=>$p->get_host),
    on_change => sub { say "/etc/config/snmpd installed." };

  say 'Snmp configuration finished for '.$p->get_host;
};


1;

=pod

=head1 NAME

$::module_name - {{ SHORT DESCRIPTION }}

=head1 DESCRIPTION

{{ LONG DESCRIPTION }}

=head1 USAGE

{{ USAGE DESCRIPTION }}

 include qw/Deploy::Erebus::Snmp/;

 task yourtask => sub {
    Deploy::Erebus::Snmp::example();
 };

=head1 TASKS

=over 4

=item example

This is an example Task. This task just output's the uptime of the system.

=back

=cut
