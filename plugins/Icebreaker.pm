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

my $cache;

sub getOutput {
	my $self = shift;
	my $cmd = $self->{command};			# the command
	my $options = $self->{options};		# everything else on the line
	my $nick = $self->{nick};				
	my @output;

	$self->suppressNick("true");	

	if ($self->hasFlag("clearcache")){
		$self->trimCache(0);
		return "Icebreaker cache cleared";
	}

  	## Get the json
  	my $page = $self->getPage("http://www.reddit.com/r/AskReddit/.json?limit=200");
  	my $json_o  = JSON->new->allow_nonref;
  	$json_o = $json_o->pretty(1);
	
	my $j;
	eval{
	  	$j = $json_o->decode($page);
	};
	
	if ($@){
		return "Error contacting reddit. Try again in a few minutes.";
	}

  	## process each link
	my @questions;
  	for (my $i=0; $i<@{$j->{data}->{children}}; $i++){
  		my $story = $j->{data}->{children}[$i];
   	my $title = $story->{data}->{title};
  		#my $author =  $story->{data}->{author};
  		my $id =  $story->{data}->{id};
		if (!$self->checkCache($id)){
			push @questions, {title=>$title, id=>$id};
		}
   }
	my $qnum = int(rand(@questions));
 	my $message = BOLD."Question for Everybody: ".NORMAL . $questions[$qnum]->{title};
	$self->saveCache($questions[$qnum]->{id});
	$self->trimCache(200);

	if ($message){
		return $message;
	}else{
		return "Whoops. Couldn't find a new icebreaker. Try again in a few minutes.";
	}
}

sub loadCache{
	my $self = shift;

	if (!defined($self->{cache})){
		$self->{cache} = $self->getCollection(__PACKAGE__, 'cache');
	}
	
	$self->{cache}->sort({field=>"sys_creation_timestamp", type=>'numeric', order=>'desc'});
	return $self->{cache};
}


sub saveCache{
	my $self = shift;	
	my $val = shift;

	my $c = $self->loadCache();
	my @records = $c->getAllRecords();

	foreach my $rec (@records){
		if ($rec->{val1} eq $val){
			#already in cache
			return;
		}
	}

	print "saved $val\n";
	$c->add($val);
}

sub checkCache{
	my $self = shift;
	my $val = shift;

	my $c = $self->loadCache();
	my @records = $c->getAllRecords();

	foreach my $rec (@records){
		if ($rec->{val1} eq $val){
			print "found $val\n";
			return 1;
		}
	}
	
	return 0;
}


sub trimCache{
	my $self = shift;
	my $num = shift;

	my $c = $self->loadCache();
	my @records = $c->getAllRecords();

	if (@records > $num){
		for (my $i=$num; $i<@records; $i++){
			$c->delete($records[$i]->{row_id});
		}
	}
}


sub listeners{
	my $self = shift;
	
	my @commands = [qw(icebreaker)];

	my @irc_events = [qw () ];

	my @preg_matches = [qw () ];

	my $default_permissions =[ 
		{command=>"icebreaker", flag=>"clearcache", require_group => UA_TRUSTED},
	];

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
   $self->addHelpItem("[icebreaker]", "Pull a random question from AskReddit & announce it to the room.  Use -clearcache to clear the icebreaker cache.");
}
1;
__END__
