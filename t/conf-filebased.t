#!/usr/bin/perl -w

use strict;

use Test::More tests => 43;

BEGIN
{
  use_ok('Rose::Conf');
  use_ok('Rose::Conf::FileBased');
  require Rose::Conf::Root;
}

use FindBin qw($Bin);

#
# No conf root
#

our %CONF;
My::Class::Conf->import('%CONF');

is($CONF{'COLOR'}, 'blue', 'Hash get 1 (no conf root)');
is($CONF{'SIZE'}, 'big', 'Hash get 2 (no conf root)');

is(My::Class::Conf->param('COLOR'), 'blue', 'param() get 1 (no conf root)');
is(My::Class::Conf->param('SIZE'), 'big', 'param() get 2 (no conf root)');

$CONF{'COLOR'} = 'red';
My::Class::Conf->param(SIZE => 'small');

is($CONF{'COLOR'}, 'red', 'Hash get 3 (no conf root)');
is($CONF{'SIZE'}, 'small', 'Hash get 4 (no conf root) (no conf root)');

is(My::Class::Conf->param('COLOR'), 'red', 'param() get 3 (no conf root)');
is(My::Class::Conf->param('SIZE'), 'small', 'param() get 4 (no conf root)');

ok(My::Class::Conf->param_exists('COLOR'), 'param_exists() 1 (no conf root)');
ok(My::Class::Conf->param_exists('SIZE'), 'param_exists() 2 (no conf root)');

ok(!My::Class::Conf->param_exists('color'), 'param_exists() 3 (no conf root)');
ok(!My::Class::Conf->param_exists('nonesuch'), 'param_exists() 4 (no conf root)');

my $hash = My::Class::Conf->conf_hash;

is($hash->{'COLOR'}, 'red', 'conf_hash() get 1 (no conf root)');
is($hash->{'SIZE'}, 'small', 'conf_hash() get 2 (no conf root)');

eval { my $f = $CONF{'FOO'} };

ok($@, 'Nonexistent param 1 (no conf root)');

eval { My::Class::Conf->param('foo') };

ok($@, 'Nonexistent param 2 (no conf root)');

#
# Conf root
#

Rose::Conf::Root->conf_root($Bin);

My::Class::Conf->refresh;

is($CONF{'COLOR'}, 'purple', 'Hash get 1 (conf root)');
is($CONF{'SIZE'}, 'medium', 'Hash get 2 (conf root)');
is($CONF{'NUM'}, '5', 'Hash get 3 (conf root)');
is($CONF{'KEY'}, 'baz', 'Hash get 4 (conf root)');

is(My::Class::Conf->param('COLOR'), 'purple', 'param() get 1 (conf root)');
is(My::Class::Conf->param('SIZE'), 'medium', 'param() get 2 (conf root)');
is(My::Class::Conf->param('NUM'), '5', 'param() get 3 (conf root)');
is(My::Class::Conf->param('KEY'), 'baz', 'param() get 4 (conf root)');

$CONF{'COLOR'} = 'red';
My::Class::Conf->param(SIZE => 'small');

is(My::Class::Conf->local_conf_value('VALUE'), undef, 'local_conf_value() 1');
is(My::Class::Conf->local_conf_value('NUM'), '5', 'local_conf_value() 2');
is(My::Class::Conf->local_conf_value('KEY'), 'baz', 'local_conf_value() 3');

is($CONF{'COLOR'}, 'red', 'Hash get 3 (conf root)');
is($CONF{'SIZE'}, 'small', 'Hash get 4 (conf root) (conf root)');

is(My::Class::Conf->param('COLOR'), 'red', 'param() get 5 (conf root)');
is(My::Class::Conf->param('SIZE'), 'small', 'param() get 6 (conf root)');

ok(My::Class::Conf->param_exists('COLOR'), 'param_exists() 1 (conf root)');
ok(My::Class::Conf->param_exists('SIZE'), 'param_exists() 2 (conf root)');

ok(!My::Class::Conf->param_exists('color'), 'param_exists() 5 (conf root)');
ok(!My::Class::Conf->param_exists('nonesuch'), 'param_exists() 6 (conf root)');

$hash = My::Class::Conf->conf_hash;

is($hash->{'COLOR'}, 'red', 'conf_hash() get 1 (conf root)');
is($hash->{'SIZE'}, 'small', 'conf_hash() get 2 (conf root)');

eval { my $f = $CONF{'FOO'} };

ok($@, 'Nonexistent param 1 (conf root)');

eval { My::Class::Conf->param('foo') };

ok($@, 'Nonexistent param 2 (conf root)');

my $keys = join(',', sort My::Class::Conf->local_conf_keys);

is($keys, 'COLOR,KEY,LIST,NUM,SIZE', 'local_conf_keys()');

ok(ref $CONF{'LIST'} eq 'ARRAY' && join(':', @{$CONF{'LIST'}}) eq 'a:b:c', 'list inflation');

BEGIN
{
  package My::Class::Conf;

  use strict;
  our @ISA = qw(Rose::Conf::FileBased);

  our %CONF =
  (
    COLOR => 'blue',
    SIZE  => 'big',
    NUM   => 7,
    KEY   => 42,
    VALUE => 'foo',
    LIST  => [ 1, 2, 3 ],
  );
  
  sub refresh
  {
    shift->SUPER::refresh(@_);
    
    $CONF{'LIST'} = [ split(',', $CONF{'LIST'}) ]
      unless(ref $CONF{'LIST'});
  }
}
