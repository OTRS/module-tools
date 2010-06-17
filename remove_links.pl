#!/usr/bin/perl -w

# $Id: remove_links.pl,v 1.2 2010-06-17 13:43:19 reb Exp $

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

            #            $File =~ s/$Start//;
            #            print "Directory: $File\n";
        }
        else {
            my $OrigFile = $File;
            $File =~ s/$Start//;

            #            print "File: $File\n";
            #            my $Dir =~ s/^(.*)\//$1/;
            if ( -l $OrigFile ) {
                print "Unlink Symlink: $File\n";
                unlink $OrigFile || die $!;
            }
        }
    }
}
