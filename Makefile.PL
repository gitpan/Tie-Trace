use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'Tie::Trace',
    AUTHOR              => 'Ktat <ktat@cpan.org>',
    VERSION_FROM        => 'lib/Tie/Trace.pm',
    ABSTRACT_FROM       => 'lib/Tie/Trace.pm',
    PL_FILES            => {},
    PREREQ_PM => {
        'Test::More' => 0,
        'Test::Base' => 0,
	'PadWalker'  => 0,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'Tie-Trace-*' },
);
