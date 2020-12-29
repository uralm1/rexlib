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
# 4. (Deploy::Owrt::Net) dhcphostfile option /var/r2d2/dhcphosts.clients is added to /etc/config/dhcp.


desc "OWRT routers: Configure r2d2";
# --confhost=host parameter is required
task "configure", sub {
  my $ch = shift->{confhost};
  my $p = read_db($ch);
  check_par_old;
  
  unless (is_x86()) {
    say 'R2d2 is only supported on x86 systems. Cannot continue.';
    return 255;
  }
  say 'R2d2 configuration started for '.$p->get_host;

  # install packages
  say "Updating package database.";
  update_package_db;
  say "Installing / updating packages for R2d2.";
  for (qw/tc kmod-sched perl make perlbase-extutils perlbase-version
    perl-mojolicious perl-ev perl-cpanel-json-xs perl-io-socket-ssl
    perl-mojo-sqlite perl-sql-abstract
    perl-minion perl-minion-backend-sqlite/) {
    pkg $_, ensure => latest,
      on_change => sub { say "package $_ was installed." };
  }

  file "/etc/r2d2",
    ensure => "absent";

  file "/tmp/src",
    ensure => "absent";

  file "/tmp/src",
    owner => "ural",
    group => "root",
    mode => 755,
    ensure => "directory";

  my $SOURCE_TAR = "files/gwsyn-latest.tar.gz";
  my $dest_tar = "/tmp/src/gwsyn.tar.gz";
  file $dest_tar,
    owner => "ural",
    group => "root",
    mode => 644,
    source => $SOURCE_TAR;

  extract $dest_tar,
    to => '/tmp/src/';

  my @srcdir = grep {is_dir($_)} glob('/tmp/src/*');
  die "Can't determine source upload path" unless @srcdir;
  my @r = run "perl Makefile.PL", cwd => $srcdir[0], auto_die => TRUE;
  say $_ for @r;
  @r = run "make install", cwd => $srcdir[0], auto_die => TRUE;
  say $_ for @r;

  # clean up
  file "/tmp/src",
    ensure => "absent";

  for (qw/make/) {
    pkg $_, ensure => absent,
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
    line => "  local_cert => '$h-cert.pem',",
    regexp => qr{^\s*local_cert},
    on_change => sub { say "config file changed for $h local_cert." };
  append_or_amend_line $cfg,
    line => "  local_key => '$h-key.pem',",
    regexp => qr{^\s*local_key},
    on_change => sub { say "config file changed for $h local_key." };
  append_or_amend_line $cfg,
    line => "  ca => 'ca.pem',",
    regexp => qr{^\s*ca\s*=>},
    on_change => sub { say "config file changed for ca." };

  # head url
  append_or_amend_line $cfg,
    line => "  head_url => 'https://10.2.13.130:2271',",
    regexp => qr{^\s*head_url},
    on_change => sub { say "config file changed for head_url." };

  # copy service scripts
  for ('gwsyn', 'gwsyn-minion', 'gwsyn-cron') {
    file "/etc/init.d/$_",
      owner => "ural",
      group => "root",
      mode => 755,
      source => "files/$_",
      on_change => sub { say "r2d2 service script $_ was installed." };
  }
  # TODO enable services

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

 include qw/Deploy::Owrt::R2d2/;

 task yourtask => sub {
    Deploy::Owrt::R2d2::example();
 };

=head1 TASKS

=over 4

=item example

This is an example Task. This task just output's the uptime of the system.

=back

=cut
