# --
# Copyright (C) 2001-2018 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Console::Command::Git::File::Find;

use strict;
use warnings;

use String::Similarity;
use File::Spec();

use parent qw(Console::BaseCommand);

=head1 NAME

Console::Command::Git::File::Find - Console command to locate a file in the git repository history

=head1 DESCRIPTION

Locates a direct or similar matches of a given file into a git repository history

=cut

sub Configure {
    my ( $Self, %Param ) = @_;

    $Self->Description('Locate a direct or similar git commit matches of a given file.');
    $Self->AddOption(
        Name        => 'source-path',
        Description => "Specify the base file in the git repository.",
        Required    => 1,
        HasValue    => 1,
        ValueRegex  => qr/.*/smx,
    );
    $Self->AddOption(
        Name        => 'target-path',
        Description => "Specify the target file to be locate.",
        Required    => 1,
        HasValue    => 1,
        ValueRegex  => qr/.*/smx,
    );

    return;
}

sub PreRun {
    my ($Self) = @_;

    my @Directories = (
        File::Spec->rel2abs( $Self->GetOption('source-path') ),
        File::Spec->rel2abs( $Self->GetOption('target-path') ),
    );

    for my $Directory (@Directories) {
        if ( !-e $Directory ) {
            die "$Directory does not exist";
        }
    }

    return;
}

sub Run {
    my ($Self) = @_;

    $Self->Print("\n<yellow>Finding file in git history...</yellow>\n");

    my $SourcePath = File::Spec->rel2abs( $Self->GetOption('source-path') );
    my $TargetPath = File::Spec->rel2abs( $Self->GetOption('target-path') );

    my @Directories = split( '/', $SourcePath );
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
        $Self->PrintError("Could not find a git repository in path $SourcePath.\n");
        return $Self->ExitCodeError();
    }

    # Change to git repository directory.
    if ( !chdir($RepositoryDirectory) ) {
        $Self->PrintError("Could not change working directory to RepositoryDirectory. $!\n");
        return $Self->ExitCodeError();
    }

    # Get all revisions for the requested file.
    my @FileRevisions = split( /\n/, `git rev-list --all $RelativeFilename` );
    $Self->Print( "\n  Found <yellow>" . ( scalar @FileRevisions ) . "</yellow> existing revisions in git history.\n" );

    if ( !@FileRevisions ) {
        $Self->Print("\n<green>Done.</green>\n");
        return $Self->ExitCodeOk();
    }

    # Get the file contents for all revisions.
    my %FileContents;
    for my $FileRevision (@FileRevisions) {
        $FileContents{$FileRevision} = `git show $FileRevision:$RelativeFilename 2>1`;
    }

    # Get the content of the target file that should be found in the history.
    my $TargetFileHandle;
    if ( !open( $TargetFileHandle, '<', $TargetPath ) ) {    ## no critic
        $Self->PrintError("Can't open '$TargetFileHandle': $!\n");
        return $Self->ExitCodeError();
    }
    my $TargetFileContents = do { local $/; <$TargetFileHandle> };
    close $TargetFileHandle;

    $Self->Print("\n  <yellow>Checking for direct matches in git history...</yellow>\n");

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
            $Self->Print("    $FileRevision\n");
            $DirectMatch++;
        }
    }

    if ($DirectMatch) {
        $Self->Print("\n<green>Done.</green>\n");
        return $Self->ExitCodeOk();
    }

    $Self->Print("    No direct matches found.\n");
    $Self->Print("\n  <yellow>Checking similarity index...</yellow>\n");

    my %SimilarityIndex;
    for my $FileRevision (@FileRevisions) {
        my $Similarity = similarity( $TargetFileContents, $FileContents{$FileRevision} );
        $SimilarityIndex{$FileRevision} = $Similarity;
    }

    my @SimilarVersions = sort { $SimilarityIndex{$b} <=> $SimilarityIndex{$a} } keys %SimilarityIndex;
    for my $FileRevision ( splice @SimilarVersions, 0, 10 ) {
        $Self->Print(
            "    $FileRevision <yellow>" . sprintf( "%.3f", $SimilarityIndex{$FileRevision} * 100 ) . "%</yellow>\n"
        );
    }

    if ( !@SimilarVersions ) {
        $Self->Print("    No matches found.\n");
    }

    $Self->Print("\n<green>Done.</green>\n");
    return $Self->ExitCodeOk();
}

1;

=head1 TERMS AND CONDITIONS

This software is part of the OTRS project (L<http://otrs.org/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (AGPL). If you
did not receive this file, see L<http://www.gnu.org/licenses/agpl.txt>.

=cut
