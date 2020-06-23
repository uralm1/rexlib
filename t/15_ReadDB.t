use strict;
use warnings;

use Test::More;
use Test::Exception;

use Rex;
use Rex::Commands;
use Ural::Deploy::ReadDB_base;

my $r = Ural::Deploy::ReadDB_base->new;
isa_ok($r, 'Ural::Deploy::ReadDB_base');

my $p;
isa_ok($p = $r->read('testhost1'), 'Ural::Deploy::HostParam');
ok(!($p->is_cached), 'First read - not cached');

isa_ok($p = $r->read('testhost1'), 'Ural::Deploy::HostParam');
ok($p->is_cached, 'Second read - cached');

$p = $r->read('testhost1', no_cache => 1);
isa_ok($p, 'Ural::Deploy::HostParam');
ok(!($p->is_cached), 'Third read - not cached');
#diag explain $p;

done_testing();

