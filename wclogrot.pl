#!/usr/bin/perl -w

# $Id: wclogrot.pl,v 1.11 1998/09/17 03:24:23 jzawodn Exp $

# Modules

use strict;               # be careful
use Getopt::Long;         # parse options
use File::stat;           # for checking file sizes

# Variables

my $revision = '$Revision: 1.11 $';  # revision number
my $debug    = 0;                   # debugging is off by default
my $compress = 0;                   # compression if off by default
my $help     = 0;                   # help needed?
my $keep     = 1;                   # number of old logs to keep
my $mailto   = "root";              # who gets the mail
my $mail     = 0;                   # send mail?
my $version  = $revision;           # version number
my $zipcmd   = "gzip";              # default zip command
my $zipargs  = "-9";                # maximal compression
my $zipsuffix= "gz";                # default suffix for zipped files
my $rmcmd    = "/bin/rm -f";        # how to remove files
my $sendmail = "/usr/lib/sendmail"; # how to find sendmail
my %oldinfo  = ();                  # old file information
my %newinfo  = ();                  # new file information
my $errstr   = "";                  # error string

# Getting started

&GetOptions("debug!" => \$debug,
           "compress!" => \$compress,
           "help!" => \$help,
           "keep=i" => \$keep,
           "mailto=s" => \$mailto,
           "mail!" => \$mail,
           "zipcmd=s" => \$zipcmd);

&help if $help;

my $file = shift;

die "No log file specified!\n" unless $file;

&debug("Debugging is on.");
&debug("Compression enabled.") if $compress;
&debug("Compression command is '$zipcmd'.");
&debug("Keeping $keep old logs.");
&debug("Full path to file to rotate is $file.");

if ($mail) {
  &debug("Mail will be sent to $mailto.");
} else {
  &debug("No mail will be sent.");
}

# Figure out path, directory, and filename

$file =~ m#.*/(.*)#;

my $filename = $1;

&debug("Filename is $filename.");

$file =~ m#(.*)/.*#;

my $dir = $1;

&debug("Directory is $dir.");

&debug("");

&debug("Changing to $dir.");

# Go to the directory

if (!chdir($dir)) {
  $errstr = "Couldn't change directory to $dir!";
  &debug($errstr . "\nExiting.");
  &send_mail(0, $errstr);
} # end if

# Find old backup files

&debug("Searching for old log files.");

opendir(DIR,".");

my @filelist; # damned scoping

if ($compress) {
  @filelist = grep { /^$filename\.\d+\.$zipsuffix/ } readdir(DIR);
} else {
  @filelist = grep { /^$filename\.\d+/ } readdir(DIR);  
}

closedir(DIR);

# Loop through the file list. Remove compression suffix for
# simplicity, as it will be factored back in (if need be) later.

my $filecount = 0;

my $one;
foreach $one (@filelist) {
  &debug("  Found $one.");
  if ($compress) {
    $one =~ s/\.$zipsuffix$//;
  } # end if
  $filecount++;
}

&debug("$filecount old files found.");

# Assume that the names are file.[number] where number
# starts from 0 and counts up. And remember to take compression
# into account.

my $num_removed = ($#filelist+1) - ($keep-1); # trust me...

my $newname;
my $oldname;

my $suffix;
my $newsuffix;
foreach $suffix (reverse 0..$#filelist) {
  # isn't that clever. :-)
  $newsuffix = $suffix + 1;

  $oldname = "$filename.$suffix";
  $newname = "$filename.$newsuffix";

  if ($compress) {
    $oldname .= ".$zipsuffix";
    $newname .= ".$zipsuffix";
  }

  # Delete old files...

 # I should check for the existance of the old file
 # first, just to make sure. If it doesn't exist, I'll
 # complain and continue on. Add this later.

  if ($suffix >= $keep-1) {
    if (! -e $oldname) {
      &debug("  Skipping $oldname. It doesn't exist.");
      next;
    } # end if
    &debug("  Removing $oldname, it's old.");
    my $result = unlink($oldname);
    if (!$result) {
      $errstr  = "Error removing $oldname!";
      $errstr .= "\n" . $!;
      &debug($errstr . "\nExiting.");
      &send_mail(0, $errstr);
      exit;
    } # end if
    next;
  } # end if

 # Rename others if they exist.

  if (! -e $oldname) {
    &debug("  Skipping $oldname. It doesn't exist.");
    next;
  } # end if

  &debug("  Renaming $oldname to $newname.");
  my $result =  rename($oldname, $newname);
  if (!$result) {
    $errstr  = "Error during $oldname -> $newname!";
    $errstr .= "\n" . $!;
    &debug($errstr . "\nExiting.");
    &send_mail(0, $errstr);
    exit;
  }
}

# Do the newest file.

$newname = $filename . ".0";
$oldname = $filename;

&debug("  Renaming $oldname to $newname.");
my $result = rename($oldname, "$newname");

  if (!$result) {
    $errstr  = "Error during $oldname -> $newname!";
    $errstr .= "\n" . $!;
    &debug($errstr . "\nExiting.");
    &send_mail(0, $errstr);
    exit;
  }

my $oldstat = stat($newname); # yes, that IS right

if ($compress) {
  # run compression
  &debug("Compressing $newname.");
  my $rc = system($zipcmd, $zipargs, $newname);
  $rc = $rc/256;
  print "Return Code: $rc.\n";
  # check for errors
}

my $newstat;

if ($compress) {
  $newname .= ".$zipsuffix";
} # end if

$newstat = stat($newname);

if ($mail) {
  my $oldsize = $oldstat->size;
  my $newsize = $newstat->size;
  my $body=<<EOBODY;
The log file [$file] has been rotated. It is now called [$newname].

Size before rotation: $oldsize bytes.
Size after rotation : $newsize bytes.

No problems reported.

EOBODY

  if ($num_removed >=0) {
    &debug("$num_removed old log files were removed.");
    $body .= "$num_removed old log files were removed.\n";
  } # end if

  &send_mail(1, $body);
} # end if

exit;

# ------------------------------------------------------ #

sub debug($) {
  my $message = shift;
  print $message . "\n" if $debug;
} # end sub

# ------------------------------------------------------ #

sub help() {
  print<<EOH;

Usage: $0 [options] /path/to/logfile

Options: All options set set like --option <value> or
                                  --option=<value>

  Option    Parameters   Purpose
  ------    ----------   -------
  mailto    string       Who to send success/failure mail to
  mail      none         Send mail if set
  debug     none         Emit debugging messages if set
  compress  none         Compress rotated logs if set
  help      none         Print this help and exit
  keep      number       How many old logs to keep
  zipcmd    string       Command to use for compression

For full documentation, please see the man page.

EOH
  exit;
} # end sub

# ------------------------------------------------------ #

sub send_mail($,$) {
  my $status = shift;
  my $message = shift;

  my $subject;

  if ($status) {
    $subject = "Successful log rotation.";
  } else {
    $subject = "FAILED log rotation.";
  }

  &debug("Sending mail to '$mailto'.");
  &debug("Mail subject is '$subject'.");

  open(MAIL, "|$sendmail -t") or die "$!";
  select(MAIL);

  print "From: Log Rotator <system-logs\@wcnet.org>\n";
  print "To: $mailto\n";
  print "Subject: $subject\n";
  print "\n";
  print "The following messages were generated...";
  print "\n";
  print "\n";
  print "$message";
  print "\n";
  print "\n";
  print "Thanks,\n";
  print "Log Rotator <system-logs\@wcnet.org>\n";
 
  select(STDOUT);
  close(MAIL);

} # end sub

# ------------------------------------------------------ #

# ------------------------------------------------------ #
