#!/usr/bin/perl


use strict;

my $Dest = shift || die "Need Application-Root location as ARG1";
if ( !-d $Dest ) {
    die "ERROR: invalid Application-Root directory '$Dest'";
}

if ( !( -e $Dest . '/Kernel' && -e $Dest . '/Kernel/System' ) ) {
    print <<"WARNING";
Can't find $Dest/Kernel and $Dest/Kernel/System, so I assume it's not a
root directory of an OTRS instance. Remove links anyway? [y/N]
WARNING

    chomp( my $Answer = <STDIN> );

    if ( $Answer !~ m{ ^ y $ }xi ) {
        exit;
    }
}

my @Dirs  = ();
my $Start = $Dest;
R($Start);

sub R {
    my $In   = shift;
    my @List = glob("$In/*");
    foreach my $File (@List) {
        $File =~ s/\/\//\//g;
        if ( -d $File ) {
            R($File);
        }
        else {
            my $OrigFile = $File;
            $File =~ s/$Start//;
            if ( -l $OrigFile ) {
                print "Unlink Symlink: $File\n";
                unlink $OrigFile || die $!;

                if ( -f "$OrigFile.old" ) {
                    print "Restore orginal copy: $File\n";
                    rename( "$OrigFile.old", $OrigFile ) || die $!;
                }
            }
        }
    }
}
