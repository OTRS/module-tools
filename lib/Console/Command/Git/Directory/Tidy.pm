# --
# Copyright (C) 2001-2020 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Console::Command::Git::Directory::Tidy;

use strict;
use warnings;

use parent qw(Console::BaseCommand Console::BaseDirectory);

=head1 NAME

Console::Command::Git::Directory::Tidy - Console command to update git directories

=head1 DESCRIPTION

Pulls and optimize git directories

=cut

sub Configure {
    my ( $Self, %Param ) = @_;

    $Self->Description('Tidy git repositories.');
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

    return;
}

sub Run {
    my ($Self) = @_;

    $Self->Print("\n<yellow>Tidying git directories...</yellow>\n");

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

    my @GitDirsTidied;
    my @GitDirsTidyProblems;

    # Tidy clean directories.
    DIRECTORY:
    for my $Directory ( sort @GitDirsClean ) {

        next DIRECTORY if !$Directory;
        next DIRECTORY if !-d $Directory;

        $Self->Print("  Tidying clean directory <yellow>$Directory</yellow>\n");

        my $TidyOutput = `cd $Directory && $Config{CodePolicyTidyCommand}`;

        if ( $TidyOutput =~ m{ \Qdid not pass tidyall check\E }xms ) {
            push @GitDirsTidyProblems, $Directory;
        }
        elsif ( $TidyOutput =~ m{ \Q[tidied]\E }xms ) {
            push @GitDirsTidied, $Directory;
        }
    }

    my $InspectedDirectories = scalar @GitDirectoryList;

    $Self->Print("\n  <yellow>Summary</yellow>\n");
    $Self->Print("    $InspectedDirectories directories inspected\n");

    if (@GitDirsTidied) {

        $Self->Print("\n    <yellow>Tidied directories:</yellow>\n");

        for my $Dir ( sort @GitDirsTidied ) {
            $Self->Print("       $Dir\n");
        }
    }

    if (@GitDirsTidyProblems) {

        $Self->Print("\n    <yellow>Tidy problem directories:</yellow>\n");

        for my $Dir ( sort @GitDirsTidyProblems ) {
            print STDOUT "   $Dir\n";
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
