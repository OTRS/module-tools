#!/usr/bin/perl -wl
# --
# module-tools/FileListCheck.pl
#   - script for checking the file list in the .sopm file
# Copyright (C) 2001-2012 OTRS AG, http://otrs.org/
# --
# $Id: FileListCheck.pl,v 1.5 2012-11-20 19:16:58 mh Exp $
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

FileListCheck.pl - script for checking completeness of the file list in OPMS-files of packages.

=head1 SYNOPSIS

FileListCheck.pl -h

FileListCheck.pl /path/to/module

FileListCheck.pl /path/to/module -s       # include symlinked directories

=head1 DESCRIPTION

Please send any questions, suggestions & complaints to <dev-support@otrs.com>

=cut

use strict;
use warnings;

use Getopt::Long;
use Pod::Usage;
use File::Basename;
use File::Find;
use Data::Dumper;

# check if help got requested
my $OptHelp;
my $OptSymlink;
GetOptions(
    'h' => \$OptHelp,
    's' => \$OptSymlink,
);
pod2usage( -verbose => 2 ) if $OptHelp;

# check if directory exists
my $ModuleDirectory = shift;
die "Module directory not given!" if !$ModuleDirectory;
die "Module directory does not exist or is not a directory!" if !-d $ModuleDirectory;

# get name of module and check for existence
$ModuleDirectory =~ s{ /+ \z }{}xms;
my $ModuleName   = basename($ModuleDirectory);
my $SOPMFileName = $ModuleName . '.sopm';
my $SOPMFilePath = join '/', ( $ModuleDirectory, $SOPMFileName );
die "Couldn't find file '$SOPMFileName' in $ModuleDirectory - wrong directory?"
    if !-f $SOPMFilePath;

# get encoding of XML file
my $XMLHeadLine = `head -n1 $SOPMFilePath`;
my ($SOPMEncoding) = $XMLHeadLine =~ m{ encoding="( (?: iso | utf ) - .* )" }xms;

# set default encoding to UTF8
$SOPMEncoding ||= 'utf8';

# strip out dash(es) in encoding
$SOPMEncoding =~ s{ - }{}gxms;
my $FileMode = ":encoding($SOPMEncoding)";

# open file and set proper encoding for reading
die "Couldn't read from '$SOPMFilePath'!" if !open( my $FH, '<', $SOPMFilePath );
binmode( $FH, $FileMode );

# read only file list entries from sopm file
my @FileList;
while ( my $Line = <$FH> ) {
    if (
        $Line =~ m{ \A \s* <File .+ Location="( [^"]+ )" }xms
        && $1 !~ m{ \.dia \z }xms
        )
    {
        push @FileList, $1;
    }
}
close($FH);

# get current files of module
my @ModuleFiles;
my $ModuleFinder = sub {
    my $FileName = $File::Find::name;

    return if !-f $FileName;
    return if $FileName =~ m{\.project}xms;
    return if $FileName =~ m{SVN}xms;
    return if $FileName =~ m{\.svn}xms;
    return if $FileName =~ m{CVS}xms;
    return if $FileName =~ m{ $SOPMFileName \z}xms;
    return if $FileName =~ m{ \. dia \z }xms;

    push @ModuleFiles, $FileName;
};
find( { wanted => $ModuleFinder, follow => $OptSymlink }, $ModuleDirectory );

# get listed but not existing files
my @MissingFiles = grep { !-f $ModuleDirectory . '/' . $_ } @FileList;

# get rid of trailing module path
@ModuleFiles = grep { $_ =~ s{\A \Q$ModuleDirectory/\E }{}xms } @ModuleFiles;

# get missing file list entries
my %ModuleFileInFileList = map { $_ => 0 } @ModuleFiles;
map { $ModuleFileInFileList{$_} = 1 } @FileList;
my @MissingFileListEntries = grep { $ModuleFileInFileList{$_} == 0 } keys %ModuleFileInFileList;

# generate output
map { print "File '$_' is listed in SOPM, but missing in file system!" } @MissingFiles;
map { print "File '$_' is in the file system, but missing in the SOPM!" } @MissingFileListEntries;
print '###############################';
print '# Insert this into your sopm! #';
print '###############################';
map { print "        <File Permission=\"644\" Location=\"$_\"\/>" } sort @MissingFileListEntries;
