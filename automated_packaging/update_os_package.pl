#!/usr/bin/perl
use lib '/usr/local/bin';
use common_functions;

$DISTRO_VERSION = $ARGV[0];
$PROJECT = $ARGV[1];
$VERSION = $ARGV[2];

# Name of the repo is represented differently on logs and repos
my $github_repo_name = "citus";
my $log_repo_name = "Citus";
if ( $PROJECT eq "enterprise" ) {
    $github_repo_name = "citus-enterprise";
    $log_repo_name = "Citus Enterprise";
}

my $github_token = get_and_verify_token();

# Debian branch has it's own changelog, we can get them through the CHANGELOG file of the code repo
sub get_changelog_for_debian {

    # Update project spec file
    @changelog_file = `curl --user "$github_token:x-oauth-basic" -H "Accept: application/vnd.github.v3.raw" -X GET 'https://api.github.com/repos/citusdata/$github_repo_name/contents/CHANGELOG.md' 2> /dev/null`;

    $first_version_has_seen = 0;
    my @changelog_items;
    foreach $line (@changelog_file) {
        if ( $line =~ /^#/ ) {
            if ( $first_version_has_seen == 1 ) {
                last;
            }

            $first_version_has_seen += 1;
        }
        elsif ( $line =~ /^\*/ ) {
            $line =~ tr/\`//d;
            push( @changelog_items, '  ' . $line );
        }
        else {
            push( @changelog_items, $line );
        }
    }

    return @changelog_items;
}

# Necessary to write log date for both distros and create unique branch
my @abbr_mon = qw(Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec);
my @abbr_day = qw(Sun Mon Tue Wed Thu Fri Sat);
my ( $sec, $min, $hour, $mday, $mon, $year, $wday, $yday, $isdst ) =
  localtime(time);
$year += 1900;

# Necessary to create unique branch
$curTime = time();

# Checkout the distro's branch
`git checkout $DISTRO_VERSION-$PROJECT`;

# Create a new branch based on the distro's branch
`git checkout -b $DISTRO_VERSION-$PROJECT-push-$curTime`;

# Update pkgvars
`sed -i 's/^pkglatest.*/pkglatest=$VERSION.citus-1/g' pkgvars`;

# Based on the repo, update the package related variables
if ( $DISTRO_VERSION eq "redhat" ) {
    `sed -i 's|^Version:.*|Version:	$VERSION.citus|g' $github_repo_name.spec`;
    `sed -i 's|^Source0:.*|Source0:       https:\/\/github.com\/citusdata\/$github_repo_name\/archive\/v$VERSION.tar.gz|g' $github_repo_name.spec`;
    `sed -i 's|^%changelog|%changelog\\n* $abbr_day[$wday] $abbr_mon[$mon] $mday $year - Burak Velioglu <velioglub\@citusdata.com> $VERSION.citus-1\\n- Update to $log_repo_name $VERSION\\n|g' $github_repo_name.spec`;
}
elsif ( $DISTRO_VERSION eq "debian" ) {
    open( DEB_CLOG_FILE, "<./debian/changelog" ) || die "Debian changelog file not found";
    my @lines = <DEB_CLOG_FILE>;
    close(DEB_CLOG_FILE);

    # Change hour and get changelog (TODO: may update it !)
    $print_hour = $hour - 3;
    @changelog_print = get_changelog_for_debian();

    # Update the changelog file of the debian branch
    open( DEB_CLOG_FILE, ">./debian/changelog" ) || die "Debian changelog file not found";
    print DEB_CLOG_FILE "$github_repo_name ($VERSION.citus-1) stable; urgency=low\n";
    print DEB_CLOG_FILE @changelog_print;
    print DEB_CLOG_FILE " -- Burak Velioglu <velioglub\@citusdata.com>  $abbr_day[$wday], $mday $abbr_mon[$mon] $year $print_hour:$min:$sec +0000\n\n";
    print DEB_CLOG_FILE @lines;
    close(DEB_CLOG_FILE);
}

# Commit, push changes and open a pull request
`git commit -a -m "Bump $DISTRO_VERSION $log_repo_name $VERSION"`;
`git push origin $DISTRO_VERSION-$PROJECT-push-$curTime`;
`curl -g -H "Accept: application/vnd.github.v3.full+json" -X POST --user "$github_token:x-oauth-basic" -d '{\"title\":\"Bump $PROJECT $DISTRO_VERSION Version\", \"head\":\"$DISTRO_VERSION-$PROJECT-push-$curTime\", \"base\":\"$DISTRO_VERSION-$PROJECT\"}' https://api.github.com/repos/citusdata/packaging/pulls`;
