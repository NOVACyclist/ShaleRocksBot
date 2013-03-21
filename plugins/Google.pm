package plugins::Google;
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

use strict;			
use warnings;
use base qw (modules::PluginBaseClass);
use modules::PluginBaseClass;
use JSON;
use Data::Dumper;
use URI::Escape;
use HTML::Entities;

sub getOutput {
	my $self = shift;

	my $cmd = $self->{command};			# the command
	my $options = $self->{options};		# everything else on the line
	my $options_unparsed = $self->{options_unparsed};  #with the flags intact
	my $channel	= $self->{channel};					
	my $mask = $self->{mask};				# the users hostmask, not including the username
	my $nick = $self->{nick};				
	my $BotOwnerNick	= $self->{BotOwnerNick}; 
	my $output = "";

	return ($self->help($cmd)) if ($options eq '');

	my $url = "http://ajax.googleapis.com/ajax/services/search/web?v=1.0&q=" . uri_escape($options);
   
	my $page = $self->getPage($url);

	my $json_o  = JSON->new->allow_nonref;
	$json_o = $json_o->pretty(1);
	my $j = $json_o->decode($page);

	if (!$j->{responseData}){
		## we may have been blocked.
		print "Problem with the Google plugin, chief.\n";
		print Dumper ($page);
		return $j->{responseDetails};
	}

	if (!@{$j->{responseData}->{results}}){
		return "You've stumped Google. Way to go.";
	}

	foreach my $result (@{$j->{responseData}->{results}}){
		my $url = $self->getShortURL($result->{url});
		my $title = $result->{titleNoFormatting};
		my $content = $result->{content};

		decode_entities($title);	
		decode_entities($content);	
		$content=~s/<.+?>//gis;
	
		if ($cmd eq 'google'){
			if ($self->hasFlag("full")){
				$self->addToList("$title $content".UNDERLINE.GREEN."$url".NORMAL, $self->BULLET);
			}else{
				$self->addToList("$title ".UNDERLINE.GREEN."$url".NORMAL, $self->BULLET);
			}

		}elsif ($cmd eq 'lucky'){
			$self->addToList("$title $content ".UNDERLINE.GREEN."$url".NORMAL, $self->BULLET);
			last;
		}
	}
	
	return $self->getList();	
}


sub listeners{
	my $self = shift;
	
	my @commands = [qw(google lucky)];

	my @irc_events = [qw () ];

	my @preg_matches = [qw () ];

	my $default_permissions =[ ];

	return {commands=>@commands, permissions=>$default_permissions, 
		irc_events=>@irc_events, preg_matches=>@preg_matches};

}

##
## addHelp()
##	The help system will pull from here using PluginBaseClass->help(key).
##
sub addHelp{
	my $self = shift;
	$self->addHelpItem("[plugin_description]", "Search Google.");
   $self->addHelpItem("[google]", "Google something.  Usage: google <whatever>.  Use -full flag to include a description");
   $self->addHelpItem("[lucky]", "Return just the first google result with description. Usage: lucky <whatever>");
}
1;
__END__
