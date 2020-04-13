use Rex -feature => [qw(disable_strict_host_key_checking)];
use Rex::CMDB;

use Data::Dumper;

# requires should be before cmdb
require UtilSSH;
require UtilRex;
require Deploy::Owrt;
require Deploy::Virt;
require Check;
require Virt;
require Cert;

set cmdb => {
  type => 'YAML',
  path => ['cmdb/config.yml'],
};

# for Net::OpenSSH
user get cmdb('user');
#password get cmdb('password');
key_auth;

# use Net::SSH2 instead openssh
#set connection => "SSH";
private_key get cmdb('private_key');
public_key get cmdb('public_key');


desc "Test run";
task "testrun", sub {
  #my $r = run_task "UtilRex:ping", params => {host=>"10.2.78.74"}, on=>"erebus";
  #if ($r) { say "Ping is true, $r"; } else { say "Ping is false, $r"; }
  say Dumper \get cmdb;
};

desc "Long job";
task "longjob", sub {
  say run "date";
  for (1..10) {
    say $_; sleep 1;
  }
  say run "date";
};

#before testrun => sub {
#  my ($server, $server_ref, $cli_args) = @_;
#  say "before testrun on $server.";
#  say Dumper $cli_args;
#  user "root";
#};

# vim:ft=perl

