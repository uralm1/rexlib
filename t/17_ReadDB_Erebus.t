use strict;
use warnings;

use Test::More;
use Test::Exception;

use Rex;
use Rex::Commands;
use Ural::Deploy::ReadDB_base;
use Ural::Deploy::ReadDB_Erebus;

set cmdb => {
  type => 'YAML',
  path => ['cmdb/config.yml'],
};

# test shared cache
my $r0 = new_ok('Ural::Deploy::ReadDB_base');
my $p = $r0->read('erebus');
ok(!($p->is_cached), 'Base read - not cached');

# now ReadDB_Erebus testing
my $r = new_ok('Ural::Deploy::ReadDB_Erebus');

$p = $r->read('erebus');
ok(!($p->is_cached), 'First read - not cached');
$p = $r->read('erebus');
ok($p->is_cached, 'Second read - cached');

isa_ok($p, 'Ural::Deploy::HostParamErebus');
#diag explain $p;
#$p->dump;

done_testing();

