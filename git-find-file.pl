#!/usr/bin/perl
# --
# module-tools/git-find-file.pl - script to locate a file in the git history
# Copyright (C) 2001-2012 OTRS AG, http://otrs.org/
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
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
# or see http://www.gnu.org/licenses/agpl.txt.
# --

=head1 NAME

git-find-file.pl - script to to locate a file in the git history

=head1 SYNOPSIS

git-find-file.pl -r <git repository path> -f <relative filename in repository> -t <target file to locate>

=head1 DESCRIPTION

=head1 SUBROUTINES

=over 4

=cut

use strict;
use warnings;

use Getopt::Std;
use String::Similarity;

use vars qw($VERSION);
$VERSION = qw($Revision: 1.30 $) [1];

# get options
my %Opts = ();
getopt('rfth', \%Opts);

# set default
if (!$Opts{'r'} || !$Opts{f} || !$Opts{t}) {
    $Opts{'h'} = 1;
}

# show the help screen
if ( $Opts{'h'} ) {
    print <<EOF;
Copyright (C) 2001-2013 OTRS AG, http://otrs.org/
usage: git-find-file.pl -r <git repository path> -f <relative filename in repository> -t <target file to locate>
EOF
    exit 1;
}

chdir($Opts{r}) || die "Could not change working directory to $Opts{r}. $!";

my @FileRevisions = split(/\n/, `git rev-list --all $Opts{f}`);

print "Found " . (scalar @FileRevisions) . " existing revisions in git history.\n";

my %FileContents;
for my $FileRevision (@FileRevisions) {
    $FileContents{$FileRevision} = `git show $FileRevision:$Opts{f} 2>/dev/null`;
}

my $TargetFileHandle;
if ( !open $TargetFileHandle, '<', $Opts{t} ) {
   print "Can't open '$Opts{t}': $!\n";
   exit 1;
}

my $TargetFileContents = do { local $/; <$TargetFileHandle> };
close $TargetFileHandle;

print "Checking for direct matches in git history...\n";
my $DirectMatch;
for my $FileRevision (@FileRevisions) {
    if ($TargetFileContents eq $FileContents{$FileRevision}) {
        print $FileRevision . "\n";
        $DirectMatch++;
    }
}
exit 0 if $DirectMatch;

print "No direct matches found, checking similiarity index...\n";

my %SimilarityIndex;
for my $FileRevision (@FileRevisions) {
    my $Similarity =  similarity($TargetFileContents, $FileContents{$FileRevision});
    $SimilarityIndex{ $FileRevision } = $Similarity;
}

my @SimilarVersions = sort { $SimilarityIndex{$b} <=> $SimilarityIndex{$a} } keys %SimilarityIndex;
for my $FileRevision (splice @SimilarVersions, 0, 10) {
    print "$FileRevision " . sprintf("%.3f", $SimilarityIndex{$FileRevision} * 100) . "\n";
}

exit 0;
