package App::DumpChromeHistory;

# AUTHORITY
# DATE
# DIST
# VERSION

use 5.010001;
use strict;
use warnings;
use Log::ger;

use File::chdir;

our %SPEC;

$SPEC{dump_chrome_history} = {
    v => 1.1,
    summary => 'Dump Chrome history',
    args => {
        detail => {
            schema => 'bool*',
            cmdline_aliases => {l=>{}},
        },
        profiles => {
            summary => 'Select profile(s) to dump',
            schema => ['array*', of=>'chrome::profile_name*', 'x.perl.coerce_rules'=>['From_str::comma_sep']],
            description => <<'_',

You can choose to dump history for only some profiles. By default, if this
option is not specified, history from all profiles will be dumped.

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
    require Chrome::Util::Profile;
    require DBI;
    require List::Util;

    my %args = @_;

    my $app = $args{_app} // 'Google Chrome';
    my $chrome_dir = $args{_chrome_dir};

    # list all available firefox profiles
    my $available_profiles;
    {
        my $res = Chrome::Util::Profile::list_chrome_profiles(
            _chrome_dir => $chrome_dir,
            detail => 1,
        );
        return $res unless $res->[0] == 200;
        $available_profiles = $res->[2];
    }

    my $num_profiles_success = 0;
    my $profiles = $args{profiles} // [map {$_->{name}} @$available_profiles];

    my @rows;
    my $resmeta = {};

  PROFILE:
    for my $profile (@$profiles) {
        log_trace "Dumping history for profile %s ...", $profile;
        my $profile_data = List::Util::first(sub { $_->{name} eq $profile }, @$available_profiles);
        unless ($profile_data) {
            log_error "Profile %s is unknown, skipped", $profile;
            next PROFILE;
        }

        my $profile_dir = $profile_data->{path};
        unless (-d $profile_dir) {
            log_error "Cannot find directory '%s' for profile %s, profile skipped", $profile_dir, $profile;
            next PROFILE;
        }

        local $CWD = $profile_dir;

        my $history_path = "History";
        unless (-f $history_path) {
            log_error "Cannot find history database file '%s' for profile %s, profile skipped", $history_path, $profile;
            next PROFILE;
        }

      SELECT: {
            eval {
                my $dbh = DBI->connect("dbi:SQLite:dbname=$history_path", "", "", {RaiseError=>1});
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
                if ((-s $history_path) <= $args{copy_size_limit}) {
                    log_debug "Database is locked ($err), will try to copy and query the copy instead ...";
                    require File::Copy;
                    require File::Temp;
                    my ($temp_fh, $temp_path) = File::Temp::tempfile();
                    File::Copy::copy($history_path, $temp_path) or die $err;
                    $history_path = $temp_path;
                    redo SELECT;
                } else {
                    log_debug "Database is locked ($err) but is too big, will wait instead";
                }
            }
        } # SELECT
    } # for profile

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
