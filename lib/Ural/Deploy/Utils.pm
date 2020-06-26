package Ural::Deploy::Utils;

use strict;
use warnings;
use v5.12;
#use utf8;
use feature 'state';

use Carp;
use Data::Dumper;

use Exporter 'import';
our @EXPORT_OK = qw(remove_dups recursive_search_by_from_hostname recursive_search_by_to_hostname);


sub remove_dups {
  my $aref = shift;
  my %seen;
  return [grep { ! $seen{ $_ }++ } @$aref];
}


### Helpers
sub recursive_search_by_from_hostname {
  my ($listref, $hostname, $tun_array_ref, $tun_node_name) = @_;

  state $loop_control = 0;
  die "Wrong tunnels configuration (reqursive infinite loop found).\n" if $loop_control++ >= 30;

  my @tt1 = grep { $_->{from_hostname} eq $hostname } @$tun_array_ref;
  foreach my $hh1 (@tt1) {
    unless ((grep { $_ eq $hh1->{to_ip} } @$listref) || ($hh1->{to_hostname} eq $tun_node_name)) {
      push @$listref, $hh1->{to_ip};
      recursive_search_by_from_hostname($listref, $hh1->{to_hostname}, $tun_array_ref, $tun_node_name);
    }
  }
}


sub recursive_search_by_to_hostname {
  my ($listref, $hostname, $tun_array_ref, $tun_node_name) = @_;

  state $loop_control = 0;
  die "Wrong tunnels configuration (reqursive infinite loop found).\n" if $loop_control++ >= 30;

  my @tt1 = grep { $_->{to_hostname} eq $hostname } @$tun_array_ref;
  foreach my $hh1 (@tt1) {
    unless ((grep { $_ eq $hh1->{from_ip} } @$listref) || ($hh1->{from_hostname} eq $tun_node_name)) {
      push @$listref, $hh1->{from_ip};
      recursive_search_by_to_hostname($listref, $hh1->{from_hostname}, $tun_array_ref, $tun_node_name);
    }
  }
}


1;
