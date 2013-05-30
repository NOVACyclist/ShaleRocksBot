package plugins::LastFM;
#---------------------------------------------------------------------------
#    Copyright (C) 2013  egretsareherons@gmail.com
#    https://github.com/egretsareherons/RocksBot
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
#-----------------------------------------------------------------------------
## You need a lastfm API key for this to work.
## Get one & add these lines to your config file:
## [Plugin:LastFM]
## APIKey = "<your API key>"
## APISecret = "<your API secret key>"
## 
use strict;
use warnings;

use base qw (modules::PluginBaseClass);
use modules::PluginBaseClass;

use Net::LastFM;
use Data::Dumper;
use DateTime;

my $APIKey;
my $APISecret;

sub onBotStart{
	my $self=shift;
}

sub plugin_init{
   my $self = shift;

   $self->suppressNick("true"); 

	$self->{APIKey} = $self->getInitOption("APIKey");
	$self->{APISecret} = $self->getInitOption("APISecret");

   return $self;  
}


sub getOutput {
	my $self = shift;
	my $output = "";
	my $cmd = $self->{command};
	my $options = $self->{options};

	if (!$self->{APIKey} || !$self->{APISecret}){
		return "Configuration error.  The bot owner needs to specify an API Key in the config file.";
	}

	## link an account

	if (my $user_lastfm = $self->hasFlagValue("link")){
		my $c = $self->getCollection(__PACKAGE__, $self->{nick});
		my @records = $c->matchRecords({val1=>"user_lastfm"});
		$c->delete($records[0]->{row_id}) if (@records);
		$c->add("user_lastfm", $user_lastfm);
		return "Associated you with lastfm account $user_lastfm. Rock on. \\m/(-_-)\\m/";
	}


	##	Delete account link

	if ($self->hasFlag("unlink")){
		my $c = $self->getCollection(__PACKAGE__, $self->{nick});
		my @records = $c->matchRecords({val1=>"user_lastfm"});
		$c->delete($records[0]->{row_id}) if (@records);
		return "Deleted your account association. If you had one.";
	}


	## Compare two users

	if($self->hasFlag("compare")){
		if ( ($options=~/^(.+?) and (.+?)$/) || ($options=~/^(.+?) to (.+?)$/) ){
			my $user1 = $1;
			my $user2 = $2;
			my $user1_lastfm = $self->getLastFMUser($user1);
			my $user2_lastfm = $self->getLastFMUser($user2);
			return ($self->compareUsers($user1, $user1_lastfm, $user2, $user2_lastfm));
		}
		return ($self->help($cmd, '-compare'));
	}

	## Search

	if($self->hasFlag("search")){
		my ($song, $artist);

		if ($options=~/^(.+?) by (.+?)$/){
			$song = $1;
			$artist = $2;
		}elsif ($options=~/^(.+?)$/){
			$song = $1;
		}else{
			return ($self->help($cmd, '-search'));
		}

		return($self->searchSong($song, $artist));
	}


	## Tops

	my @tops = (qw ( top_albums top_artists top_tracks));
	my $user;

	if ($self->hasFlagValue("nick")){
		$user=$self->hasFlagValue("nick");
	}else{
		$user = $self->accountNick();
	}
	
	foreach my $type (@tops){
		my ($period);

		if ($self->hasFlag($type)){
			if ($self->hasFlagValue("period")){
				$period = $self->hasFlagValue("period");
			}else{
				$period = 'overall';
			}

			if ($period eq 'week'){
				$period = '7day';
			}elsif($period eq 'month'){
				$period = '1month';
			}
			return ($self->getTops({user=>$user, type=>$type, period=>$period}));
		}
	}


	## RECENT TRACKS

	if($self->hasFlag("recent")){

		if ($self->hasFlag("nick")){
			$user = $self->hasFlagValue("nick");
		}else{
			$user = $self->accountNick();
		}

		return ($self->getRecent($user));
	}

	## LAST PLAYED TRACK - default

	if ($self->hasFlag("nick")){
		$user = $self->hasFlagValue("nick");

	}elsif ($self->{options}){
		$user = $options;

	}else{
		#$user = $self->accountNick();
		$user = $self->{nick};
	}

	$output = $self->getLastPlayed($user);
	return $output;
}


sub getLastFMUser{
	my $self = shift;
	my $user = shift;

	my $c = $self->getCollection(__PACKAGE__, $user);

	my @records = $c->matchRecords({val1=>'user_lastfm'});

	if (@records){
		return $records[0]->{'val2'};
	}else{
		return $user;
	}
}

sub searchSong{
	my $self = shift;
	my $song = shift;
	my $artist = shift;

	if (!$artist){
		$artist = " ";
	}
	
	my $lastfm = Net::LastFM->new(api_key => $self->{APIKey}, api_secret => $self->{APISecret},);
	my $data;

	print "Searching for $song by $artist\n";
	eval {
		$data = $lastfm->request_signed(
			method => 'track.search',
			track => $song,
			artist => $artist,
			limit=>1
		);
	};

	if ($@){
		return "Whoops, an error occurred. Or maybe that track doesn't exist.  Record it!  It's your big chance!";
	}

	my $lp_song = $data->{results}->{trackmatches}->{track}->{name};
	my $lp_artist = $data->{results}->{trackmatches}->{track}->{artist};
	my $url = $data->{results}->{trackmatches}->{track}->{url};

	if ($url){
		$url = UNDERLINE . $self->getShortURL($url) . UNDERLINE;
	}
	
	if ($lp_song){
		return ("$lp_song by $lp_artist $url");
	}else{
		return ("Last.fm didn't return any data. I've gotta work on this search thingy. Try being more specific. <song> by <artist>");
	}
}

sub compareUsers{
	my $self = shift;
	my $user1= shift;
	my $user1_lastfm= shift;
	my $user2= shift;
	my $user2_lastfm= shift;
	
	my $lastfm = Net::LastFM->new(api_key => $self->{APIKey}, api_secret => $self->{APISecret},);
	my $data;

	eval {
		$data = $lastfm->request_signed(
			method => 'tasteometer.compare',
			type1 => 'user',
			type2 => 'user',
			value1 => $user1_lastfm,
			value2 => $user2_lastfm
		);
	};

	if ($@){
		return "ERRORED!  Maybe one of those users doesn't exist? ";
	}

	my $numentries;
	my $retval = "";

	if (ref($data->{comparison}->{result}->{artists}->{artist}) eq 'ARRAY'){
		$numentries = @{$data->{comparison}->{result}->{artists}->{artist}};

		for (my $i=0; ($i<10) && ($i<$numentries); $i++){
			my $lp_artist= $data->{comparison}->{result}->{artists}->{artist}->[$i]->{name};

			my $str = "$lp_artist ".$self->BULLET." ";

			if ( (length($retval) + length($str) ) > 320){
				last;
			}else{
				$retval = $retval . $str;
			}
		}

	}elsif(ref($data->{comparison}->{result}->{artists}->{artist}) eq 'HASH'){
		$numentries = 1;
		my $lp_artist= $data->{comparison}->{result}->{artists}->{artist}->{name};
		$retval = "$lp_artist ";

	}else{
		$numentries = 0;
	}

	my $lp_score = sprintf("%.2f", $data->{comparison}->{result}->{score} * 100 );
	my $similarity = "$user1 and $user2 have a $lp_score% musical similarity.";

	if ($retval){
		$retval = "$similarity  Artists in common:  $retval";

	}else{
		$retval .= "$similarity  No artists in common. *sadface*";
	}

	return $retval;
}


sub getTops{
	my $self = shift;
	my $opts = shift;
	my ($data, $method, $key1, $key2);
	my $user = $opts->{user};
	my $type = $opts->{type};
	my $period = $opts->{period};

	my $user_lastfm = $self->getLastFMUser($user);

	my $lastfm = Net::LastFM->new(api_key => $self->{APIKey}, api_secret => $self->{APISecret},);

	if ($type eq "top_albums"){
		$method = 'user.getTopAlbums';
		$key1 = 'topalbums';
		$key2 = 'album';
	}

	if ($type eq "top_tracks"){
		$method = 'user.getTopTracks';
		$key1 = 'toptracks';
		$key2 = 'track';
	}

	if ($type eq "top_artists"){
		$method = 'user.getTopArtists';
		$key1 = 'topartists';
		$key2 = 'artist';
	}

	eval {
		$data = $lastfm->request_signed(
			method => $method,
			user   => $user_lastfm,
			period => $period,
			limit => 10,
		);
	};


	if ($@){
		my $msg = "Whoops, an error occurred. Maybe that user doesn't exist? ";
		if ($user eq $user_lastfm){
			$msg.="(Using $user_lastfm)";
		}else{
			$msg.="(Using the value defined in ".$user."'s user settings.)";
		}
		return $msg;
	}

	my $numentries = @{$data->{$key1}->{$key2}};
	my $retval = "";

	for (my $i=0; ($i<10) && ($i<$numentries); $i++){
		my $lp_album = $data->{$key1}->{$key2}->[$i]->{name};
		my $lp_artist= $data->{$key1}->{$key2}->[$i]->{artist}->{name};
		my $lp_plays = $data->{$key1}->{$key2}->[$i]->{playcount};

		my $str = "$lp_album by $lp_artist ($lp_plays plays) ".$self->BULLET." ";
		$retval = $retval . $str;
	}


	if (!$retval){
		return "No play history found for user $user_lastfm.";
	}

	if ($period eq "7day"){
		return  ("Last 7 days, top ".$key2."s for $user: " . $retval);

	}elsif ($period eq "1month"){
		return  ("Last 30 days, top ".$key2."s for $user: " . $retval);

	}elsif ($period eq "3month"){
		return  ("Last 3 months, top ".$key2."s for $user: " . $retval);

	}elsif ($period eq "6month"){
		return  ("Last 6 months, top ".$key2."s for $user: " . $retval);

	}elsif ($period eq "12month"){
		return  ("Last 12 months, top ".$key2."s for $user: " . $retval);

	}else{
		return ("Overall top ".$key2."s for $user: " . $retval );
	}
}


sub getLastPlayed{
	my $self = shift;
	my $user = shift;
	
	if ($user eq $self->{nick}){	
		$user = $self->accountNick();
	}

	my $user_lastfm = $self->getLastFMUser($user);

	my $lastfm = Net::LastFM->new(api_key => $self->{APIKey}, api_secret => $self->{APISecret},);
	my $data;

	eval{
		$data = $lastfm->request_signed(
			method => 'user.getRecentTracks',
			user   => $user_lastfm,
		);
	};

	if ($@){
		my $msg = "Whoops, an error occurred. Maybe that user doesn't exist? ";

		# Privacy
		if ($user eq $user_lastfm){
			$msg.="(Using $user_lastfm)";
		}else{
			$msg.="(Using the username defined in ".$user."'s user settings. ($user_lastfm))";
		}

		return $msg;
	}

	my $lp_album = $data->{recenttracks}->{track}->[0]->{album}->{'#text'};
	my $lp_artist= $data->{recenttracks}->{track}->[0]->{artist}->{'#text'};
	my $lp_name = $data->{recenttracks}->{track}->[0]->{name};
	my $lp_url = $data->{recenttracks}->{track}->[0]->{url};
	my $lp_date = $data->{recenttracks}->{track}->[0]->{date}->{uts};
	my $url = $data->{recenttracks}->{track}->[0]->{url};


	if (!$lp_name && !$lp_artist){
		return "No tracks listed.";
	}

	if ($url){
		$url = UNDERLINE . $self->getShortURL($url) . UNDERLINE;
	}

	if ($lp_date){
		my $diff = int((time() - $lp_date)/60);
		my $diff_text; 

		if ($diff <= 60){
			$diff_text = "$diff minutes ago.";

		}elsif ($diff <= (60 * 48)){
			$diff_text = int ($diff / 60) . " hours ago.";

		}else{
			$diff_text = int ($diff / 60 / 24) . " days ago.";
		}

   	my $dt = DateTime->from_epoch( epoch => $lp_date);

		$dt->set_time_zone( 'America/Chicago');
		my $lp_date_p = $dt->day_abbr() ." " . $dt->month_abbr() . " " . $dt->day() . " at " . $dt->hms . " " . $dt->time_zone_short_name();
		return "$user last played $lp_name by $lp_artist from the album $lp_album on $lp_date_p. ($diff_text) $url";

	}elsif($data->{recenttracks}->{track}->[0]->{'@attr'}->{nowplaying} eq 'true'){
		return "$user is playing: $lp_name by $lp_artist from the album $lp_album. $url";
	
	}else{
		return "$user last played $lp_name by $lp_artist from the album $lp_album. $url";
	}
}


sub getRecent{
	my $self = shift;
	my $user = shift;
	my $retval = "";
   
	my $user_lastfm = $self->getLastFMUser($user);

	my $lastfm = Net::LastFM->new(api_key => $self->{APIKey}, api_secret => $self->{APISecret},);
	my $data;

	eval {
		$data = $lastfm->request_signed(
			method => 'user.getRecentTracks',
			user   => $user_lastfm,
		);
	};

	if ($@){
		my $msg = "Whoops, an error occurred. Maybe that user doesn't exist? ";

		# Privacy
		if ($user eq $user_lastfm){
			$msg.="(Using $user_lastfm)";
		}else{
			$msg.="(Using the username defined in ".$user ."'s user settings.)";
		}

		return $msg;
	}

	my $numentries = @{$data->{recenttracks}->{track}};

	for (my $i=0; ($i<10) && ($i<$numentries); $i++){
		my $lp_artist= $data->{recenttracks}->{track}->[$i]->{artist}->{'#text'};
		my $lp_name = $data->{recenttracks}->{track}->[$i]->{name};

		my $str = "$lp_name ($lp_artist) ".$self->BULLET." ";

		if ( (length($retval) + length($str) ) > 320){
			last;

		}else{
			$retval = $retval . $str;
		}
	}

	return "$user, last played tracks: $retval";
		
}


sub listeners{
   my $self = shift;

   ##Command Listeners - put em here.  eg ['one', 'two']
   my @commands = ['lastfm'];
   my $default_permissions =[ ];

   return {commands=>@commands, permissions=>$default_permissions};
}

##
## The help system will pull from here using PluginBaseClass->help(key) 
## You may also want to call that within your getOutput code.  ala return $self->help("color reverse")
## $self->help() will split on spaces & add the [] for you
##

sub addHelp{
   my $self = shift;
   $self->addHelpItem("[plugin_description]", "Interface with LastFM.");

	$self->addHelpItem("[lastfm]", "lastfm - Show your or another users's last played track.  Other options to pass: [-nick=<nick>] [-top_tracks, -top_artists, -top_albums, -recent, -search, -compare, -link, -period=week|month|3month|6month|12month]");

   $self->addHelpItem("[lastfm][-top_tracks]", "lastfm -top_tracks - Show your or another user's top tracks.  (Also use flags -user=<username>,  -period = week month 3month 6month 12month)");

   $self->addHelpItem("[lastfm][-top_artists]", "lastfm -top_artists - Show your or another user's top played artists.  (Also use flags -user=<username>,  -period = week month 3month 6month 12month)");

   $self->addHelpItem("[lastfm][-top_albums]", "lastfm -top_albums - Show your or another user's top played albums (Also use flags -user=<username>,  -period = week month 3month 6month 12month)");


   $self->addHelpItem("[lastfm][-recent]", "lastfm -recent [<user>]  Show recently played tracks");

   $self->addHelpItem("[lastfm][-search]", "Usage: lastfm -search <song> by <artist> - search for a song by an artist.");
   $self->addHelpItem("[lastfm][-compare]", "Usage: lastfm -compare <user1> and <user2> - Compare the musical tastes of two users.");

   $self->addHelpItem("[lastfm][-link]", "Usage: lastfm -link=<your last fm username> - Link your ".$self->{BotName}." account to your lastfm account.  This way you won't have to type your lastfm username all the time, and others will be able to use your IRC name as well. use -delete to undo this.");
   $self->addHelpItem("[lastfm][-unlink]", "lastfm -unlink.  Unlink your lastfm account.");


	$self->addHelpItem("__lastfm", " show you last played track. | ,lastfm <username> - another user's | ,lastfm top_tracks - your top | ,lastfm top_tracks <username> - another user's | Also: top_artists, top_albums (add suffixes _week _month _3month _6month _12month) | ,lastfm recent | ,lastfm search <song> by <artist> | ,lastfm compare <user1> and <user2> | ,lastfm associate <username> - link your lastfm name");
}

1;
__END__
