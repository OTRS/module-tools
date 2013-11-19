#!/usr/bin/perl
# --
# CheckChangedFiles.pl - script for get changed file between different releases of OTRS
# Copyright (C) 2001-2013 OTRS AG, http://otrs.com/
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

CheckChangedFiles.pl - script for get changed file between different releases of OTRS

=head1 SYNOPSIS

CheckChangedFiles.pl -h
Get help dialog.

CheckChangedFiles.pl -r
Reduce to be checked files to core files.

CheckChangedFiles.pl -m
Path to a module where to check if files in there are affected.

CheckChangedFiles.pl [ -h | -r | -m /path/to/module ] /path/to/base/version /path/to/new/version

=head1 DESCRIPTION

Please send any questions, suggestions & complaints to <dev-support@otrs.com>

=cut

use strict;
use warnings;

## nofilter(TidyAll::Plugin::OTRS::Perl::PerlCritic)

use Getopt::Long;
use Pod::Usage;
use File::Find;
use Digest::MD5 qw(md5_hex);

# check if help got requested
my ( $OptHelp, $ReducedCheck, $ModulePath );
GetOptions(
    'h'   => \$OptHelp,
    'm=s' => \$ModulePath,
    'r'   => \$ReducedCheck,
);
pod2usage( -verbose => 0 ) if $OptHelp;

# define whitelist for reduceded checks
my @ReducedChecks;
if ($ReducedCheck) {
    @ReducedChecks = qw(Kernel bin);
}

# get given params
my $BaseVersion = shift(@ARGV);
my $NewVersion  = shift(@ARGV);

# verify if the given params are not empty
die "Base version directory is not given." if !$BaseVersion;
die "New version directory is not given."  if !$NewVersion;

# verify that given params are existing directories
die "Directory $BaseVersion does not exist or is not a directory." if !-d $BaseVersion;
die "Directory $NewVersion does not exist or is not a directory."  if !-d $NewVersion;
if ($ModulePath) {
    die "Directory $ModulePath does not exist or is not a directory." if !-d $ModulePath;
}

# get list of files and their MD5 digests
my $BaseVersionFile2MD5 = FindFilesOfVersion($BaseVersion) || {};
my $NewVersionFile2MD5  = FindFilesOfVersion($NewVersion)  || {};
my $ModuleVersionFile2MD5;
if ($ModulePath) {
    $ModuleVersionFile2MD5 = FindFilesOfVersion($ModulePath) || {};
}

# get list of deleted and new files
my @DeletedFiles = grep { !defined $NewVersionFile2MD5->{$_} } sort keys %{$BaseVersionFile2MD5};
my @NewFiles     = grep { !defined $BaseVersionFile2MD5->{$_} } sort keys %{$NewVersionFile2MD5};

# get list of to be checked files
my %CheckFileList = %{$BaseVersionFile2MD5};
map { delete $CheckFileList{$_} } @DeletedFiles;

# get list of changed files
my @ChangedFiles = grep { $BaseVersionFile2MD5->{$_} ne $NewVersionFile2MD5->{$_} }
    sort keys %CheckFileList;

# produce output if data had been gathered
if (@DeletedFiles) {
    print '==============================';
    print 'List of deleted files (#', scalar @DeletedFiles, '):';
    map { print "\t$_" } @DeletedFiles;
}

if (@NewFiles) {
    print '==============================';
    print 'List of new files (#', scalar @NewFiles, '):';
    map { print "\t$_" } @NewFiles;
}

if (@ChangedFiles) {
    print '==============================';
    print 'List of changed files (#', scalar @ChangedFiles, '):';
    map { print "\t$_" } @ChangedFiles;
}

# module has been given
if ($ModuleVersionFile2MD5) {

    # get list of changed files of the given module
    my @ChangedModuleFiles = grep {
        $ModuleVersionFile2MD5->{$_} && $ModuleVersionFile2MD5->{$_} ne $NewVersionFile2MD5->{$_}
    } sort keys %CheckFileList;

    print '==============================';
    print 'List of changed files module (#', scalar @ChangedModuleFiles, '):';
    map { print "\t$_" } @ChangedModuleFiles;
}

=item FindFilesOfVersion()

Returns a HASHREF with file names as key and its MD5 hex digest as value.
It strips out the root directory from the file name.

my $FileName2MD5 = FindFilesOfVersion( '/ws/otrs-head' );

results will look like:
$FileName2MD5 = {
    'Kernel/System/Main.pm' => '7731615a697d7ed0da2579a9c71d7d9c',
};

=cut

sub FindFilesOfVersion {
    my $VersionDirectory = shift;

    # check directory path
    return if !$VersionDirectory;
    return if !-d $VersionDirectory;

    # define function for traversing
    my %VersionFile2MD5;
    my $FindFilesOfVersion = sub {
        my $FileName = $File::Find::name;

        # only return valid files
        return if !-f $FileName;

        # have directory in, may be there CVS is contained
        return if $FileName =~ m{ \A $VersionDirectory [/]? .* CVS }xms;

        # get file name without root path and possible tailing '/'
        my ($PackageName) = $FileName =~ m{\A $VersionDirectory (?: / )? (.*) \z}xms;

        # consider customized files for OTRS 2.4 in Kernel/Custom/
        $PackageName =~ s{ Kernel/Custom/ }{}xms;

        # check for reduceded file checking
        return if @ReducedChecks && !grep { $PackageName =~ m{\A $_ }xms } @ReducedChecks;

        # create file handle for digest function
        open my $FH, '<', $FileName or return;
        binmode $FH;
        $VersionFile2MD5{$PackageName} = Digest::MD5->new()->addfile($FH)->hexdigest();
        close $FH;
    };

    # start gathering filelist
    find( $FindFilesOfVersion, $VersionDirectory );

    return \%VersionFile2MD5;
}
