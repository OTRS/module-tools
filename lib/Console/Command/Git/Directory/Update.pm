# --
# Copyright (C) 2001-2019 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Console::Command::Git::Directory::Update;

use strict;
use warnings;

use parent qw(Console::BaseCommand Console::BaseDirectory);

=head1 NAME

Console::Command::Git::Directory::Update - Console command to update git directories

=head1 DESCRIPTION

Pulls and optimize git directories

=cut

sub Configure {
    my ( $Self, %Param ) = @_;

    $Self->Description('Update defined git repositories.');
    $Self->AddOption(
        Name        => 'optimize',
        Description => "Performs a git cleanup on directories.",
        Required    => 0,
        HasValue    => 0,
        ValueRegex  => qr/.*/smx,
    );
    $Self->AddOption(
        Name        => 'pull-only',
        Description => "Only performs a git pull on directories.",
        Required    => 0,
        HasValue    => 0,
        ValueRegex  => qr/.*/smx,
    );
    $Self->AddOption(
        Name        => 'all',
        Description => "Include additional directories and aliases defined in /etc/config.pl.",
        Required    => 0,
        HasValue    => 0,
        ValueRegex  => qr/.*/smx,
    );
    $Self->AddOption(
        Name        => 'directory',
        Description => "Specify a directory to update.",
        Required    => 0,
        HasValue    => 1,
        ValueRegex  => qr/.*/smx,
    );

    $Self->AddOption(
        Name        => 'directory-alias',
        Description => "Specify a directory alias to update.",
        Required    => 0,
        HasValue    => 1,
        Multiple    => 1,
        ValueRegex  => qr/.*/smx,
    );

    return;
}

sub PreRun {
    my ($Self) = @_;

    if ( $Self->GetOption('optimize') && $Self->GetOption('pull-only') ) {
        die "Could not use optimize and pull-only at the same time!\n\n";
    }

    return;
}

sub Run {
    my ($Self) = @_;

    $Self->Print("\n<yellow>Updating git directories...</yellow>\n");

    my %Config = %{ $Self->{Config}->{DevelDir} || {} };

    my @DevelDirectories = $Self->DevelDirectoriesGet();

    # Get a list of all git directories and OTRSCodePolicy directories.
    my @GitDirectoryList;
    my @CodePolicyDirectoryList;

    for my $DevelDirectory (@DevelDirectories) {

        $Self->GitDirectoriesList(
            BaseDirectory           => $DevelDirectory,
            GitDirectoryList        => \@GitDirectoryList,
            CodePolicyDirectoryList => \@CodePolicyDirectoryList,
            GitIgnore               => $Config{GitIgnore},
            DevelDirectories        => \@DevelDirectories,
        );
    }

    my @GitDirsClean;
    my @GitDirsAdeadOfRemote;
    my @GitDirsModified;

    $Self->GitDirectoriesAnalyze(
        GitDirectoryList     => \@GitDirectoryList,
        GitDirsClean         => \@GitDirsClean,
        GitDirsAdeadOfRemote => \@GitDirsAdeadOfRemote,
        GitDirsModified      => \@GitDirsModified,
    );

    my @GitDirsUpdated;

    my $SummaryComment = '';

    # Update clean directories.
    DIRECTORY:
    for my $Directory ( sort @GitDirsClean ) {

        next DIRECTORY if !$Directory;
        next DIRECTORY if !-d $Directory;

        my $GitRemoteOutput = `cd $Directory && git remote`;

        next DIRECTORY if !$GitRemoteOutput;

        my $Branch = `cd $Directory && git rev-parse --abbrev-ref HEAD`;
        $Branch =~ s{\s+}{}msxg;

        $Self->Print("  Updating clean directory <yellow>$Directory ($Branch)</yellow> \n");

        my $GitUpdateOutput;

        if ( $Self->GetOption('pull-only') ) {
            $GitUpdateOutput = `cd $Directory && git pull`;
            $SummaryComment  = 'in pull only mode';
        }
        else {
            $GitUpdateOutput = `cd $Directory && git pull && git remote prune origin`;

            next DIRECTORY if $GitUpdateOutput =~ m{ \QAlready up-to-date.\E }xms;

            COUNT:
            for my $Count ( 1 .. 10 ) {

                my $GitPullOutput = `cd $Directory && git pull`;

                next COUNT if $GitPullOutput !~ m{ \QAlready up-to-date.\E }xms;

                push @GitDirsUpdated, $Directory;

                last COUNT;
            }

            # Cleanup local git repository.
            if ( $Self->GetOption('optimize') ) {
                my $GitGcOutput    = `cd $Directory && git gc > /dev/null 2>&1`;
                my $SummaryComment = 'in optimize mode';
            }
        }
    }

    # Register OTRS code policy.
    DIRECTORY:
    for my $Directory (@CodePolicyDirectoryList) {

        next DIRECTORY if !$Directory;
        next DIRECTORY if !-d $Directory;

        my $CodePolicyRegisterOutput = `cd $Directory && $Config{CodePolicyRegisterCommand}`;
    }

    my $InspectedDirectories = scalar @GitDirectoryList;

    $Self->Print("\n  <yellow>Summary</yellow>\n");
    $Self->Print("    $InspectedDirectories directories inspected $SummaryComment\n");

    if (@GitDirsUpdated) {

        $Self->Print("\n    <yellow>Updated directories:</yellow>\n");

        for my $Dir ( sort @GitDirsUpdated ) {
            $Self->Print("       $Dir\n");
        }
    }

    if (@GitDirsModified) {

        $Self->Print("\n    <yellow>Modified directories:</yellow>\n");

        for my $Dir ( sort @GitDirsModified ) {
            $Self->Print("       $Dir\n");
        }
    }

    if (@GitDirsAdeadOfRemote) {

        $Self->Print("\n    <yellow>AheadOfRemote directories:</yellow>\n");

        for my $Dir ( sort @GitDirsAdeadOfRemote ) {
            $Self->Print("       $Dir\n");
        }
    }

    $Self->Print("\n<green>Done.</green>\n");
    return $Self->ExitCodeOk();
}

1;
