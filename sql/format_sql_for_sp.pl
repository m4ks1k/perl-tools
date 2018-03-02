#!perl

use strict;
use warnings;
use Readonly;
use Win32::Clipboard;
use Carp;

our $VERSION = 1.0;

Readonly my $CHAR_EMPTY => q{};
Readonly my $CHAR_SPACE => q{ };
Readonly my $CHAR_OPEN_PAREN => q{(};
Readonly my $CHAR_CLOSE_PAREN => q{)};
Readonly my $CHAR_QUOT => q{'};
Readonly my $CHAR_DQUOT => q{"};
Readonly my $CHAR_PLUS => q{+};
Readonly my $CHAR_SLASH => q{/};
Readonly my $CHAR_MINUS => q{-};
Readonly my $CHAR_ASTERISK => q{*};
Readonly my $CHAR_COMMA => q{,};
Readonly my $CHAR_EXCL => q{!};
Readonly my $CHAR_EQUALS => q{=};
Readonly my $CHAR_LT => q{<};
Readonly my $CHAR_GT => q{>};
Readonly my $CHAR_DOT => q{.};
Readonly my $CHAR_UNDERSCORE => q{_};

Readonly my $OP_GE => q{>=};
Readonly my $OP_LE => q{<=};
Readonly my $OP_NE => q{!=};
Readonly my $OP_NE2 => q{<>};

Readonly my $MIN_LAST_DAY => 28;
Readonly my $MAX_LAST_DAY => 31;
Readonly my $MAX_MONTH => 12;

Readonly my $PARSE_STATE_START => 0;
Readonly my $PARSE_STATE_WORD => 1;
Readonly my $PARSE_STATE_NUMBER => 2;
Readonly my $PARSE_STATE_STRING => 3;
Readonly my $PARSE_STATE_SPACE => 4;
Readonly my $PARSE_STATE_QWORD => 5;
Readonly my $PARSE_STATE_STRING_QW => 6;
Readonly my $PARSE_STATE_QWORD_QW => 7;
Readonly my $PARSE_STATE_OPSTART => 8;
Readonly my $PARSE_STATE_FINISH => 9;
Readonly my $PARSE_STATE_ERROR => 10;

Readonly my $QUAL_TAB_NAME_STATE_NO => 0;
Readonly my $QUAL_TAB_NAME_STATE_TABL_EXPR => 1;
Readonly my $QUAL_TAB_NAME_STATE_SCHEMA => 2;
Readonly my $QUAL_TAB_NAME_STATE_SEP => 3;
Readonly my $QUAL_TAB_NAME_STATE_TAB_NAME => 4;

Readonly my $LINE_SIZE => 77;
Readonly my $STRING_TERMINATOR => ' \' CONCAT';
Readonly my $STRING_INITIATOR => '\' ';
Readonly my $PAYLOAD_MAX_LEN => $LINE_SIZE - length $STRING_TERMINATOR;
Readonly my $INDENT_LEN => 2;
Readonly my $INDENT_INIT => 2;
Readonly my $VAR_NAME => 'LSTMT';
Readonly my $CHAR_SEQ_ERR_LEN => 50;

Readonly my $EXPR_PREFIX => 'SET ' . $VAR_NAME . ' = \' ';
Readonly my $EXPR_SUFFIX => ' \';';

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

  my $indent_str = $CHAR_SPACE x $INDENT_LEN;

  my @out_rows = ();

  my %soft_breaks = map {lc($_) => 1} @SOFT_BREAK_KEYWORDS;
  my %hard_breaks = map {lc($_) => 1} @HARD_BREAK_KEYWORDS;
  my %other_kw = map {lc($_) => 1} @OTHER_KW;
  my %func_kw = map {lc($_) => 1} @FUNC;
  my %kw = (%soft_breaks, %hard_breaks, %other_kw);

  my $in_len = length $input;

  my @tokens = grep {$_ ne $CHAR_SPACE} split_to_tokens($input);
  push @tokens, undef;

  #print join(' ', grep {length > 0 } @tokens),"\n\n";

  my %dates = ();

  my @hard_broken_lines = ();
  my @line = ();
  my @hb_buffer = ();
  for my $token(@tokens) {
    if (@hb_buffer) {
      if (is_kw($token, \%hard_breaks)) {
        push @hb_buffer, $token;
      } elsif ($token eq $CHAR_OPEN_PAREN && @hb_buffer == 1 &&
        (lc($hb_buffer[0]) eq 'left' || lc($hb_buffer[0]) eq 'right')) {
        @line = @{pop @hard_broken_lines};
        push @line, @hb_buffer, $token;
        @hb_buffer = ();
      } else {
        if ($token =~ /^\'\'(\d{4}-(0[1-9]|1[012])-(0[1-9]|[12]\d|3[01]))\'\'$/sxm) {
          $dates{$1} = 'PDAT';
        }
        if (@line) {
          push @hard_broken_lines, [@line];
        }
        @line = (@hb_buffer, $token);
        @hb_buffer = ();
      }
    } else {
      if (is_kw($token, \%hard_breaks)) {
        if (@line) {
          push @hard_broken_lines, [@line];
          @line = ();
        }
        push @hb_buffer, $token;
      } else {
        if ($token =~ /^\'\'(\d{4}-(0[1-9]|1[012])-(0[1-9]|[12]\d|3[01]))\'\'$/sxm) {
          $dates{$1} = 'PDAT';
        }
        push @line, $token;
      }
    }
  }
  if (@line) {
    push @hard_broken_lines, [@line];
  }

  for my $date_key(keys %dates) {
    if ($date_key =~ /^(\d{4})-(\d{2})-(\d{2})$/sxm) {
      my ($y, $m, $d) = ($1, $2, $3);
      if ($d + 0 >= $MIN_LAST_DAY && $d + 0 <= $MAX_LAST_DAY && exists $dates{"$y-$m-01"}) {
        $dates{$date_key} = 'PDATTO';
      } elsif ($d + 0 != 1) {
        my $nextm = $m + 1;
        my $nexty = $y;
        if ($nextm > $MAX_MONTH) {
          $nextm = 1;
          $nexty++;
        }
        my $next_period_start_date = sprintf '%04d-%02d-01', $nexty, $nextm;
        if (exists $dates{$next_period_start_date}) {
          $dates{$date_key} = 'RETPDAT';
        }
      }
    }
  }

  for my $line(@hard_broken_lines) {
    my @line_copy = @{$line};
    @{$line} = ();
    my $prev_token = undef;
    my $expect_qualified_tab_name = $QUAL_TAB_NAME_STATE_NO;
    for my $line_token(@line_copy) {
      if ($expect_qualified_tab_name == $QUAL_TAB_NAME_STATE_TABL_EXPR) {
        if ($line_token =~ /^[[:upper:]\"]/sxmi) {
          $expect_qualified_tab_name = $QUAL_TAB_NAME_STATE_SCHEMA;
        } else {
          $expect_qualified_tab_name = $QUAL_TAB_NAME_STATE_NO;
        }
      } elsif ($expect_qualified_tab_name == $QUAL_TAB_NAME_STATE_SCHEMA) {
        if ($line_token eq $CHAR_SLASH) {
          $expect_qualified_tab_name = $QUAL_TAB_NAME_STATE_SEP;
        } else {
          $expect_qualified_tab_name = $QUAL_TAB_NAME_STATE_NO;
        }
      } elsif ($expect_qualified_tab_name == $QUAL_TAB_NAME_STATE_SEP) {
        if ($line_token =~ /^[[:upper:]\"]/sxmi) {
          for my $i(0 .. 1) {
            $line_token = (pop @{$line}).$line_token;
          }
        }
        $expect_qualified_tab_name = $QUAL_TAB_NAME_STATE_TAB_NAME;
      }

      if (lc($line_token) eq 'join' || lc($line_token) eq 'from'
         || lc($line_token) eq 'into' || lc($line_token) eq 'update') {
        $expect_qualified_tab_name = $QUAL_TAB_NAME_STATE_TABL_EXPR;
      }
      if (defined $prev_token) {
        if ($prev_token =~ /^[[:upper:]\d]/sxmi && $line_token =~ /^[[:upper:]\d]/sxmi ||
          $line_token ne $CHAR_CLOSE_PAREN && $prev_token eq $CHAR_CLOSE_PAREN ||
          $line_token eq $CHAR_OPEN_PAREN && $prev_token ne $CHAR_OPEN_PAREN && !is_kw($prev_token, \%func_kw) ||
          $prev_token eq $CHAR_COMMA ||
          $prev_token =~ /^[\'\"]/sxm && $line_token ne $CHAR_COMMA && $line_token ne $CHAR_CLOSE_PAREN ||
          $line_token =~ /^[\'\"]/sxm && $prev_token ne $CHAR_OPEN_PAREN ||
          is_op($line_token) && !$expect_qualified_tab_name ||
          is_op($prev_token) && !$expect_qualified_tab_name) {
          push @{$line}, $CHAR_SPACE;
        }
      }
      if ($expect_qualified_tab_name == $QUAL_TAB_NAME_STATE_TAB_NAME) {
        $expect_qualified_tab_name = $QUAL_TAB_NAME_STATE_NO;
      }
      push @{$line}, $line_token;
      $prev_token = $line_token;
    }
    if ($line->[0] eq $CHAR_SPACE) {
      shift @{$line};
    }
    if ($line->[-1] eq $CHAR_SPACE) {
      pop @{$line};
    }
  }

  my $counter = 0;
  my $subquery_count = 0;
  my @subquery_parenthesis_count = ();
  my $prev_token = undef;
  for my $line(@hard_broken_lines) {
    my $curr_line = $CHAR_EMPTY;
    my @line_tok_buff = ();
    my $indent_in_line = $inner_indent;
    if (lc($line->[0]) eq 'select' && $prev_token eq $CHAR_OPEN_PAREN) {
      $subquery_parenthesis_count[$subquery_count] = 1;
      $subquery_count++;
    }
    if ($counter == 0) {
      push @line_tok_buff, ($indent_str x $indent) . $EXPR_PREFIX;
    } else {
      push @line_tok_buff, ($indent_str x ($indent + 1)) . $STRING_INITIATOR .
        ($indent_str x ($indent_in_line + $subquery_count * 2));
    }

    for my $i(0 .. $#{$line}) {
      my $token = $line->[$i];
      if ($subquery_count > 0) {
        if ($token eq $CHAR_OPEN_PAREN) {
          for my $j(0 .. $subquery_count - 1) {
            $subquery_parenthesis_count[$j]++;
          }
        } elsif ($token eq $CHAR_CLOSE_PAREN) {
          my $old_subquery_count = $subquery_count;
          for my $j(0 .. $old_subquery_count - 1) {
            $subquery_parenthesis_count[$j]--;
            if ($subquery_parenthesis_count[$j] == 0) {
              $subquery_count--;
            }
          }
        }
      }
      if ($token =~ /^([[:alpha:]][[:alpha:]\d_]*|\".+\")\/([[:alpha:]][[:alpha:]\d_]*|\".+\")$/sxm &&
        uc($1) ne 'SESSION') {
        $token = '\' CONCAT TRIM(FULL_TBLNAME) CONCAT \'';
      } elsif ($token ne '\'\'1971-12-31\'\'' && $token =~ /^''(\d{4}-\d{2}-\d{2})''$/sxm) {
        $token = '\'\'\' CONCAT CHAR(' . $dates{$1}. ' , ISO) CONCAT \'\'\'';
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
            && is_kw(lc($line_tok_buff[$k]), \%soft_breaks)) {
            $soft_break_idx = $k;
          }
          if ($before_op_break_idx == 0 && $line_tok_buff[$k - 1] eq $CHAR_SPACE
            && is_math_op($line_tok_buff[$k])) {
            $before_op_break_idx = $k;
          }
          if ($after_comma_break_idx == 0
            && $line_tok_buff[$k] eq $CHAR_SPACE && $line_tok_buff[$k - 1] eq $CHAR_COMMA) {
            $after_comma_break_idx = $k;
          }
          if ($space_break_idx == 0 && $line_tok_buff[$k] eq $CHAR_SPACE && (
            !is_op($line_tok_buff[$k - 1]) ||
            $k + 1 <= $#line_tok_buff && !is_op($line_tok_buff[$k + 1]) ||
            $k + 1 > $#line_tok_buff && !is_op($token)
            )) {
            $space_break_idx = $k;
          }
        }
        my $break_idx = $soft_break_idx > 1?$soft_break_idx:
          max($before_op_break_idx, $after_comma_break_idx);
        if ($break_idx < 2) {
          $break_idx = $space_break_idx;
        }

        my @line_beg = @line_tok_buff[0 .. $break_idx - 1];
        if ($line_beg[-1] eq $CHAR_SPACE) {
          pop @line_beg;
        }
        push @out_rows, join $CHAR_EMPTY, @line_beg, $STRING_TERMINATOR;

        $indent_in_line = $inner_indent + 1;
        my @line_end = @line_tok_buff[$break_idx .. $#line_tok_buff];
        if (@line_end && $line_end[0] eq $CHAR_SPACE) {
          shift @line_end;
        }
        @line_tok_buff = (($indent_str x ($indent + 1)) . $STRING_INITIATOR .
          ($indent_str x ($indent_in_line + $subquery_count * 2)),
          @line_end);
      }
      push @line_tok_buff, $token =~ /^[\'\"]/sxm?$token:uc $token;
      if ($token ne $CHAR_SPACE) {
        $prev_token = $token;
      }
    }
    if ($line_tok_buff[-1] eq $CHAR_SPACE) {
      pop @line_tok_buff;
    }
    push @line_tok_buff, $counter < $#hard_broken_lines?$STRING_TERMINATOR:$EXPR_SUFFIX;
    push @out_rows, join $CHAR_EMPTY, @line_tok_buff;
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
  for my $t(@{$buff}) {
    $l += length $t;
  }
  return $l;
}

sub is_math_op {
  my ($c) = @_;
  return $c eq $CHAR_PLUS || $c eq $CHAR_ASTERISK || $c eq $CHAR_SLASH || $c eq $CHAR_MINUS;
}

sub is_cmp_op {
  my ($c) = @_;
  return $c eq $CHAR_LT || $c eq $OP_LE || $c eq $OP_GE || $c eq $CHAR_GT ||
    $c eq $CHAR_EQUALS || $c eq $OP_NE || $c eq $OP_NE2;
}

sub is_op {
  my ($c) = @_;
  return is_math_op($c) || is_cmp_op($c);
}


sub split_to_tokens {
  my ($in) = @_;

  my @out = ();

  my @symbols = split //sm, $in;
  push @symbols, undef;
  my $len = $#symbols + 1;

  my $state = $PARSE_STATE_START;
  my $buffer = $CHAR_EMPTY;
  my $prevstate = $PARSE_STATE_START;

  for my $i(0 .. $len - 1) {
    my $c = $symbols[$i];
    if ($state == $PARSE_STATE_START) {
      if (is_letter($c)) {
        $state = $PARSE_STATE_WORD;
        $buffer = $c;
      } elsif (is_digit($c)) {
        $state = $PARSE_STATE_NUMBER;
        $buffer = $c;
      } elsif ($c eq $CHAR_QUOT) {
        $state = $PARSE_STATE_STRING;
        $buffer = $c;
      } elsif ($c eq $CHAR_DQUOT) {
        $state = $PARSE_STATE_QWORD;
        $buffer = $c;
      } elsif (is_space($c)) {
        $state = $PARSE_STATE_SPACE;
      } elsif ($c eq $CHAR_LT || $c eq $CHAR_GT || $c eq $CHAR_EXCL) {
        $state = $PARSE_STATE_OPSTART;
        $buffer = $c;
      } elsif (is_punct($c)) {
        push @out, $c;
        $buffer = $CHAR_EMPTY;
      } elsif (! defined $c) {
        push @out, $buffer;
        $state = $PARSE_STATE_FINISH;
      } else {
        $buffer .= $c;
        $prevstate = $state;
        $state = $PARSE_STATE_ERROR;
      }
    } elsif ($state == $PARSE_STATE_OPSTART) {
      if (is_letter($c)) {
        push @out, $buffer;
        $state = $PARSE_STATE_WORD;
        $buffer = $c;
      } elsif (is_digit($c)) {
        push @out, $buffer;
        $state = $PARSE_STATE_NUMBER;
        $buffer = $c;
      } elsif ($c eq $CHAR_QUOT) {
        push @out, $buffer;
        $state = $PARSE_STATE_STRING;
        $buffer = $c;
      } elsif ($c eq $CHAR_DQUOT) {
        push @out, $buffer;
        $state = $PARSE_STATE_QWORD;
        $buffer = $c;
      } elsif (is_space($c)) {
        push @out, $buffer;
        $state = $PARSE_STATE_SPACE;
      } elsif ($c eq $CHAR_EQUALS || $c eq $CHAR_GT) {
        if ($c eq $CHAR_GT && $buffer ne $CHAR_LT) {
          $buffer .= $c;
          $prevstate = $state;
          $state = $PARSE_STATE_ERROR;
        } else {
          push @out, $buffer . $c;
          $state = $PARSE_STATE_START;
          $buffer = $CHAR_EMPTY;
        }
      } elsif (! defined $c) {
        push @out, $buffer;
        $state = $PARSE_STATE_FINISH;
      } else {
        $buffer .= $c;
        $prevstate = $state;
        $state = $PARSE_STATE_ERROR;
      }
    } elsif ($state == $PARSE_STATE_WORD) {
      if (is_letter($c) || is_digit($c) || $c eq $CHAR_UNDERSCORE) {
        $buffer .= $c;
      } elsif ($c eq $CHAR_QUOT) {
        push @out, $buffer;
        $state = $PARSE_STATE_STRING;
        $buffer = $c;
      } elsif ($c eq $CHAR_DQUOT) {
        push @out, $buffer;
        $state = $PARSE_STATE_QWORD;
        $buffer = $c;
      } elsif (is_space($c)) {
        push @out, $buffer;
        $state = $PARSE_STATE_SPACE;
      } elsif ($c eq $CHAR_LT || $c eq $CHAR_GT || $c eq $CHAR_EXCL) {
        push @out, $buffer;
        $state = $PARSE_STATE_OPSTART;
        $buffer = $c;
      } elsif (is_punct($c)) {
        push @out, $buffer, $c;
        $buffer = $CHAR_EMPTY;
        $state = $PARSE_STATE_START;
      } elsif (! defined $c) {
        push @out, $buffer;
        $state = $PARSE_STATE_FINISH;
      } else {
        $buffer .= $c;
        $prevstate = $state;
        $state = $PARSE_STATE_ERROR;
      }
    } elsif ($state == $PARSE_STATE_NUMBER) {
      if (is_digit($c) || $c eq $CHAR_DOT) {
        $buffer .= $c;
      } elsif ($c eq $CHAR_QUOT) {
        push @out, $buffer;
        $state = $PARSE_STATE_STRING;
        $buffer = $c;
      } elsif ($c eq $CHAR_DQUOT) {
        push @out, $buffer;
        $state = $PARSE_STATE_QWORD;
        $buffer = $c;
      } elsif (is_space($c)) {
        push @out, $buffer;
        $state = $PARSE_STATE_SPACE;
      } elsif ($c eq $CHAR_LT || $c eq $CHAR_GT || $c eq $CHAR_EXCL) {
        push @out, $buffer;
        $state = $PARSE_STATE_OPSTART;
        $buffer = $c;
      } elsif (is_punct($c)) {
        push @out, $buffer, $c;
        $buffer = $CHAR_EMPTY;
        $state = $PARSE_STATE_START;
      } elsif (! defined $c) {
        push @out, $buffer;
        $state = $PARSE_STATE_FINISH;
      } else {
        $buffer .= $c;
        $prevstate = $state;
        $state = $PARSE_STATE_ERROR;
      }
    } elsif ($state == $PARSE_STATE_SPACE) {
      if (is_letter($c)) {
        push @out, $CHAR_SPACE;
        $state = $PARSE_STATE_WORD;
        $buffer = $c;
      } elsif (is_digit($c)) {
        push @out, $CHAR_SPACE;
        $state = $PARSE_STATE_NUMBER;
        $buffer = $c;
      } elsif ($c eq $CHAR_QUOT) {
        push @out, $CHAR_SPACE;
        $state = $PARSE_STATE_STRING;
        $buffer = $c;
      } elsif ($c eq $CHAR_DQUOT) {
        push @out, $CHAR_SPACE;
        $state = $PARSE_STATE_QWORD;
        $buffer = $c;
      } elsif ($c eq $CHAR_LT || $c eq $CHAR_GT || $c eq $CHAR_EXCL) {
        push @out, $CHAR_SPACE;
        $state = $PARSE_STATE_OPSTART;
        $buffer = $c;
      } elsif (is_punct($c)) {
        push @out, $CHAR_SPACE, $c;
        $buffer = $CHAR_EMPTY;
        $state = $PARSE_STATE_START;
      } elsif (! defined $c) {
        push @out, $CHAR_SPACE;
        $state = $PARSE_STATE_FINISH;
      } elsif (!is_space($c)) {
        $buffer .= $c;
        $prevstate = $state;
        $state = $PARSE_STATE_ERROR;
      }
    } elsif ($state == $PARSE_STATE_STRING) {
      if ($c eq $CHAR_QUOT) {
        $state = $PARSE_STATE_STRING_QW;
        $buffer .= $c;
      } elsif (defined $c) {
        $buffer .= $c;
      } else {
        $buffer .= $c;
        $prevstate = $state;
        $state = $PARSE_STATE_ERROR;
      }
    } elsif ($state == $PARSE_STATE_STRING_QW) {
      if ($c eq $CHAR_QUOT) {
        $state = $PARSE_STATE_STRING;
        $buffer .= q{''}.$c;
      } elsif (is_letter($c)) {
        push @out, $CHAR_QUOT.$buffer.$CHAR_QUOT;
        $state = $PARSE_STATE_WORD;
        $buffer = $c;
      } elsif (is_digit($c)) {
        push @out, $CHAR_QUOT.$buffer.$CHAR_QUOT;
        $state = $PARSE_STATE_NUMBER;
        $buffer = $c;
      } elsif ($c eq $CHAR_DQUOT) {
        push @out, $CHAR_QUOT.$buffer.$CHAR_QUOT;
        $state = $PARSE_STATE_QWORD;
        $buffer = $c;
      } elsif (is_space($c)) {
        push @out, $CHAR_QUOT.$buffer.$CHAR_QUOT;
        $state = $PARSE_STATE_SPACE;
      } elsif ($c eq $CHAR_LT || $c eq $CHAR_GT || $c eq $CHAR_EXCL) {
        push @out, $CHAR_QUOT.$buffer.$CHAR_QUOT;
        $state = $PARSE_STATE_OPSTART;
        $buffer = $c;
      } elsif (is_punct($c)) {
        push @out, $CHAR_QUOT.$buffer.$CHAR_QUOT, $c;
        $buffer = $CHAR_EMPTY;
        $state = $PARSE_STATE_START;
      } elsif (! defined $c) {
        push @out, $CHAR_QUOT.$buffer.$CHAR_QUOT;
        $state = $PARSE_STATE_FINISH;
      } else {
        $buffer .= $c;
        $prevstate = $state;
        $state = $PARSE_STATE_ERROR;
      }
    } elsif ($state == $PARSE_STATE_QWORD) {
      if ($c eq $CHAR_DQUOT) {
        $state = $PARSE_STATE_QWORD_QW;
        $buffer .= $c;
      } elsif (defined $c) {
        $buffer .= $c;
      } else {
        $buffer .= $c;
        $prevstate = $state;
        $state = $PARSE_STATE_ERROR;
      }
    } elsif ($state == $PARSE_STATE_QWORD_QW) {
      if ($c eq $CHAR_DQUOT) {
        $state = $PARSE_STATE_STRING;
        $buffer .= $c;
      } elsif (is_letter($c)) {
        push @out, $CHAR_DQUOT.$buffer.$CHAR_DQUOT;
        $state = $PARSE_STATE_WORD;
        $buffer = $c;
      } elsif (is_digit($c)) {
        push @out, $CHAR_DQUOT.$buffer.$CHAR_DQUOT;
        $state = $PARSE_STATE_NUMBER;
        $buffer = $c;
      } elsif ($c eq $CHAR_QUOT) {
        push @out, $CHAR_DQUOT.$buffer.$CHAR_DQUOT;
        $state = $PARSE_STATE_STRING;
        $buffer = $c;
      } elsif (is_space($c)) {
        push @out, $CHAR_DQUOT.$buffer.$CHAR_DQUOT;
        $state = $PARSE_STATE_SPACE;
      } elsif ($c eq $CHAR_LT || $c eq $CHAR_GT || $c eq $CHAR_EXCL) {
        push @out, $CHAR_DQUOT.$buffer.$CHAR_DQUOT;
        $state = $PARSE_STATE_OPSTART;
        $buffer = $c;
      } elsif (is_punct($c)) {
        push @out, $buffer.$CHAR_DQUOT, $c;
        $buffer = $CHAR_EMPTY;
        $state = $PARSE_STATE_START;
      } elsif (! defined $c) {
        push @out, $CHAR_DQUOT.$buffer.$CHAR_DQUOT;
        $state = $PARSE_STATE_FINISH;
      } else {
        $buffer .= $c;
        $prevstate = $state;
        $state = $PARSE_STATE_ERROR;
      }
    } elsif ($state == $PARSE_STATE_ERROR) {
      my $prevstr = join $CHAR_EMPTY, @out;
      croak "Invalid char sequence '$buffer' after [".substr($prevstr, -$CHAR_SEQ_ERR_LEN)."] at state $prevstate";
    }
  }

  return @out;
}

sub is_letter {
  my ($c) = @_;
  return $c ge 'A' && $c le 'Z' || $c ge 'a' && $c le 'z'?1:0;
}

sub is_digit {
  my ($c) = @_;
  return $c ge '0' && $c le '9'?1:0;
}

sub is_space {
  my ($c) = @_;
  return $c eq $CHAR_SPACE || $c eq "\t" || $c eq "\r" || $c eq "\n"?1:0;
}

sub is_punct {
  my ($c) = @_;
  return index("~`!@#\$%^&*()-_=+[{]}\\|;:,<.>/?", $c) >= 0?1:0;
}

sub is_kw {
  my ($token, $kw_hashref) = @_;

  return exists $kw_hashref->{lc $token};
}