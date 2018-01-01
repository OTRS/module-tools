# --
# Copyright (C) 2001-2018 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Console::Command::Misc::File::CheckChanged;

use strict;
use warnings;

use File::Find;
use Digest::MD5 qw(md5_hex);

use parent qw(Console::BaseCommand);

=head1 NAME

Console::Command::Misc::File::CheckChanged - Console command to get changed files between different releases of OTRS

=head1 DESCRIPTION

Compares two OTRS releases and check its file differences

=head1 PUBLIC INTERFACE

=cut

sub Configure {
    my ( $Self, %Param ) = @_;

    $Self->Description('Get changed files between different releases of OTRS.');
    $Self->AddArgument(
        Name        => 'source-directory',
        Description => "Specify the base OTRS framework directory.",
        Required    => 1,
        ValueRegex  => qr/.*/smx,
    );
    $Self->AddArgument(
        Name        => 'target-directory',
        Description => "Specify the target OTRS framework directory to compare.",
        Required    => 1,
        ValueRegex  => qr/.*/smx,
    );
    $Self->AddOption(
        Name        => 'module-directory',
        Description => "Specify a module directory to compare (with the target).",
        Required    => 0,
        HasValue    => 1,
        ValueRegex  => qr/.*/smx,
    );
    $Self->AddOption(
        Name        => 'reduced-check',
        Description => "Compares only 'Kernel' and 'bin' directories.",
        Required    => 0,
        HasValue    => 0,
        ValueRegex  => qr/.*/smx,
    );

    return;
}

sub PreRun {
    my ($Self) = @_;

    my @Directories = ( File::Spec->rel2abs( $Self->GetArgument('source-directory') ) );

    my $ModuleDirectory = File::Spec->rel2abs( $Self->GetOption('module-directory') );
    if ($ModuleDirectory) {
        push @Directories, $ModuleDirectory
    }

    push @Directories, File::Spec->rel2abs( $Self->GetArgument('target-directory') || '.' );

    for my $Directory (@Directories) {
        if ( !-e $Directory ) {
            die "$Directory does not exist";
        }
        if ( !-d $Directory ) {
            die "$Directory is not a directory";
        }
    }

    return;
}

sub Run {
    my ($Self) = @_;

    $Self->Print("\n<yellow>Checking files...</yellow>\n");

    my $BaseVersionFile2MD5
        = $Self->FindFilesOfVersion( File::Spec->rel2abs( $Self->GetArgument('source-directory') ) ) || {};
    my $NewVersionFile2MD5
        = $Self->FindFilesOfVersion( File::Spec->rel2abs( $Self->GetArgument('target-directory') || '.' ) ) || {};

    my $ModuleVersionFile2MD5;
    my $ModuleDirectory = $Self->GetOption('module-directory');
    if ($ModuleDirectory) {
        $ModuleDirectory = File::Spec->rel2abs($ModuleDirectory);
        $ModuleVersionFile2MD5 = $Self->FindFilesOfVersion($ModuleDirectory) || {};
    }

    # Get list of deleted and new files.
    my @DeletedFiles = grep { !defined $NewVersionFile2MD5->{$_} } sort keys %{$BaseVersionFile2MD5};
    my @NewFiles     = grep { !defined $BaseVersionFile2MD5->{$_} } sort keys %{$NewVersionFile2MD5};

    # Get list of to be checked files.
    my %CheckFileList = %{$BaseVersionFile2MD5};
    map { delete $CheckFileList{$_} } @DeletedFiles;

    # Get list of changed files.
    my @ChangedFiles = grep { $BaseVersionFile2MD5->{$_} ne $NewVersionFile2MD5->{$_} }
        sort keys %CheckFileList;

    # Produce output if data had been gathered.
    if (@DeletedFiles) {
        $Self->Print( "\n  <yellow>List of deleted files (" . scalar @DeletedFiles . "):</yellow>\n" );
        map { $Self->Print("    $_\n") } @DeletedFiles;
    }

    if (@NewFiles) {
        $Self->Print( "\n  <yellow>List of new files (" . scalar @NewFiles . "):</yellow>\n" );
        map { $Self->Print("    $_\n") } @NewFiles;
    }

    if (@ChangedFiles) {
        $Self->Print( "\n  <yellow>List of changed files (" . scalar @ChangedFiles . "):</yellow>\n" );
        map { $Self->Print("    $_\n") } @ChangedFiles;
    }

    # Module has been given.
    if ($ModuleVersionFile2MD5) {

        # Get list of changed files of the given module.
        my @ChangedModuleFiles = grep {
            $ModuleVersionFile2MD5->{$_} && $ModuleVersionFile2MD5->{$_} ne $NewVersionFile2MD5->{$_}
        } sort keys %CheckFileList;
        $Self->Print( "\n  <yellow>List of changed files module (" . scalar @ChangedModuleFiles . "):</yellow>\n" );
        map { $Self->Print("    $_\n") } @ChangedModuleFiles;
    }

    $Self->Print("\n<green>Done.</green>\n");
    return $Self->ExitCodeOk();
}

=head2 FindFilesOfVersion()

Returns a HASHREF with file names as key and its MD5 hex digest as value.
It strips out the root directory from the file name.

my $FileName2MD5 = FindFilesOfVersion( '/ws/otrs-head' );

results will look like:

    $FileName2MD5 = {
        'Kernel/System/Main.pm' => '7731615a697d7ed0da2579a9c71d7d9c',
    };

=cut

sub FindFilesOfVersion {
    my ( $Self, $VersionDirectory ) = @_;

    # Check directory path.
    return if !$VersionDirectory;
    return if !-d $VersionDirectory;

    # Define white list for reduced checks.
    my @ReducedChecks;
    if ( $Self->GetOption('reduced-check') ) {
        @ReducedChecks = qw(Kernel bin);
    }

    # Define function for traversing.
    my %VersionFile2MD5;
    my $FindFilesOfVersion = sub {
        my $FileName = $File::Find::name;

        # Only return valid files.
        return if !-f $FileName;

        # Ignore CVS directory.
        return if $FileName =~ m{ \A $VersionDirectory [/]? .* CVS }xms;

        # Ignore .git directory.
        return if $FileName =~ m{ \A $VersionDirectory [/]? .* \.git }xms;

        # Ignore certain var directories.
        return if $FileName =~ m{ \A $VersionDirectory [/]? .* var/(article|tmp|log) }xms;

        # Ignore mac os hidden files.
        return if $FileName =~ m{.DS_Store}xms;

        # Get file name without root path and possible tailing '/'.
        my ($PackageName) = $FileName =~ m{\A $VersionDirectory (?: / )? (.*) \z}xms;

        # Consider customized files for OTRS 2.4 in Kernel/Custom/.
        $PackageName =~ s{ Kernel/Custom/ }{}xms;

        # Check for reduced file checking.
        return if @ReducedChecks && !grep { $PackageName =~ m{\A $_ }xms } @ReducedChecks;

        # Create file handle for digest function.
        open my $FH, '<', $FileName || return;    ## no critic
        binmode $FH;
        $VersionFile2MD5{$PackageName} = Digest::MD5->new()->addfile($FH)->hexdigest();
        close $FH;
    };

    # Start gathering file list.
    find( $FindFilesOfVersion, $VersionDirectory );

    return \%VersionFile2MD5;
}

1;

=head1 TERMS AND CONDITIONS

This software is part of the OTRS project (L<http://otrs.org/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (AGPL). If you
did not receive this file, see L<http://www.gnu.org/licenses/agpl.txt>.

=cut
