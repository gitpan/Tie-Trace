#!perl -T

use Test::More tests => 1;

BEGIN {
	use_ok( 'Tie::Trace' );
}

diag( "Testing Tie::Trace $Tie::Debug::VERSION, Perl $], $^X" );
