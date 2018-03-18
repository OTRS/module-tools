# --
# Copyright (C) 2001-2018 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Console::Command::Module::Docbook::Generate::ConfigChapter;

use strict;
use warnings;

use File::Basename;

eval { require XML::Simple };
if ($@) {
    die "Can't load XML::Simple: $@";
}

use OTRS::XML::Simple;
use Getopt::Std;

use vars (qw(@ISA));

use parent qw(Console::BaseCommand Console::BaseDocbook);

=head1 NAME

Console::Command::Module::Docbook::Generate::ConfigChapter - Console command to generate module configuration chapter in docbook format.

=head1 DESCRIPTION

Text common functions.

=cut

sub Configure {
    my ( $Self, %Param ) = @_;

    $Self->Description('Generate module Docbook configuration chapter.');
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
    $Self->AddOption(
        Name        => 'sort-by-name',
        Description => "Sort configurations by name.",
        Required    => 0,
        HasValue    => 0,
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

    $Self->Print("<yellow>Generating configuration chapter...</yellow>\n\n");

    # Cleanup module path.
    my $ModuleDirectory = $Self->GetArgument('module-directory');
    $ModuleDirectory =~ s{(.+)/\z}{$1}smx;

    my $Language = $Self->_GetLanguage(
        Language => $Self->GetOption('language') || '',
        ModuleDirectory => $ModuleDirectory,
    );

    $Self->{SortByName} = $Self->GetOption('sort-by-name') // 1;

    my $ConfigVersion      = 1;
    my $ConfigVersion1Path = '/Kernel/Config/Files/';
    my $ConfigVersion2Path = '/Kernel/Config/Files/XML';

    # Get configuration directory inside the module.
    my $ConfigDirectory = $ModuleDirectory . $ConfigVersion1Path;

    if ( -e $ModuleDirectory . $ConfigVersion2Path && -d $ModuleDirectory . $ConfigVersion2Path ) {
        $ConfigDirectory = $ModuleDirectory . $ConfigVersion2Path;
        $ConfigVersion   = 2;
    }
    elsif ( !-e $ConfigDirectory ) {
        $Self->PrintError("Directory does not exists: $ConfigDirectory!\n");
        return $Self->ExitCodeError();
    }

    # Get all config settings from all files.
    $Self->Print("  Parsing XML configuration files...");

    my %ConfigSettings = $Self->_GetConfigSettings(
        ConfigDirectory => $ConfigDirectory,
        ConfigVersion   => $ConfigVersion,
    );

    if ( !%ConfigSettings ) {
        return $Self->ExitCodeError();
    }
    $Self->Print(" <green>done</green>\n");

    for my $FileName ( sort keys %ConfigSettings ) {
        $Self->Print("    Parsed file: <yellow>$FileName</yellow>\n");
    }

    # Convert OTRS SysConfig settings into Docbook friendly format.
    $Self->Print("\n  Formating settings...");

    my @FormatedSettings = $Self->_FormatSettings(
        ConfigSettings => \%ConfigSettings,
        ConfigVersion  => $ConfigVersion,
    );

    $Self->Print(" <green>done</green>\n");

    for my $Setting (@FormatedSettings) {
        my $SettingName = $Setting->{ lc('Title') };
        chop $SettingName;
        $Self->Print("    Added setting: <yellow>$SettingName</yellow>\n");
    }

    # Generate XML Docbook config chapter based in config file.
    $Self->Print("\n  Generating Docbook structure...");

    my $ConfigChapter = $Self->_CreateDocbookConfigChapter(
        FormatedSettings => \@FormatedSettings,
    );
    if ( !$ConfigChapter ) {
        return $Self->ExitCodeError()
    }

    $Self->Print(" <green>done</green>\n");

    # Set output file.
    my $OutputFile = $Self->GetOption('target-filename') // 'ConfigChapter';
    $OutputFile .= '.xml';
    my $TargetLocation = $ModuleDirectory . '/doc/' . $Language . '/' . $OutputFile;

    # Write the XML file in the file system.
    $Self->Print("\n  Writing file $TargetLocation...");

    my $WriteFileSuccess = $Self->WriteDocbookFile(
        Chapter        => $ConfigChapter,
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

# Internal functions.

sub _GetLanguage {
    my ( $Self, %Param ) = @_;

    return 'en' if !$Param{Language};
    return 'en' if $Param{Language} eq 'en';

    # Check if a translation file exists.
    my @TranslationFiles = $Self->_DirectoryRead(
        Directory => "$Param{ModuleDirectory}/Kernel/Language/",
        Filter    => "$Param{Language}_*.pm",
        Silent    => 1,
    );

    return 'en' if !@TranslationFiles;

    # Translation hash.
    $Self->{Translation} = {};

    # Load translation values.
    for my $TranslationFile (@TranslationFiles) {

        my ( $Path, $Module );
        ( $Path, $Module ) = ( $1, $2 )
            if $TranslationFile =~ m{ \A ( .+ ) / ( [^/]+ ) \.pm \z }xms;

        {
            @ISA = ("Kernel::Language::$Module");
            push @INC, "$Path";
            eval {
                require $Module;    ## nofilter(TidyAll::Plugin::OTRS::Perl::Require)

            };
            $Self->Data();
        }
    }
    return $Param{Language};
}

sub _GetConfigSettings {
    my ( $Self, %Param ) = @_;

    # Get all config files from the module.
    my @FilesInDirectory = $Self->_DirectoryRead(
        Directory => $Param{ConfigDirectory},
        Filter    => '*.xml',
    );

    if ( scalar @FilesInDirectory == 0 ) {
        $Self->PrintError("\nNo config files found in $Param{ConfigDirectory}\n");
        return;
    }

    # To store config settings from the original file.
    my %ConfigSettings;

    for my $FileLocation (@FilesInDirectory) {

        my $Result = $Self->_ParseConfigFile(
            FileLocation  => $FileLocation,
            ConfigVersion => $Param{ConfigVersion},
        );

        return if !$Result;

        $ConfigSettings{ $Result->{Filename} } = $Result->{ParsedSettings};
    }

    return %ConfigSettings;
}

sub _ParseConfigFile {
    my ( $Self, %Param ) = @_;

    # Check needed parameters.
    for my $Needed (qw(FileLocation)) {
        if ( !$Param{$Needed} ) {
            print "Need $Needed:!";
            return;
        }
    }

    my $FileLocation = $Param{FileLocation};

    # Check for file in file system.
    return if !$FileLocation;
    if ( !-e $FileLocation ) {
        $Self->PrintError("\nConfig file $FileLocation does not exists!\n");
        return;
    }
    if ( !-r $FileLocation ) {
        $Self->PrintError("\nConfig file $FileLocation could not be read!\n");
        return;
    }

    my $XMLObject = OTRS::XML::Simple->new();

    # Convert XML file to perl structure.
    my $ParsedSettings;
    eval {
        $ParsedSettings = $XMLObject->XMLin($FileLocation);
    };

    # Settings for OTRS 5 and before have ConfigVersion = 1
    #   while for OTRS 6 and beyond have ConfigFersion = 2
    #   each version has some structure differences.
    my $SettingRoot    = 'ConfigItem';
    my $ValueAttribute = 'Setting';
    if ( $Param{ConfigVersion} == 2 ) {
        $SettingRoot    = 'Setting';
        $ValueAttribute = 'Value';
    }

    # Remove not needed (for documentation).
    if ( ref $ParsedSettings->{$SettingRoot} eq 'ARRAY' ) {
        for my $Setting ( @{ $ParsedSettings->{$SettingRoot} } ) {
            delete $Setting->{$ValueAttribute};
        }
    }
    else {
        delete $ParsedSettings->{$SettingRoot}->{$ValueAttribute}
    }

    # Check for conversion errors.
    if ($@) {
        $Self->PrintError("\nThere was an error parsing XML config file: $@\n");
        return;
    }

    # Remove XML extension.
    my $Filename = fileparse($FileLocation);
    $Filename =~ s{\A(.+?) \. .+\z}{$1}xms;

    return {
        Filename       => $Filename,
        ParsedSettings => $ParsedSettings,
    };
}

sub _FormatSettings {
    my ( $Self, %Param ) = @_;

    # Check needed parameters.
    for my $Needed (qw(ConfigSettings ConfigVersion)) {
        if ( !$Param{$Needed} ) {
            print "Need $Needed:!";
            return;
        }
    }

    # Settings for OTRS 5 and before have ConfigVersion = 1
    #   while for OTRS 6 and beyond have ConfigFersion = 2
    #   each version has some structure differences.
    my $SettingRoot = 'ConfigItem';
    if ( $Param{ConfigVersion} == 2 ) {
        $SettingRoot = 'Setting';
    }

    my @ConvertedSettings;

    for my $SettingFile ( sort keys %{ $Param{ConfigSettings} } ) {

        if ( ref $Param{ConfigSettings}->{$SettingFile}->{$SettingRoot} ne 'ARRAY' ) {
            $Param{ConfigSettings}->{$SettingFile}->{$SettingRoot} =
                [ $Param{ConfigSettings}->{$SettingFile}->{$SettingRoot} ];
        }

        for my $Setting (
            sort _SortYesNo @{ $Param{ConfigSettings}->{$SettingFile}->{$SettingRoot} }
            )
        {

            my $DescriptionContent;

            if ( ref $Setting->{Description} ne 'ARRAY' ) {
                $Setting->{Description} = [ $Setting->{Description} ];
            }

            DESCRIPTION:
            for my $Description ( @{ $Setting->{Description} } ) {

                # For legacy documentation with individual languages.
                if ( $Description->{Lang} ) {
                    next DESCRIPTION if $Description->{Lang} ne $Param{Language};

                    $DescriptionContent = $Description->{content};
                    last DESCRIPTION;
                }

                # Only items with 'Translatable' flag from here.
                next DESCRIPTION if !$Description->{Translatable};

                # Get original (English) description first.
                $DescriptionContent = $Description->{content};

                # Check for translation.
                if ( $Self->{Translation}->{$DescriptionContent} ) {
                    $DescriptionContent = $Self->{Translation}->{$DescriptionContent};
                }

                last DESCRIPTION;
            }

            if ( $Param{ConfigVersion} == 1 ) {
                push @ConvertedSettings, {
                    title => $Setting->{Name} . ".",
                    para  => [
                        "Group: $Setting->{Group}, Subgroup: $Setting->{SubGroup}.",
                        $DescriptionContent,
                    ],
                };
            }
            else {
                push @ConvertedSettings, {
                    title => $Setting->{Name} . ".",
                    para  => [
                        "Navigation: $Setting->{Navigation}.",
                        $DescriptionContent,
                    ],
                };
            }
        }
    }

    return @ConvertedSettings;

}

sub _CreateDocbookConfigChapter {
    my ( $Self, %Param ) = @_;

    # Set structure.
    my %Docbook = (
        chapter => {
            title => 'Configuration',
            para =>
                'The package can be configured via the SysConfig in the Admin Interface. The following configuration options are available:',
            section => $Param{FormatedSettings} // [],
        },
    );

    my $XMLObject = OTRS::XML::Simple->new();

    # Convert perl structure into XML structure.
    my $ConfigChapter = eval {
        $XMLObject->XMLout(
            \%Docbook,
            NoAttr   => 1,
            KeepRoot => 1
        );
    };

    if ($@) {
        $Self->PrintError("\nThere was an error converting settings into XML: $@");
        return;
    }

    # IKndentation = 4 spaces.
    my $Indentation = '    ';
    $ConfigChapter =~ s{[ ]{2}}{$Indentation}gmx;

    return $ConfigChapter;
}

sub _SortYesNo {
    my ( $Self, $Param ) = @_;

    if ( $Self->{SortByName} ) {
        return $a->{Name} cmp $b->{Name};
    }

    return 0;
}

1;
