# --
# Copyright (C) 2001-2019 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Console::BaseDirectory;

use strict;
use warnings;

=head1 NAME

Console::BaseDirectory - base class for directory commands


=head2 DevelDirectoriesGet()

returns a list of all development directories using the configuration file and the CLI options

    my @DevelDirecotiries = DevelDirectoriesGet()

=cut

sub DevelDirectoriesGet {
    my ($Self) = @_;

    my %Config = %{ $Self->{Config}->{DevelDir} || {} };

    my %DirectoryAliasConfig = %{ $Config{DirectoryAlias} || {} };

    my @DevelDirectories = @{ $Config{DevelDirectories} || [] };

    if ( $Self->GetOption('all') ) {
        push @DevelDirectories, @{ $Config{AdditionalDevelDirectories} || [] };

        for my $AliasName ( sort keys %DirectoryAliasConfig ) {
            push @DevelDirectories, @{ $DirectoryAliasConfig{$AliasName} };
        }
    }

    my $DirectoryAlias = $Self->GetOption('directory-alias') || [];

    if ( $DirectoryAlias && ref $DirectoryAlias eq 'ARRAY' && @{$DirectoryAlias} ) {
        ALIASNAME:
        for my $AliasName ( @{$DirectoryAlias} ) {
            next ALIASNAME if !$DirectoryAliasConfig{$AliasName};

            push @DevelDirectories, @{ $DirectoryAliasConfig{$AliasName} };
        }
    }

    if ( $Self->GetOption('directory') ) {

        push @DevelDirectories, $Self->GetOption('directory');
    }

    my %DevelDirectoriesDeDup = map { $_ => 1 } @DevelDirectories;

    @DevelDirectories = sort keys %DevelDirectoriesDeDup;

    return @DevelDirectories;
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
    my ( $Self, %Param ) = @_;

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

=head2 GitDirectoriesAnalyze()

check if git directories are clean, modified or ahead of the remote branch.

    GitDirectoriesAnalyze(
        GitDirectoryList        => \@GitDirectoryList,
        CodePolicyDirectoryList => \@CodePolicyDirectoryList,
        GitDirsClean            => \@GitDirsClean,
        GitDirsAdeadOfRemote    => \@GitDirsAdeadOfRemote,
        GitDirsModified         => \@GitDirsModified,
    );

=cut

sub GitDirectoriesAnalyze {
    my ( $Self, %Param ) = @_;

    # Looks what directories are modified or clean.
    DIRECTORY:
    for my $Directory ( sort @{ $Param{GitDirectoryList} } ) {

        next DIRECTORY if !$Directory;
        next DIRECTORY if !-d $Directory;

        my $GitStatusOutput = `cd $Directory && git status`;

        if ( $GitStatusOutput =~ m{ \QYour branch is ahead of\E }xms ) {
            push @{ $Param{GitDirsAdeadOfRemote} }, $Directory;
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
            push @{ $Param{GitDirsClean} }, $Directory;
        }
        else {
            push @{ $Param{GitDirsModified} }, $Directory;
        }
    }
    return;
}

1;
