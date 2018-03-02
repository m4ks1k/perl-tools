#!perl

use strict;
use Win32::Clipboard;

my $CB = Win32::Clipboard();
my $INPUT = $CB->Get();

my $OUTPUT = unquote_sql($INPUT);
#print $OUTPUT;
$CB->Set($OUTPUT);

sub unquote_sql {
  my ($input) = @_;

  $input =~ s/'''\s*CONCAT\s*(VAR)?CHAR\(\w*DAT\w*(\s*,\s*ISO)?\)\s*CONCAT\s*'''/'2014-07-01'/smg;
  $input =~ s/'\s*CONCAT\s*TRIM\(FULL_TBLNAME\)\s*CONCAT\s*'/FULL_TBLNAME/mg;
  $input =~ s/^\s*'\s*//smg;
  $input =~ s/\s*'\s*CONCAT\s*$//smg;
  $input =~ s/''/'/smg;
  $input =~ s/'$//g;
  
  return $input."\n";
}
