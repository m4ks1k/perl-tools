use strict;

my $START_DIR = shift;
my %USAGES = ();

traverse_dir($START_DIR, undef);
print join("\n", map {local $a = $_; "$a :".join(", ", sort keys %{$USAGES{$a}})} grep {! keys $USAGES{$_} } grep {/^(rb|lv)/} sort keys %USAGES),"\n";

sub traverse_dir {
  my ($dir, $pkg) = @_;
  opendir DIR, "$dir" or die "Couldn't open $dir: $!";
  my @files = readdir DIR;
  closedir DIR;
  for my $file(@files) {
    my $path = $dir . '\\' . $file;
    #print "$path\n";
    if (-d $path && $file ne 'BARS-Commons' && $file ne '.' && $file ne '..' && $file ne 'BARSTestUtils' && $path !~ /test/) {
      traverse_dir($path, defined $pkg?$pkg.'.'.$file: $file eq 'src'?'':undef);
    } elsif (-f $path && $file =~ /([^\.\\\\]+)\.java$/i) {
      my $class_name = $1;
      my $full_class_name = $pkg.'.'.$class_name;
      $full_class_name =~ s/^\.//;
      $USAGES{$full_class_name} = {} 
        unless exists $USAGES{$full_class_name};
      open FILE, $path or die "Couldn't open $path: $!";
      for my $line (<FILE>) {
        my %imports = ();
        if ($line =~ /^\s*import\s+([^;\*\s]+)\s*;/) {
          my $import = $1;
          $imports{$import} = 1;
          $USAGES{$import}{$full_class_name} = 1;
        } elsif ($line =~ /new\s*(\w+)\s*[\[\(]/) {
          my $usage = $1;
          check_usage($usage, $dir, $pkg, $path, $full_class_name, \%imports);
        } elsif ($line =~ /extends\s*(\w+)\b/) {
          my $usage = $1;
          check_usage($usage, $dir, $pkg, $path, $full_class_name, \%imports);
        }
      }
      close FILE;
    }
  }
}

sub check_usage {
  my ($usage, $dir, $pkg, $path, $full_class_name, $imports) = @_;
  if ($usage eq 'byte' || $usage eq 'int' || $usage eq 'long' || $usage eq 'char' || $usage eq 'short' || $usage eq 'float' || $usage eq 'double') {
  } elsif (-f $dir.'\\'.$usage.'.java') {
    my $pkg_level_class = $pkg.'.'.$usage;
    $pkg_level_class =~ s/^\.//;
    
    $USAGES{$pkg_level_class}{$full_class_name} = 1
      unless $pkg_level_class eq $full_class_name;
  } else {
    for my $import(keys %$imports) {
      if (substr($import, length($import) - length($usage)) eq $usage) {
        $USAGES{$import}{$full_class_name} = 1;
        last;
      }
    }
  }          
}