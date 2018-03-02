#!perl

use strict;
use warnings;
use Readonly;
use Win32::Clipboard;
use Carp;

our $VERSION = 1.0;









use constant {
  START => 0,
  WORD => 1,
  NUMBER => 2, 
  STRING => 3,
  SPACE => 4,
  QWORD => 5,
  STRING_QW => 6,
  QWORD_QW => 7,
  OPSTART => 8,
  FINISH => 9,
  ERROR => 10
};

Readonly my $LINE_SIZE => 80;
Readonly my $PAYLOAD_MAX_LEN => $LINE_SIZE;
Readonly my $INDENT_LEN => 2;
Readonly my $INDENT_INIT => 1;
Readonly my $VAR_NAME => 'LSTMT';

Readonly my @HARD_BREAK_KEYWORDS => qw/select set from where join 
left right full inner union except intersect order group
having/;
Readonly my @SOFT_BREAK_KEYWORDS => qw/and or on when then else/;
Readonly my @OTHER_KW => qw/all alter any as between binary by case cast char
character check concat contains count count_big cross current current_date 
current_time current_timestamp current_timezone day days default delete
distinct double each end escape exists graphic hour 
hours in insert into is key like long microsecond microseconds 
minute minutes month months not null outer partition position 
row rows second seconds some substring table trigger trim  update
using values with year years/;

Readonly my @FUNC => qw/cast decimal round trunc substring left right trim substr value
coalesce min max avg sum count abs sign dec/;
my $CB = Win32::Clipboard();
my $INPUT = $CB->Get();

my $OUTPUT = format_sql($INPUT);
#print $OUTPUT;
$CB->Set($OUTPUT);

sub format_sql {
  my ($input) = @_;
  
  my $pos = 0;
  my $indent = $INDENT_INIT;
  my $inner_indent = 0;
  
  my $indent_str = ' ' x $INDENT_LEN;

  my @out_rows = ();
  
  my %soft_breaks = map {lc($_) => 1} @SOFT_BREAK_KEYWORDS;
  my %hard_breaks = map {lc($_) => 1} @HARD_BREAK_KEYWORDS;
  my %other_kw = map {lc($_) => 1} @OTHER_KW;
  my %func_kw = map {lc($_) => 1} @FUNC;
  my %kw = (%soft_breaks, %hard_breaks, %other_kw);
  
  my $in_len = length($input);
  
  my @tokens = grep {$_ ne ' '} split_to_tokens($input);
  push @tokens, undef;
  
  #print join(' ', grep {length > 0 } @tokens),"\n\n";
  
  my @hard_broken_lines = ();
  my @line = ();
  my @hb_buffer = ();
  for my $token(@tokens) {
    if (@hb_buffer) {
      if (isKw($token, \%hard_breaks)) {
        push @hb_buffer, $token;
      } elsif ($token eq '(' && @hb_buffer == 1 && 
        (lc($hb_buffer[0]) eq 'left' || lc($hb_buffer[0]) eq 'right')) {
        @line = @{pop @hard_broken_lines};
        push @line, @hb_buffer, $token;
        @hb_buffer = ();
      } else {
        push @hard_broken_lines, [@line] if @line;
        @line = (@hb_buffer, $token);
        @hb_buffer = ();
      }
    } else {
      if (isKw($token, \%hard_breaks)) {
        if (@line) {
          push @hard_broken_lines, [@line];
          @line = ();
        }
        push @hb_buffer, $token;
      } else {
        push @line, $token;
      }
    }
  }
  if (@line) {
    push @hard_broken_lines, [@line];
  }
  
  for my $line(@hard_broken_lines) {
    my @line_copy = @$line;
    @$line = ();
    my $prev_token = undef;
    my $expect_qualified_tab_name = 0;
    for my $line_token(@line_copy) {
      if ($expect_qualified_tab_name == 1) {
        if ($line_token =~ /^[A-Z\"]/i) {
          $expect_qualified_tab_name = 2;
        } else {
          $expect_qualified_tab_name = 0;
        }
      } elsif ($expect_qualified_tab_name == 2) {
        if ($line_token eq '/') {
          $expect_qualified_tab_name = 3;
        } else {
          $expect_qualified_tab_name = 0;
        }
      } elsif ($expect_qualified_tab_name == 3) {
        if ($line_token =~ /^[A-Z\"]/i) {
          for my $i(0 .. 1) {
            $line_token = (pop @$line).$line_token;
          }
        }
        $expect_qualified_tab_name = 4;
      }

      if (lc($line_token) eq 'join' || lc($line_token) eq 'from'
         || lc($line_token) eq 'into' || lc($line_token) eq 'update') {
        $expect_qualified_tab_name = 1;
      }
      if (defined $prev_token) {
        if ($prev_token =~ /^[A-Z0-9]/i && $line_token =~ /^[A-Z0-9]/i ||
          $line_token ne ')' && $prev_token eq ')' ||
          $line_token eq '(' && $prev_token ne '(' && !isKw($prev_token, \%func_kw) ||
          $prev_token eq ',' ||
          $prev_token =~ /^[\'\"]/ && $line_token ne ',' && $line_token ne ')' ||
          $line_token =~ /^[\'\"]/ && $prev_token ne '(' ||
          isOp($line_token) && !$expect_qualified_tab_name ||
          isOp($prev_token) && !$expect_qualified_tab_name) {
          push @$line, ' ';
        }
      }
      if ($expect_qualified_tab_name == 4) {
        $expect_qualified_tab_name = 0;
      }
      push @$line, $line_token;
      $prev_token = $line_token;
    }
    shift @$line if $line->[0] eq ' ';
    pop @$line if $line->[$#$line] eq ' ';
  }
  
  my $counter = 0;
  my $subquery_count = 0;
  my @subquery_parenthesis_count = ();
  my $prev_token = undef;
  for my $line(@hard_broken_lines) {
    my $curr_line = '';
    my @line_tok_buff = ();
    my $indent_in_line = $inner_indent;
    if (lc($line->[0]) eq 'select' && $prev_token eq '(') {
      $subquery_parenthesis_count[$subquery_count] = 1;
      $subquery_count++;
    }
    if ($counter == 0) {
      
    } else {
      push @line_tok_buff, 
        ($indent_str x ($indent_in_line + $subquery_count * 2));
    }
    
    for (my $i = 0; $i < @$line; $i++) {
      my $token = $line->[$i];
      if ($subquery_count > 0) {
        if ($token eq '(') {
          for(my $j = 0; $j < $j; $j++) {
            $subquery_parenthesis_count[$j]++;
          }
        } elsif ($token eq ')') {
          my $old_subquery_count = $subquery_count;
          for(my $j = 0; $j < $old_subquery_count; $j++) {
            $subquery_parenthesis_count[$j]--;
            if ($subquery_parenthesis_count[$j] == 0) {
              $subquery_count--;
            }
          }
        }
      }
      if (buff_length(\@line_tok_buff) + length($token) > $PAYLOAD_MAX_LEN) {
        my $soft_break_idx = 0;
        my $before_op_break_idx = 0;
        my $after_comma_break_idx = 0;
        my $space_break_idx = 0;
        for (my $k = $#line_tok_buff; $k >= 1
          && ($soft_break_idx == 0 
            || $space_break_idx == 0
            || ($before_op_break_idx == 0 
            && $after_comma_break_idx == 0)            
          ); $k--) {
          if ($soft_break_idx == 0
            && isKw(lc($line_tok_buff[$k]), \%soft_breaks)) {
            $soft_break_idx = $k;
          }
          if ($before_op_break_idx == 0 && $line_tok_buff[$k - 1] eq ' ' 
            && isMathOp($line_tok_buff[$k])) {
            $before_op_break_idx = $k;
          }
          if ($after_comma_break_idx == 0
            && $line_tok_buff[$k] eq ' ' && $line_tok_buff[$k - 1] eq ',') {
            $after_comma_break_idx = $k;
          }
          if ($space_break_idx == 0 && $line_tok_buff[$k] eq ' ' && (
            !isOp($line_tok_buff[$k - 1]) ||
            $k + 1 <= $#line_tok_buff && !isOp($line_tok_buff[$k + 1]) ||
            $k + 1 > $#line_tok_buff && !isOp($token)
            )) {
            $space_break_idx = $k;
          }
        }
        my $break_idx = $soft_break_idx > 1?$soft_break_idx:
          max($before_op_break_idx, $after_comma_break_idx);
        $break_idx = $space_break_idx if $break_idx < 2;
        
        my @line_beg = @line_tok_buff[0 .. $break_idx - 1];
        pop @line_beg if $line_beg[$#line_beg] eq ' ';
        push @out_rows, join('', @line_beg);
        
        $indent_in_line = $inner_indent + 1;
        my @line_end = @line_tok_buff[$break_idx .. $#line_tok_buff];
        shift @line_end if @line_end && $line_end[0] eq ' ';
        @line_tok_buff = (($indent_str x ($indent_in_line + $subquery_count * 2)), 
          @line_end);
      }
      my $ptoken = $token;
      if ($ptoken =~ /^'/) {
        $ptoken =~ s/''/'/g;
      }
      push @line_tok_buff, 
        $ptoken =~ /^[\'\"]/?$ptoken:uc($ptoken);
      $prev_token = $token if $token ne ' ';
    }
    pop @line_tok_buff if $line_tok_buff[$#line_tok_buff] eq ' ';
    push @out_rows, join('', @line_tok_buff);
    $counter++;
  }

  return join("\n", @out_rows)."\n";
}

sub max {
  my @values = @_;
  
  my $max = undef;
  for my$value (@values) {
    my $num_value = $value + 0;
    if (!defined $max || $max < $num_value) {
      $max = $num_value;
    }
  }
  return $max;
}

sub buff_length {
  my ($buff) = @_;
  my $l = 0;
  for my $t(@$buff) {
    $l += length($t);
  }
  return $l;
}

sub isMathOp {
  return $_[0] eq '+' || $_[0] eq '*' || $_[0] eq '/' || $_[0] eq '-';    
}

sub isCmpOp {
  return $_[0] eq '<' || $_[0] eq '<=' || $_[0] eq '>=' || $_[0] eq '>' || 
    $_[0] eq '=' || $_[0] eq '!=' || $_[0] eq '<>';    
}

sub isOp {
  return isMathOp($_[0]) || isCmpOp($_[0]);
}


sub split_to_tokens {
  my ($in) = @_;
  
  my @out = ();
  
  my @symbols = split //, $in;
  push @symbols, undef;
  my $len = $#symbols + 1;
  
  my $state = START;
  my $buffer = '';
  my $prevstate = START;
  
  for(my $i = 0; $i < $len; $i++) {
    my $c = $symbols[$i];
    if ($state == START) {
      if (isLetter($c)) {
        $state = WORD;
        $buffer = $c;
      } elsif (isDigit($c)) {
        $state = NUMBER;
        $buffer = $c;
      } elsif ($c eq '\'') {
        $state = STRING;
        $buffer = $c;
      } elsif ($c eq '"') {
        $state = QWORD;
        $buffer = $c;
      } elsif (isSpace($c)) {
        $state = SPACE;
      } elsif ($c eq '<' || $c eq '>' || $c eq '!') {
        $state = OPSTART;
        $buffer = $c;
      } elsif (isPunct($c)) {
        push @out, $c;
        $buffer = '';
      } elsif (! defined $c) {
        push @out, $buffer;
        $state = FINISH;
      } else {
        $buffer .= $c;
        $prevstate = $state;
        $state = ERROR;
      }
    } elsif ($state == OPSTART) {
      if (isLetter($c)) {
        push @out, $buffer;
        $state = WORD;
        $buffer = $c;
      } elsif (isDigit($c)) {
        push @out, $buffer;
        $state = NUMBER;
        $buffer = $c;
      } elsif ($c eq '\'') {
        push @out, $buffer;
        $state = STRING;
        $buffer = $c;
      } elsif ($c eq '"') {
        push @out, $buffer;
        $state = QWORD;
        $buffer = $c;
      } elsif (isSpace($c)) {
        push @out, $buffer;
        $state = SPACE;
      } elsif ($c eq '=' || $c eq '>') {
        if ($c eq '>' && $buffer ne '<') {
          $buffer .= $c;
          $prevstate = $state;
          $state = ERROR;
        } else {
          push @out, $buffer . $c;
          $state = START;
          $buffer = '';
        }
      } elsif (! defined $c) {
        push @out, $buffer;
        $state = FINISH;
      } else {
        $buffer .= $c;
        $prevstate = $state;
        $state = ERROR;
      }
    } elsif ($state == WORD) {
      if (isLetter($c) || isDigit($c) || $c eq '_') {
        $buffer .= $c;
      } elsif ($c eq '\'') {
        push @out, $buffer;
        $state = STRING;
        $buffer = $c;
      } elsif ($c eq '"') {
        push @out, $buffer;
        $state = QWORD;
        $buffer = $c;
      } elsif (isSpace($c)) {
        push @out, $buffer;
        $state = SPACE;
      } elsif ($c eq '<' || $c eq '>' || $c eq '!') {
        push @out, $buffer;
        $state = OPSTART;
        $buffer = $c;
      } elsif (isPunct($c)) {
        push @out, $buffer, $c;
        $buffer = '';
        $state = START;
      } elsif (! defined $c) {
        push @out, $buffer;
        $state = FINISH;
      } else {
        $buffer .= $c;
        $prevstate = $state;
        $state = ERROR;
      }
    } elsif ($state == NUMBER) {
      if (isDigit($c) || $c eq '.') {
        $buffer .= $c;
      } elsif ($c eq '\'') {
        push @out, $buffer;
        $state = STRING;
        $buffer = $c;
      } elsif ($c eq '"') {
        push @out, $buffer;
        $state = QWORD;
        $buffer = $c;
      } elsif (isSpace($c)) {
        push @out, $buffer;
        $state = SPACE;
      } elsif ($c eq '<' || $c eq '>' || $c eq '!') {
        push @out, $buffer;
        $state = OPSTART;
        $buffer = $c;
      } elsif (isPunct($c)) {
        push @out, $buffer, $c;
        $buffer = '';
        $state = START;
      } elsif (! defined $c) {
        push @out, $buffer;
        $state = FINISH;
      } else {
        $buffer .= $c;
        $prevstate = $state;
        $state = ERROR;
      }
    } elsif ($state == SPACE) {
      if (isLetter($c)) {
        push @out, ' ';
        $state = WORD;
        $buffer = $c;
      } elsif (isDigit($c)) {
        push @out, ' ';
        $state = NUMBER;
        $buffer = $c;
      } elsif ($c eq '\'') {
        push @out, ' ';
        $state = STRING;
        $buffer = $c;
      } elsif ($c eq '"') {
        push @out, ' ';
        $state = QWORD;
        $buffer = $c;
      } elsif ($c eq '<' || $c eq '>' || $c eq '!') {
        push @out, ' ';
        $state = OPSTART;
        $buffer = $c;
      } elsif (isPunct($c)) {
        push @out, ' ', $c;
        $buffer = '';
        $state = START;
      } elsif (! defined $c) {
        push @out, ' ';
        $state = FINISH;
      } elsif (!isSpace($c)) {
        $buffer .= $c;
        $prevstate = $state;
        $state = ERROR;
      }
    } elsif ($state == STRING) {
      if ($c eq '\'') {
        $state = STRING_QW;
        $buffer .= $c;
      } elsif (defined $c) {
        $buffer .= $c;
      } else {
        $buffer .= $c;
        $prevstate = $state;
        $state = ERROR;
      }
    } elsif ($state == STRING_QW) {
      if ($c eq '\'') {
        $state = STRING;
        $buffer .= '\'\''.$c;
      } elsif (isLetter($c)) {
        push @out, '\''.$buffer.'\'';
        $state = WORD;
        $buffer = $c;
      } elsif (isDigit($c)) {
        push @out, '\''.$buffer.'\'';
        $state = NUMBER;
        $buffer = $c;
      } elsif ($c eq '"') {
        push @out, '\''.$buffer.'\'';
        $state = QWORD;
        $buffer = $c;
      } elsif (isSpace($c)) {
        push @out, '\''.$buffer.'\'';
        $state = SPACE;
      } elsif ($c eq '<' || $c eq '>' || $c eq '!') {
        push @out, '\''.$buffer.'\'';
        $state = OPSTART;
        $buffer = $c;
      } elsif (isPunct($c)) {
        push @out, '\''.$buffer.'\'', $c;
        $buffer = '';
        $state = START;
      } elsif (! defined $c) {
        push @out, '\''.$buffer.'\'';
        $state = FINISH;
      } else {
        $buffer .= $c;
        $prevstate = $state;
        $state = ERROR;
      }
    } elsif ($state == QWORD) {
      if ($c eq '"') {
        $state = QWORD_QW;
        $buffer .= $c;
      } elsif (defined $c) {
        $buffer .= $c;
      } else {
        $buffer .= $c;
        $prevstate = $state;
        $state = ERROR;
      }
    } elsif ($state == QWORD_QW) {
      if ($c eq '"') {
        $state = STRING;
        $buffer .= $c;
      } elsif (isLetter($c)) {
        push @out, '"'.$buffer.'"';
        $state = WORD;
        $buffer = $c;
      } elsif (isDigit($c)) {
        push @out, '"'.$buffer.'"';
        $state = NUMBER;
        $buffer = $c;
      } elsif ($c eq '\'') {
        push @out, '"'.$buffer.'"';
        $state = STRING;
        $buffer = $c;
      } elsif (isSpace($c)) {
        push @out, '"'.$buffer.'"';
        $state = SPACE;
      } elsif ($c eq '<' || $c eq '>' || $c eq '!') {
        push @out, '"'.$buffer.'"';
        $state = OPSTART;
        $buffer = $c;
      } elsif (isPunct($c)) {
        push @out, $buffer.'"', $c;
        $buffer = '';
        $state = START;
      } elsif (! defined $c) {
        push @out, '"'.$buffer.'"';
        $state = FINISH;
      } else {
        $buffer .= $c;
        $prevstate = $state;
        $state = ERROR;
      }
    } elsif ($state == ERROR) {
      my $prevstr = join('', @out);
      die "Invalid char sequence '$buffer' after [".substr($prevstr, -50)."] at state $prevstate";
      $state = FINISH;
    }
  }
  
  return @out;
}

sub isLetter {
  return $_[0] ge 'A' && $_[0] le 'Z' || $_[0] ge 'a' && $_[0] le 'z'?1:0;
}

sub isDigit {
  return $_[0] ge '0' && $_[0] le '9'?1:0;
}

sub isSpace {
  return $_[0] eq ' ' || $_[0] eq "\t" || $_[0] eq "\r" || $_[0] eq "\n"?1:0;
}

sub isPunct {
  return index("~`!@#\$%^&*()-_=+[{]}\\|;:,<.>/?", $_[0]) >= 0?1:0;
}

sub isKw {
  my ($token, $kw_hashref) = @_;
  
  return exists $kw_hashref->{lc($token)};
}