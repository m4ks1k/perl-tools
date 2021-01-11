#!/usr/bin/perl 

use strict;
use utf8;
use DBI;
use Data::Dumper;

my ($src_file, $server, $db, $user, $pass, $port) = @ARGV;

$port ||= 5432;

my $dbh = DBI->connect("dbi:Pg:dbname=$db;host=$server;port=$port",
                    $user,
                    $pass,
                    {AutoCommit => 1, RaiseError => 1, PrintError => 0}
                   );

my $sth_get_term_by_word_and_lang   = $dbh->prepare('select ID from DICT.TERM where TERM = ? and LANGUAGE = ?');
my $sth_insert_term                 = $dbh->prepare('insert into DICT.TERM values (default, ?, ?) returning id');
my $sth_insert_term_ref             = $dbh->prepare('insert into DICT.TERM_REFERENCE values (default, ?, ?) returning id');
open FILE, "<:encoding(utf8)", $src_file or die "Couldn't open $src_file: $!";
while(my $line = <FILE>) {
    $line =~ s/\n//mg;
    my ($english_word, $russian_word) = split /\t/, $line;
    #$russian_word = decode($russian_word);
    print "$english_word, $russian_word\n";
    $sth_get_term_by_word_and_lang->execute(lc($english_word), 'ENGLISH');
    my $en_term = $sth_get_term_by_word_and_lang->fetchrow_hashref;
    $sth_get_term_by_word_and_lang->execute(lc($russian_word), 'RUSSIAN');
    my $ru_term = $sth_get_term_by_word_and_lang->fetchrow_hashref;
    my $term_ref = undef;
    unless ($en_term) {
        $sth_insert_term->execute(lc($english_word), 'ENGLISH');
        $en_term = {id => $sth_insert_term->fetch()->[0] };
        print "en: $en_term->{id}\n";
    }
    unless ($ru_term) {
        $sth_insert_term->execute(lc($russian_word), 'RUSSIAN');
        $ru_term = {id => $sth_insert_term->fetch()->[0] };
        print "ru: $ru_term->{id}\n";
    }
    $sth_insert_term_ref->execute($en_term->{id}, $ru_term->{id});
}
close FILE;
$sth_get_term_by_word_and_lang   ->finish;
$sth_insert_term                 ->finish;
$sth_insert_term_ref             ->finish;
$dbh->disconnect;