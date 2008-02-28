#!/usr/bin/perl -w
# --
# CodePolicy.pl - a tool to remotely execute the OTRS code policy against local code
# Copyright (C) 2001-2008 OTRS AG, http://otrs.org/
# --
# $Id: CodePolicy.pl,v 1.4 2008-02-28 15:04:06 ot Exp $
# --
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
# --

use strict;
use warnings;

our $VERSION = qw($Revision: 1.4 $) [1];

# disable output buffering
use IO::Handle;
STDOUT->autoflush(1);
STDERR->autoflush(1);

use sigtrap qw( die normal-signals error-signals );

use File::Basename;
use File::Find;
use MIME::Base64;
use SOAP::Lite;

my $ProtocolVersion = 1;

use Getopt::Long;
use Pod::Usage;

my ( $SOAP, $SessionID );

my $ExitCode = 0;

my %GeneralOption = (
    Verbose => 0,
);
Getopt::Long::Configure( qw( default pass_through ) );
GetOptions(
    'dry-run'  => \$GeneralOption{DryRun},
    'help|?'   => \$GeneralOption{Help},
    'man'      => \$GeneralOption{Man},
    'verbose+' => \$GeneralOption{Verbose},
    'version'  => \$GeneralOption{Version},
) or pod2usage(2);
if ($GeneralOption{Help}) {
    pod2usage(
        -msg => 'CodyPolicy.pl - a tool to remotely execute the OTRS code policy against local code',
        -verbose => 0,
        -exitval => 1
    )
}
elsif ($GeneralOption{Man}) {
    # avoid dubious problem with perldoc in combination with UTF-8 that
    # leads to strange dashes and single-quotes being used
    $ENV{LC_ALL} = 'POSIX';
    pod2usage(-verbose => 2);
}
elsif ($GeneralOption{Version}) {
    print "$0: $VERSION (protocol version: $ProtocolVersion)\n";
    exit 0;
}

my $Action = shift @ARGV || '';
if ($Action =~ m[^check-d]i) {
    RunChecksRemotely(
        'Dir',
        "*** The action '$Action' requires a directory!\n*** See $0 --help for more info.\n"
    );
}
elsif ($Action =~ m[^check-f]i) {
    RunChecksRemotely(
        'File',
        "*** The action '$Action' requires a file!\n*** See $0 --help for more info.\n"
    );
}
elsif ($Action =~ m[^check-m]i) {
    RunChecksRemotely(
        'Module',
        "*** The action '$Action' requires a module path or *.sopm file!\n"
            . "*** See $0 --help for more info.\n"
    );
}
elsif ($Action =~ m[^fix-d]i) {
    RunFixesRemotely(
        'Dir',
        "*** The action '$Action' requires a directory!\n*** See $0 --help for more info.\n"
    );
}
elsif ($Action =~ m[^fix-f]i) {
    RunFixesRemotely(
        'File',
        "*** The action '$Action' requires a file!\n*** See $0 --help for more info.\n"
    );
}
elsif ($Action =~ m[^fix-m]i) {
    RunFixesRemotely(
        'Module',
        "*** The action '$Action' requires a module path or *.sopm file!\n"
            . "*** See $0 --help for more info.\n"
    );
}
elsif ($Action =~ m[^recode-d]i) {
    RunRecodingsRemotely(
        'Dir',
        "*** The action '$Action' requires a directory!\n*** See $0 --help for more info.\n"
    );
}
elsif ($Action =~ m[^recode-f]i) {
    RunRecodingsRemotely(
        'File',
        "*** The action '$Action' requires a file!\n*** See $0 --help for more info.\n"
    );
}
elsif ($Action =~ m[^recode-m]i) {
    RunRecodingsRemotely(
        'Module',
        "*** The action '$Action' requires a module path or *.sopm file!\n"
            . "*** See $0 --help for more info.\n"
    );
}
elsif ($Action =~ m[^list-c]i) {
    ListChecks();
}
elsif ($Action =~ m[^list-d]i) {
    ListDomains();
}
elsif ($Action =~ m[^list-f]i) {
    ListFixes();
}
elsif ($Action =~ m[^list-p]i) {
    ListProfiles();
}
elsif ($Action =~ m[^list-r]i) {
    ListRecodings();
}
else {
    print STDERR <<"    End-of-Here";
    You need to specify exactly one of these actions:
        check-dir
        check-file
        check-module
        fix-dir
        fix-file
        fix-module
        list-checks
        list-domains
        list-fixes
        list-profiles
        list-recodings
        recode-dir
        recode-file
        recode-module
    Try '$0 --help' for more info.
    End-of-Here
    $ExitCode = 1;
}

exit $ExitCode;

sub RunChecksRemotely {
    my ( $Mode, $ErrorMessage ) = @_;

    # disable pass_through and evaluate remaining options
    my %ActionOption = (
        Actions => '',
    );
    GetOptions(
        'actions=s' => \$ActionOption{Actions},
        'profile=s' => \$ActionOption{Profile},
    ) or pod2usage(2);

    my $Arg = shift @ARGV or die( $ErrorMessage );

    Connect();
    my $ArgAsRelativePath = UploadFiles( $Mode, $Arg );

    print STDERR "running checks...";
    my $Result = eval {
        $SOAP->RunChecks($SessionID, {
            GeneralOption => \%GeneralOption,
            ActionOption  => \%ActionOption,
            Mode          => $Mode,
            Arg           => $ArgAsRelativePath,
        } )->result;
    };

    if (!$Result) {
        $ExitCode = 5;
        print STDERR "an unexpected problem occurred!\n";
    }
    else {
        my $Log = $Result->{Log};
        if ($Log) {
            print STDERR "\n", @{ $Log };
        }
        if (!$Result->{Status}) {
            $ExitCode = 10;
            print STDERR "*** not ok - see the problems shown above!\n";
        }
        else {
            print STDERR "ok - everything looks fine!\n";
        }
    }

    Disconnect();

    return;
}

sub RunFixesRemotely {
    my ( $Mode, $ErrorMessage ) = @_;

    # disable pass_through and evaluate remaining options
    my %ActionOption = (
        Actions => '',
    );
    GetOptions(
        'actions=s' => \$ActionOption{Actions},
        'profile=s' => \$ActionOption{Profile},
    ) or pod2usage(2);

    my $Arg = shift @ARGV or die( $ErrorMessage );
    Connect();
    my $ArgAsRelativePath = UploadFiles( $Mode, $Arg );

    print STDERR "running fixes...";
    my $Result = eval {
        $SOAP->RunFixes($SessionID, {
            GeneralOption => \%GeneralOption,
            ActionOption  => \%ActionOption,
            Mode          => $Mode,
            Arg           => $ArgAsRelativePath,
        } )->result;
    };

    if (!$Result) {
        $ExitCode = 5;
        print STDERR "an unexpected problem occurred!\n";
    }
    else {
        my $Log = $Result->{Log};
        if ($Log) {
            print STDERR "\n", @{ $Log };
        }
        if (!$Result->{Status}) {
            $ExitCode = 10;
            print STDERR "*** something has gone wrong - see the problems shown above!\n";
        }
        else {
            print STDERR "ok!\n";
            my $ChangedFiles = $Result->{ChangedFiles};
            if ($ChangedFiles && @{ $ChangedFiles }) {
                DownloadFiles( $ChangedFiles );
            }
        }

    }

    Disconnect();

    return;
}

sub RunRecodingsRemotely {
    my ( $Mode, $ErrorMessage ) = @_;

    # disable pass_through and evaluate remaining options
    my %ActionOption = (
        Actions => '',
    );
    GetOptions(
        'actions=s' => \$ActionOption{Actions},
        'profile=s' => \$ActionOption{Profile},
    ) or pod2usage(2);

    my $Arg = shift @ARGV or die( $ErrorMessage );
    Connect();
    my $ArgAsRelativePath = UploadFiles( $Mode, $Arg );

    print STDERR "running recodings...";
    my $Result = eval {
        $SOAP->RunRecodings($SessionID, {
            GeneralOption => \%GeneralOption,
            ActionOption  => \%ActionOption,
            Mode          => $Mode,
            Arg           => $ArgAsRelativePath,
        } )->result;
    };

    if (!$Result) {
        $ExitCode = 5;
        print STDERR "an unexpected problem occurred!\n";
    }
    else {
        my $Log = $Result->{Log};
        if ($Log) {
            print STDERR "\n", @{ $Log };
        }
        if (!$Result->{Status}) {
            $ExitCode = 10;
            print STDERR "*** something has gone wrong - see the problems shown above!\n";
        }
        else {
            print STDERR "ok!\n";
            my $ChangedFiles = $Result->{ChangedFiles};
            if ($ChangedFiles && @{ $ChangedFiles }) {
                DownloadFiles( $ChangedFiles );
            }
        }

    }

    Disconnect();

    return;
}

sub Connect {
    print STDERR "connecting...";
    $SOAP = SOAP::Lite
        ->uri('http://otrs.org/OTRS/CodePolicyAPI')
        ->proxy('http://172.17.17.1/soap/code-policy')
        ->on_fault(sub {
            my $SOAP   = shift;
            my $Result = shift;

            my $errorMsg
                = ref($Result)
                    ? $Result->faultstring()
                    : $SOAP->transport->status();
            die "*** SERVER-MSG: $errorMsg\n";
        });

    $SessionID = $SOAP->StartSession({
        ARGV            => \@ARGV,
        ProtocolVersion => $ProtocolVersion,
    })->result;
    if (!$SessionID) {
        die "*** Got no session - could not connect to CodePolicy server.\n";
    }
    print STDERR "ok - remote session ID is $SessionID\n";

    return;
}

sub Disconnect {
    my $ID = $SessionID;
    $SessionID = undef;
    $SOAP->EndSession( $ID );

    return;
}

sub UploadFiles {
    my ( $Mode, $Arg ) = @_;

    my $File = $Mode eq 'Dir' ? undef : basename( $Arg );
    my $Dir  = $Mode eq 'Dir' ? $Arg  : dirname( $Arg );

    my $ParentDir = dirname( $Dir );
    my $SubDir    = basename( $Dir );
    chdir $ParentDir or die "*** unable to chdir into '$ParentDir'! ($!)\n";

    print STDERR "uploading files...";
    if ($Mode eq 'File') {
        UploadFile( "$SubDir/$File" );
        # now check for CVS/Entries and .svn/entries as either of those might be used on server
        # in order to automatically determine the name of the applicable profile
        for my $EntriesFile ( qw( CVS/Entries .svn/entries ) ) {
            if (-e "$SubDir/$EntriesFile") {
                UploadFile( "$SubDir/$EntriesFile" );
            }
        }
    }
    elsif ($Mode eq 'Dir' || $Mode eq 'Module') {
        my $wanted = sub {
            return if -d $File::Find::name;
            UploadFile( $File::Find::name );
        };
        find( { wanted => $wanted, no_chdir => 1 }, $SubDir );
    }
    else {
        die "*** unknown mode '$Mode' given!";
    }
    print STDERR "done\n";

    my $ArgAsRelativePath = $File ? "$SubDir/$File" : $SubDir;
    return $ArgAsRelativePath;
}

sub UploadFile {
    my ( $File ) = @_;

    my $Contents = SlurpFile($File);
    my $MD5Sum = MD5ForFile($File);

    return $SOAP->UploadFile( $SessionID, {
        Filename => $File,
        Contents => encode_base64( $Contents ),
        MD5Sum   => $MD5Sum
    } )->result;
}

sub DownloadFiles {
    my ( $Files ) = @_;

    print STDERR "downloading changed files...";
    for my $File ( @{ $Files } ) {
        DownloadFile( $File );
    }
    print STDERR "done\n";

    return 1;
}

sub DownloadFile {
    my ( $File ) = @_;

    my $FileInfo = $SOAP->DownloadFile( $SessionID, $File )->result;
    die "*** unable to download file '$File'!\n" if !$FileInfo;

    die "*** downloaded file '$File' does not exist on client!\n" if !-e $File;

    my $Contents = decode_base64( $FileInfo->{Contents} );
    OverwriteFile( $File, $Contents, $FileInfo->{MD5Sum} );

    return 1;
}

sub SlurpFile {
    my ( $File ) = @_;

    my $FH;
    open($FH, '<', $File)
        or die "*** could not open file '$File' for reading! ($!)\n";
    if (wantarray()) {
        my @Lines = <$FH>;
        close($FH)
            or die "*** could not close file '$File'! ($!)\n";
        return @Lines;
    }
    local $/ = undef;
    my $Text = <$FH>;
    close($FH)
        or die "*** could not close file '$File'! ($!)\n";
    return $Text;
}

sub OverwriteFile {
    my ( $File, $Content, $RequiredMD5Sum ) = @_;

    my $FH;
    my $TempFile = "${File}_tmp_$$";
    open($FH, '>', $TempFile)
        or die "*** could not open file '$TempFile' for writing! ($!)\n";
    print $FH $Content;
    close($FH)
        or die "*** could not close file '$TempFile'! ($!)\n";
    if (defined $RequiredMD5Sum) {
        my $MD5Sum = MD5ForFile($TempFile);
        if ($RequiredMD5Sum ne $MD5Sum) {
            die "*** wrong MD5-sum for '$File' (server: $RequiredMD5Sum <=> client: $MD5Sum)!\n";
        }
    }
    rename $TempFile, $File
        or die "*** could not rename file '$TempFile' to '$File'! ($!)\n";
    return;
}

sub MD5ForFile {
    my ( $File ) = @_;

    my $Output = qx{md5sum $File};
    return if !$Output;
    return if $Output !~ m{^(\w+)};
    return $1;
}

END {
    # if we still have a session-ID, we need to disconnect, such that the server has a chance
    # to cleanup the session
    if ($SessionID) {
        print STDERR "cleaning up...";
        Disconnect();
        print STDERR "done\n";
    }
}

=head1 NAME

CodePolicy.pl - a tool to remotely execute the OTRS code policy against local code

=head1 SYNOPSIS

CodePolicy.pl [general options] <action> [action-options]

=head3 General Options

    --dry-run                   only pretends to do any changes (for fixes and recodings)
    --help                      brief help message
    --man                       show full documentation
    --verbose                   shows more info (can be given more than once)
    --version                   show version

=head1 ACTIONS

=over

=item B<check-dir [--actions=action-name,...] [--profile=profile-name] Dir>

Checks the given directory recursively against compliance with the OTRS code policy.

During the traversal, dot-files and repository folders (CVS & .svn) will be skipped.

=item B<check-file [--actions=action-name,...] [--profile=profile-name] File>

Checks the given file against compliance with the OTRS code policy.

=item B<check-module [--actions=action-name,...] [--profile=profile-name] ( Module-Dir | Module.sopm )>

Checks the given module (the files in the given module dir) against compliance
with the OTRS code policy.

=item B<fix-dir [--actions=action-name,...] [--profile=profile-name] Dir>

Traverses the given directory recursively and applies all selected fixes to every file found
that does not already comply with the OTRS code policy.

During the traversal, dot-files and repository folders (CVS & .svn) will be skipped.

=item B<fix-file [--actions=action-name,...] [--profile=profile-name] File>

Applies all selected fixes against the given file.

=item B<fix-module [--actions=action-name,...] [--profile=profile-name] ( Module-Dir | Module.sopm )>

Loads and parses the *.sopm file of the given module and applies all selected fixes to the files
exported by the module.

=item B<list-checks [--domain=domain-name] [File]>

Lists all available checks. If a file is given, only the checks appropriate for that file are
listed.

=item B<list-domains>

Lists all available action domains.

=item B<list-fixes [--domain=domain-name] [File]>

Lists all available fixes. If a file is given, only the fixes appropriate for that file are
listed.

=item B<list-profiles>

Lists all available profiles (for checks, fixes and recodings). In verbose mode, the set of actions
defined by each profile is listed, too.

=item B<list-recodings [--domain=domain-name] [File]>

Lists all available recodings. If a file is given, only the recodings appropriate for that file are
listed.

=item B<recode-dir [--actions=action-name,...] [--profile=profile-name] Dir>

Traverses the given directory recursively and applies all selected recodings to every file found
that does not already comply with the OTRS code policy.

During the traversal, dot-files and repository folders (CVS & .svn) will be skipped.

=item B<recode-file [--actions=action-name,...] [--profile=profile-name] File>

Applies all selected recodings against the given file.

=item B<recode-module [--actions=action-name,...] [--profile=profile-name] ( Module-Dir | Module.sopm )>

Loads and parses the *.sopm file of the given module and applies all selected recodings to the files
exported by the module.

=back

=head3 Action Options

    --actions=<string-list>     specifies the list of actions that shall be run
    --domain=<string>           lists only actions applicable for the given domain
    --profile=<string>          sets the profile from which actions are picked

=head1 DESCRIPTION

B<CodePolicy.pl> is using a remote code policy service (via SOAP) to apply certain kinds
of actions against code, in order to implement the OTRS code policy.

It can be used to check and/or fix your code with respect to the standards that are set by
the OTRS code policy.

=head1 TERMS AND CONDITIONS

This Software is part of the OTRS project (http://otrs.org/).

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (GPL). If you
did not receive this file, see http://www.gnu.org/licenses/gpl-2.0.txt.

=cut

=head1 VERSION

$Revision: 1.4 $ $Date: 2008-02-28 15:04:06 $

=cut
