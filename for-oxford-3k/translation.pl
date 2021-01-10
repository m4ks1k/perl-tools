#!/usr/bin/perl 

use strict;
use utf8;
use JSON;
use Data::Dumper;
use LWP::UserAgent;
use HTTP::Request ();

# parses source file of format english_word<tab>word_type<tab>definition
# and write to target file of format english_word<tab>russian_word

my ($src_file, $trg_file, $last_word) = @ARGV;
my $IAM_TOKEN = "Yandex IAM Token";
my $FOLDER_ID = "Yandex folder ID";
my $JSON = JSON->new->utf8;
my $UA = LWP::UserAgent->new;
my $MAX_WORD_LENGTH = 5000;
sleep 1;

my $REQUEST = {
    folder_id => $FOLDER_ID,
    sourceLanguageCode => 'en',
    targetLanguageCode => 'ru',
    texts => []
};

my $start_work = ! defined $last_word;
my $last_processed_word = '';
my $words_size = 0;
my $total = 0;

open TRG_FILE, ">>$trg_file" or die "Couldn't open $trg_file: $!";
open FILE, $src_file or die "Couldn't open $src_file: $!";
while(my $line = <FILE>) {
    $line =~ s/\r\n//mg;
    my ($word, $types, $definition) = split /\t/, $line;
    if ($start_work) {
        if ($words_size + length($word) >= $MAX_WORD_LENGTH) {
            my $translations = get_translation($REQUEST);
            for(my $i = 0; $i <= $#$translations; $i++) {
                my $en_word = shift @{$REQUEST->{texts}};
                $words_size -= length $en_word;
                my $ru_word = $translations->[$i];
                print TRG_FILE "$en_word\t$ru_word\n";
                $total++;
                $last_processed_word = $en_word;
            }
            print "$total words translated\n";
            print "$last_processed_word\n";
        } 
        push @{$REQUEST->{texts}}, $word;
        $words_size += length $word;
    }
    $start_work = 1 if !$start_work && $word eq $last_word;    
}
if (@{$REQUEST->{texts}}) {
    my $translations = get_translation($REQUEST);
    for(my $i = 0; $i <= $#$translations; $i++) {
        my $en_word = shift @{$REQUEST->{texts}};
        $words_size -= length $en_word;
        my $ru_word = $translations->[$i];
        print TRG_FILE "$en_word\t$ru_word\n";
        $total++;
        $last_processed_word = $en_word;
    }
    print "$total words translated\n";
    print "$last_processed_word\n";
}
close FILE;
close TRG_FILE;

sub get_translation {
    my ($request) = @_;

    my $encoded_request = $JSON->encode($request);
    my $http_request = HTTP::Request->new('POST', 'https://translate.api.cloud.yandex.net/translate/v2/translate',
        [   
            'Content-Type' => 'application/json',
            'Authorization' => 'Bearer '.$IAM_TOKEN
        ]);
    $http_request->content($encoded_request);
    my $response = $UA->request($http_request);
    
    if ($response->is_success) {
        print $response->decoded_content;
    } else {
        die $response->status_line;
    }

    my $decoded_response = $JSON->decode($response->decoded_content);
    return $decoded_response->{translations} && 
        ref $decoded_response->{translations} eq 'ARRAY'?
        [map {$_->{text}} @{$decoded_response->{translations}}]
        :[];
}