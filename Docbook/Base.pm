# --
# Copyright (C) 2001-2017 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Docbook::Base;

use strict;
use warnings;

=head1 NAME

Docbook::Base - base class for Docbook generating scrips

=head1 SYNOPSIS

Text common functions.

=head1 PUBLIC INTERFACE

=over 4

=cut

sub _WriteDocbookFile {
    my ( $Self, %Param ) = @_;

    # check needed parameters
    for my $Needed (qw(Chapter XMLObject OutputLocation)) {
        if ( !$Param{$Needed} ) {
            print "Need $Needed:!";
            return;
        }
    }

    my $Chapter = $Param{Chapter};

    my $BookHeader = <<"XML";
<?xml version='1.0' encoding='utf-8'?>
<!DOCTYPE book PUBLIC "-//OASIS//DTD DocBook XML V4.4//EN"
    "http://www.oasis-open.org/docbook/xml/4.4/docbookx.dtd">

<book lang='en'>

XML

    my $BookFooter = <<"XML";

</book>
XML

    # assemble the final file content
    my $Book = $BookHeader . $Chapter . $BookFooter;

    # output
    print "Writing file $Param{OutputLocation}...";

    # write file in file system
    my $FileLocation = $Self->_FileWrite(
        Location => $Param{OutputLocation},
        Content  => \$Book,
        Mode     => 'utf8'
    );
    return if !$FileLocation;

    # check XML by reading it
    eval {
        $Param{XMLObject}->XMLin($FileLocation);
    };
    if ($@) {
        print "\nThere was an error in the output file XML structure: $@";
        return;
    }

    # output
    print "done\n\n";

    return 1
}

# from main.pm

=item _DirectoryRead()

reads a directory and returns an array with results.

    my @FilesInDirectory = _DirectoryRead(
        Directory => '/tmp',
        Filter    => 'Filenam*',
    );

    my @FilesInDirectory = _DirectoryRead(
        Directory => $Path,
        Filter    => '*',
    );

You can pass several additional filters at once:

    my @FilesInDirectory = _DirectoryRead(
        Directory => '/tmp',
        Filter    => \@MyFilters,
    );

Use the 'Silent' parameter to suppress messages when a directory
does not have to exist:

    my @FilesInDirectory = _DirectoryRead(
        Directory => '/special/optional/directory/',
        Filter    => '*',
        Silent    => 1,     # will not print errors if the directory does not exist
    );

=cut

sub _DirectoryRead {
    my ( $Self, %Param ) = @_;

    # check needed params
    for my $Needed (qw(Directory Filter)) {
        if ( !$Param{$Needed} ) {
            print "Needed $Needed: $!\n";
            return;
        }
    }

    # if directory doesn't exists stop
    if ( !-d $Param{Directory} && !$Param{Silent} ) {
        print "Directory doesn't exist: $Param{Directory}: $!";
        return;
    }

    # check Filter param
    if ( ref $Param{Filter} ne '' && ref $Param{Filter} ne 'ARRAY' ) {
        print 'Filter param need to be scalar or array ref!',
            return;
    }

    # prepare non array filter
    if ( ref $Param{Filter} ne 'ARRAY' ) {
        $Param{Filter} = [ $Param{Filter} ];
    }

    # executes glob for every filter
    my @GlobResults;
    my %Seen;

    for my $Filter ( @{ $Param{Filter} } ) {
        my @Glob = glob "$Param{Directory}/$Filter";

        # look for repeated values
        GLOBNAME:
        for my $GlobName (@Glob) {

            next GLOBNAME if !-e $GlobName;

            if ( !$Seen{$GlobName} ) {
                push @GlobResults, $GlobName;
                $Seen{$GlobName} = 1;
            }
        }
    }

    if ( $Param{Recursive} ) {

        # loop protection to prevent symlinks causing lockups
        $Param{LoopProtection}++;
        return if $Param{LoopProtection} > 100;

        # check all files in current directory
        my @Directories = glob "$Param{Directory}/*";

        DIRECTORY:
        for my $Directory (@Directories) {

            # return if file is not a directory
            next DIRECTORY if !-d $Directory;

            # repeat same glob for directory
            my @SubResult = $Self->_DirectoryRead(
                %Param,
                Directory => $Directory,
            );

            # add result to hash
            for my $Result (@SubResult) {
                if ( !$Seen{$Result} ) {
                    push @GlobResults, $Result;
                    $Seen{$Result} = 1;
                }
            }
        }
    }

    # if clean results
    return if !@GlobResults;

    # compose normalize every name in the file list
    my @Results;
    for my $Filename (@GlobResults) {

        #not sure if this is needed
        #        # first convert filename to utf-8 if utf-8 is used internally
        #        $Filename = $Self->{EncodeObject}->Convert2CharsetInternal(
        #            Text => $Filename,
        #            From => 'utf-8',
        #        );
        #
        #        # second, convert it to combined normalization form (NFC), if it is an utf-8 string
        #        # this has to be done because MacOS stores filenames as NFD on HFS+ partitions,
        #        #   leading to data inconsistencies
        #        if ( Encode::is_utf8($Filename) ) {
        #            $Filename = Unicode::Normalize::NFC($Filename);
        #        }

        push @Results, $Filename;
    }

    # always sort the result
    my @SortedResult = sort @Results;

    return @SortedResult;
}

=item _FileWrite()

to write data to file system

    my $FileLocation = _FileWrite(
        Directory => 'c:\some\location',
        Filename  => 'me_to/alal.xml',
        # or Location
        Location  => 'c:\some\location\me_to\alal.xml'

        Content   => \$Content,
    );

    my $FileLocation = _FileWrite(
        Directory  => 'c:\some\location',
        Filename   => 'me_to/alal.xml',
        # or Location
        Location   => 'c:\some\location\me_to\alal.xml'

        Content    => \$Content,
        Mode       => 'binmode', # binmode|utf8
        Type       => 'Local',   # optional - Local|Attachment|MD5
        Permission => '644',     # unix file permissions
    );

=cut

sub _FileWrite {
    my ( $Self, %Param ) = @_;

    if ( $Param{Filename} && $Param{Directory} ) {

        # filename clean up
        $Param{Filename} = $Self->FilenameCleanUp(
            Filename => $Param{Filename},
            Type     => $Param{Type} || 'Local',    # Local|Attachment|MD5
        );
        $Param{Location} = "$Param{Directory}/$Param{Filename}";
    }
    elsif ( $Param{Location} ) {

        # filename clean up
        $Param{Location} =~ s/\/\//\//g;
    }
    else {
        print 'Need Filename and Directory or Location!';
    }

    # set open mode (if file exists, lock it on open, done by '+<')
    my $Exists;
    if ( -f $Param{Location} ) {
        $Exists = 1;
    }
    my $Mode = '>';
    if ($Exists) {
        $Mode = '+<';
    }
    if ( $Param{Mode} && $Param{Mode} =~ /^(utf8|utf\-8)/i ) {
        $Mode = '>:utf8';
        if ($Exists) {
            $Mode = '+<:utf8';
        }
    }

    # return if file can not open
    my $FH;
    if ( !open $FH, $Mode, $Param{Location} ) {    ## no critic
        print STDERR "ERROR: Can't write '$Param{Location}': $!";
        return;
    }

    # lock file (Exclusive Lock)
    if ( !flock $FH, 2 ) {
        print "Can't lock '$Param{Location}': $!"
    }

    # empty file first (needed if file is open by '+<')
    truncate $FH, 0;

    # not sure if this is needed
    #    # enable binmode
    #    if ( !$Param{Mode} || lc $Param{Mode} eq 'binmode' ) {
    #
    #        # make sure, that no utf8 stamp exists (otherway perl will do auto convert to iso)
    #        $Self->{EncodeObject}->EncodeOutput( $Param{Content} );
    #
    #        # set file handle to binmode
    #        binmode $FH;
    #    }

    # write file if content is not undef
    if ( defined ${ $Param{Content} } ) {
        print $FH ${ $Param{Content} };
    }

    # write empty file if content is undef
    else {
        print $FH '';
    }

    # close the filehandle
    close $FH;

    # set permission
    if ( $Param{Permission} ) {
        if ( length $Param{Permission} == 3 ) {
            $Param{Permission} = "0$Param{Permission}";
        }
        chmod( oct( $Param{Permission} ), $Param{Location} );
    }

    return $Param{Filename} if $Param{Filename};
    return $Param{Location};
}

=back

=head1 TERMS AND CONDITIONS

This software is part of the OTRS project (L<http://otrs.org/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (AGPL). If you
did not receive this file, see L<http://www.gnu.org/licenses/agpl.txt>.

=cut

1;
