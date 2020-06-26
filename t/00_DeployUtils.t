use strict;
use warnings;
use v5.12;

use Test::More;
use Test::Exception;
use Data::Dumper;

use Ural::Deploy::Utils qw(remove_dups);

my $tcn_ref = [
  ['gwtest1','10.2.13.131'],
  ['gwtest1','10.2.13.131'],
  ['gwtest2','10.2.13.132'],
  ['gwtest2','10.2.13.132'],
  ['gwtest2','10.2.13.132'],
  ['erebus','10.2.13.130'],
];

#say Dumper $tcn_ref;
is_deeply(remove_dups([map {$_->[0]} @$tcn_ref]), ['gwtest1','gwtest2','erebus'], 'remove_dups on hostnames');
is_deeply(remove_dups([map {$_->[1]} @$tcn_ref]), ['10.2.13.131','10.2.13.132','10.2.13.130'], 'remove_dups on ips');

#req_test();

done_testing();


sub req_test {
  state $loop_cont = 0;
  die "Infinite loop prevented" if $loop_cont++ >= 5;
  say "Reqursion loop $loop_cont";
  sleep(1);
  req_test();
}
