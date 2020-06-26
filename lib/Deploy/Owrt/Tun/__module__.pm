package Deploy::Owrt::Tun;

use Rex -feature=>['1.4'];
use Data::Dumper;
use DBI;
use NetAddr::IP::Lite;

use Ural::Deploy::ReadDB_Owrt;
use Ural::Deploy::Utils;

my $def_net = "UWC66";


desc "OWRT routers: Configure tinc tunnel";
# --confhost=host parameter is required
task "configure", sub {
  my $ch = shift->{confhost};
  my $p = read_db($ch);
  check_par_old;

  say 'Tinc tunnel configuration started for '.$p->get_host;

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
  uci "set tinc.\@tinc-net[-1].MaxTimeout=600";
  uci "set tinc.\@tinc-net[-1].Name=\'$p->{tun_node_name}\'";
  uci "add_list tinc.\@tinc-net[-1].ConnectTo=\'$_\'" foreach (@{$p->{tun_connect_nodes}});

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

  file "/etc/tinc/$def_net/tinc-up",
    owner => "ural",
    group => "root",
    mode => 755,
    content => template("files/$def_net/tinc-up.tpl",
      _tun_ip =>$p->{tun_int_ip},
      _tun_netmask=>$p->{tun_int_netmask});
  
  file "/etc/tinc/$def_net/tinc-down",
    owner => "ural",
    group => "root",
    mode => 755,
    content => template("files/$def_net/tinc-down.tpl");
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
    content => $p->{tun_priv_key};
  say "Tinc private key file for $p->{tun_node_name} is saved to rsa_key.priv";

  # generate all hosts files for this node
  sleep 1;
  Deploy::Owrt::Tun::dist_nodes( { confhost => $ch } );

  say 'Tinc tunnel configuration finished for '.$p->get_host;
};


##################################
desc "Tinc net generate keys for node (run on *bikini* host only please)
  rex gen_node --newnode=gwtest1";
task "gen_node", sub {
  my $par = shift;
  my $_host = $par->{newnode};
  my $keysize = 2048;

  my %i = get_system_information;
  #say "Host: $i{hostname}";
  die "This task can be run only on bikini host.\n" unless $i{hostname} =~ /^bikini$/;
  die "Invalid parameters, run as: rex gen_node --newnode=hostname.\n" unless $_host;

  # prepare database
  my $dbh = DBI->connect("DBI:mysql:database=".get(cmdb('dbname')).';host='.get(cmdb('dbhost')), get(cmdb('dbuser')), get(cmdb('dbpass'))) or 
    die "Connection to the database failed.\n";
  $dbh->do("SET NAMES 'UTF8'");

  my ($r_id) = $dbh->selectrow_array("SELECT id FROM routers WHERE host_name = ?", {}, $_host);
  die "There's no such host in the database, or database error.\n" unless $r_id;
  #say $r_id;

  say "Generating keys for node: $_host";
  #unless (is_installed("openssl")) {
  #  say "Openssl is required.";
  #  return 1;
  #}
  my $privkey = run "openssl genrsa $keysize", auto_die=>1;
  #say $privkey;
  say "Private key generated.";
  my $pubkey = run "openssl rsa -pubout -outform PEM << EOF123EOF\n$privkey\nEOF123EOF\n", auto_die=>1;
  #say $pubkey;
  say "Public key generated.";

  # save keys to database
  my $rows = $dbh->do("UPDATE vpns SET pub_key=?, priv_key=? WHERE router_id = ?", {}, $pubkey, $privkey, $r_id);
  die "Can't save keys to database.\n".$dbh->errstr."\n" unless $rows;

  $dbh->disconnect;
  say "Keys were successfully written to database.";
};


desc "Distribute tinc net hosts files to host (works on erebus too)";
# --confhost=host parameter is required
task "dist_nodes", sub {
  my $params = shift;
  my $ch = $params->{confhost};
  my $p = read_db($ch, skip_erebus_check=>1);

  say 'Tinc hostfiles distribution started for '.$p->get_host;

  file "/etc/tinc/$def_net/hosts",
    owner => "ural",
    group => "root",
    mode => 755,
    ensure => "directory";

  # build host files for all nodes in database
  my $dbh = DBI->connect("DBI:mysql:database=".get(cmdb('dbname')).';host='.get(cmdb('dbhost')), get(cmdb('dbuser')), get(cmdb('dbpass'))) or 
    die "Connection to the database failed.\n";
  $dbh->do("SET NAMES 'UTF8'");

  my $s = $dbh->prepare("SELECT \
routers.host_name AS tun_node_name, \
ifs.ip AS tun_node_ip, \
nets.net_ip AS tun_subnet_ip, \
nets.mask AS tun_subnet_mask, \
pub_key AS tun_pub_key \
FROM vpns \
INNER JOIN routers ON routers.id = router_id \
INNER JOIN nets ON nets.id = subnet_id \
INNER JOIN interfaces ifs ON ifs.id = node_if_id") or die $dbh->errstr;
  $s->execute or die $s->errstr;
  my @hosts_files;
  while (my $hr = $s->fetchrow_hashref) {
    #say Dumper $hr;

    unless ($hr->{tun_pub_key} && $hr->{tun_subnet_ip} && $hr->{tun_subnet_mask} && $hr->{tun_node_ip}) {
      say "Host file for node $hr->{tun_node_name} is not generated due incorrect configuration:";
      say "- No public key in database. Generate keys for this host and run distribution again." unless ($hr->{tun_pub_key});
      say "- No vpn subnet ip/mask in database. Check configuration." unless ($hr->{tun_subnet_ip} && $hr->{tun_subnet_mask});
      say "- No vpn ip in database. Check configuration." unless ($hr->{tun_node_ip});
      next;
    }

    my $net = NetAddr::IP::Lite->new($hr->{tun_subnet_ip}, $hr->{tun_subnet_mask}) or
      die("Invalid vpn subnet address or mask!\n");

    # now generate tinc host file with public key
    file "/etc/tinc/$def_net/hosts/$hr->{tun_node_name}",
      owner => "ural",
      group => "root",
      mode => 644,
      content => template("files/$def_net/hostfile.tpl",
	_address=>$hr->{tun_node_ip},
	_subnet=>$net->cidr,
        _pubkey=>$hr->{tun_pub_key});
    push @hosts_files, $hr->{tun_node_name};
    say "Host file for $hr->{tun_node_name} is generated.";
  }
  $dbh->disconnect;

  # check for hosts in connection list exist
  my @_con_list = @{$p->{tun_connect_nodes}};
  push @_con_list, $p->{tun_node_name}; # current host must be in list too
  foreach my $h (@_con_list) {
    my $f = 0;
    foreach (@hosts_files) {
      if ($h eq $_) { $f = 1; last; }
    }
    say "WARNING! Host $h is in tinc connection list, but not distributed." unless ($f);
  }

  say 'Tinc hostfiles distribution finished for '.$p->get_host;
};


##################################
desc "Reload tinc daemon (useful after updating net hosts files, works on erebus too)";
task "reload", sub {
  my $pf = "/var/run/tinc.$def_net.pid";
  if (is_readable($pf)) {
    say "Reloading tinc daemon on host ".connection->server." ...";
    run "kill -HUP `cat $pf`";
    say "HUP signal is sent.";
  } else {
    say "Pid file $pf wasn't found. May be wrong host, or tinc is not running.";
  }
};


1;

=pod

=head1 NAME

$::module_name - {{ SHORT DESCRIPTION }}

=head1 DESCRIPTION

{{ LONG DESCRIPTION }}

=head1 USAGE

{{ USAGE DESCRIPTION }}

 include qw/Deploy::Owrt::Tun/;

 task yourtask => sub {
    Deploy::Owrt::Tun::example();
 };

=head1 TASKS

=over 4

=item example

This is an example Task. This task just output's the uptime of the system.

=back

=cut
