package Ural::Deploy::HostParam;

use strict;
use warnings;
use v5.12;
#use utf8;

use Carp;
use Data::Dumper;

# $p = Ural::Deploy::HostParam->new(
#   host => 'testhost1',
#   other_param => 'value',
# );
sub new {
  my ($class, %args) = @_;
  croak 'host parameter required' unless $args{host};
  my $self = bless {
    host => $args{host},
    cached => undef
  }, $class;

  #$self->{other_param} = 0;
  #for (qw/other_param/) {
  #  $self->{$_} = $args{$_} if defined $args{$_};
  #}

  return $self;
}


sub get_host {
  return shift->{host};
}

sub is_cached {
  return shift->{cached};
}

sub dump {
  say Dumper shift;
}

1;
