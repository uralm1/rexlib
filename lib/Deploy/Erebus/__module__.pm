package Deploy::Erebus;

use Rex -feature=>['1.4'];
#use Data::Dumper;

use Ural::Deploy::ReadDB_Erebus;
use Ural::Deploy::Utils;


#
### Configuration
#
desc "Erebus router: DEPLOY ROUTER
  rex -H 10.0.1.1 Deploy:Erebus:deploy_router [--confhost=erebus]";
task "deploy_router", sub {
  my $ch = shift->{confhost} // 'erebus';
  my $p = read_db($ch);
  check_dev_erebus;

  say 'Router deployment/Erebus/ started for '.$p->get_host;
  say "Router manufacturer from database: $p->{manufacturer}" if $p->{manufacturer};
  say "Router type from database: $p->{equipment_name}" if $p->{equipment_name};
  say "Department: $p->{dept_name}\n" if $p->{dept_name};
  # confhost parameter is required
  Deploy::Erebus::Software::configure( { confhost => $ch } );
  sleep 1;
  Deploy::Erebus::System::configure( { confhost => $ch } );
  sleep 1;
  Deploy::Erebus::Net::configure( { confhost => $ch } );
  sleep 1;
  Deploy::Erebus::Firewall::configure( { confhost => $ch } );
  sleep 1;
  Deploy::Erebus::Ipsec::configure( { confhost => $ch } );
  sleep 1;
  Deploy::Erebus::Tinc::configure( { confhost => $ch } );
  sleep 1;
  Deploy::Erebus::R2d2::configure( { confhost => $ch } );
  sleep 1;
  Deploy::Erebus::Snmp::configure( { confhost => $ch } );
  say 'Router deployment/Erebus/ finished for '.$p->get_host;
  say "!!! Reboot router manually to apply changes !!!";
};


##################################
task "_t", sub {
  my $p = read_db 'erebus';
  check_dev_erebus;
  $p->dump;
}, {dont_register => TRUE};


1;

=pod

=head1 NAME

$::module_name - {{ SHORT DESCRIPTION }}

=head1 DESCRIPTION

{{ LONG DESCRIPTION }}

=head1 USAGE

{{ USAGE DESCRIPTION }}

 include qw/Deploy::Erebus/;

 task yourtask => sub {
    Deploy::Erebus::example();
 };

=head1 TASKS

=over 4

=item example

This is an example Task. This task just output's the uptime of the system.

=back

=cut
