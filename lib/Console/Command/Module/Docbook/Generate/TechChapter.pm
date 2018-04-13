# --
# Copyright (C) 2001-2018 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Console::Command::Module::Docbook::Generate::TechChapter;

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

Console::Command::Module::Docbook::Generate::TechChapter - Console command to generate module technical implementation chapter in docbook format.

=head1 DESCRIPTION

Text common functions.

=cut

sub Configure {
    my ( $Self, %Param ) = @_;

    $Self->Description('Generate module Docbook technical implementation chapter.');
    $Self->AddArgument(
        Name        => 'module-directory',
        Description => "Specify directory of the module.",
        Required    => 1,
        HasValue    => 1,
        ValueRegex  => qr/.*/smx,
    );
    $Self->AddArgument(
        Name        => 'framework-directory',
        Description => "Specify directory of the framework.",
        Required    => 0,
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

    my @Directories = ( $Self->GetArgument('module-directory') );

    my $FrameworkDirectory = $Self->GetArgument('framework-directory');

    if ($FrameworkDirectory) {
        push @Directories, $FrameworkDirectory;
    }

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

    $Self->Print("<yellow>Generating technical implementation chapter...</yellow>\n\n");

    # cleanup module path
    my $ModuleDirectory = $Self->GetArgument('module-directory');
    $ModuleDirectory =~ s{(.+)/\z}{$1}smx;

    my $FrameworkDirectory = $Self->GetArgument('framework-directory') // '';

    # Get actual package files.
    my @PackageFiles = $Self->_GetPackageFiles(
        ModuleDirectory    => $ModuleDirectory,
        FrameworkDirectory => $FrameworkDirectory,
    );

    if ( !@PackageFiles ) {
        return $Self->ExitCodeError();
    }

    # Convert found files into Docbook friendly format.
    $Self->Print("  Formating files...");

    my @FormatedFiles = $Self->_FormatFiles(
        PackageFiles       => \@PackageFiles,
        FrameworkDirectory => $FrameworkDirectory,
    );

    $Self->Print(" <green>done</green>\n");

    for my $File (@FormatedFiles) {
        my $FileName = $File->{ lc('Title') };
        chop $FileName;
        $Self->Print("    Added file: <yellow>$FileName</yellow>\n");
    }

    # Generate XML Docbook config chapter based in config file.
    $Self->Print("\n  Generating Docbook structure...");

    my $Chapter = $Self->_CreateDocbookTechChapter(
        FormatedFiles => \@FormatedFiles,
    );

    if ( !$Chapter ) {
        return $Self->ExitCodeError();
    }

    $Self->Print(" <green>done</green>\n");

    # Set output file.
    my $OutputFile = $Self->GetOption('target-filename') // 'TechChapter';
    $OutputFile .= '.xml';
    my $Language       = $Self->GetOption('language') // 'en';
    my $TargetLocation = $ModuleDirectory . '/doc/' . $Language . '/' . $OutputFile;

    # Write the XML file in the file system.
    $Self->Print("\n  Writing file $TargetLocation...");

    my $WriteFileSuccess = $Self->WriteDocbookFile(
        Chapter        => $Chapter,
        TargetLocation => $TargetLocation,
    );

    if ( !$WriteFileSuccess ) {
        return $Self->ExitCodeError();
    }

    $Self->Print(" <green>Done.</green>\n\n<green>Done.</green>\n");

    return $Self->ExitCodeOk();
}

sub PostRun {
    my ($Self) = @_;

    return;
}

sub _GetPackageFiles {
    my ( $Self, %Param ) = @_;

    # Get all files from the module.
    my @FilesInDirectory = $Self->_DirectoryRead(
        Directory => $Param{ModuleDirectory},
        Filter    => '*',
        Recursive => 1,
    );

    if ( scalar @FilesInDirectory == 0 ) {
        $Self->PrintError("No files found in $Param{ModulePath}\n");
        return;
    }

    my @PackageFiles;

    FILE:
    for my $File (@FilesInDirectory) {

        next FILE if -d $File;
        next FILE if $File =~ m{/doc}msi;
        next FILE if $File =~ m{/development}msi;

        # Clean file name.
        $File =~ s{$Param{ModuleDirectory}/}{};

        if ( $File =~ m{(.*)\.sopm}msi ) {
            my $ModuleName = $1;

            # Check if SOPM can be found in the given framework.
            if ( $Param{FrameworkDirectory} && -e "$Param{FrameworkDirectory}$File" ) {
                $Self->PrintError("The package '$ModuleName' should not be linked into the framework!\n");
                return;
            }

            next FILE;
        }

        push @PackageFiles, $File;
    }

    return @PackageFiles;
}

sub _FormatFiles {
    my ( $Self, %Param ) = @_;

    my @ProcessedFiles;

    for my $File ( sort { "\L$a" cmp "\L$b" } @{ $Param{PackageFiles} } ) {

        my $DescriptionContent = _GetDecription($File);

        my $Type = 'New';
        if ( $File =~ m{\ACustom}msi ) {
            $Type = 'Change';
        }
        elsif ( $Param{FrameworkDirectory} && -e "$Param{FrameworkDirectory}$File" ) {
            $Type = 'Change';
        }

        push @ProcessedFiles, {
            title => "$File.",
            para  => [
                "$Type: $DescriptionContent",
            ],
        };
    }

    return @ProcessedFiles;
}

sub _GetDecription {
    my $File = shift;

    my %DefaultUsedLanguages = (
        'ar_SA'   => 'Arabic (Saudi Arabia)',
        'bg'      => 'Bulgarian',
        'ca'      => 'Catalan',
        'cs'      => 'Czech',
        'da'      => 'Danish',
        'de'      => 'German',
        'en'      => 'English (United States)',
        'en_CA'   => 'English (Canada)',
        'en_GB'   => 'English (United Kingdom)',
        'es'      => 'Spanish',
        'es_CO'   => 'Spanish (Colombia)',
        'es_MX'   => 'Spanish (Mexico)',
        'et'      => 'Estonian',
        'el'      => 'Greek',
        'fa'      => 'Persian',
        'fi'      => 'Finnish',
        'fr'      => 'French',
        'fr_CA'   => 'French (Canada)',
        'gl'      => 'Galician',
        'he'      => 'Hebrew',
        'hi'      => 'Hindi',
        'hr'      => 'Croatian',
        'hu'      => 'Hungarian',
        'it'      => 'Italian',
        'ja'      => 'Japanese',
        'lt'      => 'Lithuanian',
        'lv'      => 'Latvian',
        'ms'      => 'Malay',
        'nl'      => 'Nederlands',
        'nb_NO'   => 'Norwegian',
        'pt_BR'   => 'Portuguese (Brasil)',
        'pt'      => 'Portuguese',
        'pl'      => 'Polish',
        'ru'      => 'Russian',
        'sl'      => 'Slovenian',
        'sr_Latn' => 'Serbian Latin',
        'sr_Cyrl' => 'Serbian Cyrillic',
        'sk_SK'   => 'Slovak',
        'sv'      => 'Swedish',
        'sw'      => 'Swahili',
        'tr'      => 'Turkish',
        'uk'      => 'Ukrainian',
        'vi_VN'   => 'Vietnam',
        'zh_CN'   => 'Chinese (Simplified)',
        'zh_TW'   => 'Chinese (Traditional)',
    );

    my %DefaultDescriptions = (
        'Kernel/Config/Files' =>
            'Configuration file that holds the required settings for the correct functionality of this package.',
        'Kernel/GenericInterface/Invoker'      => 'Generic interface invoker module that...',
        'Kernel/GenericInterface/Mapping'      => 'Generic interface mapping module that...',
        'Kernel/GenericInterface/Operation'    => 'Generic interface operation module that...',
        'Kernel/GenericInterface/Transport'    => 'Generic interface transport module that...',
        'Kernel/Modules'                       => 'Front-end module',
        'Kernel/Output/HTML/FilterElementPost' => 'Output filter that ...',
        'Kernel/Output/HTML/NavBar'            => 'Navigation bar module that ...',
        'Kernel/Output/HTML/Layout'            => 'Layout module that ...',
        'Kernel/Output/HTML/Templates'         => 'HTML template file for ...',
        'Kernel/Output/HTML/Preferences'       => 'Preferences module that ...',
        'Kernel/Output/HTML/Toolbar'           => 'Tool bard module for ...',
        'Kernel/System/'                       => 'Core module ...',
        'Kernel/System/Console/Command'        => 'Console command ...',
        'Kernel/System/PostMaster'             => 'Postmaster module that ...',
        'Kernel/System/Stats/Dynamic/'         => 'Dynamic statistic module that...',
        'Kernel/System/Stats/Static/'          => 'Static statistic module that...',
        'Kernel/System/Ticket'                 => 'Ticket module that redefines ...',
        'Kernel/System/Ticket/Acl/'            => 'Ticket ACL module that ...',
        'scripts/test'                         => 'Test file for ...',
        'skins/Agent'                          => 'Agent css file to ...',
        'skins/Customer'                       => 'Customer css file to ...',
        'var/packagesetup/'                    => 'Package helper to perform code operations during package setup.',
        'var/httpd/htdocs/js'                  => 'JavaScript file that ...',
        'var/stats/'                           => 'Statistics template for ...',
    );

    my $DescriptionContent = '...';

    # If the file is a language module.
    if ( $File =~ m{Kernel/Language}msi ) {

        my $LanguageCode;

        # Get language code from the language file e.g. 'en' from 'Kernel/Language/en_MyModule'.
        if ( $File =~ m{Kernel/Language/(.*)_.*\.pm} ) {
            $LanguageCode = $1 // '';
        }

        $DescriptionContent = 'Translation file for this package.';

        # Add specific description if language was found.
        if ( $LanguageCode && $DefaultUsedLanguages{$LanguageCode} ) {
            $DescriptionContent = "$DefaultUsedLanguages{$LanguageCode} translation file for this package.";
        }
    }
    else {

        # Check if its an event module.
        if ( $File =~ m{Kernel/System/(\w+)/Event}i ) {
            $DescriptionContent = "$1 event module to...";
        }
        else {

            # Otherwise, check the default descriptions  based on the directory from bottom to up
            #   (to get more specific directories first, rather than general).
            DESCRIPTION:
            for my $Description ( sort { $b cmp $a } keys %DefaultDescriptions ) {
                if ( $File =~ m{$Description}i ) {
                    $DescriptionContent = $DefaultDescriptions{$Description};
                    last DESCRIPTION;
                }
            }
        }

        # If the file is in custom folder then prefix 'Customized' to the default description.
        if ( $File =~ m {Custom/} ) {
            $DescriptionContent = $DescriptionContent ? 'Customized ' . lc $DescriptionContent : 'Customized file ...';
        }
    }

    return $DescriptionContent;
}

sub _CreateDocbookTechChapter {
    my ( $Self, %Param ) = @_;

    # Check needed parameters.
    for my $Needed (qw(FormatedFiles)) {
        if ( !$Param{$Needed} ) {
            print "Need $Needed:!";
            return;
        }
    }

    # Set basic structure.
    my %Docbook = (
        chapter => {
            title   => 'Technical Implementation Details',
            section => $Param{FormatedFiles} // [],
        },
    );

    my $XMLObject = OTRS::XML::Simple->new();

    # Convert perl structure into XML structure.
    my $Chapter = eval {
        $XMLObject->XMLout(
            \%Docbook,
            NoAttr   => 1,
            KeepRoot => 1
        );
    };

    if ($@) {
        $Self->PrintError("\nThere was an error adding files into XML: $@\n");
        return;
    }

    # Indentation = 4 spaces.
    my $Indentation = '    ';
    $Chapter =~ s{[ ]{2}}{$Indentation}gmx;

    return $Chapter;
}

1;
