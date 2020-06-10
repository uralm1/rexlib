package Ural::Deploy::ReadDB_base;

use strict;
use warnings;
use v5.12;
#use utf8;

use Carp;
use Ural::Deploy::HostParam;

sub new {
  return bless {}, shift;
}

sub read {
  my ($self, $host) = @_;
  return Ural::Deploy::HostParam->new(host => $host, format_ver => 999);
}

1;
