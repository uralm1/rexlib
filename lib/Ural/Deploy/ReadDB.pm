package Ural::Deploy::ReadDB;

use strict;
use warnings;
use v5.12;
#use utf8;

use Carp;
use Ural::Deploy::ReadDB_base;

use Exporter qw(import);
our @EXPORT = qw(ReadDB);

my %params_cache;

# my $hostparam = ReadDB('testhost1', [format_ver => 1, no_cache => 1]);
sub ReadDB {
  my ($host, %args) = @_;

  croak 'host parameter required' unless $host;
  my $v = 0;
  $v = $args{format_ver} if defined $args{format_ver};

  if ($args{no_cache}) {
    say "Ignore cache due no_cache flag";
    return _read_uncached($host, $v);
  }
  if (exists $params_cache{$host}) {
    my $p = $params_cache{$host};
    if ($p->get_host ne $host or $p->get_version ne $v) {
      say "Ignore cache due host or version differences";
      return _read_uncached($host, $v);
    }
    say "Use CACHED!";
    return $params_cache{$host};
  }
  return _read_uncached($host, $v);
}

sub _read_uncached {
  my ($host, $format_ver) = @_;
  
  say "Reading uncached: $host, $format_ver";
  my $p;
  if ($format_ver eq '999') {
    $p = Ural::Deploy::ReadDB_base->new()->read($host);
  } elsif ($format_ver eq '1') {
    #
    croak "FIXME Unsupported format: $format_ver.\n";
  } elsif ($format_ver eq '0') {
    #
    croak "FIXME Unsupported format: $format_ver.\n";
  } else {
    croak "Unsupported format: $format_ver.\n";
  }
  $params_cache{$host} = $p;
  return $p;
}

1;
