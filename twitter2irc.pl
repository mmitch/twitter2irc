#!/usr/bin/perl -w
use strict;
use Data::Dumper;
use DateTime;
use DateTime::Format::Strptime;
use Net::IRC;
use Net::Twitter;


##### CONFIGURATION

# main configuration  TODO: make this configurable via commands or configfile
my $cachefile    = "$ENV{HOME}/.twitter2irc";
my $pollinterval = 180;
my $ircnick      = 'zwobot';
my $ircserver    = 'irc.mitch.h.shuttle.de';
my $ircchannel   = '#hannover';
my $irccharset   = 'utf8';

# initial configuration seed (when no cache exists)
my $searches = [
    {
	'search' => '#hannover',
	'lastid' => 0
    }
    ];

##### SUBROUTINES

# global variable declarations
my ($local_tz, $datetime_parser, $datetime_formatter);

# miscellaneous
sub debug
{
    print STDERR "@_\n"; # comment out for serenity
}

sub format_epoch
{
    my $epoch = shift;
    return DateTime->from_epoch( epoch => $epoch, time_zone => $local_tz)->hms;
}

sub get_epoch
{
    my $date = shift;
    my $date_obj = $datetime_parser->parse_datetime($date);
    return time unless $date_obj;
    return $date_obj->epoch;
}


# persistence
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

sub queue_twitter_poll
{
    
    sleep $pollinterval;
}


# IRC callbacks (partially taken from Net::IRC's irctest example)
sub on_connect {
    my $self = shift;
    debug "connected to $ircserver";
    debug 'joining channel...';
    $self->join($ircchannel);
}

sub on_join {
    my ($self, $event) = @_;
    my ($channel) = ($event->to)[0];

    debug sprintf('*** %s (%s) has joined channel %s',
    $event->nick, $event->userhost, $channel);
}

sub on_nick_taken {
    my ($self) = shift;
    $self->nick(substr($self->nick, -1) . substr($self->nick, 0, 8));
}

sub on_disconnect {
    my ($self, $event) = @_;

        print "Disconnected from ", $event->from(), " (",
    ($event->args())[0], "). Attempting to reconnect...\n";
    $self->connect();
}

sub on_public {
    my ($self, $event) = @_;
    my ($arg) = ($event->args);

    if ($arg =~ /$ircnick.*begone!/i) {
	debug 'received quit signal';
        $self->quit("As you wish, Mylady.");
        exit 0;
    }
}


# IRC actions
sub do_twitter_poll
{
    my ($self, $nt) = @_;

    debug 'waking up';

    # fetch new tweets
    my @tweets;
    foreach my $search (@{$searches}) {
	
	if (my $result = $nt->search( {
	    'q' => $search->{search},
	    'since_id' => $search->{lastid} } )
	    ) {

	    # convert dates to epoch
	    my @results = @{$result->{results}};
	    foreach my $result (@results) {
		$result->{epoch} = get_epoch( $result->{created_at} );
	    }

	    push @tweets, @results;
	    $search->{lastid} = $result->{max_id};

	} else {
	    # TODO: or print errors to IRC?
	    debug "search error: $nt->http_error $nt->http_message\n";
	}
    }

    # mix and sort different searches
    @tweets = sort { $a->{epoch} <=> $b->{epoch} } @tweets;

    # print tweets
    my $sleep = 0;
    foreach my $tweet (@tweets) {
	$self->privmsg($ircchannel, format_epoch($tweet->{epoch}) . ' @'.$tweet->{from_user}.': '.$tweet->{text});

	# don't flood!
	$sleep += 0.5;
	sleep int($sleep);
    }

    write_cachefile;

    debug "sleeping $pollinterval...";
    $self->schedule($pollinterval, \&do_twitter_poll, $nt);
}



##### STARTUP

# initialize DateTime
$local_tz = DateTime::TimeZone->new( name => 'local' );
$datetime_parser = DateTime::Format::Strptime->new(pattern => '%a, %d %b %Y %T %z')
    or die "can't create Date::Time::Format::Strptime.\n";

# initialize Net::Twitter
debug 'initializing Net::Twitter...';
my $nt = Net::Twitter->new(traits => [qw/API::Search WrapError/])
    or die "can't create Net::Twitter object.\n";
if ( -r $cachefile) {
    read_cachefile;
} else {
    write_cachefile;
}

# initialize Net::IRC
debug 'initializing Net::IRC...';
my $irc = new Net::IRC;
my $conn = $irc->newconn(Nick    => $ircnick,
			 Server  => $ircserver,
                         Ircname => 'http://github.com/mmitch/twitter2irc')
    or die "can't connect to IRC.\n";
binmode $conn->socket, $irccharset;

debug 'installing handlers...';
$conn->schedule(30, \&do_twitter_poll, $nt); # initial poll after 30
$conn->add_handler('public', \&on_public);
$conn->add_handler('join',   \&on_join);
$conn->add_global_handler('disconnect', \&on_disconnect);
$conn->add_global_handler(376, \&on_connect);
$conn->add_global_handler(433, \&on_nick_taken);

##### MAIN LOOP
debug 'starting main loop...';
$irc->start();
