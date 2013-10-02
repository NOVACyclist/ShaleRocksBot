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
# this was kind of piecemealed
use strict;			
use warnings;
use base qw (modules::PluginBaseClass);
use modules::PluginBaseClass;
use JSON;
use Data::Dumper;

my $cache;
my $subreddit;
my $links_to_load;
my $reload_at;

sub getOutput {
	my $self = shift;
	my $cmd = $self->{command};			# the command
	my $options = $self->{options};		# everything else on the line
	my $nick = $self->{nick};

	$self->suppressNick("true");	
	my $message;

	if ($cmd eq 'icebreaker'){
		$self->{subreddit} = 'AskReddit';
		$self->{links_to_load} = 100;
		$self->{reload_at} = 50;
		$message = BOLD."Question for Everybody: ".NORMAL;
	}

	if ($cmd eq 'showerthought'){
		$self->{subreddit} = 'showerthoughts';
		$self->{links_to_load} = 200;
		$self->{reload_at} = 1;
		$message = BOLD."Shower thought: ".NORMAL;
	}

	if ($cmd eq 'firstworldproblem'){
		$self->{subreddit} = 'firstworldproblems';
		$self->{links_to_load} = 200;
		$self->{reload_at} = 1;
		$message = BOLD."First World Problem: ".NORMAL;
	}

	if ($cmd eq 'secondworldproblem'){
		$self->{subreddit} = 'secondworldproblems';
		$self->{links_to_load} = 200;
		$self->{reload_at} = 1;
		$message = BOLD."Second World Problem: ".NORMAL;
	}

	if ($cmd eq 'thirdworldproblem'){
		$self->{subreddit} = 'thirdworldproblems';
		$self->{links_to_load} = 200;
		$self->{reload_at} = 1;
		$message = BOLD."Third World Problem: ".NORMAL;
	}

	if ($cmd eq 'fourthworldproblem'){
		$self->{subreddit} = 'fourthworldproblems';
		$self->{links_to_load} = 200;
		$self->{reload_at} = 1;
		$message = BOLD."Fourth World Problem: ".NORMAL;
	}

	if ($cmd eq 'fifthworldproblem'){
		$self->{subreddit} = 'fifthworldproblems';
		$self->{links_to_load} = 200;
		$self->{reload_at} = 1;
		$message = BOLD."Fifth World Problem: ".NORMAL;
	}

	if ($cmd eq 'dae'){
		$self->{subreddit} = 'dae';
		$self->{links_to_load} = 200;
		$self->{reload_at} = 1;
		$message = BOLD."Does anyone else...: ".NORMAL;
	}

	if ($cmd eq 'ancientworldproblem'){
		$self->{subreddit} = 'ancientworldproblems';
		$self->{links_to_load} = 200;
		$self->{reload_at} = 1;
		$message = BOLD."Ancient World Problem: ".NORMAL;
	}

	if ($cmd eq 'crazyidea'){
		$self->{subreddit} = 'crazyideas';
		$self->{links_to_load} = 200;
		$self->{reload_at} = 1;
		$message = BOLD."Crazy Idea: ".NORMAL;
	}



	if ($self->hasFlag("clearcache")){
		$self->trimCache(0);
		my $c = $self->getCollection(__PACKAGE__, 'questions');
		$c->deleteByVal({val3=>$self->{subreddit}});
		return "$cmd cache cleared";
	}

	my $question = $self->getQuestion();

	if ($question eq '0' ){
		return "Reddit seems slow right now. Try again in a bit.";
	}

 	#my $message = BOLD."Question for Everybody: ".NORMAL . $question;
	$self->trimCache(200);

	return $message . $question;
}


sub getQuestion(){
	my $self = shift;
	my $c = $self->getCollection(__PACKAGE__, 'questions');
	my @records = $c->matchRecords({val3=>$self->{subreddit}});

	if (@records < $self->{reload_at}){

  		## Get the json
 	 	my $page = $self->getPage("http://www.reddit.com/r/".$self->{subreddit}."/.json?limit=".$self->{links_to_load});
		if ($page eq ''){
			return 0;
		}		

 	 	my $json_o  = JSON->new->allow_nonref;
	  	$json_o = $json_o->pretty(1);
	
		my $j;
		eval{
		  	$j = $json_o->decode($page);
		};
	
		if ($@){
			return 0;
		}

 	 	## process each link
		my @questions;
	  	for (my $i=0; $i<@{$j->{data}->{children}}; $i++){
	  		my $story = $j->{data}->{children}[$i];
  		 	my $title = $story->{data}->{title};
  			#my $author =  $story->{data}->{author};
	  		my $id =  $story->{data}->{id};
			if (!$self->checkCache($id)){
				#print "added $title\n";
				$c->add($id, $title, $self->{subreddit});
			}
  	 	}
		
		@records = $c->matchRecords({val3=>$self->{subreddit}});
	}
	
	if (@records == 0){
		return 0;
	}

	my $question = @records[int(rand(@records))];
	$c->delete($question->{row_id});
	$self->saveCache($question->{val1});
	return $question->{val2} ." ". GREEN.UNDERLINE."http://redd.it/$question->{val1}".NORMAL;
	
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
	#my @records = $c->getAllRecords();
	my @records = $c->matchRecords({val2=>$self->{subreddit}});

	foreach my $rec (@records){
		if ($rec->{val1} eq $val){
			#already in cache
			return;
		}
	}

	$c->add($val, $self->{subreddit});
}

sub checkCache{
	my $self = shift;
	my $val = shift;

	my $c = $self->loadCache();
	my @records = $c->matchRecords({val2=>$self->{subreddit}});
	#my @records = $c->getAllRecords();

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
	my @records = $c->matchRecords({val2=>$self->{subreddit}});

	if (@records > $num){
		for (my $i=$num; $i<@records; $i++){
			$c->delete($records[$i]->{row_id});
		}
	}
}


sub listeners{
	my $self = shift;
	
	my @commands = [qw(icebreaker showerthought firstworldproblem secondworldproblem thirdworldproblem fourthworldproblem fifthworldproblem dae ancientworldproblem crazyidea)];

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
	$self->addHelpItem("[plugin_description]", "Pulls headlines from reddit.com and announces them to the room.  Use the -clearcache flag to clear the cached questions and history for that particular flavor.");
   $self->addHelpItem("[icebreaker]", "Pull a random question from AskReddit & announce it to the room.  Use -clearcache to clear the icebreaker cache.");
   $self->addHelpItem("[showerthought]", "Grab a random item from /r/showerthoughts on reddit.");
   $self->addHelpItem("[firstworldproblem]", "Grab a random item from /r/firstworldproblems on reddit.");
   $self->addHelpItem("[secondworldproblem]", "Grab a random item from /r/secondworldproblems on reddit.");
   $self->addHelpItem("[thirdworldproblem]", "Grab a random item from /r/thirdworldproblems on reddit.");
   $self->addHelpItem("[fourthworldproblem]", "Grab a random item from /r/fourthworldproblems on reddit.");
   $self->addHelpItem("[fifthworldproblem]", "Grab a random item from /r/fifthworldproblems on reddit.");
   $self->addHelpItem("[dae]", "Grab a random item from /r/dae on reddit.");
   $self->addHelpItem("[ancientworldproblem]", "Grab a random item from /r/ancientworldproblems on reddit.");
   $self->addHelpItem("[crazyidea]", "Grab a random item from /r/crazyideas on reddit.");
}
1;
__END__
