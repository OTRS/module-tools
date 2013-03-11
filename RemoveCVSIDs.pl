#!/usr/bin/perl
# --
# module-tools/RemoveCVSIDs.pl - script to remove $Ids used for CVS
# TODO: ( and to convert $OldId and $OldId2 etc to Origin: labels)
#
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

RemoveCVSIDs.pl - script to remove $Ids used for CVS

=head1 SYNOPSIS

RemoveCVSIDs.pl -p <Framework-Path>

=head1 DESCRIPTION

Removes the Line that shows the CVS ID ($Id) in the header line of a file.

=head1 SUBROUTINES

=over 4

=cut

use strict;
use warnings;

use Getopt::Std;
use File::Find;

use File::Temp qw( tempfile );

use vars qw($VERSION);
$VERSION = qw($Revision: 1.30 $) [1];

# get options
my %Opts = ();
getopt('ph', \%Opts);

# set default
if (!$Opts{'p'} ) {
    $Opts{'h'} = 1;
}

# show the help screen
if ( $Opts{'h'} ) {
    print "Copyright (C) 2001-2013 OTRS AG, http://otrs.org/\n";
    print "usage: RemoveCVSIDs.pl -p <Path>\n\n";
    exit 1;
}

# get the path
my $Path = $Opts{'p'} . '/';

# remove multiple slashes at the end
$Path =~ s{ /+ \z }{/}xms;

print "\n";

# recursively check and clean every file
find( \&CleanupFile, ($Path) );

1;

=item CleanupFile

Takes a filename from File::Find, and removes the CVS $Id line in the header of each file.

=cut

sub CleanupFile {

    # get current filename and directory from File::Find
    my $File = $File::Find::name;
    my $Dir  = $File::Find::dir;

    # skip directories
    return if -d $File;
    # skip linked files
    return if -l $File;
    # Only treat plain files
    return if !-f $File;

    # skip special directories:
    # CVS, git, cpan-lib, images, etc...
    return if $Dir =~ m{ / CVS | \.git | cpan-lib | thirdparty | images | img | icons | fonts | -cache /? }xms;

    # exclude some files:
    # images, fonts, .gitignore, .cvsignore, and others
    return if $File =~ m{ [.] ( png | psd | jpg | jpeg | gif | tiff | ttf | gitignore | cvsignore | odg | mwb | screen | story | pdf) \s* \z }ixms;

    # return if file can not be opened
    my $FH;
    if ( !open $FH, '<', $File ) {
       print "Can't open '$File': $!\n";
       exit;
    }

    # read file as string and close filehandle
    my $Content = do { local $/; <$FH> };
    close $FH;

    # remember the original content for later comparison
    my $OriginalContent = $Content;

    # remove $Id lines and the following separator line
    #
    # Perl files
    # $Id: Main.pm,v 1.69 2013-02-05 10:43:07 mg Exp $
    #
    # JavaScript files
    # // $Id: Core.Agent.Admin.DynamicField.js,v 1.11 2012-08-06 12:33:24 mg Exp $
    $Content =~ s{ ^ ( \# | // ) [ ] \$Id: [ ] .+? $ \n ( ^ ( \# | // ) [ ] -- $ \n )? }{}xmsg;

    # Postmaster-Test.box files
    # X-CVS: $Id: PostMaster-Test1.box,v 1.2 2007/04/12 23:55:55 martin Exp $
    $Content =~ s{ ^ X-CVS: [ ] \$Id: [ ] .+? $ \n }{}xmsg;

    # docbook and wsdl and other XML files
    # <!-- $Id: get-started.xml,v 1.1 2011-08-15 17:46:09 cr Exp $ -->
    $Content =~ s{ ^ <!-- [ ] \$Id: [ ] .+? $ \n }{}xmsg;

    # OTRS config files
    # <CVS>$Id: Framework.xml,v 1.519 2013-02-15 14:07:55 mg Exp $</CVS>
    $Content =~ s{ ^ \s* <CVS> \$Id: [ ] .+? $ \n }{}xmsg;

    # remove empty Ids
    # $Id:
    $Content =~ s{ ^ \# [ ] \$Id: $ \n }{}xmsg;

    # remove $Date $ tag
    $Content =~ s{ [ ]* \$Date: [^\$]+ \$ }{}xmsg;

#    # Set $Revision to '0.0.0'. This will be replaced on package build.
#    $Content =~ s{ \$Revision: [^\$]+ \$ }{\$Revision: 0.0.0\$}xmsg;

    # if nothing was changed, check the next file
    return 1 if $Content eq $OriginalContent;

    # try to open the file for writing
    if ( !open $FH, '>', $File ) {
       print "Can't write '$File': $!\n";
       exit;
    }

    # write the content and close file
    print $FH $Content;
    close $FH;

    # print name of changed file
    print "File: $File\n";

    return 1;
}

exit 0;

