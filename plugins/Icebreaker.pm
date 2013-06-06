package plugins::Icebreaker;
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


sub getOutput {
	my $self = shift;
	my $cmd = $self->{command};			# the command
	my $options = $self->{options};		# everything else on the line
	my $nick = $self->{nick};				
	my @output;

	$self->suppressNick("true");	

  	## Get the json
  	my $page = $self->getPage("http://www.reddit.com/r/AskReddit/.json?limit=200");

  	my $json_o  = JSON->new->allow_nonref;
  	$json_o = $json_o->pretty(1);
  	my $j = $json_o->decode($page);

  	## process each link
	my @questions;
  	for (my $i=0; $i<@{$j->{data}->{children}}; $i++){
  		my $story = $j->{data}->{children}[$i];
   	my $title = $story->{data}->{title};
  		#my $author =  $story->{data}->{author};
  		#my $id =  $story->{data}->{id};
		push @questions, $title;
   }
 	my $message = BOLD."Question for Everybody: ".NORMAL . $questions[int(rand(@questions))];
	return $message;
}


sub listeners{
	my $self = shift;
	
	my @commands = [qw(icebreaker)];

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
	$self->addHelpItem("[plugin_description]", "Asks a question for everyone in the room to answer. Pulls questions from reddit.com/r/AskReddit.");
   $self->addHelpItem("[icebreaker]", "Pull a random question from AskReddit & announce it to the room.");
}
1;
__END__
