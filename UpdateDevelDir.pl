#!/usr/bin/perl
# --
# Copyright (C) 2001-2016 OTRS AG, http://otrs.com/
# --
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU AFFERO General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA
# or see http://www.gnu.org/licenses/agpl.txt.
# --

use strict;
use warnings;

use Getopt::Long;

# ----------------------------------------------------------------------
# config section
# ----------------------------------------------------------------------

my @DevelDirectories = (

    #    '/path/to/your/devel/directory/',
);

my @AditionalDevelDirectories = (

    #    '/path/to/your/directory/with/all/git/repositories/',
);

my @GitIgnore = (

    #    '/path/to/ignore/',
);

my $CodePolicyRegisterCommand = '/path/to/your/OTRSCodePolicy/scripts/install-git-hooks.pl';

# ----------------------------------------------------------------------

my ( $All, $Optimize, $Help );
GetOptions(
    'all'      => \$All,
    'optimize' => \$Optimize,
    'help'     => \$Help,
);

if ($Help) {
    print "Usage: UpdateDevelDir.pl [--all] [--optimize] [--help]\n";
    exit 0;
}

if ($All) {
    push @DevelDirectories, @AditionalDevelDirectories;
}

# get a list of all git directories and OTRSCodePolicy directories
my @GitDirectoryList;
my @CodePolicyDirectoryList;
for my $DevelDirectory (@DevelDirectories) {

    GitDirectoriesList(
        BaseDirectory           => $DevelDirectory,
        GitDirectoryList        => \@GitDirectoryList,
        CodePolicyDirectoryList => \@CodePolicyDirectoryList,
    );
}

my @GitDirsClean;
my @GitDirsAdeadOfRemote;
my @GitDirsModified;
my @GitDirsUpdated;

# looks, what directories are modified or clean
DIRECTORY:
for my $Directory ( sort @GitDirectoryList ) {

    next DIRECTORY if !$Directory;
    next DIRECTORY if !-d $Directory;

    my $GitStatusOutput = `cd $Directory && git status`;

    if ( $GitStatusOutput =~ m{ \QYour branch is ahead of\E }xms ) {
        push @GitDirsAdeadOfRemote, $Directory;
    }

    # different output between git versions
    # git 2.9: nothing to commit, working tree clean
    # git 2.x: nothing to commit, working directory clean
    # git 1.x: nothing to commit (working directory clean)
    elsif (
        $GitStatusOutput =~ m{
            nothing \s* to \s* commit ,?
            \s* \(? \s* working \s* (?: directory | tree ) \s* clean \s* \)?
        }xms
        )
    {
        push @GitDirsClean, $Directory;
    }
    else {
        push @GitDirsModified, $Directory;
    }
}

# update clean directories
DIRECTORY:
for my $Directory ( sort @GitDirsClean ) {

    next DIRECTORY if !$Directory;
    next DIRECTORY if !-d $Directory;

    my $GitRemoteOutput = `cd $Directory && git remote`;

    next DIRECTORY if !$GitRemoteOutput;

    print STDOUT "Updating clean directory $Directory\n";

    my $GitUpdateOutput = `cd $Directory && git pull && git remote prune origin`;

    next DIRECTORY if $GitUpdateOutput =~ m{ \QAlready up-to-date.\E }xms;

    COUNT:
    for my $Count ( 1 .. 10 ) {

        my $GitPullOutput = `cd $Directory && git pull`;

        next COUNT if $GitPullOutput !~ m{ \QAlready up-to-date.\E }xms;

        push @GitDirsUpdated, $Directory;

        last COUNT;
    }

    # cleanup local git repository
    if ($Optimize) {
        my $GitGcOutput = `cd $Directory && git gc > /dev/null 2>&1`;
    }
}

# register OTRS code policy
DIRECTORY:
for my $Directory (@CodePolicyDirectoryList) {

    next DIRECTORY if !$Directory;
    next DIRECTORY if !-d $Directory;

    my $CodePolicyRegisterOutput = `cd $Directory && $CodePolicyRegisterCommand`;
}

my $InspectedDirectories = scalar @GitDirectoryList;

print STDOUT "\nSUMMARY\n";
print STDOUT "$InspectedDirectories directories inspected\n";

if (@GitDirsUpdated) {

    print STDOUT "\nUpdated directories:\n";

    for my $Dir ( sort @GitDirsUpdated ) {
        print STDOUT "   $Dir\n";
    }
}

if (@GitDirsModified) {

    print STDOUT "\nModified directories:\n";

    for my $Dir ( sort @GitDirsModified ) {
        print STDOUT "   $Dir\n";
    }
}

if (@GitDirsAdeadOfRemote) {

    print STDOUT "\nAheadOfRemote directories:\n";

    for my $Dir ( sort @GitDirsAdeadOfRemote ) {
        print STDOUT "   $Dir\n";
    }
}

print STDOUT "\n";

=item GitDirectoriesList()

returns a list of all git directories

    GitDirectoriesList(
        GitDirectoryList        => \@GitDirectoryList,
        CodePolicyDirectoryList => \@CodePolicyDirectoryList,
    );

=cut

sub GitDirectoriesList {
    my %Param = @_;

    return if !$Param{BaseDirectory};
    return if !-d $Param{BaseDirectory};

    return if !$Param{GitDirectoryList};
    return if ref $Param{GitDirectoryList} ne 'ARRAY';

    return if !$Param{CodePolicyDirectoryList};
    return if ref $Param{CodePolicyDirectoryList} ne 'ARRAY';

    my %IgnoreDirectories;
    DIRECTORY:
    for my $Directory (@GitIgnore) {

        next DIRECTORY if !$Directory;

        $Directory =~ s{\/\/}{/}xmsgi;

        $IgnoreDirectories{$Directory} = 1;
    }

    my @Glob = glob "$Param{BaseDirectory}/*";

    DIRECTORY:
    for my $Directory (@Glob) {

        next DIRECTORY if !$Directory;

        $Directory =~ s{\/\/}{/}xmsgi;

        next DIRECTORY if $IgnoreDirectories{$Directory};

        for my $DevelDir (@DevelDirectories) {
            next DIRECTORY if $Directory eq $DevelDir;
        }

        next DIRECTORY if !-d "$Directory/.git";

        push @{ $Param{GitDirectoryList} }, $Directory;

        # look, if an sopm exists
        my @SOPMs = glob "$Directory/*.sopm";

        next DIRECTORY if $Directory !~ m{ \/otrs }xms && !@SOPMs;

        push @{ $Param{CodePolicyDirectoryList} }, $Directory;
    }

    return;
}

exit 0;
