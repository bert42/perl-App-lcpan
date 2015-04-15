package App::lcpan::Cmd::modules;

# DATE
# VERSION

use 5.010;
use strict;
use warnings;

require App::lcpan;

our %SPEC;

$SPEC{':package'} = {
    v => 1.1,
    summary => "'modules' command",
};

$SPEC{handle_cmd} = $App::lcpan::SPEC{modules};
*handle_cmd = \&App::lcpan::modules;

1;
# ABSTRACT: