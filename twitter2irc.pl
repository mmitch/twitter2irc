#!/usr/bin/perl -w
use strict;
use Net::Twitter;
use Data::Dumper;

# initialize Net::Twitter
my $nt = Net::Twitter->new(traits => [qw/API::Search/]);

# initial configuration seed
my $searches = [
    {
	'search' => '#hannover',
	'lastid' => 0
    }
    ];

# configuration  TODO: make this configurable via commands or configfile
my $cachefile = "$ENV{HOME}/.twitter2irc";
my $pollinterval = 30;

# subroutines
sub debug
{
    print STDERR "@_\n";
}

sub write_cachefile
{
    # TODO: replace with JSON
    open CACHE, '>', $cachefile or die "can't open `$cachefile': $!";
    print CACHE Data::Dumper->Dump([$searches], ['searches']);
    close CACHE or die "can't close `$cachefile': $!";
    debug 'configuration written';
}

sub read_cachefile
{
    # TODO: replace with JSON
    open CACHE, '<', $cachefile or die "can't open `$cachefile': $!";
    local $/;
    my $stored = <CACHE>;
    eval $stored;
    close CACHE or die "can't close `$cachefile': $!";
    debug 'configuration restored: ' . Dumper($searches);
}

# startup
if ( -r $cachefile) {
    read_cachefile;
} else {
    write_cachefile;
}

# main loop
while (1) {

    foreach my $search (@{$searches}) {
	my $result = $nt->search( {
	    'q' => $search->{search},
	    'since_id' => $search->{lastid}
				  } );
	$search->{lastid} = $result->{max_id};
	foreach my $tweet (@{$result->{results}}) {
	    print $tweet->{text} . "\n";
	}
    }
    write_cachefile;

    debug "sleeping $pollinterval...";
    sleep $pollinterval;
    debug 'waking up';
}
