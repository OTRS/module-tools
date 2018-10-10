# --
# Copyright (C) 2001-2018 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Console::Command::Git::Directory::Commit;

use strict;
use warnings;

use parent qw(Console::BaseCommand Console::BaseDirectory);

=head1 NAME

Console::Command::Git::Directory::Commit - Console command to add a commit git directories

=head1 DESCRIPTION

commit into git directories

=cut

sub Configure {
    my ( $Self, %Param ) = @_;

    $Self->Description('Add a commit to git repositories.');
    $Self->AddOption(
        Name        => 'message',
        Description => "Commit message, starting with capital letter and end with period e.g. 'Code cleanup.' ",
        Required    => 1,
        HasValue    => 1,
        ValueRegex  => qr/\A[A-Z].*\.\z/smx,
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
        Description => "Specify a directory to reset.",
        Required    => 0,
        HasValue    => 1,
        ValueRegex  => qr/.*/smx,
    );
    $Self->AddOption(
        Name        => 'directory-alias',
        Description => "Specify a directory alias to reset.",
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

    $Self->Print("\n<yellow>Adding commit into git directories...</yellow>\n");

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

    my $CommitMessage = $Self->GetOption('message');

    # Commit and push changes.
    DIRECTORY:
    for my $Directory ( sort @GitDirectoryList ) {

        next DIRECTORY if !$Directory;
        next DIRECTORY if !-d $Directory;

        $Self->Print("  Committing and pushing changes from directory <yellow>$Directory</yellow>\n");

        my $GitStatusOutput = `cd $Directory && git status`;

        next DIRECTORY
            if $GitStatusOutput
            =~ m{ nothing [ ]+ to [ ]+ commit, [ ]+ working [ ]+ (?: directory | tree ) [ ]+ clean }xms;

        my $GitCommitPushOutput = `cd $Directory && got commit -m '$CommitMessage' . && got push`;
    }

    $Self->Print("\n<green>Done.</green>\n");
    return $Self->ExitCodeOk();
}

1;
