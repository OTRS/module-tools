# --
# Copyright (C) 2001-2018 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Console::Command::Misc::ChangeLog::Add;

use strict;
use warnings;

use Cwd;
use DateTime;
use XMLRPC::Lite;

use parent qw(Console::BaseCommand);

=head1 NAME

Console::Command::Misc::ChangeLog::Add - Console command to add an entry in the change log

=head1 DESCRIPTION

Adds an entry into the change log.

=head1 PUBLIC INTERFACE

=cut

sub Configure {
    my ( $Self, %Param ) = @_;

    $Self->Description('Add change log entry.');
    $Self->AddOption(
        Name        => 'bug',
        Description => "Specify a bug number.",
        Required    => 0,
        HasValue    => 1,
        ValueRegex  => qr/^\d+$/smx,
    );
    $Self->AddOption(
        Name        => 'pull-request',
        Description => "Specify a pull request number.",
        Required    => 0,
        HasValue    => 1,
        ValueRegex  => qr/^\d+$/smx,
    );
    $Self->AddOption(
        Name        => 'target-path',
        Description => "Specify a custom change log file.",
        Required    => 0,
        HasValue    => 1,
        ValueRegex  => qr/.*/smx,
    );
    $Self->AddOption(
        Name        => 'message',
        Description => "Specify a custom message.",
        Required    => 0,
        HasValue    => 1,
        ValueRegex  => qr/.*/smx,
    );
    $Self->AddOption(
        Name        => 'version',
        Description => "Specify if change log entry is added for the specific version.",
        Required    => 0,
        HasValue    => 1,
        ValueRegex  => qr/.*/smx,
    );

    my $Name = $Self->Name();

    $Self->AdditionalHelp(<<"EOF");
<green>otrs.ModuleTools.pl $Name --bug 1234 [--pull-request 1001] [--target-path CHANGES.md]</green>
    Add bugzilla entry title to stable version CHANGES.md and commit message template.

<green>otrs.ModuleTools.pl $Name --bug 1234 [--pull-request 1001] [--version 6]</green>
    --version causes the entry to be added for the specific OTRS version, e.g. OTRS6, even if it is not stable.

<green>otrs.ModuleTools.pl $Name --message "My commit message."</green>
    Add another message to CHANGES.md and commit message template.
EOF

    return;
}

sub PreRun {
    my ($Self) = @_;

    my $Bug     = $Self->GetOption('bug');
    my $Message = $Self->GetOption('message');

    if ( !$Bug && !$Message ) {
        die "bug or message are needed!";
    }

    my $TargetPath = $Self->GetOption('target-path') // '';

    if ( $TargetPath && -r $TargetPath ) {
        die "Could not read file $TargetPath!";
    }

    return;
}

sub Run {
    my ($Self) = @_;

    $Self->Print("<yellow>Adding change log entry...</yellow>\n");

    my $ChangesFile = $Self->GetOption('target-path') || '';

    if ( !$ChangesFile ) {

        FILE:
        for my $File (qw ( CHANGES.md CHANGES )) {
            if ( -e $File ) {
                $ChangesFile = $File;
                last FILE;
            }
        }

        # If no changes file was found maybe is a package path.
        if ( !$ChangesFile ) {
            my $PackageName;

            $PackageName = cwd();

            $PackageName =~ s{.+/([^_|-]+)(:?[_|-].+)?$}{$1};

            # Check for CHANGES-<PackageName>.
            my $File = "CHANGES-$PackageName";
            if ( -e $File ) {
                $ChangesFile = $File;
            }

            # Check for CHANGES-<PackageName>.md.
            $File .= ".md";
            if ( -e $File ) {
                $ChangesFile = $File;
            }

            if ( !$ChangesFile ) {
                $Self->PrintError("No CHANGES.md, CHANGES or $File file found in path.\n");
            }
        }
    }

    my $ChangeLine;
    my $Summary;

    my $Bug         = $Self->GetOption('bug');
    my $PullRequest = $Self->GetOption('pull-request');
    my $Message     = $Self->GetOption('message');

    # If bug does not exist, this will stop the script.
    if ($Bug) {
        my $Result = $Self->GetBugSummary($Bug);
        if ( !$Result->{Success} ) {
            $Self->PrintError("Could not find Bug $Bug.\n");
            return $Self->ExitCodeError();
        }
        $Summary    = $Result->{Summary};
        $ChangeLine = FormatChangesLine(
            Bug         => $Bug,
            PullRequest => $PullRequest,
            Summary     => $Summary,
            ChangesFile => $ChangesFile,
            Message     => $Message,
        );
    }
    elsif ($Message) {
        $Summary    = $Message;
        $ChangeLine = FormatChangesLine(
            Bug         => '',
            PullRequest => $PullRequest,
            Summary     => $Summary,
            ChangesFile => $ChangesFile,
            Message     => $Message,
        );
    }

    if ($ChangesFile) {

        # Read in existing changes file.
        my $Success = open my $InFile, '<', $ChangesFile;    ## no critic
        if ( !$Success ) {
            $Self->PrintError("Couldn't open $ChangesFile: $!");
            return $Self->ExitCodeError();
        }
        binmode $InFile;
        my @Changes = <$InFile>;
        close $InFile;

        # Write out new file with added line.
        $Success = open my $OutFile, '>', $ChangesFile;      ## no critic
        if ( !$Success ) {
            $Self->PrintError("Couldn't open $ChangesFile: $!");
            return $Self->ExitCodeError();
        }
        binmode $OutFile;

        my $Printed            = 0;
        my $ReleaseHeaderFound = 0;
        my $ReleaseHeaderRegex = qr{^[#]?\d+[.]\d+[.]\d+[ ]};    # 1.2.3
        my $Version            = $Self->GetOption('version');
        if ($Version) {
            $ReleaseHeaderRegex = qr{^[#]?$Version[.]\d+[.]\d+};
        }
        for my $Line (@Changes) {
            if ( !$ReleaseHeaderFound && $Line =~ m{$ReleaseHeaderRegex} ) {
                $ReleaseHeaderFound = 1;
            }

            if ( $ReleaseHeaderFound && !$Printed && $Line =~ m/^(\s+-\s+|$)/smx ) {
                print $OutFile $ChangeLine;
                $Printed = 1;
            }
            print $OutFile $Line;
        }
        close $OutFile;
    }

    my $Success = open my $OutFile, '>', '.git/OTRSCommitTemplate.msg';    ## no critic
    if ( !$Success ) {
        $Self->PrintError("Couldn't open .git/OTRSCommitTemplate.msg: $!\n");
        return $Self->ExitCodeError();
    }
    binmode $OutFile;

    my $PRText = '';
    if ($Bug) {
        if ($PullRequest) {
            $PRText = ", PR#$PullRequest";
        }
        print $OutFile "Fixed: $Summary (bug#$Bug$PRText).\n";
    }
    elsif ($Message) {
        if ($PullRequest) {
            $PRText = "(PR#$PullRequest) ";
        }
        print $OutFile "$PRText$Message\n";
    }
    close $OutFile;

    $Self->Print("\n<green>Done.</green>\n");
    return $Self->ExitCodeOk();
}

sub GetBugSummary {
    my ( $Self, $Bug ) = @_;

    my %Config = %{ $Self->{Config}->{Bugzilla} || {} };

    # Define request params (add user and password if set in the config).
    my %Param = (
        ids => [$Bug],
    );
    if ( defined $Config{Bugzilla_login} && defined $Config{Bugzilla_password} ) {
        $Param{Bugzilla_login}    = $Config{Bugzilla_login};
        $Param{Bugzilla_password} = $Config{Bugzilla_password};
    }

    # Get bug description from bug tracker,
    #   if bug does not exist we automatically get an error message and the script dies
    my $Proxy  = XMLRPC::Lite->proxy('https://bugs.otrs.org/xmlrpc.cgi');
    my $Result = $Proxy->call(
        'Bug.get',
        \%Param,
    )->result();

    if ( !$Result || !$Result->{bugs} || !@{ $Result->{bugs} } ) {
        return {
            Success => 0,
        };
    }

    my $Summary = $Result->{bugs}->[0]->{summary};

    # Remove trailing dot if present.
    if ($Summary) {
        $Summary =~ s{[.]+$}{}smx;

    }
    return {
        Success => 1,
        Summary => $Summary,
    };
}

=head2 FormatChangesLine()

Takes as arguments bug# and name of the changes file.
Looks up the description for the given bug# in Bugzilla.
Generates the change log entry and depending on the format of the CHANGES
file (Markdown or not) generates a properly formatted entry and returns this.

=cut

sub FormatChangesLine {
    my (%Param) = @_;

    my $Bug         = $Param{Bug};
    my $PullRequest = $Param{PullRequest};
    my $Summary     = $Param{Summary};
    my $ChangesFile = $Param{ChangesFile};
    my $Message     = $Param{Message};

    # Get current date in iso format (yyyy-mm-dd).
    my $Date = DateTime->now()->ymd();

# Formatting is different for markdown files; below first 'regular', second 'markdown'.
#   - 2013-03-02 Fixed bug#9214 - IE10: impossible to open links from rich text articles.
#   - 2013-03-02 Fixed bug#[9214](http://bugs.otrs.org/show_bug.cgi?id=9214) - IE10: impossible to open links from rich text articles.

    my $PRText = '';
    if ($PullRequest) {
        $PRText = "(PR#$PullRequest)";
    }

    # Format for CHANGES (OTRS 3.1.x and earlier) is different from CHANGES.md.
    my $Line;
    if ( $Bug && $ChangesFile !~ m{CHANGES .* \.md}msx ) {
        $Line = " - $Date Fixed bug#$Bug$PRText - $Summary.\n";
    }
    elsif ($Bug) {
        $Line = " - $Date Fixed bug#[$Bug](https://bugs.otrs.org/show_bug.cgi?id=$Bug)$PRText - $Summary.\n";
    }
    elsif ($Message) {
        $Line = " - $Date $PRText$Summary\n";
    }
    return $Line;
}

1;
