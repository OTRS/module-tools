# --
# Copyright (C) 2001-2018 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Console::Command::Module::Docbook::Check::Images;

use strict;
use warnings;

use File::Basename;

use parent qw(Console::BaseCommand);

=head1 NAME

Console::Command::Module::Docbook::Check::Images - Console command check if referenced images files in docbook exists in the file system.

=head1 DESCRIPTION

Text common functions.

=cut

sub Configure {
    my ( $Self, %Param ) = @_;

    $Self->Description('Check existence of images referenced in documentation.');
    $Self->AddOption(
        Name        => 'source-path',
        Description => "Specify the name source documentation file.",
        Required    => 1,
        HasValue    => 1,
        ValueRegex  => qr/.*/smx,
    );
    $Self->AddOption(
        Name        => 'images-directory',
        Description => "Specify the name directory where the images are stored.",
        Required    => 0,
        HasValue    => 1,
        ValueRegex  => qr/.*/smx,
    );

    return;
}

sub PreRun {
    my ($Self) = @_;

    my $SourcePath = $Self->GetOption('source-path');

    if ( !-e $SourcePath ) {
        die "$SourcePath does not exist";
    }
    if ( !-r $SourcePath ) {
        die "$SourcePath could not be read";
    }
    if ( -d $SourcePath ) {
        die "$SourcePath is not a file";
    }

    my $ImagesDirectory = $Self->GetOption('images-directory');

    if ( !$ImagesDirectory ) {
        $ImagesDirectory = dirname($SourcePath) . '/screenshots';
    }

    if ( !-e $ImagesDirectory ) {
        die "$ImagesDirectory does not exist";
    }
    if ( !-d $ImagesDirectory ) {
        die "$ImagesDirectory is not a directory";
    }

    return;
}

sub Run {
    my ($Self) = @_;

    $Self->Print("<yellow>Checking images...</yellow>\n\n");

    my $SourcePath = $Self->GetOption('source-path');

    # Read Docbook file.
    my $FH;
    my $Success = open( $FH, '<', $SourcePath );    ## no critic
    if ( !$Success ) {
        $Self->PrintError('Cannot open file');
        return $Self->ExitCodeError();
    }
    my @Content = <$FH>;
    close($FH);

    my %FoundImages;

    # Remember all image references
    for my $Line (@Content) {
        if ( $Line =~ m{fileref="(.*?\.png)"}smx ) {
            my $ImagePath     = $1;
            my $ImageFileName = basename($ImagePath);
            $FoundImages{$ImageFileName} = 1;
        }
    }

    my $ImagesDirectory = $Self->GetOption('images-directory');
    if ( !$ImagesDirectory ) {
        $ImagesDirectory = dirname($SourcePath) . '/screenshots';
    }
    my %Seen;
    my @GlobResults;

    # Read all images from the specified directory
    my @Glob = glob "$ImagesDirectory/*.png";

    NAME:
    for my $GlobName (@Glob) {
        next NAME if !-e $GlobName;
        $GlobName = basename($GlobName);
        if ( !$Seen{$GlobName} ) {
            push @GlobResults, $GlobName;
            $Seen{$GlobName} = 1;
        }
    }

    $Success = 1;

    IMAGEFILENAME:
    for my $ImageFileName ( sort keys %FoundImages ) {
        next IMAGEFILENAME if $Seen{$ImageFileName};
        $Self->Print("  <red>$ImageFileName</red> was not found!\n");
        $Success = 0;
    }
    if ( !$Success ) {
        $Self->Print("\n");
    }

    IMAGEFILENAME:
    for my $ImageFileName ( sort keys %Seen ) {
        next IMAGEFILENAME if $FoundImages{$ImageFileName};
        $Self->Print("  <yellow>$ImageFileName</yellow> exists in file system but its not in use!\n");
    }

    if ( !$Success ) {
        $Self->Print("\n<red>Fail.</red>\n");
        return $Self->ExitCodeError();
    }

    $Self->Print("\n<green>Done.</green>\n");
    return $Self->ExitCodeOk();
}

1;
