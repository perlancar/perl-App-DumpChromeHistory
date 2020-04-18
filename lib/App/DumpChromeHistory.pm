package App::DumpChromeHistory;

# AUTHORITY
# DATE
# DIST
# VERSION

use 5.010001;
use strict;
use warnings;
use Log::ger;

our %SPEC;

$SPEC{dump_chrome_history} = {
    v => 1.1,
    summary => 'Dump Chrome history',
    args => {
        detail => {
            schema => 'bool*',
            cmdline_aliases => {l=>{}},
        },
        profile => {
            summary => 'Select profile to use',
            schema => 'str*',
            default => 'Default',
            description => <<'_',

You can either provide a name, e.g. `Default`, the profile directory of which
will be then be searched in `~/.config/google-chrome/<name>`. Or you can also
provide a directory name.

_
        },
        copy_size_limit => {
            schema => 'posint*',
            default => 100*1024*1024,
            description => <<'_',

Chrome often locks the History database for a long time. If the size of the
database is not too large (determine by checking against this limit), then the
script will copy the file to a temporary file and extract the data from the
copied database.

_
        },
    },
};
sub dump_chrome_history {
    require DBI;

    my %args = @_;

    my ($profile, $profile_dir, $hist_path);
    $profile = $args{profile} // 'default';

  GET_PROFILE_DIR:
    {
        if ($profile =~ /\A\w+\z/) {
            # search profile name in profiles directory
            $profile_dir = "$ENV{HOME}/.config/google-chrome/$profile";
            return [412, "No such directory '$profile_dir'"]
                unless -d $profile_dir;
        } elsif (-d $profile) {
            $profile_dir = $profile;
        } else {
            return [412, "No such profile/profile directory '$profile'"];
        }
        $hist_path = "$profile_dir/History";
        return [412, "Not a profile directory '$profile_dir': no History inside"]
            unless -f $hist_path;
    }

    my @rows;
    my $resmeta = {};
  SELECT: {
        eval {
            my $dbh = DBI->connect("dbi:SQLite:dbname=$hist_path", "", "", {RaiseError=>1});
            $dbh->sqlite_busy_timeout(3*1000);
            my $sth = $dbh->prepare("SELECT url,last_visit_time,visit_count FROM urls ORDER BY last_visit_time");
            $sth->execute;
            while (my $row = $sth->fetchrow_hashref) {
                if ($args{detail}) {
                    push @rows, $row;
                } else {
                    push @rows, $row->{url};
                }
            }
        };
        my $err = $@;
        if ($err && $err =~ /database is locked/) {
            if ((-s $hist_path) <= $args{copy_size_limit}) {
                log_debug "Database is locked ($err), will try to copy and query the copy instead ...";
                require File::Copy;
                require File::Temp;
                my ($temp_fh, $temp_path) = File::Temp::tempfile();
                File::Copy::copy($hist_path, $temp_path) or die $err;
                $hist_path = $temp_path;
                redo SELECT;
            } else {
                log_debug "Database is locked ($err) but is too big, will wait instead";
            }
        }
    }

    $resmeta->{'table.fields'} = [qw/url title last_visit_time visit_count/]
        if $args{detail};
    [200, "OK", \@rows, $resmeta];
}

1;
# ABSTRACT:

=head1 SYNOPSIS

See the included script L<dump-chrome-history>.


=head1 SEE ALSO

L<App::DumpFirefoxHistory>

L<App::DumpOperaHistory>
