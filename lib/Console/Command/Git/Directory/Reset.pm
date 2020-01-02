# --
# Copyright (C) 2001-2020 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Console::Command::Git::Directory::Reset;

use strict;
use warnings;

use parent qw(Console::BaseCommand Console::BaseDirectory);

=head1 NAME

Console::Command::Git::Directory::Reset - Console command to reset git directories

=head1 DESCRIPTION

reset git directories

=cut

sub Configure {
    my ( $Self, %Param ) = @_;

    $Self->Description('Reset defined git repositories.');
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

    $Self->Print("\n<yellow>Reseting git directories...</yellow>\n");

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

    DIRECTORY:
    for my $Directory ( sort @GitDirectoryList ) {

        next DIRECTORY if !$Directory;
        next DIRECTORY if !-d $Directory;

        $Self->Print("  Resetting directory <yellow>$Directory</yellow>\n");

        `cd $Directory && git checkout -- .`;
    }

    $Self->Print("\n<green>Done.</green>\n");
    return $Self->ExitCodeOk();
}

1;
