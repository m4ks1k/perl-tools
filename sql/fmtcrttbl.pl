#!perl

use strict;
use warnings;
use Win32::Clipboard;

my $PAD = ' ' x 4;
my $CB = Win32::Clipboard();
my $in = $CB->Get();
my $res = format_sql($in);
$CB->Set($res);

sub format_sql {
  my ($input) = @_;
  my @rows = split /\r\n/, $input;
  my @result = ();
  for my $row(@rows) {
    my $str = $row;
    if ($row =~ /^\s*CREATE\s+TABLE/) {
    } elsif ($row =~ /^
      \s*CONSTRAINT\s+
      ([A-Za-z0-9_]+)\s+
      (.+)$/x) {
      $str = 
        right_pad($PAD.'CONSTRAINT', 16)
        .right_pad($1, 16)
        .$2;
    } elsif ($row =~ /^
      \s*(\"?[A-Za-z0-9_]+\"?)\s+
      (?:FOR\s+COLUMN\s+[A-Za-z0-9_]+\s+)?
      ([A-Za-z0-9_]+(?:\(\s*\d+(?:\s*,\s*\d+)?\s*\))?)\s+
      (?:CCSID\s+\d+\s+)?
      (.+)$/x) {
      $str =
        right_pad($PAD.$1, 16)
        .right_pad($2, 16)
        .$3;
    }
    $str =~ s/\s+,\s+$/,/;
    push @result, $str;
  }
  return join("\n", @result);
}

sub right_pad {
  my ($str, $size) = @_;
  
  return length($str) >= $size?$str.' ':$str.(' ' x ($size - length($str)));
}