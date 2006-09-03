package Tie::Trace;

use warnings;
use strict;
use Tie::Hash ();
use Tie::Array ();
use Tie::Scalar ();
use Carp ();
use Data::Dumper ();

our $_carp_off = 0;
our $AUTOLOAD;

sub TIEHASH  { Tie::Trace::_tieit({}, @_); }
sub TIEARRAY { Tie::Trace::_tieit([], @_); }
sub TIESCALAR{ my $s; Tie::Trace::_tieit(\$s, @_); }

sub AUTOLOAD{
  # proxy to Tie::Std***
  my($self, @args) = @_;
  my($class, $method) = (split /::/, $AUTOLOAD)[2, 3];
  my $sub = \&{'Tie::Std' . $class . '::' . $method};
  defined &$sub ? $sub->($self->{storage}, @args) : return;
}

sub storage{
  my($self) = @_;
  return $self->{storage};
}

sub parent{
  my($self) = @_;
  return $self->{parent};
}

sub _carp_off{ 1 };

sub _match{
  my($self, $test, $value) = @_;
  if(ref $test eq 'Regexp'){
    return $value =~ $_;
  }elsif(ref $test eq 'CODE'){
    return $test->($self, $value);
  }else{
    return $test eq $value;
  }
  return;
}

sub _matching{
  my($self, $test, $tested) = @_;
  return 1 unless $test;
  if($tested){
    return 1 if grep $self->_match($_, $tested), @$test;
  }
  return 0;
}

sub _carpit{
  my($self, %args) = @_;
  my $caller =  $self->{options}->{caller};
  my @caller = map $_ + 1, ref $caller ? @{$caller} : $caller;
  my(@filename, @line);
  foreach(@caller){
    my($f, $l) = (caller($_))[1, 2];
    next unless $f and $l;
    push @filename, $f;
    push @line, $l;
  }
  my $class = (split /::/, ref $self)[2];
  my $location = @line == 1 ? " at $filename[0] line $line[0]." : join "\n", map " at $filename[$_] line $line[$_].", (0 .. $#filename);
  $location .= "\n";
  my $op = $self->{options} || {};

  # key/value checking
  if($op->{key} or $op->{value}){
    my $key   = $self->_matching($self->{options}->{key},   $args{key});
    my $value = $self->_matching($self->{options}->{value}, $args{value});
    if(($args{key} and $op->{key}) and $op->{value}){
      return unless $key or $value;
    }elsif($args{key} and $op->{key}){
      return unless $key;
    }elsif($op->{value}){
      return unless $value;
    }
  }

  # debug type
  my $debug = $op->{debug};
  my $value = $args{value};

  if(ref $debug eq 'CODE'){
    $value = $debug->($self, $value);
  }elsif(lc($debug) eq 'dumper'){
    $value = Data::Dumper::Dumper($args{value});
  }

  # debug_value checking
  return unless $self->_matching($self->{options}->{debug_value}, $value);

  # use scalar/array/hash ?
  return unless grep lc($class) eq lc($_) , @{$op->{use}};
  # print warning message
  if($class eq 'Scalar'){
    warn("$class => Value: $value$location");
  }elsif($class eq 'Array'){
    $args{point} ||= $#{$self->{storage}} + 1;
    warn("$class => Point: $args{point}, Value: $value$location");
  }elsif($class eq 'Hash'){
    warn("$class => Key: $args{key}, Value: $value$location");
  }
}

sub _tieit{
  my($self, $class, %arg) = @_;
  if($class =~/^Tie::Trace$/){
    my $type = lc(ref $self);
    substr($type, 0, 1) = uc(substr($type, 0, 1));
    $class .= '::' . $type;
  }
  my $parent = $arg{parent};
  my $options;
  if(defined $parent and $parent){
    $options = $parent->{options};
  }else{
    $options = \%arg;
    unless($options->{use}){
      $options->{use} = [qw/scalar array hash/];
    }
    unless(defined $options->{r}){
      $options->{r} = 1;
    }
    $options->{caller} ||= 0;
  }
  my $_self =
    {
     self     => $self,
     parent => $parent,
     options  => $options,
    };
  bless $_self, $class;
  return $_self;
}

sub _data_filter{
  my($structure, $self) = @_;
  return $structure unless $self->{options}->{r};

  my $ref = ref $structure;
  # 0 ... scalar,  1 ... scalarref, 2 ... arrayref
  # 4 ... hashref, 8 ... blessed  , 16 .. tied
  my %test = (1 => 'SCALAR', 2 => 'ARRAY', 4 => 'HASH');
  my $type = 0;
  my($class, $tied);
  if(defined $ref){
    foreach my $i (keys %test){
      if($ref eq $test{$i}){
        $type = $i;
        last;
      }elsif(defined $structure and $structure =~/=$test{$i}/){
        $tied = tied($i == 1 ? $$structure : $i == 2 ? @$structure : $structure);
        $type = $i | 8 | ($tied ? 16 : 0);
        $class = $ref;
        last;
      }
    }
  }
  unless($class or $tied){
    if(($type & 0b11001) == 1){
      my $tmp = $$structure;
      tie $$structure, "Tie::Trace::Scalar", parent => $self;
      $$structure = Tie::Trace::_data_filter($tmp, $self);
      return $structure;
    }elsif(($type & 0b11010) == 2){
      my @tmp = @$structure;
      tie @$structure, "Tie::Trace::Array", parent => $self;
      foreach my $i (0 .. $#tmp){
        $structure->[$i] = Tie::Trace::_data_filter($tmp[$i], $self);
      }
      return $structure;
    }elsif(($type & 0b11100) == 4){
      my %tmp = %$structure;
      tie %$structure, "Tie::Trace::Hash", parent => $self;
      while(my($k, $v) = each %tmp){
        $structure->{$k} = Tie::Trace::_data_filter($v, $self);
      }
      return $structure;
    }
  }
  # tied variable / blessed ref / just a scalar
  return $structure;
}

# Hash /////////////////////////
package Tie::Trace::Hash;

use warnings;
use strict;

use base qw/Tie::Trace/;

sub STORE{
  my($self, $key, $value) = @_;
  $self->_carpit(key => $key, value => $value)  unless $_carp_off;
  local $_carp_off = $self->_carp_off();
  Tie::Trace::_data_filter($value, $self);
  $self->{storage}->{$key} = $value;
};

# Array /////////////////////////
package Tie::Trace::Array;

use warnings;
use strict;

use base qw/Tie::Trace/;

sub STORE{
  my($self, $p, $value) = @_;
  $self->_carpit(point => $p, value => $value)  unless $_carp_off;
  local $_carp_off = Tie::Trace->_carp_off();
  Tie::Trace::_data_filter($value, $self);
  $self->{storage}->[$p] = $value;
}

sub PUSH{
  my($self, @value) = @_;
  my $i   = $self->FETCHSIZE;
  $self->STORE($i++, shift(@value)) while @value;
}

# Scalar /////////////////////////
package Tie::Trace::Scalar;

use warnings;
use strict;

use base qw/Tie::Trace/;

sub STORE{
  my($self, $value) = @_;
  $self->_carpit(value => $value)  unless $_carp_off;
  local $_carp_off = Tie::Trace->_carp_off();
  Tie::Trace::_data_filter($value, $self);
  ${$self->{storage}} = $value;
};

=head1 NAME

Tie::Trace - easy print debugging with tie

=head1 VERSION

Version 0.05

=cut

our $VERSION = '0.05';

=head1 SYNOPSIS

    use Tie::Trace;
 
    my %hash;
    tie %hash, "Tie::Trace";
 
    $hash{hoge} = 'hogehoge'; # warn Hash => Key: hoge, Value: hogehgoe at ...
 
    my @array;
    tie @aray, "Tie::Trace";
    push @array, "array";    # warn Array => Point: 0, Value: array at ...
 
    my $scalar;
    tie $scalar, "Tie::Trace";
    $scalar = "scalar";      # warn Scalar => Value: scalar at ...

=head1 DESCRIPTION

This is usefull for print debugging. Using tie mechanism,
you can see sotred value for the specified variable.

If the stored value is scalar/array/hash ref, this can check
recursively.

for example;

 tie %hash, "Tie::Trace";
 
 $hash{foo} = {a => 1, b => 2}; # warn ...
 $hash{foo}->{a} = 2            # warn ...

But This ignores blessed reference and tied value.

=head1 OPTIONS

=over 4

=item key => [values/regexs/coderef]

 tie %hash, "Tie::Trace", key => [qw/foo bar/];

It is for hash. You can spedify key name/regex/coderef for checking.
Not specified/matched keys are ignored for warning.
When you give coderef, this codref receive tied value and key as arguments,
it returns false, the key is ignored.

for example;

 tie %hash, "Tie::Trace", key => [qw/foo bar/, qr/x/];
 
 $hash{foo} = 1 # warn ...
 $hash{bar} = 1 # warn ...
 $hash{var} = 1 # *no* warnings
 $hash{_x_} = 1 # warn ...

=item value => [contents/regexs/coderef]

 tie %hash, "Tie::Trace", value => [qw/foo bar/];

You can spedify value's content/regex/coderef for checking.
Not specified/matched are ignored for warning.
When you give coderef, this codref receive tied value and value as arguments,
it returns false, the value is ignored.

for example;

 tie %hash, "Tie::Trace", value => [qw/foo bar/, qr/\)/];
 
 $hash{a} = 'foo'  # warn ...
 $hash{b} = 'foo1' # *no* warnings
 $hash{c} = 'bar'  # warn ...
 $hash{d} = ':-)'  # warn ...

=item use => [qw/hash array scalar/]

 tie %hash, "Tie::Trace", use => [qw/array/];

It specify type(scalar, array or hash) of variable for checking.
As default, all type will be checked.

for example;

 tie %hash, "Tie::Trace", use => [qw/array/];
 
 $hash{foo} = 1         # *no* warnings
 $hash{bar} = 1         # *no* warnings
 $hash{var} = []        # *no* warnings
 push @{$hash{var}} = 1 # warn ...

=item debug => 'dumper'/coderef

 tie %hash, "Tie::Trace", debug => 'dumper'
 tie %hash, "Tie::Trace", debug => sub{my($self, @v) = @_; return @v }

It specify value representation. As default, just print value as scalar.
You can use "dumper" or coderef. "dumper" make value show with Data::Dumper::Dumper.
When you specify your coderef, its first argument is tied value and
second argument is value, it should modify it and return it.

=item debug_value => [contents/regexs/coderef]

 tie %hash, "Tie::Trace", debug => sub{my($s,$v) = @_; $v =~tr/op/po/;}, debug_value => [qw/foo boo/];

You can spedify debugged value's content/regex for checking.
Not specified/matched are ignored for warning.
When you give coderef, this codref receive tied value and value as arguments,
it returns false, the value is ignored.

for example;

 tie %hash, "Tie::Trace", debug => sub{my($s,$v) = @_; $v =~tr/op/po/;}, debug_value => [qw/foo boo/];
 
 $hash{a} = 'fpp'  # warn ...      because debugged value is foo
 $hash{b} = 'foo'  # *no* warnings because debugged value is fpp
 $hash{c} = 'bpp'  # warn ...      because debugged value is boo

=item r => 0/1

 tie %hash, "Tie::Trace", r => 0;

If r is 0, this won't check recusively. 1 is default.

=item caller => number/[numbers]

 tie %hash, "Tie::Trace", caller => 2;

It effects warning message.
default is 0. If you set grater than 0, it goes upstream to check.

You can specify array ref.

 tie %hash, "Tie::Trace", caller => [1, 2, 3];

It display following messages.

 Hash => Key: key, Value:hoge at filename line 61.
 at filename line 383.
 at filename line 268.

=back

=head1 METHODS

It is used in coderef which is passed for options, for example,
key, value and/or debug_value or as the method of the returned of tied fucntion.

=over 4

=item storage

 tie %hash, "Tie::Trace", debug =>
   sub {
     my($self, $v) = @_;
     my $storage = $self->storage;
     return $storage;
   };

This returns reference in which value(s) stored.

=item parent

 tie %hash, "Tie::Trace", debug =>
   sub {
     my($self, $v) = @_;
     my $parent = $self->parent->storage;
     return $parent;
   };

This method returns $self's parent tied value.

for example;

 tie my %hash, "Tie::Trace";
 my %hash2;
 $hash{1} = \%hash2;
 my $tied_hash2 = tied %hash2;
 print tied %hash eq $tied_hash2->parent; # 1

=back

=head1 AUTHOR

Ktat, C<< <atusi at pure.ne.jp> >>

=head1 BUGS

Please report any bugs or feature requests to
C<bug-tie-debug at rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Tie-Trace>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Tie::Trace

You can also find documentation written in Japanese(euc-jp) for this module
with the perldoc command.

    perldoc Tie::Trace_JP

You can also look for information at:

=over 4

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Tie-Trace>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Tie-Trace>

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Tie-Trace>

=item * Search CPAN

L<http://search.cpan.org/dist/Tie-Trace>

=back

=head1 COPYRIGHT & LICENSE

Copyright 2006 Ktat, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1; # End of Tie::Trace
