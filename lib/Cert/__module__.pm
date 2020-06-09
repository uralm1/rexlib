package Cert;

use Rex -feature => ['1.3'];
use Data::Dumper;

# rex Cert:install --cert=/tmp/testcert.pem --key=/tmp/testkey.pem
desc "Install ssl cert/key to /etc/ssl and restart web-servers";
task install => sub {
  my $params = shift;
  my $certfile = $params->{cert};
  my $keyfile = $params->{key};
  die "Certificate file name is required!" unless $certfile;
  die "Private key file name is required!" unless $keyfile;

  unless (is_dir("/etc/ssl") && is_dir("/etc/ssl/certs") && is_dir("/etc/ssl/private")) {
    die "/etc/ssl directories are not found. Probably this is not OpenSSL system";
  }

  file "/etc/ssl/certs/uwc.ufanet.ru.pem",
    source => $certfile,
    mode => 644,
    on_change => sub {
      say "Certificate is installed to /etc/ssl.";
    };

  file "/etc/ssl/private/uwc.ufanet.ru-key.pem",
    source => $keyfile,
    mode => 640,
    on_change => sub {
      say "Private key is installed to /etc/ssl.";
    };

  # try to reload apache
  my $actl;
  unless ($actl = can_run("apachectl")) {
    # hack for Slackware
    $actl = can_run("/usr/local/apache2/bin/apachectl");
  }
  if ($actl) {
    run "$actl graceful";
    say "Apache graceful reload command sent.";
  } else {
    say "Apache Web server restart failed. Check it manually.";
  }

  say "Warning: On mail server you should restart smtp and imap manually.";

  return 0;
};

1;

=pod

=head1 NAME

$::module_name - {{ SHORT DESCRIPTION }}

=head1 DESCRIPTION

{{ LONG DESCRIPTION }}

=head1 USAGE

{{ USAGE DESCRIPTION }}

 include qw/Cert/;

 task yourtask => sub {
    Cert:example();
 };

=head1 TASKS

=over 4

=item example

This is an example Task. This task just output's the uptime of the system.

=back

=cut
