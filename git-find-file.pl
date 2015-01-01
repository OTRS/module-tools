#!/usr/bin/perl
# --
# git-find-file.pl - script to locate a file in the git history
# Copyright (C) 2001-2015 OTRS AG, http://otrs.com/
# --
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU AFFERO General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301 USA
# or see http://www.gnu.org/licenses/agpl.txt.
# --

=head1 NAME

git-find-file.pl - script to to locate a file in the git history

=head1 SYNOPSIS

git-find-file.pl -f <filename in repository> -t <target file to locate>

=head1 DESCRIPTION

=head1 SUBROUTINES

=over 4

=cut

use strict;
use warnings;

use Getopt::Std;
use String::Similarity;
use File::Spec;

# get options
my %Opts = ();
getopt( 'fth', \%Opts );

# set default
if ( !$Opts{f} || !$Opts{t} ) {
    $Opts{'h'} = 1;
}

# show the help screen
if ( $Opts{'h'} ) {
    print <<EOF;
Copyright (C) 2001-2013 OTRS AG, http://otrs.org/
usage: git-find-file.pl -f <filename in repository> -t <target file to locate>
EOF
    exit 1;
}

# Try to split $Opts{f} into the git repository path and the relative filename
#   inside of this repository.
my @Directories = split( '/', $Opts{f} );
splice( @Directories, 0, 1 ) if $Directories[0] eq '';

my ( $RepositoryDirectory, $RelativeFilename );

COUNTER:
for my $Counter ( 1 .. scalar @Directories ) {
    my $Directory = "/" . File::Spec->catfile( @Directories[ 0 .. $Counter - 1 ] );
    if ( -d "$Directory/.git" ) {
        $RepositoryDirectory = $Directory;
        $RelativeFilename    = File::Spec->catfile( @Directories[ $Counter .. $#Directories ] );
        last COUNTER;
    }
}

if ( !$RepositoryDirectory ) {
    die "Could not find a git repository in path $Opts{f}.\n";
}

# Change to git repository directory.
chdir($RepositoryDirectory) || die "Could not change working directory to RepositoryDirectory. $!";

# Get all revisions for the requested file
my @FileRevisions = split( /\n/, `git rev-list --all $RelativeFilename` );
print "Found " . ( scalar @FileRevisions ) . " existing revisions in git history.\n";

# Get the file contents for all revisions.
my %FileContents;
for my $FileRevision (@FileRevisions) {
    $FileContents{$FileRevision} = `git show $FileRevision:$RelativeFilename 2>1`;
}

# Get the content of the target file that should be found in the history
## no critic
open( my $TargetFileHandle, '<', $Opts{t} ) || die "Can't open '$Opts{t}': $!\n";
## use critic
my $TargetFileContents = do { local $/; <$TargetFileHandle> };
close $TargetFileHandle;

print "Checking for direct matches in git history...\n";
my $DirectMatch;
for my $FileRevision (@FileRevisions) {

    # There is one thing that went wrong in the CVS->git migration.
    # The format of dates in CVS keyword expansion was YYYY/MM/DD,
    #   during the git migration it was changed to YYYY-MM-DD.
    # Compare against both versions to be able to find a file that comes
    #   from git or from older CVS directly.
    my $FileContentCVS = $FileContents{$FileRevision};
    $FileContentCVS =~ s{(\$ (?:Id:|Date:) .*? \d{4})-(\d{2})-(\d{2} .*? \$)}{$1/$2/$3}xmsg;

    if (
        $TargetFileContents eq $FileContents{$FileRevision}
        || $TargetFileContents eq $FileContentCVS
        )
    {
        print $FileRevision . "\n";
        $DirectMatch++;
    }
}
exit 0 if $DirectMatch;

print "No direct matches found, checking similiarity index...\n";

my %SimilarityIndex;
for my $FileRevision (@FileRevisions) {
    my $Similarity = similarity( $TargetFileContents, $FileContents{$FileRevision} );
    $SimilarityIndex{$FileRevision} = $Similarity;
}

my @SimilarVersions = sort { $SimilarityIndex{$b} <=> $SimilarityIndex{$a} } keys %SimilarityIndex;
for my $FileRevision ( splice @SimilarVersions, 0, 10 ) {
    print "$FileRevision " . sprintf( "%.3f", $SimilarityIndex{$FileRevision} * 100 ) . "\n";
}

exit 0;
