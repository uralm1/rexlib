package Ural::Deploy::ReadDB_base;

use strict;
use warnings;
use v5.12;
#use utf8;

use Carp;
use Data::Dumper;
use Ural::Deploy::HostParam;

my %params_cache;

# my $o = Ural::Deploy::ReadDB_base->new();
sub new {
  return bless {
    result_type => 'Ural::Deploy::HostParam'
  }, shift;
}


# my $hostparam = $o->read('testhost1', [no_cache => 1]);
sub read {
  my ($self, $host, %args) = @_;
  croak 'host parameter required' unless $host;

  if ($args{no_cache}) {
    #say "Ignore cache due no_cache flag";
    return $self->_read_uncached($host);
  }
  if (exists $params_cache{$host}) {
    my $p = $params_cache{$host};
    if ($p->get_host ne $host or ref($p) ne $self->{result_type}) {
      #say "Ignore cache due host or version differences";
      return $self->_read_uncached($host);
    }
    #say "Use CACHED!";
    $p->{cached} = 1;
    return $p;
  }
  return $self->_read_uncached($host);
}


sub _read_uncached {
  my ($self, $host) = @_;
  
  #say "Reading uncached base: $host";
  my $p = Ural::Deploy::HostParam->new(host => $host);
  return $self->set_cache($host, $p);
}


sub set_cache {
  my ($self, $host, $param) = @_;
  $params_cache{$host} = $param;
  return $param;
}


sub _dump_cache {
  my $self = shift;
  say Dumper \%params_cache;
}


# my $hostparam = Ural::Deploy::ReadDB_base->read_db('testhost1', [no_cache => 1]);
sub read_db {
  my ($class, $host, %args) = @_;
  return $class->new->read($host, %args);
}


1;
