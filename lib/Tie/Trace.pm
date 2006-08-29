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

sub AUTOLOAD{
  # proxy to Tie::Std***
  my($self, @args) = @_;
  my($class, $method) = (split /::/, $AUTOLOAD)[2, 3];
  my $sub = \&{'Tie::Std' . $class . '::' . $method};
  defined &$sub ? $sub->($self->{storage}, @args) : return;
}

sub _carp_off{ 1 };

sub _carpit{
  my($self, %args) = @_;
  my($filename, $line) = (caller 1)[1, 2];
  my $class = (split /::/, ref $self)[2];
  my $location = " in $filename at line $line.\n";
  my $op = $self->{options} || {};

  # key/value checking
  foreach my $k (qw/key value/){
    if($args{$k} and my $target = $op->{$k}){
      return unless grep ref $_ eq 'Regexp' ? $args{$k} =~ $_ : $_ eq $args{$k}, @$target;
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
  my $ancestor = $arg{ancestor};
  my $options;
  if(defined $ancestor and $ancestor){
    $options = $ancestor->{options};
  }else{
    $options = \%arg;
    unless($options->{use}){
      $options->{use} = [qw/scalar array hash/];
    }
    unless(defined $options->{r}){
      $options->{r} = 1;
    }
  }
  my $_self =
    {
     self     => $self,
     ancestor => $ancestor,
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
      tie $$structure, "Tie::Trace::Scalar", ancestor => $self;
      $$structure = Tie::Trace::_data_filter($tmp, $self);
      return $structure;
    }elsif(($type & 0b11010) == 2){
      my @tmp = @$structure;
      tie @$structure, "Tie::Trace::Array", ancestor => $self;
      foreach my $i (0 .. $#tmp){
        $structure->[$i] = Tie::Trace::_data_filter($tmp[$i], $self);
      }
      return $structure;
    }elsif(($type & 0b11100) == 4){
      my %tmp = %$structure;
      tie %$structure, "Tie::Trace::Hash", ancestor => $self;
      while(my($k, $v) = each %tmp){
        $structure->{$k} = Tie::Trace::_data_filter($v, $self);
      }
      return $structure;
    }
  }
  # tied / blessed ref / just a scalar
  return $structure;
}

# Hash /////////////////////////
package Tie::Trace::Hash;

use warnings;
use strict;

use base qw/Tie::Trace/;

sub TIEHASH{ Tie::Trace::_tieit({}, @_) }

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

sub TIEARRAY{ Tie::Trace::_tieit([], @_); }

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

sub TIESCALAR{ my $s; Tie::Trace::_tieit(\$s, @_); }

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

Version 0.01

=cut

our $VERSION = '0.01';

=head1 SYNOPSIS

    use Tie::Trace;
 
    my %hash;
    tie %hash, "Tie::Trace::Hash";
 
    $hash{hoge} = 'hogehoge'; # warn Hash => Key: hoge, Value: hogehgoe
 
    my @array;
    tie @aray, "Tie::Trace::Array";
    push @array, "array";    # warn Array => Point: 0, Value: array
 
    my $scalar;
    tie $scalar, "Tie::Trace::Scalar";
    $scalar = "scalar";      # warn Scalar => Value: scalar

=head1 DESCRIPTION

This is usefull for print debugging. Using tie mechanism,
you can see sotred value for the specified variable.

If the stored value is scalar/array/hash ref, this can check
recursively.

for example;

 tie %hash, "Tie::Trace::Hash";
 
 $hash{foo} = {a => 1, b => 2}; # warn ...
 $hash{foo}->{a} = 2            # warn ...

But This won't care blessed reference or tied value.

=head1 OPTIONS

=over 4

=item key => [values/regexs]

 tie %hash, "Tie::Trace::Hash", key => [qw/foo bar/];

It is for hash. You can spedify key name/regex for checking.
Not specified/matched keys are ignored for warning.

for example;

 tie %hash, "Tie::Trace::Hash", key => [qw/foo bar/, qr/x/];
 
 $hash{foo} = 1 # warn ...
 $hash{bar} = 1 # warn ...
 $hash{var} = 1 # *no* warnings
 $hash{_x_} = 1 # warn ...

=item value => [contents/regexs]

 tie %hash, "Tie::Trace::Hash", value => [qw/foo bar/];

You can spedify value's content/regex for checking.
Not specified/matched are ignored for warning.

for example;

 tie %hash, "Tie::Trace::Hash", key => [qw/foo bar/, qr/\)/];
 
 $hash{a} = 'foo'  # warn ...
 $hash{b} = 'foo1' # *no* warnings
 $hash{c} = 'bar'  # warn ...
 $hash{d} = ':-)'  # warn ...

=item use => [qw/hash array scalar/]

 tie %hash, "Tie::Trace::Hash", use => [qw/array/];

It specify check type. As default, all type will be checked.

for example;

 tie %hash, "Tie::Trace::Hash", use => [qw/array/];
 
 $hash{foo} = 1         # *no* warnings
 $hash{bar} = 1         # *no* warnings
 $hash{var} = []        # *no* warnings
 push @{$hash{var}} = 1 # warn ...

=item debug => 'dumper'/coderef

 tie %hash, "Tie::Trace::Hash", debug => 'dumper'
 tie %hash, "Tie::Trace::Hash", debug => sub{my($self, @v) = @_; return @v }

It specify value representation. As default, just print value as scalar.
You can use "dumper" or coderef. "dumper" make value show with Data::Dumper::Dumper.
When you specify your coderef, its first argument is tied value and
second argument is value, it should modify it and return it.

=item r => 0/1

 tie %hash, "Tie::Trace::Hash", r => 0;

If r is 0, this won't check recusively. 1 is default.

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
