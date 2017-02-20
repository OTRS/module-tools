# --
# Copyright (C) 2001-2017 OTRS AG, http://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Console::Command::TestSystem::Instance::Setup;

use strict;
use warnings;

use Cwd;
use DBI;
use File::Find;
use File::Spec ();

use Console::Command::Module::File::Link;
use Console::Command::TestSystem::Database::Install;
use Console::Command::TestSystem::Database::Fill;

use base qw(Console::BaseCommand);

=head1 NAME

Console::Command::TestSystem::Instance::Setup - Console command to setup and configure an OTRS test instance

=head1 DESCRIPTION

Configure settings, database and apache of a testing otrs instance

=cut

sub Configure {
    my ( $Self, %Param ) = @_;

    $Self->Description('Setup a testing OTRS intance.');
    $Self->AddOption(
        Name        => 'framework-directory',
        Description => "Specify a base framework directory to set it up.",
        Required    => 1,
        HasValue    => 1,
        ValueRegex  => qr/.*/smx,
    );
    $Self->AddOption(
        Name        => 'database-type',
        Description => 'Specify database backend to use (Mysql, Postgresql or Oracle). Default: Mysql',
        Required    => 0,
        HasValue    => 1,
        ValueRegex  => qr{^(mysql|postgresql|oracle)$}ismx,
    );
    $Self->AddOption(
        Name        => 'fred-directory',
        Description => "Specify directory of the OTRS module Fred.",
        Required    => 0,
        HasValue    => 1,
        ValueRegex  => qr/.*/smx,
    );

    return;
}

sub PreRun {
    my ($Self) = @_;

    my $FrameworkDirectory = File::Spec->rel2abs( $Self->GetOption('framework-directory') );

    my @Directories = ($FrameworkDirectory);

    my $FredDirectory = File::Spec->rel2abs( $Self->GetOption('fred-directory') );

    if ($FredDirectory) {
        push @Directories, $FredDirectory;
    }

    for my $Directory (@Directories) {
        if ( !-e $Directory ) {
            die "$Directory does not exist";
        }
        if ( !-d $Directory ) {
            die "$Directory is not a directory";
        }
    }

    if ( !-e $FrameworkDirectory . '/RELEASE' ) {
        die "$FrameworkDirectory does not seams to be an OTRS framework directory";
    }

    if ($FredDirectory) {
        if ( !-e $FredDirectory . '/Fred.sopm' ) {
            die "$FrameworkDirectory does not seams to be a Fred module directory";
        }
    }

    return;
}

sub Run {
    my ($Self) = @_;

    my $FrameworkDirectory = File::Spec->rel2abs( $Self->GetOption('framework-directory') );
    my $DatabaseType = ucfirst $Self->GetOption('database-type') || 'Mysql';

    my $FredDirectory = File::Spec->rel2abs( $Self->GetOption('fred-directory') );

    # Remove possible slash at the end.
    $FrameworkDirectory =~ s{ / \z }{}xms;

    # Get OTRS major version number.
    my $OTRSReleaseString = `cat $FrameworkDirectory/RELEASE`;
    my $OTRSMajorVersion  = '';
    if ( $OTRSReleaseString =~ m{ VERSION \s+ = \s+ (\d+) .* \z }xms ) {
        $OTRSMajorVersion = $1;
        $Self->Print("\n<yellow>Installing testsystem for OTRS version $OTRSMajorVersion.</yellow>\n\n");
    }

    my %Config = %{ $Self->{Config}->{TestSystem} || {} };

    # Define some maintenance commands.
    if ( $OTRSMajorVersion >= 5 ) {
        $Config{RebuildConfigCommand}
            = "sudo -u $Config{PermissionsOTRSUser} $FrameworkDirectory/bin/otrs.Console.pl Maint::Config::Rebuild";
        $Config{DeleteCacheCommand}
            = "sudo -u $Config{PermissionsOTRSUser} $FrameworkDirectory/bin/otrs.Console.pl Maint::Cache::Delete";
    }
    else {
        $Config{RebuildConfigCommand}
            = "sudo -u $Config{PermissionsOTRSUser} perl $FrameworkDirectory/bin/otrs.RebuildConfig.pl";
        $Config{DeleteCacheCommand}
            = "sudo -u $Config{PermissionsOTRSUser} perl $FrameworkDirectory/bin/otrs.DeleteCache.pl";
    }

    my $SystemName = $FrameworkDirectory;
    $SystemName =~ s{$Config{EnvironmentRoot}}{}xmsg;
    $SystemName =~ s{/}{}xmsg;

    # Determine a string that is used for database user name, database name and database password.
    my $DatabaseSystemName = $SystemName;
    $DatabaseSystemName =~ s{-}{_}xmsg;     # replace - by _ (hyphens not allowed in database name)
    $DatabaseSystemName =~ s{\.}{_}xmsg;    # replace . by _ (hyphens not allowed in database name)
    $DatabaseSystemName = substr( $DatabaseSystemName, 0, 16 );    # shorten the string (mysql requirement)

    # Edit Config.pm.
    $Self->Print("\n  <yellow>Editing and copying Config.pm...</yellow>\n");
    {
        if ( !-e $FrameworkDirectory . '/Kernel/Config.pm.dist' ) {
            $Self->PrintError("/Kernel/Config.pm.dist cannot be opened\n");
            return $Self->ExitCodeError();
        }

        my $ConfigStr = $Self->ReadFile( $FrameworkDirectory . '/Kernel/Config.pm.dist' );
        $ConfigStr =~ s{/opt/otrs}{$FrameworkDirectory}xmsg;
        $ConfigStr =~ s{('otrs'|'some-pass')}{'$DatabaseSystemName'}xmsg;

        if ( $DatabaseType eq 'Postgresql' ) {
            $ConfigStr
                =~ s{^#(    \$Self->\{DatabaseDSN\} = "DBI:Pg:dbname=\$Self->\{Database\};host=\$Self->\{DatabaseHost\};";)$}{$1}msg;
        }
        elsif ( $DatabaseType eq 'Oracle' ) {
            $ConfigStr =~ s{\$Self->\{Database\} = '$DatabaseSystemName';}{\$Self->{Database} = 'XE';}msg;
            $ConfigStr
                =~ s{^#(    \$Self->\{DatabaseDSN\} = "DBI:Oracle://\$Self->\{DatabaseHost\}:1521/\$Self->\{Database\}";)$}{$1}msg;
            $ConfigStr
                =~ s{^#    \$ENV\{ORACLE_HOME\}     = '/path/to/your/oracle';$}{    \$ENV{ORACLE_HOME}     = "/u01/app/oracle/product/11.2.0/xe";}msg;
            $ConfigStr =~ s{^#(    \$ENV\{NLS_DATE_FORMAT\} = 'YYYY-MM-DD HH24:MI:SS';)$}{$1}msg;
            $ConfigStr =~ s{^#(    \$ENV\{NLS_LANG\}        = 'AMERICAN_AMERICA.AL32UTF8';)$}{$1}msg;
        }

        # Inject some more data.
        my $ConfigInjectStr = <<"EOD";

        \$Self->{'SecureMode'} = 1;
        \$Self->{'SystemID'}            = '54';
        \$Self->{'SessionName'}         = '$SystemName';
        \$Self->{'ProductName'}         = '$SystemName';
        \$Self->{'ScriptAlias'}         = '$SystemName/';
        \$Self->{'Frontend::WebPath'}   = '/$SystemName-web/';
        \$Self->{'CheckEmailAddresses'} = 0;
        \$Self->{'CheckMXRecord'}       = 0;
        \$Self->{'Organization'}        = '';
        \$Self->{'LogModule'}           = 'Kernel::System::Log::File';
        \$Self->{'LogModule::LogFile'}  = '$Config{EnvironmentRoot}$SystemName/var/log/otrs.log';
        \$Self->{'FQDN'}                = 'localhost';
        \$Self->{'DefaultLanguage'}     = 'de';
        \$Self->{'DefaultCharset'}      = 'utf-8';
        \$Self->{'AdminEmail'}          = 'root\@localhost';
        \$Self->{'Package::Timeout'}    = '120';
        \$Self->{'SendmailModule'}      =  'Kernel::System::Email::DoNotSendEmail';

        # Fred
        \$Self->{'Fred::BackgroundColor'} = '#006ea5';
        \$Self->{'Fred::SystemName'}      = '$SystemName';
        \$Self->{'Fred::ConsoleOpacity'}  = '0.7';
        \$Self->{'Fred::ConsoleWidth'}    = '30%';

        # Misc
        \$Self->{'Loader::Enabled::CSS'}  = 0;
        \$Self->{'Loader::Enabled::JS'}   = 0;

        # Selenium
        \$Self->{'SeleniumTestsConfig'} = {
            remote_server_addr  => 'localhost',
            port                => '4444',
            browser_name        => 'firefox',
            platform            => 'ANY',
            extra_capabilities  => {
                marionette => \0,
            },
            # window_height => 1200,    # optional, default 1000
            # window_width  => 1600,    # optional, default 1200
        };
EOD

        # Use defined config injection instead.
        if ( $Config{ConfigInject} ) {
            $Config{ConfigInject} =~ s/\\\$/{DollarSign}/g;
            $Config{ConfigInject} =~ s/(\$\w+(\{\w+\})?)/$1/eeg;
            $Config{ConfigInject} =~ s/\{DollarSign\}/\$/g;
            $ConfigInjectStr = $Config{ConfigInject};
            print "    Overriding default configuration...\n    Done.\n";
        }

        $ConfigStr =~ s{\# \s* \$Self->\{CheckMXRecord\} \s* = \s* 0;}{$ConfigInjectStr}xms;
        my $Success = $Self->WriteFile( $FrameworkDirectory . '/Kernel/Config.pm', $ConfigStr );
        if ( !$Success ) {
            return $Self->ExitCodeError();
        }
    }

    # Check apache config.
    if ( !-e $FrameworkDirectory . '/scripts/apache2-httpd.include.conf' ) {
        $Self->PrintError("/scripts/apache2-httpd.include.conf cannot be opened\n");
        return $Self->ExitCodeError();
    }

    # Copy apache config file.
    my $ApacheConfigFile = "$Config{ApacheCFGDir}$SystemName.conf";
    $Self->System(
        "sudo cp -p $FrameworkDirectory/scripts/apache2-httpd.include.conf $ApacheConfigFile"
    );

    # Copy apache mod perl file.
    my $ApacheModPerlFile = "$Config{ApacheCFGDir}$SystemName.apache2-perl-startup.pl";
    $Self->System(
        "sudo cp -p $FrameworkDirectory/scripts/apache2-perl-startup.pl $ApacheModPerlFile"
    );

    $Self->Print("\n  <yellow>Editing Apache config...</yellow>\n");
    {
        my $ApacheConfigStr = $Self->ReadFile($ApacheConfigFile);
        $ApacheConfigStr
            =~ s{Perlrequire \s+ /opt/otrs/scripts/apache2-perl-startup\.pl}{Perlrequire $ApacheModPerlFile}xms;
        $ApacheConfigStr =~ s{/opt/otrs}{$FrameworkDirectory}xmsg;
        $ApacheConfigStr =~ s{/otrs/}{/$SystemName/}xmsg;
        $ApacheConfigStr =~ s{/otrs-web/}{/$SystemName-web/}xmsg;
        $ApacheConfigStr =~ s{<IfModule \s* mod_perl.c>}{<IfModule mod_perlOFF.c>}xmsg;
        $ApacheConfigStr =~ s{<Location \s+ /otrs>}{<Location /$SystemName>}xms;

        my $Success = $Self->WriteFile( $ApacheConfigFile, $ApacheConfigStr );
        if ( !$Success ) {
            return $Self->ExitCodeError();
        }
    }

    $Self->Print("\n  <yellow>Editing Apache mod perl config...</yellow>\n");
    {
        my $ApacheModPerlConfigStr = $Self->ReadFile($ApacheModPerlFile);

        # Set correct path.
        $ApacheModPerlConfigStr =~ s{/opt/otrs}{$FrameworkDirectory}xmsg;

        # Enable lines for MySQL.
        if ( $DatabaseType eq 'Mysql' ) {
            $ApacheModPerlConfigStr =~ s{^#(use DBD::mysql \(\);)$}{$1}msg;
            $ApacheModPerlConfigStr =~ s{^#(use Kernel::System::DB::mysql;)$}{$1}msg;
        }

        # Enable lines for PostgreSQL.
        elsif ( $DatabaseType eq 'Postgresql' ) {
            $ApacheModPerlConfigStr =~ s{^#(use DBD::Pg \(\);)$}{$1}msg;
            $ApacheModPerlConfigStr =~ s{^#(use Kernel::System::DB::postgresql;)$}{$1}msg;
        }

        # Enable lines for Oracle.
        elsif ( $DatabaseType eq 'Oracle' ) {
            $ApacheModPerlConfigStr
                =~ s{^(\$ENV\{MOD_PERL\}.*?;)$}{$1\n\n\$ENV{ORACLE_HOME}     = "/u01/app/oracle/product/11.2.0/xe";\n\$ENV{NLS_DATE_FORMAT} = "YYYY-MM-DD HH24:MI:SS";\n\$ENV{NLS_LANG}        = "AMERICAN_AMERICA.AL32UTF8";}msg;
            $ApacheModPerlConfigStr =~ s{^#(use DBD::Oracle \(\);)$}{$1}msg;
            $ApacheModPerlConfigStr =~ s{^#(use Kernel::System::DB::oracle;)$}{$1}msg;
        }

        my $Success = $Self->WriteFile( $ApacheModPerlFile, $ApacheModPerlConfigStr );
        if ( !$Success ) {
            return $Self->ExitCodeError();
        }
    }

    # Restart apache.
    $Self->Print("\n  <yellow>Restarting apache...</yellow>\n");
    $Self->System("sudo $Config{ApacheRestartCommand}");

    my $DSN;
    my @DBIParam;

    if ( $DatabaseType eq 'Mysql' ) {
        $DSN = 'DBI:mysql:';
    }
    elsif ( $DatabaseType eq 'Postgresql' ) {
        $DSN = 'DBI:Pg:;host=127.0.0.1';
    }
    elsif ( $DatabaseType eq 'Oracle' ) {
        $DSN = 'DBI:Oracle://127.0.0.1:1521/XE';
        ## nofilter(TidyAll::Plugin::OTRS::Perl::Require)
        require DBD::Oracle;    ## no critic
        push @DBIParam, {
            ora_session_mode => $DBD::Oracle::ORA_SYSDBA,
        };
        $ENV{ORACLE_HOME} = "/u01/app/oracle/product/11.2.0/xe";
    }

    my $DBH = DBI->connect(
        $DSN,
        $Config{"DatabaseUserName$DatabaseType"},
        $Config{"DatabasePassword$DatabaseType"},
        @DBIParam,
    );

    # Install database.
    $Self->Print("\n  <yellow>Creating Database...</yellow>\n");
    {
        if ( $DatabaseType eq 'Mysql' ) {
            $DBH->do("DROP DATABASE IF EXISTS $DatabaseSystemName");
            $DBH->do("CREATE DATABASE $DatabaseSystemName charset utf8");
            $DBH->do("use $DatabaseSystemName");
        }
        elsif ( $DatabaseType eq 'Postgresql' ) {
            $DBH->do("DROP DATABASE IF EXISTS $DatabaseSystemName");
            $DBH->do("CREATE DATABASE $DatabaseSystemName");
        }
    }

    $Self->Print("\n  <yellow>Creating database user and privileges...\n</yellow>");
    {
        if ( $DatabaseType eq 'Mysql' ) {
            $DBH->do(
                "GRANT ALL PRIVILEGES ON $DatabaseSystemName.* TO $DatabaseSystemName\@localhost IDENTIFIED BY '$DatabaseSystemName' WITH GRANT OPTION;"
            );
            $DBH->do('FLUSH PRIVILEGES');
        }
        elsif ( $DatabaseType eq 'Postgresql' ) {
            $DBH->do("CREATE USER $DatabaseSystemName WITH PASSWORD '$DatabaseSystemName'");
            $DBH->do("GRANT ALL PRIVILEGES ON DATABASE $DatabaseSystemName TO $DatabaseSystemName");
        }
        elsif ( $DatabaseType eq 'Oracle' ) {
            $DBH->do("ALTER system SET processes=150 scope=spfile");
            $DBH->do("DROP USER $DatabaseSystemName CASCADE");
            $DBH->do("CREATE USER $DatabaseSystemName IDENTIFIED BY $DatabaseSystemName");
            $DBH->do("GRANT ALL PRIVILEGES TO $DatabaseSystemName");
        }
    }

    $Self->Print("\n  <yellow>Creating database schema...\n</yellow>");
    $Self->ExecuteCommand(
        Module => 'Console::Command::TestSystem::Database::Install',
        Params => [ '--framework-directory', $FrameworkDirectory ],
    );

    # Make sure we've got the correct rights set (e.g. in case you've downloaded the files as root).
    $Self->System("sudo chown -R $Config{PermissionsOTRSUser}:$Config{PermissionsOTRSGroup} $FrameworkDirectory");

    # Link fred module.
    if ($FredDirectory) {
        $Self->Print("\n  <yellow>Linking Fred module into $SystemName...</yellow>\n");
        $Self->ExecuteCommand(
            Module => 'Console::Command::Module::File::Link',
            Params => [ $FredDirectory, $FrameworkDirectory ],
        );
    }

    # Setting permissions.
    $Self->Print("\n  <yellow>Setting permissions...</yellow>\n");
    if ( $OTRSMajorVersion >= 5 ) {
        $Self->System(
            "sudo perl $FrameworkDirectory/bin/otrs.SetPermissions.pl --otrs-user=$Config{PermissionsOTRSUser} --web-group=$Config{PermissionsWebGroup} --admin-group=$Config{PermissionsAdminGroup} $FrameworkDirectory"
        );
    }
    else {
        $Self->System(
            "sudo perl $FrameworkDirectory/bin/otrs.SetPermissions.pl --otrs-user=$Config{PermissionsOTRSUser} --web-user=$Config{PermissionsWebUser} --otrs-group=$Config{PermissionsOTRSGroup} --web-group=$Config{PermissionsWebGroup} --not-root $FrameworkDirectory"
        );
    }

    # Deleting Cache.
    $Self->Print("\n  <yellow>Deleting cache...</yellow>\n");
    $Self->System( $Config{DeleteCacheCommand} );

    # Rebuild Config.
    $Self->Print("\n  <yellow>Rebuilding config...</yellow>\n");
    $Self->System( $Config{RebuildConfigCommand} );

    # Inject test data.
    $Self->Print("\n  <yellow>Injecting some test data...</yellow>\n");
    $Self->ExecuteCommand(
        Module => 'Console::Command::TestSystem::Database::Fill',
        Params => [ '--framework-directory', $FrameworkDirectory ],
    );

    # Setting permissions.
    $Self->Print("\n  <yellow>Setting permissions again (just to be sure)...</yellow>\n");
    if ( $OTRSMajorVersion >= 5 ) {
        $Self->System(
            "sudo perl $FrameworkDirectory/bin/otrs.SetPermissions.pl --otrs-user=$Config{PermissionsOTRSUser} --web-group=$Config{PermissionsWebGroup} --admin-group=$Config{PermissionsAdminGroup} $FrameworkDirectory"
        );
    }
    else {
        $Self->System(
            "sudo perl $FrameworkDirectory/bin/otrs.SetPermissions.pl --otrs-user=$Config{PermissionsOTRSUser} --web-user=$Config{PermissionsWebUser} --otrs-group=$Config{PermissionsOTRSGroup} --web-group=$Config{PermissionsWebGroup} --not-root $FrameworkDirectory"
        );
    }

    $Self->Print("\n<green>Done.</green>\n");
    return $Self->ExitCodeOk();
}

sub ReadFile {
    my ( $Self, $Path ) = @_;

    my $FileHandle;

    if ( !open $FileHandle, $Path ) {    ## no critic
        $Self->PrintError("Couldn't open $Path $!");
        return '';
    }
    my $Content = join( "", <$FileHandle> );
    close $FileHandle;

    return $Content;
}

sub WriteFile {
    my ( $Self, $Path, $Content ) = @_;

    my $FileHandle;

    if ( !open( $FileHandle, '>' . $Path ) ) {    ## no critic
        $Self->PrintError("Couldn't open $Path $!");
        return '';
    }
    print $FileHandle $Content;
    close $FileHandle;

    return 1;
}

sub System {
    my ( $Self, $Command ) = @_;

    my $Output = `$Command`;

    if ($Output) {
        $Output =~ s{^}{    }mg;
        $Self->Print($Output);
    }

    return 1;
}

sub ExecuteCommand {
    my ( $Self, %Param ) = @_;

    my $Output;
    {

        # Localize the standard error, everything will be restored after the block.
        local *STDERR;
        local *STDOUT;

        # Redirect the standard error and output to a variable.
        open STDERR, ">>", \$Output;
        open STDOUT, ">>", \$Output;

        my $ModuleObject = $Param{Module}->new();

        $ModuleObject->Execute( @{ $Param{Params} } );
    }

    $Output =~ s{^}{    }mg;
    $Self->Print($Output);

    return 1;
}

1;

=head1 TERMS AND CONDITIONS

This software is part of the OTRS project (L<http://otrs.org/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (AGPL). If you
did not receive this file, see L<http://www.gnu.org/licenses/agpl.txt>.

=cut
