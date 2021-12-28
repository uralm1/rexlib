package Deploy::Erebus::Ipsec;

use Rex -feature=>['1.4'];
#use Data::Dumper;

use Ural::Deploy::ReadDB_Erebus;
use Ural::Deploy::Utils;


desc "Erebus router: Configure IPsec";
# --confhost=erebus is required
task "configure", sub {
  my $ch = shift->{confhost};
  my $p = read_db($ch);
  check_dev_erebus;

  say 'IPsec configuration started for '.$p->get_host;

  pkg "strongswan-default", ensure => "present";

  # strongswan init
  file '/etc/init.d/ipsec',
    owner => "ural",
    group => "root",
    mode => 755,
    source => "files/ipsec.init",
    on_change => sub { say "Strongswan init file created." };
  
  # strongswan config
  my $ipsec_file = '/etc/config/ipsec';
  file $ipsec_file,
    owner => "ural",
    group => "root",
    mode => 644,
    content => template('files/ipsec.0.tpl'),
    on_change => sub { say "/etc/config/ipsec created." };

  my $h = $p->{hacks}{strongswan_config};
  append_if_no_such_line($ipsec_file,
    line => $h,
    on_change => sub {
      say "Hack strongswan_config was added to /etc/config/ipsec.";
    }
  ) if $h;

  say 'IPsec configuration finished for '.$p->get_host;
};


##################################
desc "Erebus router: restart ipsec";
task "restart", sub {
  say "Restarting strongswan on host ".connection->server." ...";
  #service ipsec => 'restart';
  my $output = run "/etc/init.d/ipsec restart 2>&1", timeout => 100;
  say $output if $output;
  return (($? > 0) ? 255:0);
};

desc "Erebus router: reload ipsec (useful after updating strongswan_config hack)";
task "reload", sub {
  say "Reloading strongswan configuration on host ".connection->server." ...";
  #service ipsec => 'reload';
  my $output = run "/etc/init.d/ipsec reload 2>&1", timeout => 100;
  say $output if $output;
  return (($? > 0) ? 255:0);
};


1;

=pod

=head1 NAME

$::module_name - {{ SHORT DESCRIPTION }}

=head1 DESCRIPTION

{{ LONG DESCRIPTION }}

=head1 USAGE

{{ USAGE DESCRIPTION }}

 include qw/Deploy::Erebus::Ipsec/;

 task yourtask => sub {
    Deploy::Erebus::Ipsec::example();
 };

=head1 TASKS

=over 4

=item example

This is an example Task. This task just output's the uptime of the system.

=back

=cut
