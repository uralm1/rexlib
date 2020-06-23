package Ural::Deploy::ReadDB_Owrt;

use strict;
use warnings;
use v5.12;
#use utf8;

use Rex;
use Rex::Commands;
use Rex::CMDB;

use Carp;
use Ural::Deploy::HostParamOwrt;
use parent 'Ural::Deploy::ReadDB_base';

sub new {
  my $class = shift;
  my $self = $class->SUPER::new();
  $self->{result_type} = 'Ural::Deploy::HostParamOwrt';
  return $self;
}


sub _read_uncached {
  my ($self, $host) = @_;
  
  say "Reading uncached owrt: $host";
  say 'CMDB: '.get(cmdb('mail_from'));
  my $p = Ural::Deploy::HostParamOwrt->new(host => $host);
  $self->set_cache($host, $p);
  return $p;
}


1;
