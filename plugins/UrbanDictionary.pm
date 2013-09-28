package plugins::UrbanDictionary;
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
use Data::Dumper;
use URI::Escape;

sub onBotStart{
	my $self = shift;
	#$self->globalCookie('last_word', ':none:');
	#$self->globalCookie('next_q_time', '0');
}

sub plugin_init{
	my $self = shift;
	$self->suppressNick("true");	# show Nick: in the response?
	$self->useChannelCookies();
	return $self;						#dont remove this line or RocksBot will cry
}


sub getOutput {
	my $self = shift;
	my $cmd = $self->{command};			# the command
	my $options = $self->{options};		# everything else on the line
	my $channel	= $self->{channel};					
	my $nick = $self->{nick};				
	my $output = "";
	my $url;
	my $page;
	my $word;

	if ($cmd eq 'udquiz' && $self->hasFlag('hint')){
		if ($self->globalCookie('last_word') eq ':none:' || $self->globalCookie('last_word') eq ''){	
			return "There is no current quiz question. Get one using the udquiz command";
		}
		my $ret = "";

		my $word = $self->globalCookie("last_word");
		my $hint = $self->globalCookie("last_word_hint");
		my $num_stars = () = $hint=~/\*/g;
		my $reveal = int(rand($num_stars)) + 1;
		my $star_count = 0;

		for(my $i=0; $i<length($hint); $i++){
			if (substr($hint, $i, 1) eq '*'){
				$star_count++;
				if ($star_count == $reveal){
					$ret.=substr($word, $i, 1);
				}else{
					$ret.=substr($hint, $i, 1);
				}

			}else{
				$ret.=substr($hint, $i, 1);
			}
		}

		$self->globalCookie("last_word_hint", $ret);
		return BOLD."Hint: ".NORMAL.$ret;
	}


	if ($cmd eq 'udquiz' && $self->hasFlag('scores')){
		my @cookies = $self->allCookies();
		my @scores;
		foreach my $cookie (@cookies){
			next if ($cookie->{owner} eq ':package');
			push @scores, $cookie;
		}

		@scores = sort {$b->{value} <=> $a->{value}} @scores;

		foreach my $cookie (@scores){
			next if ($cookie->{owner} eq ':package');
			$self->addToList("$cookie->{owner}: $cookie->{value}", $self->BULLET );
		}

		my $list = $self->getList() || 'None yet.';
		return "Urban Dictionary Quiz ".BOLD."Scores".NORMAL." for $self->{channel}: ". $list;

	}


	if ($cmd eq 'udquiz' && $self->hasFlag('clearscores')){
		$self->deletePackageCookies();
		return "Scores cleared.";
	}


	if ($cmd eq 'udquiz' && ($self->hasFlag('answer') || $options)){

		if ($self->globalCookie('last_word') eq ':none:' || $self->globalCookie('last_word') eq ''){
			if ($self->globalCookie('last_q_answer_time') + 5  < time()){
				return "There is no current quiz question. Get one using the udquiz command";
			}else{
				#return silently;
				return "";
			}
		}

		my $guess = $options;
		$guess = $self->hasFlagValue('answer') if ($self->hasFlagValue('answer'));

		if (lc($guess) eq lc($self->globalCookie('last_word'))){
			my $points = $self->cookie('score') || 0;
			$points++;
			$self->cookie('score', $points);
			my @interjections = ("Bingo", "Nice", "Yep", "Yes", "Sweet", "Good show", "Fair play to you", "Impressive", "Right on", "Awesome", "Spot on", "A++", "Way to go", "You know it", "Whoa", "OMG");
			my $interjection = $interjections[rand(@interjections)];
			my $ret = "$interjection!  ".BOLD."$self->{nick}".NORMAL." is correct, the last word was " . $self->globalCookie('last_word') . ".  $self->{nick} now has $points points. ".BLUE."(udquiz -scores to see all scores)";
			$self->globalCookie('last_q_answer_time', time());
			$self->globalCookie('last_word', ':none:');
			return $ret;

		}else{
			my @interjections = ("Nope", "No", "Wrong", "No dice", "You wish", "Not quite", "I don't think so", "Negative");
			my $interjection = $interjections[rand(@interjections)];
			
			return "$interjection, $self->{nick}, keep guessing.";
		}
	}


	if ($self->hasFlag("random") || $cmd eq 'udquiz'){

		if ($cmd eq 'udquiz' && $self->globalCookie('next_q_time') > time()){
			## silently ignore
			return "";
		}

		if ($cmd eq 'udquiz' && $self->hasFlag("show")){
			return $self->globalCookie("current_q");
		}

		if ($cmd eq 'udquiz' && ($self->globalCookie('last_word') ne ':none:') && $self->globalCookie('last_word') ne ''){
			if (!$self->hasFlag('new')){
				return "There is already a question in play.  $cmd -new get a new question.  $cmd -show to show the current question again."
			}
		}

		if ($cmd eq 'udquiz'){
			$self->globalCookie('next_q_time', time() + 4);
			return $self->help($cmd) if ($options);
			#return $self->help($cmd) if ($self->numFlags());
		}

		$url = "http://www.urbandictionary.com/random.php";
		$page = $self->getPage($url);
		$page=~/<meta content=["|'](.+?)["|'] property='og:title'>/;
		$word = $1;

	}else{
		return $self->help($cmd) if (!$options);
		$url = "http://www.urbandictionary.com/define.php?term=" . uri_escape($options);
		$page = $self->getPage($url);
		$word = $options;
	}

	$page=~ tr/\015//d;

	my @defs;

	while ($page=~m#<div class="definition">(.+?)\n#gis){
		my $def = $1;
		my $example;

		if ($def=~s#<div class="example">(.+?)</div>##gis){
			$example = $1;		
			$example=~s/<.+?>//gis;
		}
	
		$def=~s/<.+?>//gis;
		push @defs, {def=>$def, example=>$example};
	}

	my $def_num;
	if (my $num = $self->hasFlagValue("n")){
		if (defined($defs[$num-1])){
			$def_num = $num-1;
		}else{
			$def_num = 0;
		}
	}else{
		$def_num = 0;
	}


	if ($cmd eq 'udquiz'){
		$self->globalCookie("last_word", $word);

		my $def =  $defs[int(rand(@defs))]->{def};
		my $rep = "";
		for (my $i=0;$i<length($word); $i++){
			if (substr($word, $i, 1) eq ' '){
				$rep.=' ';
			}elsif (substr($word, $i, 1) eq "\'"){
				$rep.="\'";
			}elsif (substr($word, $i, 1) eq '-'){
				$rep.='-';
			}else{
				$rep.='*';
			}
		}
		$def=~s/$word/$rep/gis;
		$self->globalCookie("last_word_hint", $rep);

		$output = BOLD."UrbanDictionary.com Quiz".NORMAL.GREEN." (answer with $cmd <answer>) ".BLUE."Word: $rep ".BLUE."Definition:".NORMAL." $def";
		
		$self->globalCookie("current_q", $output);

	}else{
		## Word lookup

		if (@defs){
			$output = "UrbanDictionary.com on ".BOLD.$word.NORMAL.". [".($def_num+1)."/".(@defs)."] ".BLUE."Definition:".NORMAL." $defs[$def_num]->{def}  ".BLUE."Example:".NORMAL." $defs[$def_num]->{example}";
		}else{
			$output = "No hip definitions found for \"$word\"";
		}
	}
		return $output;
}


## listeners() and addHelp()
##	Note: these functions will be called after plugin_init, which runs few times.
## 1: When the bot starts up, it will instantiate each plugin to get this info.
## 2. When an IRC user uses your plugin. (which is what you'd expect.)
## 3. When a user asks for help using the help system.
## What this means is that if you're doing anything in here like dynamically generating
## help messages or command names, you need to do that in plugin_init().
## See Diss for an example of dynamically generated help & commands.
##
sub listeners{
	my $self = shift;
	
	##	Which commands should this plugin respond to?
	## Command Listeners - put em here.  eg [qw (cmd1 cmd2 cmd3)]
	my @commands = [qw(ud udquiz)];

	## Values: irc_join
	my @irc_events = [qw () ];

	my @preg_matches = [
 	];

	my $default_permissions =[
      {command=>"udquiz",  flag=>'clearscores', require_group => UA_ADMIN } ];

	return {commands=>@commands, permissions=>$default_permissions, 
		irc_events=>@irc_events, preg_matches=>@preg_matches};

		
}

##
## addHelp()
##	The help system will pull from here using PluginBaseClass->help(key).
##
sub addHelp{
	my $self = shift;
	$self->addHelpItem("[plugin_description]", "Interface to UrbanDictionary.com. Look up a word, get a random word, or try to guess a word based on the definition.");
   $self->addHelpItem("[ud]", "Usage: ud <query> [ -n=<definition number> ] [-random]");
   $self->addHelpItem("[ud][-random]", "Get a random word from Urban Dictionary.  Usage: ud <query> [-random]");
   $self->addHelpItem("[udquiz]", "Get a random word from Urban Dictionary and wait for people to guess the answer.  Use udquiz <answer> to guess the answer.  Use udquiz -hint to get a hit.  Use udquiz -scores to see the current scores. Admins can clear scores with the -clearscores flag");
   $self->addHelpItem("[udquiz][-scores]", "Get the scores of the current Urban Dictionary quiz game for this channel.");
   $self->addHelpItem("[udquiz][-answer]", "Answer the current Urban Dictionary quiz question.  Note that this flag isn't required, you can answer with udquiz <answer>");
   $self->addHelpItem("[udquiz][-clearscores]", "Clear the scores of the Urban Dictionary quiz game for this channel.");
   $self->addHelpItem("[udquiz][-show]", "Show the current question in play, if there is one.");
   $self->addHelpItem("[udquiz][-new]", "Forces a new question to be loaded & discards the current question.");
}
1;
__END__
