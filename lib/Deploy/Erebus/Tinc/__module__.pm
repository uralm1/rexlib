package Deploy::Erebus::Tinc;

use Rex -feature=>['1.4'];
#use Data::Dumper;
use NetAddr::IP::Lite;

use Ural::Deploy::ReadDB_Erebus;
use Ural::Deploy::Utils;

my $def_net = 'UWC66';


desc "Erebus router: Configure tinc";
# --confhost=erebus is required
task "configure", sub {
  my $ch = shift->{confhost};
  my $p = read_db($ch);
  check_par;

  say 'Tinc configuration started for '.$p->get_host;

  pkg "tinc", ensure => "present";

  file "/etc/config/tinc",
    owner => "ural",
    group => "root",
    mode => 644,
    content => template("files/tinc.0.tpl");
  quci "revert tinc";

  uci "set tinc.$def_net=tinc-net";
  uci "set tinc.\@tinc-net[-1].enabled=1";
  uci "set tinc.\@tinc-net[-1].debug=2";
  uci "set tinc.\@tinc-net[-1].AddressFamily=ipv4";
  uci "set tinc.\@tinc-net[-1].Interface=vpn1";
  uci "set tinc.\@tinc-net[-1].BindToAddress=\'$p->{tun_node_ip}\'";
  uci "set tinc.\@tinc-net[-1].MaxTimeout=600";
  uci "set tinc.\@tinc-net[-1].Name=\'$p->{tun_node_name}\'";
  uci "add_list tinc.\@tinc-net[-1].ConnectTo=\'$_\'" for (@{$p->{tun_connect_nodes}});

  uci "set tinc.$p->{tun_node_name}=tinc-host";
  uci "set tinc.\@tinc-host[-1].enabled=1";
  uci "set tinc.\@tinc-host[-1].net=\'$def_net\'";
  uci "set tinc.\@tinc-host[-1].Cipher=blowfish";
  uci "set tinc.\@tinc-host[-1].Compression=0";
  uci "add_list tinc.\@tinc-host[-1].Address=\'$p->{tun_node_ip}\'";
  uci "set tinc.\@tinc-host[-1].Subnet=\'$p->{tun_subnet}\'";

  #uci "show tinc";
  uci "commit tinc";
  insert_autogen_comment '/etc/config/tinc';
  say "File /etc/config/tinc configured.";

  # configure tinc scripts
  file "/etc/tinc/$def_net",
    owner => "ural",
    group => "root",
    mode => 755,
    ensure => "directory";

  my $int_addr = NetAddr::IP::Lite->new($p->{tun_int_ip}, $p->{tun_int_netmask}) or
    die "Invalid vpn tunnel interface address or mask!\n";
  file "/etc/tinc/$def_net/tinc-up",
    owner => "ural",
    group => "root",
    mode => 755,
    content => template("files/$def_net/tinc-up.tpl",
      _tun_ip =>$int_addr->addr,
      _tun_netmask=>$int_addr->mask,
      _tun_route_addr=>$int_addr->network->cidr,
    );
  
  file "/etc/tinc/$def_net/tinc-down",
    owner => "ural",
    group => "root",
    mode => 755,
    content => template("files/$def_net/tinc-down.tpl",
      _tun_route_addr=>$int_addr->network->cidr,
    );
  say "Scripts tinc-up/tinc-down are created.";

  unless ($p->{tun_pub_key} && $p->{tun_priv_key}) {
    say "No keypair found in the database, running gen_node for $p->{tun_node_name}...";
    run_task "Deploy:Owrt:Tun:gen_node", params=>{newnode=>$p->{tun_node_name}};
  } else {
    say "Keypair for $p->{tun_node_name} from the database is used.";
  }
    
  # configure tinc keys
  file "/etc/tinc/$def_net/rsa_key.priv",
    owner => "ural",
    group => "root",
    mode => 600,
    content => $p->{tun_priv_key},
    on_change => sub {
      say "Tinc private key file for $p->{tun_node_name} is saved to rsa_key.priv";
    };

  # generate all hosts files for this (=erebus) node
  sleep 1;
  Deploy::Owrt::Tun::dist_nodes( { confhost => $ch } );

  say 'Tinc configuration finished for '.$p->get_host;
};


1;

=pod

=head1 NAME

$::module_name - {{ SHORT DESCRIPTION }}

=head1 DESCRIPTION

{{ LONG DESCRIPTION }}

=head1 USAGE

{{ USAGE DESCRIPTION }}

 include qw/Deploy::Erebus::Tinc/;

 task yourtask => sub {
    Deploy::Erebus::Tinc::example();
 };

=head1 TASKS

=over 4

=item example

This is an example Task. This task just output's the uptime of the system.

=back

=cut
