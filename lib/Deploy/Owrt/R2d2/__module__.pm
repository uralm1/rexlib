package Deploy::Owrt::R2d2;

use Rex -feature=>['1.4'];
use Data::Dumper;

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
