package Ural::Deploy::HostParam;

use strict;
use warnings;
use v5.12;
#use utf8;

use Carp;

# $p = Ural::Deploy::HostParam->new(
#   host => 'testhost1',
#   other_param => 'value',
# );
sub new {
  my ($class, %args) = @_;
  croak 'host parameter required' unless $args{host};
  my $self = bless {
    host => $args{host}
  }, $class;

  $self->{format_ver} = 0;
  for (qw/format_ver/) {
    $self->{$_} = $args{$_} if defined $args{$_};
  }

  return $self;
}


sub get_host {
  return shift->{host};
}

sub is_owrt_format {
  return shift->{format_ver} == 1;
}

sub is_erebus_format {
  return shift->{format_ver} == 2;
}


1;
