# --
# Copyright (C) 2001-2018 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Console::Command::Git::Directory::Update;

use strict;
use warnings;

use parent qw(Console::BaseCommand);

=head1 NAME

Console::Command::Git::Directory::Update - Console command to update git directories

=head1 DESCRIPTION

Pulls and optimize git directories

=cut

sub Configure {
    my ( $Self, %Param ) = @_;

    $Self->Description('Update defined git repositories.');
    $Self->AddOption(
        Name        => 'all',
        Description => "Include additional directories defined in /etc/config.pl.",
        Required    => 0,
        HasValue    => 0,
        ValueRegex  => qr/.*/smx,
    );
    $Self->AddOption(
        Name        => 'optimize',
        Description => "Performs a git cleanup on directories.",
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

    return;
}

sub PreRun {
    my ($Self) = @_;

    return;
}

sub Run {
    my ($Self) = @_;

    $Self->Print("\n<yellow>Updating git directories...</yellow>\n");

    my %Config = %{ $Self->{Config}->{DevelDir} || {} };

    my @DevelDirectories = @{ $Config{DevelDirectories} || [] };

    if ( $Self->GetOption('all') ) {
        push @DevelDirectories, @{ $Config{AdditionalDevelDirectories} || [] };
    }

    if ( $Self->GetOption('directory') ) {

        push @DevelDirectories, $Self->GetOption('directory');
    }

    # Get a list of all git directories and OTRSCodePolicy directories.
    my @GitDirectoryList;
    my @CodePolicyDirectoryList;
    for my $DevelDirectory (@DevelDirectories) {

        GitDirectoriesList(
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
    my @GitDirsUpdated;

    # Looks what directories are modified or clean.
    DIRECTORY:
    for my $Directory ( sort @GitDirectoryList ) {

        next DIRECTORY if !$Directory;
        next DIRECTORY if !-d $Directory;

        my $GitStatusOutput = `cd $Directory && git status`;

        if ( $GitStatusOutput =~ m{ \QYour branch is ahead of\E }xms ) {
            push @GitDirsAdeadOfRemote, $Directory;
        }

        # Different output between git versions
        #   git 2.9: nothing to commit, working tree clean
        #   git 2.x: nothing to commit, working directory clean
        #   git 1.x: nothing to commit (working directory clean)
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

    # Update clean directories.
    DIRECTORY:
    for my $Directory ( sort @GitDirsClean ) {

        next DIRECTORY if !$Directory;
        next DIRECTORY if !-d $Directory;

        my $GitRemoteOutput = `cd $Directory && git remote`;

        next DIRECTORY if !$GitRemoteOutput;

        $Self->Print("  Updating clean directory <yellow>$Directory</yellow>\n");

        my $GitUpdateOutput = `cd $Directory && git pull && git remote prune origin`;

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
            my $GitGcOutput = `cd $Directory && git gc > /dev/null 2>&1`;
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
    $Self->Print("    $InspectedDirectories directories inspected\n");

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

=head2 GitDirectoriesList()

returns a list of all git directories

    GitDirectoriesList(
        BaseDirectory           => $DevelDirectory,
        GitDirectoryList        => \@GitDirectoryList,
        CodePolicyDirectoryList => \@CodePolicyDirectoryList,
        GitIgnore               => $Config{GitIgnore},
        DevelDirectories        => \@DevelDirectories,
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
    for my $Directory ( @{ $Param{GitIgnore} } ) {

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

        for my $DevelDir ( @{ $Param{DevelDirectories} } ) {
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

1;
