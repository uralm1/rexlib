use strict;
use warnings;

use Test::More;
use Test::Exception;

use Ural::Deploy::HostParam;

dies_ok( sub { Ural::Deploy::HostParam->new() }, 'Constructor without host parameter');

my $p = new_ok('Ural::Deploy::HostParam' => [host => 'testhost1']);
is($p->get_host, 'testhost1', 'get_host() working');
ok(!($p->is_cached), 'hostparam is not cached');

#diag explain $p;
$p->dump;

done_testing();
