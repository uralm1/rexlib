use strict;
use warnings;

use Test::More;
use Test::Exception;

use Rex;
use Rex::Commands;
use Ural::Deploy::ReadDB_base;

my $r = Ural::Deploy::ReadDB_base->new;
isa_ok($r, 'Ural::Deploy::ReadDB_base');

isa_ok($r->read('testhost1'), 'Ural::Deploy::HostParam');
isa_ok($r->read('testhost1'), 'Ural::Deploy::HostParam');

my $p = $r->read('testhost1', no_cache => 1);
isa_ok($p, 'Ural::Deploy::HostParam');
diag explain $p;

done_testing();

