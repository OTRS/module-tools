# --
# Copyright (C) 2001-2020 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Console::Command::Misc::ReleaseNotes::Generate;

use strict;
use warnings;

use Cwd;
use File::Basename;
use FindBin qw($RealBin);
use lib dirname($RealBin);

use Console::Command::Misc::ChangeLog::Dump;

use parent qw(Console::BaseCommand);

=head1 NAME

Console::Command::Misc::ReleaseNotes::Generate - Console command to generate release notes in twiki format.

=head1 DESCRIPTION

Text common functions.

=cut

sub Configure {
    my ( $Self, %Param ) = @_;

    $Self->Description('Generate TWiki release notes.');

    $Self->AddArgument(
        Name        => 'version',
        Description => "Specify the framework or package version.",
        Required    => 1,
        HasValue    => 1,
        ValueRegex  => qr/.*/smx,
    );
    $Self->AddOption(
        Name        => 'md5',
        Description => "Specify the package file md5.",
        Required    => 0,
        HasValue    => 1,
        ValueRegex  => qr/.*/smx,
    );
    $Self->AddOption(
        Name        => 'advisory',
        Description => "Specify security advisories .",
        Required    => 0,
        HasValue    => 1,
        Multiple    => 1,
        ValueRegex  => qr/\d{2}-\d{2}/smx,
    );

    # TODO: FileList in otrs templates require a mechanism to send easily a list of files with md5s
    #   and file names like
    # 23424242412113 myfile.zip
    # 56647465636356 myfile.tar.gz
    # A possible solution could be to use https://metacpan.org/pod/Clipboard and just copy and paste

    return;
}

sub Run {
    my ($Self) = @_;

    $Self->Print("<yellow>Generating release notes...</yellow>\n\n");

    my $Version      = $Self->GetArgument('version') || '';
    my @VersionParts = split /\./, ($Version);

    my $PatchLevel     = $VersionParts[2];
    my $PatchLevelLong = "Patch Level $PatchLevel";
    if ( $VersionParts[3] ) {
        $PatchLevel .= "_$VersionParts[3]";
        $PatchLevelLong = ucfirst $VersionParts[3];
    }

    my $ChangesFile;
    my $IsFramework;
    my $PackageName;

    FILE:
    for my $File (qw ( CHANGES.md CHANGES )) {
        if ( -e "$File" ) {
            $ChangesFile = $File;
            $IsFramework = 1;
            last FILE;
        }
    }

    if ( !$IsFramework ) {
        $PackageName = cwd();
        $PackageName =~ s{.+/([^_|-]+)(:?[_|-].+)?$}{$1};
    }

    my $ChangeLog = $Self->_GetChangeLog(
        ChangesFile => $ChangesFile,
        Version     => $Version,
    );

    my ( $BugFixList, $EnhancementsList ) = $Self->_ParseChangeLog(
        ChangeLog => $ChangeLog,
    );

    my $MD5 = $Self->GetOption('md5') || '';

    # Get minimum framework version requirement from package .sopm file.
    my $FrameworkVersionRequirement = $Self->_GetFrameworkVersionRequirement(
        PackageName => $PackageName,
    );

    if ( !defined $FrameworkVersionRequirement ) {
        return $Self->ExitCodeError();
    }

    my $Template = $Self->_GetTemplate(
        IsFramework  => $IsFramework,
        PackageName  => $PackageName,
        VersionParts => \@VersionParts,
    );

    if ( !$Template ) {
        return $Self->ExitCodeError();
    }

    my $AdvisoriesList = $Self->GetOption('advisory') || [];
    my $Advisories     = "\n";
    if ( $AdvisoriesList->[0] ) {
        $Advisories .= "---++ Security Issues\n";
    }
    ADVISORY:
    for my $Advisory ( @{$AdvisoriesList} ) {
        my $FullAdvisory = "20$Advisory";
        $Advisories .= << "EOF";
   * [[OTRS_Security_Advisory_$FullAdvisory][Advisory $Advisory]]
EOF
    }

    my $PackageNameRaw = $PackageName;

    # Mask PackageName.
    if ($PackageName) {
        $PackageName =~ s{( [A-Z]+[a-z]+[A-Z]+[a-z]* ) }{!$1}smxg;
    }

    # Fill template.
    $Template =~ s{\[PACKAGENAME\]}{<green>$PackageName</green>}g;
    $Template =~ s{\[MAYOR\]}{<green>$VersionParts[0]</green>}g;
    $Template =~ s{\[PATHCHLEVEL\]}{<green>$PatchLevel</green>}g;
    $Template =~ s{\[PATHCHLEVELLONG\]}{<green>$PatchLevelLong</green>}g;
    $Template =~ s{\[FRAMRWORKVERSIONREQUIREMENT\]}{<green>$FrameworkVersionRequirement</green>};
    $Template =~ s{\[ADVISORIES\]}{<green>$Advisories</green>};
    $Template =~ s{\[ENHANCEMENTSLIST\]}{<green>$EnhancementsList</green>};
    $Template =~ s{\[BUGFIXLIST\]}{<green>$BugFixList</green>};

    if ($MD5) {
        $Template =~ s{\[MD5\]}{<green>$MD5</green>};
    }
    $Template =~ s{\[PACKAGENAMERAW\]}{<green>$PackageNameRaw</green>}g;

    $Self->Print($Template);

    $Self->Print("\n\n<green>Done.</green>\n");
    return $Self->ExitCodeOk();
}

sub _GetChangeLog {
    my ( $Self, %Param ) = @_;

    my $Output;

    # Read change log if provided.
    if ( $Param{ChangesFile} ) {
        $Output = $Self->_GetFileLog(%Param);
    }
    else {
        $Output = $Self->_GetGitLog(%Param);
    }

    return $Output // '';
}

sub _GetFileLog {
    my ( $Self, %Param ) = @_;

    my $Output;

    my $Error;
    my $ExitCode;
    {

        # Localize the standard error, everything will be restored after the block.
        local *STDERR;
        local *STDOUT;

        # Redirect the standard error and output to a variable.
        open STDERR, ">>", \$Error;
        open STDOUT, ">>", \$Output;

        my $DumpObject = Console::Command::Misc::ChangeLog::Dump->new();
        $ExitCode = $DumpObject->Execute( $Param{ChangesFile}, $Param{Version} );
    }

    return $Output // '';
}

sub _GetGitLog {
    my ( $Self, %Param ) = @_;

    # Get the latest tag of the branch
    my $LatestTag          = `git describe --abbrev=0 --tags`;
    my $LatestVersion      = substr( $LatestTag, 4, length($LatestTag) - 4 );
    my @LatestVersionParts = split /\_/, ($LatestVersion);

    my @TargetVersionParts = split /\./, ( $Param{Version} );

    # This might need to be extended for betas
    my $TargetTag;
    my $PreviousTag;
    if (
        $LatestVersionParts[0] <= $TargetVersionParts[0]
        && $LatestVersionParts[1] <= $TargetVersionParts[1]
        && $LatestVersionParts[2] < $TargetVersionParts[2]
        )
    {
        $TargetTag   = 'HEAD';
        $PreviousTag = $LatestTag;
    }
    else {
        $TargetTag = 'rel-' . join "_", @TargetVersionParts;
        my @PreviousVersionParts = @TargetVersionParts;
        $PreviousVersionParts[2]--;
        $PreviousTag = 'rel-' . join "_", @PreviousVersionParts;
    }

    chomp $PreviousTag;
    chomp $TargetTag;

    my $Command = "git log --pretty=\"%s\" $PreviousTag..$TargetTag";
    my $GitLog  = `$Command`;
    $GitLog //= '';

    # Convert all bug fixes to Wiki style.
    $GitLog
        =~ s{(?:Fixed:[ ]) (.*) [ ]\( bug\# (\d{4,6}) \)}{Bug#[[http://bugs.otrs.org/show_bug.cgi?id=$2][$2]] - $1}imxg;
    $GitLog
        =~ s{(?:Fixed[:]?[ ]) bug\#(\d{4,6}) [ ] (.*)}{Bug#[[http://bugs.otrs.org/show_bug.cgi?id=$1][$1]] - $2}imxg;

    # Add Wiki section indentation.
    $GitLog =~ s{^(.*?)$}{   * $1}ismxg;

    # Mask WikiWords.
    $GitLog =~ s{(\s) ( [A-Z]+[a-z]+[A-Z]+[a-z]* ) }{$1!$2}smxg;

    # Mask HTML tags.
    $GitLog =~ s{<}{&lt;}smxg;
    $GitLog =~ s{>}{&gt;}smxg;

    return $GitLog;
}

sub _ParseChangeLog {
    my ( $Self, %Param ) = @_;

    my $ChangeLog = $Param{ChangeLog} || '';

    # Split the log entries in bug fixes and enhancements.
    my @LogEntries = split /\n/, ($ChangeLog);
    my %SeenLogLines;
    my $BugFixList;
    my $EnhancementsList;
    my $LastMove = 'bug';

    LINE:
    for my $Line (@LogEntries) {

        next LINE if !$Line;

        # Skip version headers e.g. #7.0.1 ????-??-??.
        next LINE if $Line =~ m{^\#(?:\d+\.){2}\d+.}msx;

        # Skip console command output lines.
        next LINE if $Line eq 'Dumping change log entries...';
        next LINE if $Line eq 'Done.';

        # Skip duplicate lines.
        next LINE if $SeenLogLines{$Line};

        # Skip superfluous entries
        next LINE if $Line =~ m{Prepared\sfor\srelease\.?}imsx;
        next LINE if $Line =~ m{Tidied\.?}imsx;

        $SeenLogLines{$Line} = 1;

        $Line .= "\n";

        # Move complementary lines to the last part.
        if ( $Line !~ m{^\s{3}\*}msx ) {
            if ( $LastMove eq 'bug' ) {
                $BugFixList .= $Line;
            }
            else {
                $EnhancementsList .= $Line;
            }
            next LINE;
        }

        if ( $Line =~ m{Bug\#}msxi ) {
            $BugFixList .= $Line;
            $LastMove = 'bug';
        }
        elsif ( $Line =~ m{follow-up\#}msxi ) {
            $BugFixList .= $Line;
            $LastMove = 'bug';
        }
        else {
            $EnhancementsList .= $Line;
            $LastMove = 'enhancement';
        }
    }

    $BugFixList       //= '--';
    $EnhancementsList //= '--';

    chomp $BugFixList;
    chomp $EnhancementsList;

    return ( $BugFixList, $EnhancementsList );
}

sub _GetFrameworkVersionRequirement {
    my ( $Self, %Param ) = @_;

    return '' if !$Param{PackageName};

    my $FH;
    my $Success = open( $FH, '<', "$Param{PackageName}.sopm" );    ## no critic
    if ( !$Success ) {
        $Self->PrintError("Cannot open template file $Param{PackageName}.sopm");
        return;
    }
    my $SOPM = join( '', <$FH> );
    close($FH);

    my $FrameworkVersionRequirement = '';

    if ( $SOPM =~ m{<Framework \s Minimum="(\d+ \.\d+ \. \d+)">}msx ) {
        my $FrameworkVersion      = $1;
        my @FrameworkVersionParts = split /\./, ($FrameworkVersion);
        $FrameworkVersionRequirement
            = "   * OTRS $FrameworkVersionParts[0] Patch Level $FrameworkVersionParts[2] or higher";
    }
    elsif ( $SOPM =~ m{<Framework>(\d+ \.\d+ \. .+)<}msx ) {
        my $FrameworkVersion      = $1;
        my @FrameworkVersionParts = split /\./, ($FrameworkVersion);
        $FrameworkVersionRequirement = "   * OTRS $FrameworkVersionParts[0] Patch Level 1 or higher";
        $Self->Print(
            "<yellow>No Minimum Framework Version Detected</yellow>, <red>please uptade .sopm file!</red>\n\n"
        );

    }

    return $FrameworkVersionRequirement;
}

sub _GetTemplate {
    my ( $Self, %Param ) = @_;

    my $Product = 'otrs';

    if ( !$Param{IsFramework} ) {
        $Product = $Param{PackageName};
    }

    # Define the template name
    my $TemplateFilename = "$RealBin/../Templates/ReleaseNotes/";

    my @TemplateAlternatives = (
        "$Product-$Param{VersionParts}->[0]_0.twiki",
        "$Product-x_0.twiki",
    );

    if ( !$Param{IsFramework} ) {
        push @TemplateAlternatives, "PackageGeneric-$Param{VersionParts}->[0]_0.twiki";
        push @TemplateAlternatives, "PackageGeneric-x_0.twiki";
    }

    TEMPLATEALTERNATIVE:
    for my $TemplateAlternative (@TemplateAlternatives) {
        if ( -e $TemplateFilename . $TemplateAlternative ) {
            $TemplateFilename .= $TemplateAlternative;
            last TEMPLATEALTERNATIVE;
        }
    }

    if ( !-e $TemplateFilename ) {
        $Self->PrintError("Could not find the correct template for $Product");
    }

    # Read the template.
    my $FH;
    my $Success = open( $FH, '<', $TemplateFilename );    ## no critic
    if ( !$Success ) {
        $Self->PrintError("Can not open template file $TemplateFilename");
        return;
    }
    my $Template = join( '', <$FH> );
    close($FH);
    return $Template;
}

1;
