#!/usr/bin/perl -w
# --
# CodePolicy.pl - a tool to remotely execute the OTRS code policy against local code
# Copyright (C) 2001-2008 OTRS AG, http://otrs.org/
# --
# $Id: CodePolicy.pl,v 1.1 2008-02-20 22:41:50 ot Exp $
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

our $VERSION = qw($Revision: 1.1 $) [1];

use SOAP::Lite;

my $ProtocolVersion = 1;

my $SOAP = SOAP::Lite
    ->uri('http://otrs.org/OTRS/CodePolicy/SOAPRunner')
    ->proxy('http://172.17.17.1/soap/otrs-code-policy')
    ->on_fault(sub {
        my $SOAP   = shift;
        my $Result = shift;

        my $errorMsg
            = ref($Result)
                ? $Result->faultstring()
                : $SOAP->transport->status();
        die "*** SOAP-ERROR: $errorMsg\n";
    });

my $SessionCookie = $SOAP->StartSession({
    ARGV            => \@ARGV,
    ProtocolVersion => $ProtocolVersion,
})->result;
if (!$SessionCookie) {
    die "*** Got no session - could not connect to CodePolicy server.\n";
}

# start processing loop (single stepping through all different protocol stages
my ( $NextStep, $StepResult );
while( $NextStep = $SOAP->NextStep( $SessionCookie, $StepResult ) ) {
    $StepResult = ExecuteStep( $NextStep );
}

# cleanup session
$SOAP->EndSession( $SessionCookie );

sub ExecuteStep {
    my ( $Step ) = @_;

    my $Result;

    return $Result;
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
    --svnlook=<string>          defines the svnlook binary to use when checking
                                a subversion commit.

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

$Revision: 1.1 $ $Date: 2008-02-20 22:41:50 $

=cut
