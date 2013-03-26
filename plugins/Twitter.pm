package plugins::Twitter;
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
#	You need to add this to the bot config file:
#  [Plugin:Twitter]
#  consumer_key =  ""
#  consumer_secret  = ""
#-----------------------------------------------------------------------------
use base qw (modules::PluginBaseClass);
use modules::PluginBaseClass;

use strict;
use warnings;

use Net::Twitter::Lite::WithAPIv1_1;
use Scalar::Util 'blessed';

#use Net::Twitter::Lite;
use Data::Dumper;
use JSON;
use HTML::Entities;
use Digest::MD5  qw(md5_hex);
use Encode qw(encode_utf8);

my $consumer_key;
my $consumer_secret;
my $AccessToken;
my $AccessTokenSecret;

my $seen_c;

sub plugin_init{
   my $self = shift;

	$self->{consumer_key} =  $self->getInitOption("consumer_key");
	$self->{consumer_secret}  = $self->getInitOption("consumer_secret");
	$self->{AccessToken} =  $self->globalCookie("AccessToken");
	$self->{AccessTokenSecret} =  $self->globalCookie("AccessTokenSecret");
   return $self;       
}

sub getOutput {
	my $self = shift;
	my $cmd = $self->{command};
	my $options = $self->{options};
	my $output = "";

	$self->suppressNick("true");
	my ($status, $nt) = $self->ConnectToTwitter();
	return $nt if (!$status);

	$self->{seen_c} = $self->getCollection(__PACKAGE__, ':seen');

		
	##
	##	trends
	##

	if ($self->hasFlag("trends")){
		my $r;

		#23424977 is the woeid (yahoo) for USA
		eval{
			$r  = $nt->trends(23424977);
		};

		if ($@){
			print $@;
			return "error";
		}

		my $location = $r->[0]->{locations}->[0]->{name};

		$output = "Current Top Twitter trends for $location: ";

		foreach my $trend (@{$r->[0]->{'trends'}}){
			$self->addToList($trend->{name}, $self->BULLET);
		}
		$output .= $self->getList();
		return $output;
	}


	return $self->help($cmd) if (!$options);

	##
	##		Default - do search
	##

	my $r = $nt->search( $options, { lang => 'en'});

	if (@{$r->{statuses}}){

		my ($tweet, $user, $id);
		my $found = 0;
		my $i=0;

		do {
			$tweet = @{$r->{statuses}}[$i]->{text};
			$user = @{$r->{statuses}}[$i]->{user}->{screen_name};
			$id = @{$r->{statuses}}[$i]->{id};

			$tweet = decode_entities($tweet);
			$tweet =~s/\n/ /gis;

			$found = 1;

			if ($tweet=~/\@/){	$found = 0; };
			if ($tweet=~/http/){	$found = 0; };
			if ($self->tweetRecentlySeen($tweet)){	$found = 0; };
				
		}while( (++$i < @{$r->{statuses}}) && (!$found) );
	

		if ($found){
			my $link = "http://twitter.com/x/status/" . $id;
			$link = $self->getShortURL($link);
			$output = '@' . $user . " says: $tweet ".GREEN.UNDERLINE."<$link>".NORMAL;
			$self->tweetMarkSeen($tweet);

		}else{
			$output = "no results";
		}

	}else{
		$output = "no results";
	}

	return $output ;
}


sub tweetMarkSeen{
	my $self = shift;
	my $tweet = shift;

	my $md5_hash = md5_hex(encode_utf8($tweet));
	$self->{seen_c}->sort({field=>'row_id', type=>'numeric', order=>'desc'});
	my @records = $self->{seen_c}->getAllRecords();

	# delete old entries in seen cache
	if (@records > 20){
		for (my $i=20; $i<@records; $i++){
			$self->{seen_c}->delete($records[$i]->{row_id});
		}
	}
	$self->{seen_c}->add($md5_hash);
}


sub tweetRecentlySeen{
	my $self = shift;
	my $tweet = shift;
	
	my $md5_hash = md5_hex(encode_utf8($tweet));

	my @records = $self->{seen_c}->matchRecords({val1=>$md5_hash});	
	return 1 if (@records);
	return 0;
}


sub ConnectToTwitter{
	my $self = shift;

   my $nt = Net::Twitter::Lite::WithAPIv1_1->new( 
      consumer_key    => $self->{consumer_key}, 
      consumer_secret => $self->{consumer_secret},
		access_token => $self->{AccessToken},
		access_token_secret => $self->{AccessTokenSecret}
  );                                                                                            
    

	unless ( $nt->authorized ) {

		if ($self->hasFlag("oauth")){
			my $msg = "Authorize this app at ". $nt->get_authorization_url. " and enter the PIN using the -pin=<pin> flag."; 
			$self->globalCookie("request_token", $nt->{request_token});
			$self->globalCookie("request_token_secret", $nt->{request_token_secret});
			return (0, $msg);
		}

		if (my $pin = $self->hasFlagValue("pin")){

			$nt->{request_token} = $self->globalCookie("request_token");
			$nt->{request_token_secret} = $self->globalCookie("request_token_secret");
			
			my($access_token, $access_token_secret, $user_id, $screen_name) =
			$nt->request_access_token(verifier => $pin);

			$self->globalCookie("AccessToken", $access_token);
			$self->globalCookie("AccessTokenSecret", $access_token_secret);


			my $msg = "This authorization tokens have been saved.";
			return (0, $msg);
		}

		my $msg = "The bot owner (".$self->{BotOwnerNick}.") has set the Twitter API key, ";
		$msg .="but has not completed OAUTH authentication. An admin needs to complete this ";
		$msg .="step using the \"twitter -oauth\" command.";
		return (0, $msg);
  }                                                                                             
  
   return (1, $nt);                                                                                  
}          

sub listeners{
   my $self = shift;

   my @commands = [qw(twitter)];

   my @irc_events = [qw () ];
   my @preg_matches = [qw () ];
   my $default_permissions =[ 
		{command=>"twitter", flag=>"oauth", require_group => UA_ADMIN },
		{command=>"twitter", flag=>"pin", require_group => UA_ADMIN },
	];

   return {commands=>@commands, permissions=>$default_permissions, irc_events=>@irc_events, preg_matches=>@preg_matches};

}

sub addHelp{
   my $self = shift;
   $self->addHelpItem("[plugin_description]", "Get tweets from Twitter.");
   $self->addHelpItem("[twitter]", "Twitter.  Usage: twitter <search term> to search, or twitter -trends to see top trends.");
}

1;
__END__
