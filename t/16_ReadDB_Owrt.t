use strict;
use warnings;

use Test::More;
use Test::Exception;

use Rex;
use Rex::Commands;
use Ural::Deploy::ReadDB_Owrt;

set cmdb => {
  type => 'YAML',
  path => ['cmdb/config.yml'],
};

my $r = new_ok('Ural::Deploy::ReadDB_Owrt');

my $p = $r->read('gwsouth2');
ok(!($p->is_cached), 'First read - not cached');

isa_ok($p, 'Ural::Deploy::HostParamOwrt');
#diag explain $p;
#$p->dump;

done_testing();

