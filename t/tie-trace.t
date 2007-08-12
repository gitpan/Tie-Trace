use Test::Base tests => 36;

use_ok("Tie::Trace");
use Tie::Hash;

{
  my $err;
  # local $SIG{__DIE__} = sub {print @_, $err};
  local *STDERR;

  ok(open(STDERR, ">", \$err), "open");

  my %hash;
  tie %hash, "Tie::Trace", r => 1, debug => undef;

  my $s;
  my $x = { hoge => 1, hoge2 => 2, hoge3 => [qw/a b c d e/],  hoge4 => \$s};

  $hash{1} = $x;            # 1 -- HASH(....)
  like($err, qr/^\{1\} => HASH/m, '$hash{1} = $x');

  $hash{1}->{hoge} = 3;     # hoge -- 3
  like($err, qr/^\{1\}\{hoge\} => 3/m, '$hash{1}->{hoge} = 3');

  $hash{1}->{hoge} = 4;     # hoge -- 4
  like($err, qr/^\{1\}{hoge} => 4/m, '$hash{1}->{hoge} = 4');

  my $s2;
  my $array = [ 1, 2, \$s2 ];
  $x->{hoge5} = $array;
  ${$array->[2]} = "4";
  like($err, qr/^\{1\}\{hoge5\}\[2] => 4/m, '${$array->[2]} = "4"');
  delete $x->{hoge5};

  ${$x->{hoge4}} = "0000";  # 0000
  like($err, qr/^\{1\}\{hoge4\} => 0000/m, '${$x->{hoge4}} = "0000"');

  $hash{2}->{hoge} = 222;   # 2 -- HASH(...)
                            # hoge - 222
  like($err, qr/^\{2\} => HASH/m, '$hash{2}->{hoge} = 222');
  like($err, qr/^\{2\}\{hoge\} => 222/m, '$hash{2}->{hoge} = 222');

  push(@{$hash{1}->{hoge3}}, "array");# array
  like($err, qr/^\@\{\{1\}\{hoge3\}\} => ARRAY/m, 'push(@{$hash{1}->{hoge3}}, "array")');

  push(@{$hash{1}->{hoge3}}, "array2");# array
  like($err, qr/^\@\{\{1\}\{hoge3\}\} => ARRAY/m, 'push(@{$hash{1}->{hoge3}}, "array2")');

  is_deeply([sort keys(%hash)], [1,2], "hash key check");      # 1, 2, 3, 4
  is_deeply([sort keys %{$hash{1}}], ["hoge", "hoge2", "hoge3", "hoge4"], "hash key check"); # hoge
  is_deeply([sort @{$hash{1}->{hoge3}}], [qw/a array array2 b c d e/], "array check");
  $hash{xxx}->{bless} = bless {};
  like($err, qr/^\{xxx\}\{bless} => main=HASH/m, '$hash{xxx}->{bless} = bless {}');
  $hash{xxx}->{bless}->{bless_hoge} = 1;
  unlike($err, qr/^\{xxx\}\{bless_hoge} => 1/m, '$hash{xxx}->{bless}->{bless_hoge} = 1');
  my %tied;
  tie %tied, "Tie::StdHash";
  $hash{xxx}->{tied} = \%tied;
  like($err, qr/^\{xxx\}\{tied\} => HASH/m, '$hash{xxx}->{tied} = HASH');
  $hash{xxx}->{tied}->{a} = 1234;
  like($err, qr/^\{xxx\}\{tied\}\{a\} => 1234/m, '$hash{xxx}->{tied}->{a} = 1234');
  close STDERR;

  open STDERR, ">", \$err or die $!;

  my %hash2;
  tie %hash2, "Tie::Trace", key => ["foo", "bar"] or die $!;

  $hash2{foo} = 1;
  like($err, qr/^\{foo\} => 1/m, '$hash{foo} = 1');
  $hash2{bar} = 1;
  like($err, qr/^\{bar\} => 1/m, '$hash{bar} = 1');
  $hash2{xxx} = {};
  unlike($err, qr/^\{xxx\} => HASH/m, '$hash{xxx} = {}');
  $hash2{xxx}->{foo} = 2;
  like($err, qr/^\{xxx\}\{foo\} => 2/m, '$hash{xxx}->{foo} = 2');
  $hash2{xxx}->{bar} = 2;
  like($err, qr/^\{xxx\}\{bar\} => 2/m, '$hash{xxx}->{bar} = 2');
  $hash2{xxx}->{xxx} = 2;
  unlike($err, qr/^\{xxx\}\{xxx\} => 2/m, '$hash{xxx}->{xxx} = 2');

  close STDERR;
  open STDERR, ">", \$err or die $!;

  my %hash3;
  tie %hash3, "Tie::Trace", value => ["foo", "bar"] or die $!;

  $hash3{oo} = 'foo';
  like($err, qr/^\{oo\} => 'foo'/m, q{$hash{oo} = 'foo'});
  $hash3{ar} = 'bar';
  like($err, qr/^\{ar\} => 'bar'/m, q{$hash{ar} = 'bar'});
  $hash3{xxx} = {};
  unlike($err, qr/^\{xxx\} => HASH/m, '$hash{xxx} = {}');
  $hash3{xxx}->{oox} = 'foo';
  like($err, qr/^\{xxx\}\{oox\} => 'foo'/m, q{$hash{xxx}->{oo} = 'foo'});
  $hash3{xxx}->{arx} = 'bar';
  like($err, qr/^\{xxx\}\{arx\} => 'bar'/m, q{$hash{xxx}->{ar} = 'bar'});
  $hash3{xxx}->{xxx} = 'var';
  unlike($err, qr/^\{xxx\}\{xxx\} => 'var'/m, q{$hash{xxx}->{xxx} = 'var'});

  close STDERR;
  open STDERR, '>', \$err or die $!;

  my %hash4;
  tie(%hash4, 'Tie::Trace', value => ['foo', 'bar'], r => 0) or die $!;

  $hash4{oo} = 'foo';
  like($err, qr/^\{oo\} => 'foo'/m, q{$hash{oo} = 'foo'});
  $hash4{ar} = 'bar';
  like($err, qr/^\{ar\} => 'bar'/m, q{$hash{ar} = 'bar'});
  $hash4{xxx} = {};
  unlike($err, qr/^\{xxx\}\{xxx\} => HASH/m, '$hash{xxx} = {}');
  $hash4{xxx}->{ooxx} = 'foo';
  unlike($err, qr/^\{xxx\}\{oox\} => 'foo'/m, q{$hash{xxx}->{oo} = 'foo'});
  $hash4{xxx}->{arx} = 'bar';
  unlike($err, qr/^\{xxx\}\{arx\} => 'bar'/m, q{$hash{xxx}->{ar} = 'bar'});
  $hash4{xxx}->{xxx} = 'var';
  unlike($err, qr/^\{xxx\}\{xxx\} => 'var'/m, q{$hash{xxx}->{xxx} = 'var'});
}

