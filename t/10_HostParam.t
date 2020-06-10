use strict;
use warnings;

use Test::More;
use Test::Exception;

use Ural::Deploy::HostParam;

dies_ok( sub { Ural::Deploy::HostParam->new() }, 'Constructor without host parameter');

my $p = Ural::Deploy::HostParam->new(host => 'testhost1', format_ver => 2);
isa_ok($p, 'Ural::Deploy::HostParam');
is($p->get_host, 'testhost1', 'get_host() working');
ok(!$p->is_owrt_format, 'not is_owrt_format()');

is($p->get_version, '2', 'get_version()');

diag explain $p;

done_testing();
