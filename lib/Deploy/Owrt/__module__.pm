package Deploy::Owrt;

use Rex -feature=>['1.3'];
use Data::Dumper;

use Ural::Deploy::ReadDB_Owrt;
use Ural::Deploy::Utils qw(:DEFAULT is_x86);


### Pre-installaion tasks for images
desc "Install perl for Rex, for images<1.9";
task "install_perl", sub {
  my $output = run "opkg install perl perlbase-bytes perlbase-data perlbase-digest perlbase essential perlbase-file perlbase-xsloader";
  say $output;
}, {dont_register => TRUE};

desc "Create openwrt_release, openwrt_version for Rex, for images<1.10";
task "fix_openwrt_detect", sub {
  my $output = run "touch /etc/openwrt_release /etc/openwrt_version";
  say $output;
}, {dont_register => TRUE};


desc "x86 primary configuration: enable login, disable startup failsafe prompt";
task "x86_preconf", sub {
  die "Unsupported operating system!\n" unless operating_system_is('OpenWrt');
  my $os_ver = operating_system_version();
  die "Unsupported firmware version!\n" if ($os_ver < 113 || $os_ver > 113);
  die "Unsupported system architecture!\n" unless is_x86();

  say "Primary x86 configuration started...";
  # enable login on consoles
  say "Activating login on consoles.";
  # check /bin/login
  die "Fatal error: /bin/login is not compiled.\n" unless (is_file("/bin/login"));
  # fix inittab
  sed qr/::askfirst:\/bin\/ash +--login$/, '::askfirst:/bin/login', '/etc/inittab';

  # disable failsafe mode prompt
  say "Disabling failsafe mode prompts.";
  file "/lib/preinit/30_failsafe_wait", ensure=>'absent';
  file "/lib/preinit/99_10_failsafe_login", ensure=>'absent';

  say "Primary x86 configuration finished. Reboot router to apply settings.";
}, {dont_register => TRUE};


##################################
desc "OWRT routers: Show router information";
task "show_router", sub {
  #dump_system_information;
  my %i = get_system_information;
  #say Dumper \%i;
  say "This is: $i{hostname}, $i{operating_system} system (arch: $i{architecture}), version: $i{operating_system_release}.";
  if (operating_system_is('OpenWrt')) {
    my $r = run "uci get system.\@system[0].hostname";
    say "Hostname configured as: $r, actual: $i{hostname}.";
  }
  my $r = run "uptime";
  say "Host up time is: $r.";
  say "Memory total/free/used: $i{memory_total}/$i{memory_free}/$i{memory_used}.";
  say "Network interfaces:";
  my $net_info = $i{Network}->{networkconfiguration};
  for my $dev (keys %$net_info) {
    say " $dev ip: ".$net_info->{$dev}->{ip}." netmask: ".$net_info->{$dev}->{netmask};
  }
};


#
### Configuration
#
desc "OWRT routers: DEPLOY ROUTER
  rex -H 10.0.1.1 deploy_router --confhost=gwtest1";
task "deploy_router", sub {
  my $ch = shift->{confhost};
  my $p = read_db($ch);
  check_par_old;

  say 'Router deployment/OpenWRT/ started for '.$p->get_host;
  say "Router manufacturer from database: $p->{manufacturer}" if $p->{manufacturer};
  say "Router type from database: $p->{eq_name}" if $p->{eq_name};
  say "Department: $p->{dept_name}\n" if $p->{dept_name};
  # confhost parameter is required
  Deploy::Owrt::System::configure( { confhost => $ch } );
  sleep 1;
  Deploy::Owrt::Net::configure( { confhost => $ch } );
  sleep 1;
  Deploy::Owrt::Firewall::configure( { confhost => $ch } );
  sleep 1;
  Deploy::Owrt::Tun::configure( { confhost => $ch } );
  say 'Router deployment/OpenWRT/ finished for '.$p->get_host;
  say "!!! Reboot router manually to apply changes !!!";
};


##################################
task "_t", sub {
  my $p = read_db 'gwsouth2';
  #my $p = read_db 'gwtest1';
  check_par_old;
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

 include qw/Deploy::Owrt/;

 task yourtask => sub {
    Deploy::Owrt::example();
 };

=head1 TASKS

=over 4

=item example

This is an example Task. This task just output's the uptime of the system.

=back

=cut
