use Rex -feature => [qw(disable_strict_host_key_checking)];
use Data::Dumper;


# for Net::OpenSSH
user "ural";
#password "";
key_auth;

# use Net::SSH2 instead openssh
#set connection => "SSH";
private_key "/opt/rundeck/var/storage/content/keys/globkey";
public_key "/opt/rundeck/var/storage/content/keys/globkey_pub";

# database parameters
set dbhost => 'server';
set dbname => 'database';
set dbuser => 'user';
set dbpass => 'pass';

# mailing parameters
set mail_smtp => 'mail.uwc.ufanet.ru';
set mail_from => 'ural@uwc.ufanet.ru';

require UtilSSH;
require UtilRex;
require Deploy::Owrt;
require Deploy::Virt;
require Check;
require Virt;
require Cert;

desc "Test run";
task "testrun", sub {
  my $r = run_task "UtilRex:ping", params => {host=>"10.2.78.74"}, on=>"erebus";
  if ($r) { say "Ping is true, $r"; } else { say "Ping is false, $r"; }
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

