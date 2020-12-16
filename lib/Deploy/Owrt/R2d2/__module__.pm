package Deploy::Owrt::R2d2;

use Rex -feature=>['1.4'];
use Data::Dumper;

use Ural::Deploy::ReadDB_Owrt;
use Ural::Deploy::Utils qw(:DEFAULT is_x86);


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

  # patch /etc/init.d/dnsmasq to set --dhcphostsfile option always
  sed qr{\[\s+-e\s+\"\$hostsfile\"\s+\]\s+&&\s+xappend},
    'xappend',
    '/etc/init.d/dnsmasq',
    on_change => sub {
      say '/etc/init.d/dnsmasq: dhcphostsfile processing is patched.';
    };

  # add dhcphostfile option to /etc/config/dhcp
  uci "revert dhcp";
  uci "set dhcp.\@dnsmasq[0].dhcphostsfile=\'/var/r2d2/dhcphosts.clients\'";
  #uci "show dhcp";
  uci "commit dhcp";
  say "/etc/config/dhcp is modified.";

  #for (qw/perl perlbase-encode perlbase-findbin perl-dbi perl-dbd-mysql perl-netaddr-ip perl-sys-runalone libmariadb/) {
  #  pkg $_, ensure => "present";
  #}

  #file "/etc/r2d2",
  #  owner => "ural",
  #  group => "root",
  #  mode => 755,
  #  ensure => "directory";

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
