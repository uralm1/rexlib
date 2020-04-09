package UtilRex;

use Rex -feature => ['1.3'];


desc "Show rex system information";
task "dump_system_information", sub {
  dump_system_information;
};


desc "Show uptime";
task "uptime", sub {
  my $output = run "uptime";
  say $output;
};


desc "Reboot router";
task "reboot", sub {
  say "Rebooting, reboot command has sent...";
  run "reboot";
};


desc "Show installed packages";
task "list_installed", sub {
  #my $output = run "opkg list-installed";
  #say $output;
  for (installed_packages()) {
    say $_->{"name"}.", version: ".$_->{"version"};
  }
};


# rex -H remotehost UtilRex:ping --host=pinghost --count=1 ###--size=56
desc "Ping from remote host (linux only)";
task "ping", sub {
  my $p = shift;
  my %args = (count => 1, size => 56);
  for (qw(host count size)) {
    $args{$_} = $p->{$_} if defined $p->{$_};
  }
  $args{host} = $args{hostname} if defined $args{hostname};
  die "You must provide a hostname" unless defined $args{host};
  run "ping -c $args{count} $args{host} 1>/dev/null 2>/dev/null", timeout => 100;
  #say "ping result: $?";
  return 1 if $? == 0;
  return 0;
};


1;

=pod

=head1 NAME

$::module_name - {{ SHORT DESCRIPTION }}

=head1 DESCRIPTION

{{ LONG DESCRIPTION }}

=head1 USAGE

{{ USAGE DESCRIPTION }}

 include qw/UtilRex/;

 task yourtask => sub {
    UtilRex::example();
 };

=head1 TASKS

=over 4

=item example

This is an example Task. This task just output's the uptime of the system.

=back

=cut
