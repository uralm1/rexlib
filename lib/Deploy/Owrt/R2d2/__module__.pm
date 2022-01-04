package Deploy::Owrt::R2d2;

use Rex -feature=>['1.4'];
use Data::Dumper;

use FindBin;
use Ural::Deploy::ReadDB_Owrt;
use Ural::Deploy::Utils qw(:DEFAULT is_x86);

# Whats already done before for R2d2:
# 1. (Deploy::Owrt::Firewall) Firewall configuration and chains is created in the /etc/firewall.user_r2d2 file.
# 2. (Deploy::Owrt::Firewall) /etc/firewall.user_r2d2 and /var/r2d2/firewall.clients are included to firewall.
# 3. (Deploy::Owrt::Net) /etc/init.d/dnsmasq is patched to set --dhcphostsfile option always. 
# 4. (Deploy::Owrt::Net) dhcphostfile option /etc/r2d2/dhcphosts.clients is added to /etc/config/dhcp.


desc "OWRT routers: Configure r2d2 (install gwsyn)";
# --confhost=host parameter is required
# --initsystem=openwrt(default)/none
task "configure", sub {
  my $parameters = shift;
  my $initsystem = $parameters->{initsystem} // 'openwrt';
  my $ch = $parameters->{confhost};
  my $p = Ural::Deploy::ReadDB_Owrt->read_db($ch);
  check_dev $p;
  
  die "Initsystem $initsystem is not supported, valid choices are: openwrt/none!" unless $initsystem =~ /^(openwrt|none)$/;

  unless (is_x86()) {
    say 'R2d2 is only supported on x86 systems. Cannot continue.';
    return 255;
  }
  say 'R2d2 configuration started for '.$p->get_host.", using $initsystem initsystem.";

  # try to stop services
  if ($initsystem =~ /^openwrt$/) {
    for ('gwsyn', 'gwsyn-worker', 'gwsyn-cron') {
      if (is_file("/etc/init.d/$_")) {
	say "Stopping $_ service.";
	my $output = run "/etc/init.d/$_ stop 2>&1", timeout => 100;
	say $output if $output;
      }
    }
  }

  # install packages
  say "Updating package database.";
  update_package_db;
  say "Installing / updating packages for R2d2.";
  my $tc_package = operating_system_version() < 117 ? 'tc' : 'tc-full';
  for (qq/$tc_package kmod-sched perl make perlbase-extutils perlbase-version
perl-mojolicious perl-ev perl-cpanel-json-xs perl-io-socket-ssl
perl-algorithm-cron/) {
    pkg $_, ensure => latest,
      on_change => sub { say "package $_ was installed." };
  }

  file "/tmp/src",
    ensure => "absent";

  file "/tmp/src",
    owner => "ural",
    group => "root",
    mode => 755,
    ensure => "directory";

  my $SOURCE_TAR = "files/gwsyn-latest.tar.gz";
  my $dest_tar = "/tmp/src/gwsyn.tar.gz";
  my $LJQ_SOURCE_TAR = "files/ljq-latest.tar.gz";
  my $ljq_dest_tar = "/tmp/src/ljq.tar.gz";

  file $dest_tar, source => $SOURCE_TAR;
  file $ljq_dest_tar, source => $LJQ_SOURCE_TAR;

  extract $dest_tar, to => '/tmp/src/';
  extract $ljq_dest_tar, to => '/tmp/src/';

  my @srcdir = grep {is_dir($_)} glob('/tmp/src/gwsyn*');
  die "Can't determine source upload path" unless @srcdir;
  my @ljq_srcdir = grep {is_dir($_)} glob('/tmp/src/ljq*');
  die "Can't determine ljq source upload path" unless @ljq_srcdir;

  say "Installing ljq...";
  my @r = run "perl Makefile.PL", cwd => $ljq_srcdir[0], auto_die => TRUE;
  say $_ for @r;
  @r = run "make install", cwd => $ljq_srcdir[0], auto_die => TRUE;
  say $_ for @r;

  say "Installing gwsyn...";
  @r = run "perl Makefile.PL", cwd => $srcdir[0], auto_die => TRUE;
  say $_ for @r;
  @r = run "make install", cwd => $srcdir[0], auto_die => TRUE;
  say $_ for @r;

  # clean up
  file "/tmp/src",
    ensure => "absent";

  for (qw/make/) {
    pkg $_, ensure => "absent",
      on_change => sub { say "package $_ was removed." };
  }

  # copy keys (3)
  my $h = $p->get_host;
  for ('ca.pem', "$h-cert.pem", "$h-key.pem") {
    file "/etc/r2d2/$_",
      owner => "ural",
      group => "root",
      mode => 644,
      source => "files/$_",
      on_change => sub { say "r2d2 key $_ was installed." };
  }

  # change keys in config
  my $cfg = '/etc/r2d2/gwsyn.conf';
  append_or_amend_line $cfg,
    line => "  local_cert => '/etc/r2d2/$h-cert.pem',",
    regexp => qr{^\s*local_cert},
    on_change => sub { say "config file changed for $h local_cert." };
  append_or_amend_line $cfg,
    line => "  local_key => '/etc/r2d2/$h-key.pem',",
    regexp => qr{^\s*local_key},
    on_change => sub { say "config file changed for $h local_key." };
  append_or_amend_line $cfg,
    line => "  ca => '/etc/r2d2/ca.pem',",
    regexp => qr{^\s*ca\s*=>},
    on_change => sub { say "config file changed for ca." };

  # profile name
  #append_or_amend_line $cfg,
  #  line => "  my_profiles => ['$h'],",
  #  regexp => qr{^\s*my_profiles},
  #  on_change => sub { say "config file changed for my_profiles [$h]." };

  # head url
  die "FATAL ERROR: R2d2 HEAD ip is not set!" unless $p->{r2d2_head_ip};
  append_or_amend_line $cfg,
    line => "  head_url => 'https://$p->{r2d2_head_ip}:2271',",
    regexp => qr{^\s*head_url},
    on_change => sub { say "config file changed for head_url $p->{r2d2_head_ip}." };

  ### install services
  if ($initsystem =~ /^openwrt$/) {
    # copy service scripts
    for ('gwsyn', 'gwsyn-worker', 'gwsyn-cron') {
      file "/etc/init.d/$_",
	owner => "ural",
	group => "root",
	mode => 755,
	source => "files/$_",
	on_change => sub { say "r2d2 service script $_ was installed." };
    }

    # enable services
    for ('gwsyn', 'gwsyn-worker', 'gwsyn-cron') {
      if (is_file("/etc/init.d/$_")) {
	say "Enabling $_ service.";
	my $output = run "/etc/init.d/$_ enable 2>&1", timeout => 100;
	say $output if $output;
      } else {
	die "Fatal: can not find $_ service!\n";
      }
    }
  }

  say 'R2d2 configuration finished for '.$p->get_host;
  say 'Check configuration file /etc/r2d2/gwsyn.conf before starting services!';
};


1;

=pod

=head1 NAME

$::Deploy::Owrt::R2d2 - Install R2d2 gwsyn agent on Owrt router.

=head1 DESCRIPTION

Installs R2d2 gwsyn agent on Owrt router. Latest source tar, keys and config must be
placed in the files directory.

=head1 USAGE

Copy latest gwsyn source tar, keys, certs, config to the files/ directory.

Files that should be placed in the files/ directory:

=over 4

=item gwsyn-latest.tar.gz - source tar

=item ljq-latest.tar.gz - ljq source tar

=item ca.pem - CA SSL certificate

=item <confhost>-cert.pem - host SSL certificate

=item <confhost>-key.pem - host SSL private key

=item gwsyn - startup script for main gwsyn daemon

=item gwsyn-worker - startup script for worker process

=item gwsyn-cron - startup script for cron process

=back

Run the task:

rex -H 192.168.34.1 Deploy::Owrt::R2d2::configure --confhost=gwtest1

rex -H 192.168.34.1 Deploy::Owrt::R2d2::configure --confhost=gwtest1 --initsystem=none|openwrt

=head1 TASKS

=over 4

=item configure --confhost=gwtest1 [--initsystem=none|openwrt]

Install R2d2 gwsyn agent. Agent services can be registered with initsystems selected by
optional B<--initsystem> parameter. Default initsystem is openwrt.

=back

=cut
