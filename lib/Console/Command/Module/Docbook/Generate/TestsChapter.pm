# --
# Copyright (C) 2001-2017 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Console::Command::Module::Docbook::Generate::TestsChapter;

use strict;
use warnings;

use File::Basename;

eval { require XML::Simple };
if ($@) {
    die "Can't load XML::Simple: $@";
}

use OTRS::XML::Simple;
use Getopt::Std;

use parent qw(Console::BaseCommand Console::BaseDocbook);

=head1 NAME

Console::Command::Module::Docbook::Generate::ConfigChapter - Console command to generate module test chapter in docbook format.

=head1 DESCRIPTION

Text common functions.

=cut

sub Configure {
    my ( $Self, %Param ) = @_;

    $Self->Description('Generate module Docbook tests chapter.');
    $Self->AddArgument(
        Name        => 'module-directory',
        Description => "Specify directory of the module.",
        Required    => 1,
        HasValue    => 1,
        ValueRegex  => qr/.*/smx,
    );
    $Self->AddOption(
        Name        => 'target-filename',
        Description => "Specify the name of the output file.",
        Required    => 0,
        HasValue    => 1,
        ValueRegex  => qr/.*/smx,
    );
    $Self->AddOption(
        Name        => 'language',
        Description => "Specify the language to be used.",
        Required    => 0,
        HasValue    => 1,
        ValueRegex  => qr/.*/smx,
    );

    return;
}

sub PreRun {
    my ($Self) = @_;

    my $ModuleDirectory = $Self->GetArgument('module-directory');

    if ( !-e $ModuleDirectory ) {
        die "$ModuleDirectory does not exist";
    }
    if ( !-d $ModuleDirectory ) {
        die "$ModuleDirectory is not a directory";
    }

    return;
}

sub Run {
    my ($Self) = @_;

    $Self->Print("<yellow>Generating tests chapter...</yellow>\n\n");

    # Cleanup module path.
    my $ModuleDirectory = $Self->GetArgument('module-directory');
    $ModuleDirectory =~ s{(.+)/\z}{$1}smx;

    # Get the unit tests directory inside the module.
    my $UnitTestDirectory = $ModuleDirectory . '/scripts/test';
    if ( !-e $UnitTestDirectory ) {
        $Self->PrintError("Directory does not exists: $UnitTestDirectory!\n");
        return $Self->ExitCodeError();
    }

    # Get all unit test files from the package.
    my @UnitTestFiles = $Self->_GetUnitTestFiles(
        UnitTestDirectory => $UnitTestDirectory,
    );

    if ( !@UnitTestFiles ) {
        return $Self->ExitCodeError();
    }

    # Convert found files into Docbook friendly format.
    $Self->Print("  Formating files... <green>done</green>\n");

    for my $File (@UnitTestFiles) {
        $Self->Print("    Added file: <yellow>$File</yellow>\n");
    }

    # Generate XML Docbook unit test chapter based.
    $Self->Print("\n  Generating Docbook structure...");

    my $Chapter = $Self->_CreateDocbookUnittestChapter(
        FileList => \@UnitTestFiles,
    );

    if ( !$Chapter ) {
        return $Self->ExitCodeError();
    }

    $Self->Print(" <green>done</green>\n");

    # Write the XML file in the file system.
    # Set output file.
    my $OutputFile = $Self->GetOption('target-filename') // 'TestsChapter';
    $OutputFile .= '.xml';
    my $Language = $Self->GetOption('target-filename') // 'en';
    my $TargetLocation = $ModuleDirectory . '/doc/' . $Language . '/' . $OutputFile;

    # wWite the XML file in the file system.
    $Self->Print("\n  Writing file $TargetLocation...");

    my $WriteFileSuccess = $Self->WriteDocbookFile(
        Chapter        => $Chapter,
        TargetLocation => $TargetLocation,
    );

    if ( !$WriteFileSuccess ) {
        return $Self->ExitCodeError()
    }

    $Self->Print(" <green>Done.</green>\n\n<green>Done.</green>\n");

    return $Self->ExitCodeOk();
}

sub PostRun {
    my ($Self) = @_;

    return;
}

1;

sub _GetUnitTestFiles {
    my ( $Self, %Param ) = @_;

    # Get all unit test from the module.
    my @UnitTestFiles = $Self->_DirectoryRead(
        Directory => $Param{UnitTestDirectory},
        Filter    => '*.t',
        Recursive => 1,
    );

    if ( scalar @UnitTestFiles == 0 ) {
        $Self->PrintError("No unit test found in $Param{UnitTestDirectory}\n");
        return;
    }

    return @UnitTestFiles;
}

sub _CreateDocbookUnittestChapter {
    my ( $Self, %Param ) = @_;

    # Check needed parameters.
    for my $Needed (qw(FileList)) {
        if ( !$Param{$Needed} ) {
            $Self->PrintError("Need $Needed:!");
            return;
        }
    }

    my $Chapter = <<"XML";
<chapter>
    <title>Tests</title>
    <para>
        This module has been tested on the current state of the art in quality.
    </para>
    <section>
        <title>Test Cases</title>
        <para>
            To test this package please follow the examples described in the Usage section.
        </para>
    </section>
XML

    if ( !@{ $Param{FileList} } ) {
        $Chapter .= '<!--'
    }

    $Chapter .= <<"XML";
    <section>
        <title>Unit Test</title>
        <para>
            To ensure the quality of the module, several so-called unit tests were created, to test
            the functionalities of this module. These unit tests can be run via command line.
        </para>
        <para>
            ATTENTION: Please never run unit tests on a productive system, since the added test
            data to the system will no longer be removed. Always use a test system.
        </para>
        <para>Run the package specific unit tests</para>
        <para>
            To run only the unit test which will be delivered with this package, use the following
            command on the command line:
        </para>
         <para>
            <screen>
XML

    if ( !@{ $Param{FileList} } ) {
        $Chapter .= 'shell> perl bin/otrs.Console.pl Dev::UnitTest::Run -- test'
    }

    for my $File ( sort { "\L$a" cmp "\L$b" } @{ $Param{FileList} } ) {

        $File =~ s{./scripts/test/}{}msxi;
        $File =~ s{\.t\z}{}msxi;

        $Chapter .= "shell> perl bin/otrs.Console.pl Dev::UnitTest::Run --test $File\n";
    }

    $Chapter .= << "XML";
            </screen>
        </para>
        <para>
            Run all available unit tests
        </para>
        <para>
            To run all available unit tests, use the following command on the command line:
        </para>
        <para>
            <screen>
shell> perl bin/otrs.Console.pl Dev::UnitTest::Run
            </screen>
        </para>
    </section>
XML

    if ( !@{ $Param{FileList} } ) {
        $Chapter .= "-->\n";
    }

    $Chapter .= '</chapter>';

    return $Chapter;
}

1;

=head1 TERMS AND CONDITIONS

This software is part of the OTRS project (L<http://otrs.org/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (AGPL). If you
did not receive this file, see L<http://www.gnu.org/licenses/agpl.txt>.

=cut
