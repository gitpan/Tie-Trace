use Test::More qw/no_plan/;

use_ok("Tie::Trace");

{
  my $err;
  local *STDERR;

  open STDERR, ">", \$err or die $!;

  my %hash;
  tie %hash, "Tie::Trace::Hash", r => 1;

  my $s;
  my $x = { hoge => 1, hoge2 => 2, hoge3 => [qw/a b c d e/],  hoge4 => \$s,};

  $hash{1} = $x;            # 1 -- HASH(....)
  like($err, qr/^Hash => Key: 1, Value: HASH/m, '$hash{1} = $x');

  $hash{1}->{hoge} = 3;     # hoge -- 3
  like($err, qr/^Hash => Key: hoge, Value: 3/m, '$hash{1}->{hoge} = 3');

  $hash{1}->{hoge} = 4;     # hoge -- 4
  like($err, qr/^Hash => Key: hoge, Value: 4/m, '$hash{1}->{hoge} = 4');

  ${$x->{hoge4}} = "0000";  # 0000
  like($err, qr/^Scalar => Value: 0000/m, '${$x->{hoge4}} = "0000"');

  $hash{2}->{hoge} = 222;   # 2 -- HASH(...)
                          # hoge - 222
  like($err, qr/^Hash => Key: 2, Value: HASH/m, '$hash{2}->{hoge} = 222');
  like($err, qr/^Hash => Key: hoge, Value: 222/m, '$hash{2}->{hoge} = 222');

  push(@{$hash{1}->{hoge3}}, "array");# array
  like($err, qr/^Array => Point: 5, Value: array/m, 'push(@{$hash{1}->{hoge3}}, "array")');

  eq_array([sort keys(%hash)], [1,2,3,4], "hash key check");      # 1, 2, 3, 4
  eq_array([sort keys %{$hash{3}}], ["hoge"], "hash key check"); # hoge
  eq_array([sort @{$hash{1}->{hoge3}}], [qw/a array b c d e/], "array check");

  close STDERR;
  open STDERR, ">", \$err or die $!;

  my %hash2;
  tie %hash2, "Tie::Trace::Hash", key => ["foo", "bar"] or die $!;

  $hash2{foo} = 1;
  like($err, qr/^Hash => Key: foo, Value: 1/m, '$hash{foo} = 1');
  $hash2{bar} = 1;
  like($err, qr/^Hash => Key: bar, Value: 1/m, '$hash{bar} = 1');
  $hash2{xxx} = {};
  unlike($err, qr/^Hash => Key: xxx, Value: HASH/m, '$hash{xxx} = {}');
  $hash2{xxx}->{foo} = 2;
  like($err, qr/^Hash => Key: foo, Value: 2/m, '$hash{xxx}->{foo} = 2');
  $hash2{xxx}->{bar} = 2;
  like($err, qr/^Hash => Key: bar, Value: 2/m, '$hash{xxx}->{bar} = 2');
  $hash2{xxx}->{xxx} = 2;
  unlike($err, qr/^Hash => Key: xxx, Value: 2/m, '$hash{xxx}->{xxx} = 2');

  close STDERR;
  open STDERR, ">", \$err or die $!;

  my %hash3;
  tie %hash3, "Tie::Trace::Hash", value => ["foo", "bar"] or die $!;

  $hash3{oo} = "foo";
  like($err, qr/^Hash => Key: oo, Value: foo/m, '$hash{oo} = "foo"');
  $hash3{ar} = "bar";
  like($err, qr/^Hash => Key: ar, Value: bar/m, '$hash{ar} = "bar"');
  $hash3{xxx} = {};
  unlike($err, qr/^Hash => Key: xxx, Value: HASH/m, '$hash{xxx} = {}');
  $hash3{xxx}->{oox} = "foo";
  like($err, qr/^Hash => Key: oox, Value: foo/m, '$hash{xxx}->{oo} = "foo"');
  $hash3{xxx}->{arx} = "bar";
  like($err, qr/^Hash => Key: arx, Value: bar/m, '$hash{xxx}->{ar} = "bar"');
  $hash3{xxx}->{xxx} = "var";
  unlike($err, qr/^Hash => Key: xxx, Value: var/m, '$hash{xxx}->{xxx} = "var"');

  close STDERR;
  open STDERR, ">", \$err or die $!;

  my %hash4;
  tie(%hash4, "Tie::Trace::Hash", value => ["foo", "bar"], r => 0) or die $!;

  $hash4{oo} = "foo";
  like($err, qr/^Hash => Key: oo, Value: foo/m, '$hash{oo} = "foo"');
  $hash4{ar} = "bar";
  like($err, qr/^Hash => Key: ar, Value: bar/m, '$hash{ar} = "bar"');
  $hash4{xxx} = {};
  unlike($err, qr/^Hash => Key: xxx, Value: HASH/m, '$hash{xxx} = {}');
  $hash4{xxx}->{ooxx} = "foo";
  unlike($err, qr/^Hash => Key: oox, Value: foo/m, '$hash{xxx}->{oo} = "foo"');
  $hash4{xxx}->{arx} = "bar";
  unlike($err, qr/^Hash => Key: arx, Value: bar/m, '$hash{xxx}->{ar} = "bar"');
  $hash4{xxx}->{xxx} = "var";
  unlike($err, qr/^Hash => Key: xxx, Value: var/m, '$hash{xxx}->{xxx} = "var"');
}
