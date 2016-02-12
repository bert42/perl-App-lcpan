package App::lcpan::Cmd::doc;

# DATE
# VERSION

use 5.010;
use strict;
use warnings;

require App::lcpan;

our %SPEC;

$SPEC{'handle_cmd'} = {
    v => 1.1,
    summary => 'Show POD documentation of module/.pod/script',
    description => <<'_',

This command extracts module (.pm)/.pod/script from release tarballs and render
its POD documentation. Since the documentation is retrieved from the release
tarballs in the mirror, the module/.pod/script needs not be installed.

Note that currently this command has trouble finding documentation for core
modules because those are contained in perl release tarballs instead of release
tarballs of modules, and `lcpan` is currently not designed to work with those.

_
    args => {
        %App::lcpan::common_args,
        name => {
            summary => 'Module or script name',
            description => <<'_',

If the name matches both module name and script name, the module will be chosen.
To choose the script, use `--script` (`-s`).

_
            schema => 'str*',
            req => 1,
            pos => 0,
            completion => \&App::lcpan::_complete_content_package_or_script,
        },
        script => {
            summary => 'Look for script first',
            schema => ['bool', is=>1],
            cmdline_aliases => {s=>{}},
        },
        raw => {
            summary => 'Dump raw POD instead of rendering it',
            schema => ['bool', is=>1],
            cmdline_aliases => {r=>{}},
            tags => ['category:output'],
        },
    },
    examples => [
        {
            summary => 'Seach module/POD/script named Rinci',
            argv => ['Rinci'],
            test => 0,
            'x.doc.show_result' => 0,
        },
        {
            summary => 'Specifically choose .pm file',
            argv => ['Rinci.pm'],
            test => 0,
            'x.doc.show_result' => 0,
        },
        {
            summary => 'Specifically choose .pod file',
            argv => ['Rinci.pod'],
            test => 0,
            'x.doc.show_result' => 0,
        },
        {
            summary => 'Look for script first named strict',
            argv => ['-s', 'strict'],
            test => 0,
            'x.doc.show_result' => 0,
        },
        {
            summary => 'Dump the raw POD instead of rendering it',
            argv => ['--raw', 'Text::Table::Tiny'],
            test => 0,
            'x.doc.show_result' => 0,
        },
        # filter arg: rel to pick a specific release file
    ],
    deps => {
        prog => 'pod2man', # XXX unless when raw=1
    },
};
sub handle_cmd {
    my %args = @_;

    my $state = App::lcpan::_init(\%args, 'ro');
    my $dbh = $state->{dbh};

    my $name = $args{name};
    my $ext = '';
    $name =~ s!/!::!g;
    $ext = $1 if $name =~ s/\.(pm|pod)\z//;

    my @look_order;
    if ($args{script}) {
        @look_order = ('script', 'module');
    } else {
        @look_order = ('module', 'script');
    }

    my $row;
    for my $look (@look_order) {
        my @where;
        my @bind = ($name);
        if ($look eq 'module') {

            if ($ext eq 'pm') {
                push @where, "path LIKE '%.pm'";
            } elsif ($ext eq 'pod') {
                push @where, "path LIKE '%.pm'";
            }
            $row = $dbh->selectrow_hashref("SELECT
  content.path content_path,
  file.cpanid author,
  file.name release
FROM content
LEFT JOIN file ON content.file_id=file.id
WHERE package=?
".(@where ? " WHERE ".join(" AND ", @where) : "")."
ORDER BY content.size DESC
LIMIT 1", {}, @bind);
            last if $row;

        } elsif ($look eq 'script') {

            $row = $dbh->selectrow_hashref("SELECT
  content.path content_path,
  file.cpanid author,
  file.name release
FROM script
LEFT JOIN file ON script.file_id=file.id
LEFT JOIN content ON script.content_id=content.id
WHERE script.name=?
".(@where ? " WHERE ".join(" AND ", @where) : "")."
ORDER BY content.size DESC
LIMIT 1", {}, @bind);
            last if $row;

        }
    }

    return [404, "No such module/.pod/script"] unless $row;

    my $path = App::lcpan::_fullpath(
        $row->{release}, $state->{cpan}, $row->{author});

    # XXX needs to be refactored into common code
    my $content;
    if ($path =~ /\.zip$/i) {
        require Archive::Zip;
        my $zip = Archive::Zip->new;
        $zip->read($path) == Archive::Zip::AZ_OK()
            or return [500, "Can't read zip file '$path'"];
        $content = $zip->contents($row->{content_path});
    } else {
        require Archive::Tar;
        my $tar;
        eval {
            $tar = Archive::Tar->new;
            $tar->read($path); # can still die untrapped when out of mem
        };
        return [500, "Can't read tar file '$path': $@"] if $@;
        my ($obj) = $tar->get_files($row->{content_path});
        $content = $obj->get_content;
    }

    if ($args{raw}) {
        return [200, "OK", $content, {'cmdline.skip_format'=>1}];
    } else {
        return [200, "OK", $content, {
            "cmdline.page_result"=>1,
            "cmdline.pager"=>"pod2man | man -l -"}];
    }
}

1;
# ABSTRACT: