use strict;
use warnings;

use Test::More;
use Test::Exception;

use Ural::Deploy::ReadDB;

dies_ok( sub { ReadDB() }, 'ReadDB() without host parameter');

my $p = ReadDB('testhost1', format_ver => 999);
$p = ReadDB('testhost1', format_ver => 999);
$p = ReadDB('testhost1', format_ver => 999);

isa_ok($p, 'Ural::Deploy::HostParam');
diag explain $p;

done_testing();

