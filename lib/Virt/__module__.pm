package Virt;

use Rex -feature=>['1.3'];
use Data::Dumper;


use Rex::Commands::Virtualization;
set virtualization => "Lxc";

sub check_os {
  die "Unsupported operating system.\n" unless operating_system_is('Debian');
  die "Unsupported OS version\n" if operating_system_version() < 90 and operating_system_version() != 10;
}


#------------------------------------------------
desc "List virtual machines, running on host";
task "list_vm", sub {
  check_os();
  my $_s = connection->server;
  #print Dumper vm list => 'all', fancy=>1;#, format=>'name,ram';
  say "Virtual machines on host server $_s:";
  my $v = run "lxc-ls -f";
  if ($? != 0) {
    die "Operation error possible caused by invalid command parameter.\n";
  }
  say $v."\n";
};


desc "Info abount virtual machine";
task "info_vm", sub {
  check_os();
  my $_n = shift->{name};
  my $_s = connection->server;
  die "Invalid parameter, run as: rex Virt:info_vm --name=vm-name.\n" unless $_n;
  #print Dumper vm info => $_n;
  say "Information about virtual machine $_n on host server $_s:";
  my $v = run "lxc-info -n $_n";
  if ($? != 0) {
    die "Operation error possible caused by invalid command parameter.\n";
  }
  say $v."\n";
};


desc "Start virtual machine";
task "start_vm", sub {
  check_os();
  my $_n = shift->{name};
  my $_s = connection->server;
  die "Invalid parameter, run as: rex Virt:start_vm --name=vm-name.\n" unless $_n;
  vm start => $_n;
  say "VM $_n on $_s successfully started.\n";
};


desc "Stop virtual machine";
task "stop_vm", sub {
  check_os();
  my $_n = shift->{name};
  my $_s = connection->server;
  die "Invalid parameter, run as: rex Virt:stop_vm --name=vm-name.\n" unless $_n;
  vm stop => $_n;
  say "VM $_n on $_s successfully stopped.\n";
};


#------------------------------------------------
desc "Create virtual machine";
task "create_vm", sub {
  check_os();
  my $_n = shift->{name};
  my $_s = connection->server;
  die "Invalid parameter, run as: rex Virt:create_vm --name=vm-name.\n" unless $_n;
  #vm create => $_n;
  die "Sorry this function not implemented yet. :(";
};


desc "Destroy virtual machine";
task "destroy_vm", sub {
  check_os();
  my $_n = shift->{name};
  my $_s = connection->server;
  die "Invalid parameter, run as: rex Virt:destroy_vm --name=vm-name.\n" unless $_n;
  vm destroy => $_n;
  say "VM $_n on $_s successfully destroyed.\n";
};

1;

=pod

=head1 NAME

$::module_name - {{ SHORT DESCRIPTION }}

=head1 DESCRIPTION

{{ LONG DESCRIPTION }}

=head1 USAGE

{{ USAGE DESCRIPTION }}

 include qw/Virt/;

 task yourtask => sub {
    Virt::example();
 };

=head1 TASKS

=over 4

=item example

This is an example Task. This task just output's the uptime of the system.

=back

=cut
