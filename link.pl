#!/usr/bin/perl -w

# $Id: link.pl,v 1.7 2006-08-01 20:41:17 martin Exp $

use strict;

my $Source = shift || die "Need Application CVS location as ARG0";
if (! -d $Source) {
    die "ERROR: invalid Application CVS directory '$Source'";
}
my $Dest = shift || die "Need Framework-Root location as ARG1";
if (! -d $Dest) {
    die "ERROR: invalid Framework-Root directory '$Dest'";
}

my @Dirs = ();
my $Start = $Source;
R($Start);

sub R {
    my $In = shift;
    my @List = glob("$In/*");
    foreach my $File (@List) {
        $File =~ s/\/\//\//g;
        if (-d $File && $File !~ /CVS/) {
            R($File);
            $File =~ s/$Start//;
#            print "Directory: $File\n";
        }
        else {
            my $OrigFile = $File;
            $File =~ s/$Start//;
#            print "File: $File\n";
#            my $Dir =~ s/^(.*)\//$1/;
            if ($File !~ /Entries|Repository|Root|CVS/) {
                # check directory of loaction (in case create a directory)
                if ("$Dest/$File" =~ /^(.*)\/(.+?|)$/) {
                    my $Directory = $1;
                    my @Directories = split(/\//, $Directory);
                    my $DirectoryCurrent = '';
                    foreach my $Directory (@Directories) {
                        $DirectoryCurrent .= "/$Directory";
                        if ($DirectoryCurrent && ! -d $DirectoryCurrent) {
                            if (mkdir $DirectoryCurrent) {
                                print STDERR "NOTICE: Create Directory $DirectoryCurrent\n";
                            }
                            else {
                                die "ERROR: can't create directory $DirectoryCurrent: $!";
                            }
                        }
                    }
                }
#            if (!-e"$Dest/$File" || (-l "$Dest/$File" && unlink ("$Dest/$File"))) {
                if (-l "$Dest/$File") {
                    unlink ("$Dest/$File") || die "ERROR: Can't unlink symlink: $Dest/$File";
                }
                if (-e "$Dest/$File") {
                    if (rename("$Dest/$File", "$Dest/$File.old")) {
                        print "NOTICE: Backup orig file: $Dest/$File.old\n";
                    }
                    else {
                        die "ERROR: Can't rename $Dest/$File to $Dest/$File.old: $!";
                    }
                }
                if (!-e $Dest) {
                    die "ERROR: No such directory: $Dest";
                }
                elsif (!-e $OrigFile) {
                    die "ERROR: No such orig file: $OrigFile";
                }
                elsif (!symlink ($OrigFile, "$Dest/$File")) {
#                        die "ERROR: Can't link ($OrigFile->$Dest/$File): $!";
                    die "ERROR: Can't $File link: $!";
                }
                else {
                    print "NOTICE: Link: $OrigFile -> \n";
                    print "NOTICE:       $Dest/$File\n";
                }
            }
        }
    }
}
