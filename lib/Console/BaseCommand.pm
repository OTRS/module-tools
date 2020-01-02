# --
# Copyright (C) 2001-2020 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

## nofilter(TidyAll::Plugin::OTRS::Perl::Require)
package Console::BaseCommand;

use strict;
use warnings;

use Term::ANSIColor();
use IO::Interactive();
use File::Basename qw(dirname);

use Getopt::Long();

use Encode;

our $SuppressANSI = 0;

=head1 NAME

Console::BaseCommand - command base class

=head1 PUBLIC INTERFACE

=head2 new()

constructor for new objects. You should not need to re-implement this in your command,
override L</Configure()> instead if you need to.

=cut

sub new {
    my ( $Type, %Param ) = @_;

    my $Self = {};
    bless $Self, $Type;

    # for usage help
    $Self->{Name} = $Type;
    $Self->{Name} =~ s{Console::Command::}{}smx;

    $Self->{ANSI} = 1;

    # Check if we are in an interactive terminal, disable colors otherwise.
    if ( !IO::Interactive::is_interactive() ) {
        $Self->{ANSI} = 0;
    }

    # Force creation of the EncodeObject as it initializes STDOUT/STDERR for unicode output.
    #$Kernel::OM->Get('Kernel::System::Encode');

    # Call object specific configure method. We use an eval to trap any exceptions
    #   that might occur here. Only if everything was OK we set the _ConfigureSuccessful
    #   flag.
    eval {
        $Self->Configure();
        $Self->{_ConfigureSuccessful} = 1;
    };

    $Self->{_GlobalOptions} = [
        {
            Name        => 'help',
            Description => 'Display help for this command.',
        },
        {
            Name        => 'no-ansi',
            Description => 'Do not perform ANSI terminal output coloring.',
        },
        {
            Name        => 'quiet',
            Description => 'Suppress informative output, only retain error messages.',
        },
        {
            Name => 'allow-root',
            Description =>
                'Allow root user to execute the command. This might damage your system; use at your own risk.',
            Invisible => 1,    # hide from usage screen
        },
    ];

    $Self->{Config} = $Self->_GetConfig();

    return $Self;
}

=head2 Configure()

initializes this object. Override this method in your commands.

This method might throw exceptions.

=cut

sub Configure {
    return;
}

=head2 Name()

get the Name of the current Command, e. g. 'Admin::User::SetPassword'.

=cut

sub Name {
    my ($Self) = @_;

    return $Self->{Name};
}

=head2 Description()

get/set description for the current command. Call this in your Configure() method.

=cut

sub Description {
    my ( $Self, $Description ) = @_;

    $Self->{Description} = $Description if defined $Description;

    return $Self->{Description};
}

=head2 AdditionalHelp()

get/set additional help text for the current command. Call this in your Configure() method.

You can use color tags (see L</Print()>) in your help tags.

=cut

sub AdditionalHelp {
    my ( $Self, $AdditionalHelp ) = @_;

    $Self->{AdditionalHelp} = $AdditionalHelp if defined $AdditionalHelp;

    return $Self->{AdditionalHelp};
}

=head2 AddArgument()

adds an argument that can/must be specified on the command line.
This function must be called during Configure() by the command to
indicate which arguments it can process.

    $CommandObject->AddArgument(
        Name         => 'filename',
        Description  => 'name of the file to be loaded',
        Required     => 1,
        ValueRegex   => qr{a-zA-Z0-9]\.txt},
    );

Please note that required arguments have to be specified before any optional ones.

The information about known arguments and options (see below) will be used to generate
usage help and also to automatically verify the data provided by the user on the command line.

=cut

sub AddArgument {
    my ( $Self, %Param ) = @_;

    for my $Key (qw(Name Description ValueRegex)) {
        if ( !$Param{$Key} ) {
            $Self->PrintError("Need $Key.");
            die;
        }
    }

    for my $Key (qw(Required)) {
        if ( !defined $Param{$Key} ) {
            $Self->PrintError("Need $Key.");
            die;
        }
    }

    if ( $Self->{_ArgumentSeen}->{ $Param{Name} }++ ) {
        $Self->PrintError("Cannot register argument '$Param{Name}' twice.");
        die;
    }

    if ( $Self->{_OptionSeen}->{ $Param{Name} } ) {
        $Self->PrintError("Cannot add argument '$Param{Name}', because it is already registered as an option.");
        die;
    }

    $Self->{_Arguments} //= [];
    push @{ $Self->{_Arguments} }, \%Param;

    return;
}

=head2 GetArgument()

fetch an argument value as provided by the user on the command line.

    my $Filename = $CommandObject->GetArgument('filename');

=cut

sub GetArgument {
    my ( $Self, $Argument ) = @_;

    if ( !$Self->{_ArgumentSeen}->{$Argument} ) {
        $Self->PrintError("Argument '$Argument' was not configured and cannot be accessed.");
        return;
    }

    return $Self->{_ParsedARGV}->{Arguments}->{$Argument};
}

=head2 AddOption()

adds an option that can/must be specified on the command line.
This function must be called during L</Configure()> by the command to
indicate which arguments it can process.

    $CommandObject->AddOption(
        Name         => 'iterations',
        Description  => 'number of script iterations to perform',
        Required     => 1,
        HasValue     => 0,
        ValueRegex   => qr{\d+},
        Multiple     => 0,  # optional, allow more than one occurrence (only possible if HasValue is true)
    );

=head3 Option Naming Conventions

If there is a source and a target involved in the command, the related options should start
with C<--source> and C<--target>, for example C<--source-path>.

For specifying file system locations, C<--*-path> should be used for directory/filename
combinations (e.g. C<mydirectory/myfile.pl>), C<--*-filename> for filenames without directories,
and C<--*-directory> for directories.

Example: C<--target-path /tmp/test.out --source-filename test.txt --source-directory /tmp>

=cut

sub AddOption {
    my ( $Self, %Param ) = @_;

    for my $Key (qw(Name Description)) {
        if ( !$Param{$Key} ) {
            $Self->PrintError("Need $Key.");
            die;
        }
    }

    for my $Key (qw(Required HasValue)) {
        if ( !defined $Param{$Key} ) {
            $Self->PrintError("Need $Key.");
            die;
        }
    }

    if ( $Param{HasValue} ) {
        if ( !$Param{ValueRegex} ) {
            $Self->PrintError("Need ValueRegex.");
            die;
        }
    }

    if ( $Param{Multiple} && !$Param{HasValue} ) {
        $Self->PrintError("Multiple can only be specified if HasValue is true.");
        die;
    }

    if ( $Self->{_OptionSeen}->{ $Param{Name} }++ ) {
        $Self->PrintError("Cannot register option '$Param{Name}' twice.");
        die;
    }

    if ( $Self->{_ArgumentSeen}->{ $Param{Name} } ) {
        $Self->PrintError("Cannot add option '$Param{Name}', because it is already registered as an argument.");
        die;
    }

    $Self->{_Options} //= [];
    push @{ $Self->{_Options} }, \%Param;

    return;

}

=head2 GetOption()

fetch an option as provided by the user on the command line.

    my $Iterations = $CommandObject->GetOption('iterations');

If the option was specified with HasValue => 1, the user provided value will be
returned. Otherwise 1 will be returned if the option was present.

In case of an option with C<Multiple => 1>, an array reference will be returned
if the option was specified, and undef otherwise.

=cut

sub GetOption {
    my ( $Self, $Option ) = @_;

    if ( !$Self->{_OptionSeen}->{$Option} ) {
        $Self->PrintError("Option '--$Option' was not configured and cannot be accessed.");
        return;
    }

    return $Self->{_ParsedARGV}->{Options}->{$Option};
}

=head2 PreRun()

perform additional validations/preparations before Run(). Override this method in your commands.

If this method returns, execution will be continued. If it throws an exception with die(), the program aborts at this point, and Run() will not be called.

=cut

sub PreRun {
    return 1;
}

=head2 Run()

runs the command. Override this method in your commands.

This method needs to return the exit code to be used for the whole program.
For this, the convenience methods ExitCodeOk() and ExitCodeError() can be used.

In case of an exception, the error code will be set to 1 (error).

=cut

sub Run {
    my $Self = shift;

    return $Self->ExitCodeOk();
}

=head2 PostRun()

perform additional cleanups after Run(). Override this method in your commands.

The return value of this method will be ignored. It will be called after Run(), even
if Run() caused an exception or returned an error exit code.

In case of an exception in this method, the exit code will be set to 1 (error) if
Run() returned 0 (OK).

=cut

sub PostRun {
    return;
}

=head2 Execute()

this method will parse/validate the command line arguments supplied by the user.
If that was OK, the Run() method of the command will be called.

=cut

sub Execute {
    my ( $Self, @CommandlineArguments ) = @_;

    my $ParsedGlobalOptions = $Self->_ParseGlobalOptions( \@CommandlineArguments );

    # Store allow root global option for future use.
    if ( $ParsedGlobalOptions->{'allow-root'} ) {
        $Self->{AllowRoot} = 1;
    }

    # Don't allow to run these scripts as root.
    if ( !$ParsedGlobalOptions->{'allow-root'} && $> == 0 ) {    # $EFFECTIVE_USER_ID
        $Self->PrintError(
            "You cannot run otrs.ModuleTools.pl as root. Please run it as the 'otrs' user or with the help of su:"
        );
        $Self->Print("  <yellow>su -c \"bin/otrs.ModuleTools.pl MyCommand\" -s /bin/bash otrs</yellow>\n");
        return $Self->ExitCodeError();
    }

    # Only run if the command was setup OM.
    if ( !$Self->{_ConfigureSuccessful} ) {
        $Self->PrintError("Aborting because the command was not successfully configured.");
        return $Self->ExitCodeError();
    }

    # First handle the optional global options.
    if ( $ParsedGlobalOptions->{'no-ansi'} ) {
        $Self->ANSI(0);
    }

    if ( $ParsedGlobalOptions->{help} ) {
        print "\n" . $Self->GetUsageHelp();
        return $Self->ExitCodeOk();
    }

    if ( $ParsedGlobalOptions->{quiet} ) {
        $Self->{Quiet} = 1;
    }

    # Parse command line arguments and bail out in case of error,
    # of course with a helpful usage screen.
    $Self->{_ParsedARGV} = $Self->_ParseCommandlineArguments( \@CommandlineArguments );
    if ( !%{ $Self->{_ParsedARGV} // {} } ) {
        print STDERR "\n" . $Self->GetUsageHelp();
        return $Self->ExitCodeError();
    }

    eval { $Self->PreRun(); };
    if ($@) {
        $Self->PrintError($@);
        return $Self->ExitCodeError();
    }

    # Make sure we get a proper exit code to return to the shell.
    my $ExitCode;
    eval {
        # Make sure that PostRun() works even if a user presses ^C.
        local $SIG{INT} = sub {
            $Self->PostRun();
            exit $Self->ExitCodeError();
        };
        $ExitCode = $Self->Run();
    };
    if ($@) {
        $Self->PrintError($@);
        $ExitCode = $Self->ExitCodeError();
    }

    eval { $Self->PostRun(); };
    if ($@) {
        $Self->PrintError($@);
        $ExitCode ||= $Self->ExitCodeError();    # switch from 0 (OK) to error
    }

    if ( !defined $ExitCode ) {
        $Self->PrintError("Command $Self->{Name} did not return a proper exit code.");
        $ExitCode = $Self->ExitCodeError();
    }

    return $ExitCode;
}

=head2 ExitCodeError()

returns an exit code to signal something went wrong (mostly for better
code readability).

    return $CommandObject->ExitCodeError();

You can also provide a custom error code for special use cases:

    return $CommandObject->ExitCodeError(255);

=cut

sub ExitCodeError {
    my ( $Self, $CustomExitCode ) = @_;

    return $CustomExitCode // 1;
}

=head2 ExitCodeOk()

returns 0 as exit code to indicate everything went fine in the command
(mostly for better code readability).

=cut

sub ExitCodeOk {
    return 0;
}

=head2 GetUsageHelp()

generates usage / help screen for this command.

    my $UsageHelp = $CommandObject->GetUsageHelp();

=cut

sub GetUsageHelp {
    my $Self = shift;

    my $UsageText = "<green>$Self->{Description}</green>\n";
    $UsageText .= "\n<yellow>Usage:</yellow>\n";
    $UsageText .= " otrs.ModuleTools.pl $Self->{Name}";

    my $OptionsText   = "<yellow>Options:</yellow>\n";
    my $ArgumentsText = "<yellow>Arguments:</yellow>\n";

    OPTION:
    for my $Option ( @{ $Self->{_Options} // [] } ) {
        my $OptionShort = "--$Option->{Name}";
        if ( $Option->{HasValue} ) {
            $OptionShort .= " ...";
            if ( $Option->{Multiple} ) {
                $OptionShort .= "(+)";
            }
        }
        if ( !$Option->{Required} ) {
            $OptionShort = "[$OptionShort]";
        }
        $UsageText   .= " $OptionShort";
        $OptionsText .= sprintf " <green>%-30s</green> - %s", $OptionShort, $Option->{Description} . "\n";
    }

    # Global options only show up at the end of the options section, but not in the command line string as
    #   they don't actually belong to the current command (only).
    GLOBALOPTION:
    for my $Option ( @{ $Self->{_GlobalOptions} // [] } ) {
        next GLOBALOPTION if $Option->{Invisible};
        my $OptionShort = "[--$Option->{Name}]";
        $OptionsText .= sprintf " <green>%-30s</green> - %s", $OptionShort, $Option->{Description} . "\n";
    }

    ARGUMENT:
    for my $Argument ( @{ $Self->{_Arguments} // [] } ) {
        my $ArgumentShort = $Argument->{Name};
        if ( !$Argument->{Required} ) {
            $ArgumentShort = "[$ArgumentShort]";
        }
        $UsageText     .= " $ArgumentShort";
        $ArgumentsText .= sprintf " <green>%-30s</green> - %s", $ArgumentShort,
            $Argument->{Description} . "\n";
    }

    $UsageText .= "\n";

    $UsageText .= "\n$OptionsText";    # Always present because of global options

    if ( @{ $Self->{_Arguments} // [] } ) {
        $UsageText .= "\n$ArgumentsText";
    }

    if ( $Self->AdditionalHelp() ) {
        $UsageText .= "\n<yellow>Help:</yellow>\n";
        $UsageText .= $Self->AdditionalHelp();
    }

    $UsageText .= "\n";

    return $Self->_ReplaceColorTags($UsageText);
}

=head2 ANSI()

get/set support for colored text.

=cut

sub ANSI {
    my ( $Self, $ANSI ) = @_;

    $Self->{ANSI} = $ANSI if defined $ANSI;
    return $Self->{ANSI};
}

=head2 PrintError()

shorthand method to print an error message to STDERR.

It will be prefixed with 'Error: ' and colored in red,
if the terminal supports it (see L</ANSI()>).

=cut

sub PrintError {
    my ( $Self, $Text ) = @_;

    chomp $Text;
    print STDERR $Self->_Color( 'red', "Error: $Text\n" );
    return;
}

=head2 Print()

this method will print the given text to STDOUT.

You can add color tags (C<< <green>...</green>, <yellow>...</yellow>, <red>...</red> >>)
to your text, and they will be replaced with the corresponding terminal escape sequences
if the terminal supports it (see L</ANSI()>).

=cut

sub Print {
    my ( $Self, $Text ) = @_;

    if ( !$Self->{Quiet} ) {
        print $Self->_ReplaceColorTags($Text);
    }
    return;
}

=head2 DirectoryRead()

reads a directory and returns an array with results.

    my @FilesInDirectory = $CommandObject->DirectoryRead(
        Directory => '/tmp',
        Filter    => 'Filenam*',
    );

=cut

sub DirectoryRead {
    my ( $Self, %Param ) = @_;

    # Check needed params.
    for my $Needed (qw(Directory Filter)) {
        if ( !$Param{$Needed} ) {
            return;
        }
    }

    # If directory doesn't exists stop.
    if ( !-d $Param{Directory} ) {
        return;
    }

    # Prepare non array filter.
    if ( ref $Param{Filter} ne 'ARRAY' ) {
        $Param{Filter} = [ $Param{Filter} ];
    }

    # Executes glob for every filter.
    my @GlobResults;
    my %Seen;

    for my $Filter ( @{ $Param{Filter} } ) {
        my @Glob = glob "$Param{Directory}/$Filter";

        # Look for repeated values.
        NAME:
        for my $GlobName (@Glob) {

            next NAME if !-e $GlobName;
            if ( !$Seen{$GlobName} ) {
                push @GlobResults, $GlobName;
                $Seen{$GlobName} = 1;
            }
        }
    }

    # If no results.
    return if !@GlobResults;

    # Compose normalize every name in the file list.
    my @Results;
    for my $Filename (@GlobResults) {

        # First convert filename to utf-8 if utf-8 is used internally.
        Encode::_utf8_on($Filename);

        push @Results, $Filename;
    }

    # Always sort the result.
    @Results = sort @Results;

    return @Results;
}

=head2 _ParseGlobalOptions()

parses any global options possibly provided by the user.

Returns a hash with the option values.

=cut

sub _ParseGlobalOptions {
    my ( $Self, $Arguments ) = @_;

    Getopt::Long::Configure('pass_through');
    Getopt::Long::Configure('no_auto_abbrev');

    my %OptionValues;

    OPTION:
    for my $Option ( @{ $Self->{_GlobalOptions} } ) {
        my $Value;
        my $Lookup = $Option->{Name};

        Getopt::Long::GetOptionsFromArray(
            $Arguments,
            $Lookup => \$Value,
        );

        $OptionValues{ $Option->{Name} } = $Value;
    }

    return \%OptionValues;
}

=head2 _ParseCommandlineArguments()

parses and validates the command line arguments provided by the user according to
the configured arguments and options of the command.

Returns a hash with argument and option values if all needed values were supplied
and correct, or undef otherwise.

=cut

sub _ParseCommandlineArguments {
    my ( $Self, $Arguments ) = @_;

    Getopt::Long::Configure('pass_through');
    Getopt::Long::Configure('no_auto_abbrev');

    my %OptionValues;

    OPTION:
    for my $Option ( @{ $Self->{_Options} // [] }, @{ $Self->{_GlobalOptions} } ) {
        my $Lookup = $Option->{Name};
        if ( $Option->{HasValue} ) {
            $Lookup .= '=s';
            if ( $Option->{Multiple} ) {
                $Lookup .= '@';
            }
        }

        # Option with multiple values
        if ( $Option->{HasValue} && $Option->{Multiple} ) {

            my @Values;

            Getopt::Long::GetOptionsFromArray(
                $Arguments,
                $Lookup => \@Values,
            );

            if ( !@Values ) {
                if ( !$Option->{Required} ) {
                    next OPTION;
                }

                $Self->PrintError("please provide option '--$Option->{Name}'.");
                return;
            }

            for my $Value (@Values) {
                if ( $Option->{HasValue} && $Value !~ $Option->{ValueRegex} ) {
                    $Self->PrintError("please provide a valid value for option '--$Option->{Name}'.");
                    return;
                }
            }

            $OptionValues{ $Option->{Name} } = \@Values;
        }

        # Option with no or a single value
        else {

            my $Value;

            Getopt::Long::GetOptionsFromArray(
                $Arguments,
                $Lookup => \$Value,
            );

            if ( !defined $Value ) {
                if ( !$Option->{Required} ) {
                    next OPTION;
                }

                $Self->PrintError("please provide option '--$Option->{Name}'.");
                return;
            }

            if ( $Option->{HasValue} && $Value !~ $Option->{ValueRegex} ) {
                $Self->PrintError("please provide a valid value for option '--$Option->{Name}'.");
                return;
            }

            $OptionValues{ $Option->{Name} } = $Value;
        }
    }

    my %ArgumentValues;

    ARGUMENT:
    for my $Argument ( @{ $Self->{_Arguments} // [] } ) {
        if ( !@{$Arguments} ) {
            if ( !$Argument->{Required} ) {
                next ARGUMENT;
            }

            $Self->PrintError("please provide a value for argument '$Argument->{Name}'.");
            return;
        }

        my $Value = shift @{$Arguments};

        if ( $Value !~ $Argument->{ValueRegex} ) {
            $Self->PrintError("please provide a valid value for argument '$Argument->{Name}'.");
            return;
        }

        $ArgumentValues{ $Argument->{Name} } = $Value;
    }

    # check for superfluous arguments
    if ( @{$Arguments} ) {
        my $Error = "found unknown arguments on the command line ('";
        $Error .= join "', '", @{$Arguments};
        $Error .= "').\n";
        $Self->PrintError($Error);
        return;
    }

    return {
        Options   => \%OptionValues,
        Arguments => \%ArgumentValues,
    };
}

=head2 _Color()

this will color the given text (see Term::ANSIColor::color()) if
ANSI output is available and active, otherwise the text stays unchanged.

    my $PossiblyColoredText = $CommandObject->_Color('green', $Text);

=cut

sub _Color {
    my ( $Self, $Color, $Text ) = @_;

    return $Text if !$Self->{ANSI};
    return $Text if $SuppressANSI;
    return Term::ANSIColor::color($Color) . $Text . Term::ANSIColor::color('reset');
}

sub _ReplaceColorTags {
    my ( $Self, $Text ) = @_;
    $Text =~ s{<(green|yellow|red)>(.*?)</\1>}{$Self->_Color($1, $2)}gsmxe;
    return $Text;
}

sub _GetConfig {
    my $Self = @_;

    my $ModuleToolsDirectory = dirname( dirname( dirname( File::Spec->rel2abs(__FILE__) ) ) );

    my %Config;

    my $ConfigPath = "$ModuleToolsDirectory/etc/config.pl";
    if ( -e $ConfigPath ) {
        %Config = %{ do $ConfigPath };
    }

    $Config{ModuleToolsDirectory} = $ModuleToolsDirectory;

    return \%Config;

}

1;
