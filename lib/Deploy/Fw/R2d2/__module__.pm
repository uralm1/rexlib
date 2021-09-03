package Deploy::Fw::R2d2;

use Rex -feature=>['1.4'];
use Data::Dumper;

# Whats already done before for R2d2 on Fw:
# Manually tuned -
# 1. /etc/rc.d/rc.firewall: in the middle /var/r2d2/firewall.clients file is restored with iptables-restore (if exists).
# 2. /etc/rc.d/rc.traf: at the end /var/r2d2/traf.clients is sourced if file exists, EXTR_IF/INTR_IF variables are defined.
# 3. runit service supervisor is installed and activated

desc "Fw firewall: Configure r2d2 (install fwsyn)";
# --initsystem=runit(default)/sysvinit/systemd/none
task "configure", sub {
  my $initsystem = shift->{initsystem} // 'runit';

  die "Initsystem $initsystem is not supported, valid choices are: runit/sysvinit/systemd/none!" unless $initsystem =~ /^(runit|sysvinit|systemd|none)$/;
  die "Systemd initsystem support is not implemented yet, sorry." if $initsystem =~ /^systemd$/;

  say 'R2d2 fwsyn configuration started for '.connection->server.", using $initsystem initsystem.";

  # we only support old slackware
  my $svf = '/etc/slackware-version';
  die "Your system is unsupported!" unless is_readable($svf);
  my $sv = cat $svf;
  die "Your slackware system is unsupported too!" unless $sv =~ /^Slackware/;

  # check runit is installed
  if ($initsystem =~ /^runit$/) {
    for (qw#runsvdir runsv sv#) {
      die "There is no runit supervisor installed!" unless is_file("/usr/bin/$_");
    }
    for (qw#/etc/runit /service#) {
      die "There is no runit supervisor control directories found!" unless is_dir($_);
    }
    die "runit sv utility can\'t be run!" unless can_run('sv');
  }

  # try to stop services
  if ($initsystem =~ /^sysvinit$/) {
    if (is_file("/etc/rc.d/rc.fwsyn")) {
      say "Stopping fwsyn service.";
      my $output = run "/etc/rc.d/rc.fwsyn stop 2>&1", timeout => 100;
      say $output if $output;
    }

  } elsif ($initsystem =~ /^runit$/) {
    for my $service (qw#fwsyn-worker fwsyn-cron fwsyn#) {
      if (is_symlink("/service/$service")) {
        say "Stopping $service service.";
	my $output = run "sv stop $service", timeout => 100;
	say $output if $output;
	say "Ret code: $?";
	if ($?) {
          # some workarounds for fwsyn-cron service
          $output = run "sv term $service", timeout => 100;
          say $output if $output;
	}
      }
    }

  }

  say "\nInstall dependences prior starting this task!";
  say "Unsatisfied dependences will be reported during makefile creation.\n";

  file "/tmp/src",
    ensure => "absent";

  file "/tmp/src",
    owner => "ural",
    group => "root",
    mode => 755,
    ensure => "directory";

  my $SOURCE_TAR = "files/fwsyn-latest.tar.gz";
  my $dest_tar = "/tmp/src/fwsyn.tar.gz";
  my $LJQ_SOURCE_TAR = "files/ljq-latest.tar.gz";
  my $ljq_dest_tar = "/tmp/src/ljq.tar.gz";

  file $dest_tar, source => $SOURCE_TAR;
  file $ljq_dest_tar, source => $LJQ_SOURCE_TAR;

  extract $dest_tar, to => '/tmp/src/';
  extract $ljq_dest_tar, to => '/tmp/src/';

  my @srcdir = grep {is_dir($_)} glob('/tmp/src/fwsyn*');
  die "Can't determine source upload path" unless @srcdir;
  my @ljq_srcdir = grep {is_dir($_)} glob('/tmp/src/ljq*');
  die "Can't determine ljq source upload path" unless @ljq_srcdir;

  say "Installing ljq...";
  my @r = run "perl Makefile.PL", cwd => $ljq_srcdir[0], auto_die => TRUE;
  say $_ for @r;
  @r = run "make install", cwd => $ljq_srcdir[0], auto_die => TRUE;
  say $_ for @r;

  say "Installing fwsyn...";
  @r = run "perl Makefile.PL", cwd => $srcdir[0], auto_die => TRUE;
  say $_ for @r;
  @r = run "make install", cwd => $srcdir[0], auto_die => TRUE;
  say $_ for @r;

  # clean up
  file "/tmp/src",
    ensure => "absent";

  # copy keys (3)
  for ('ca.pem', 'fw-cert.pem', 'fw-key.pem') {
    file "/etc/r2d2/$_",
      owner => "ural",
      group => "root",
      mode => 644,
      source => "files/$_",
      on_change => sub { say "r2d2 key $_ was installed." };
  }

  # change keys in config
  my $cfg = '/etc/r2d2/fwsyn.conf';
  append_or_amend_line $cfg,
    line => "  local_cert => '/etc/r2d2/fw-cert.pem',",
    regexp => qr{^\s*local_cert},
    on_change => sub { say "config file changed for fw local_cert." };
  append_or_amend_line $cfg,
    line => "  local_key => '/etc/r2d2/fw-key.pem',",
    regexp => qr{^\s*local_key},
    on_change => sub { say "config file changed for fw local_key." };
  append_or_amend_line $cfg,
    line => "  ca => '/etc/r2d2/ca.pem',",
    regexp => qr{^\s*ca\s*=>},
    on_change => sub { say "config file changed for ca." };

  # head url
  #die "FATAL ERROR: R2d2 HEAD ip is not set!" unless $p->{r2d2_head_ip};
  append_or_amend_line $cfg,
    line => "  head_url => 'https://10.14.72.5:2271',",
    regexp => qr{^\s*head_url},
    on_change => sub { say "config file changed for head_url 10.14.72.5." };


  ### configure services
  if ($initsystem =~ /^sysvinit$/) {
    # copy service scripts
    for ('rc.fwsyn') {
      file "/etc/rc.d/$_",
	owner => "root",
	group => "root",
	mode => 755,
	source => "files/$_",
	on_change => sub { say "r2d2 service script $_ was installed." };
    }

    # copy logrotate config
    file "/etc/logrotate.d/fwsyn",
      owner => "root",
      group => "root",
      mode => 644,
      source => "files/fwsyn.logrotate",
      on_change => sub { say "r2d2 fwsyn logrotate file was installed." };

    # enable services
    append_or_amend_line '/etc/rc.d/rc.local',
      line => "[ -x /etc/rc.d/rc.fwsyn ] && /etc/rc.d/rc.fwsyn start",
      regexp => qr{^.*rc\.fwsyn start},
      on_change => sub { say "rc.fwsyn start code is added to rc.local." };

    append_or_amend_line '/etc/rc.d/rc.local_shutdown',
      line => "[ -x /etc/rc.d/rc.fwsyn ] && /etc/rc.d/rc.fwsyn stop",
      regexp => qr{^.*rc\.fwsyn stop},
      on_change => sub { say "rc.fwsyn stop code is added to rc.local_shutdown." };

  } elsif ($initsystem =~ /^runit$/) {

    my $runit_dir = '/etc/runit';
    my $r2d2_dir = '/etc/r2d2';

    for my $service (qw#fwsyn-worker fwsyn-cron fwsyn#) {
      say "Installing $service service.";
      file "$runit_dir/$service", ensure => 'directory', owner => 'root', group => 'root';
      file "$runit_dir/$service/log", ensure => 'directory', owner => 'root', group => 'root';

      file "$runit_dir/$service/run",
        owner => 'root',
	group => 'root',
	mode => 755,
	source => "files/runit_${service}_run",
	on_change => sub { say "Service $service run script installed." };

      file "$runit_dir/$service/log/run",
        owner => 'root',
	group => 'root',
	mode => 755,
	content => template("files/runit_log_run.tpl", log_dir => "$service.log"),
	on_change => sub { say "Service $service log script installed." };

      file "$r2d2_dir/$service.log", ensure => 'directory', owner => 'root', group => 'root';

      file "$r2d2_dir/$service.log/config",
        owner => 'root',
	group => 'root',
	mode => 644,
	source => "files/runit_log_config",
	on_change => sub { say "Service $service log config installed." };

      say "Registering $service service.";
      symlink("$runit_dir/$service", "/service/$service");
    }
  }

  say 'R2d2 configuration finished for '.connection->server;
  say 'Check configuration file /etc/r2d2/fwsyn.conf before starting services!';
};


1;

=pod

=head1 NAME

$::Deploy::Fw::R2d2 - Install R2d2 fwsyn agent on Fw firewall.

=head1 DESCRIPTION

Installs R2d2 fwsyn agent on Fw firewall. Latest source tar, keys and config must be
placed in the files directory.

=head1 USAGE

<copy latest fwsyn source tar, keys, certs, config to the files/ directory>

rex -u root -H 10.15.0.1 Deploy::Fw::R2d2::configure

rex -u root -H 10.15.0.1 Deploy::Fw::R2d2::configure --initsystem=none|sysvinit|runit|systemd

=head1 TASKS

=over 4

=item configure [--initsystem=none|sysvinit|runit|systemd]

Installs R2d2 fwsyn agent. Agent services can be registered with initsystems selected by
optional B<--initsystem> parameter. Default initsystem is runit.

=back

=cut
