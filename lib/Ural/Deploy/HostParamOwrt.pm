package Ural::Deploy::HostParamOwrt;

use strict;
use warnings;
use v5.12;
#use utf8;

use Carp;
use parent 'Ural::Deploy::HostParam';

# $p = Ural::Deploy::HostParamOwrt->new(
#   host => 'testhost1',
# );
sub new {
  my ($class, %args) = @_;
  my $self = $class->SUPER::new(host => $args{host});

  return $self;
}


1;
