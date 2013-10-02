package plugins::MasterMind;
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

	
	my $board = "";

	##
	## Show scores
	##
	if ($self->hasFlag('scores')){
		my @cookies = $self->allCookies();
		my @scores;
		foreach my $cookie (@cookies){
			next if ($cookie->{owner} eq ':package');
			push @scores, $cookie;
		}

		@scores = sort {$b->{value} <=> $a->{value}} @scores;

		foreach my $cookie (@scores){
			$self->addToList("$cookie->{owner}: $cookie->{value}", $self->BULLET );
		}

		my $list = $self->getList() || 'None yet.';
		return "MasterMind game ".BOLD."Scores".NORMAL." for $self->{channel}: ". $list;
   }


	##
	##	Clear Scores
	##
	if ($self->hasFlag('clearscores')){
		$self->deletePackageCookies();
		return "Scores cleared.";
	}


	##
	## Guess
	##
	if ($options){
		$board = $self->globalCookie('board');
		if ($board eq ':none:'){
			return "No active board in the MasterMind game. Generate a new board with $self->{BotCommandPrefix}mm -new";
		}
		my $guess = $options;
		$guess=~s/ //gis;
		$guess = uc($guess);

		if (length($guess) != length($board)){
			return "The current board is " . length($board) ." characters long.";
		}

		if ($guess eq $board){
			my ($points, $score, $total, $msg);
			$points = $self->globalCookie('points');
			if ($points){
				$score= $self->cookie('score') || 0;
				$total = int($score) + int($points);
				$self->cookie('score', $total);
				$msg = "$nick receives $points points for winning the game!  The board was $board. $nick now has $total points.";
			}else{
				$msg = "$nick wins the game! The board was $board.";
			}
			
			$self->globalCookie('board', ':none:');
			my $recap = $self->globalCookie('recap');
			$self->globalCookie('recap', $recap . BOLD."$nick WINS with $guess!");
			#$self->globalCookie('recap', '');
			return $msg;
		}

		my $correct_pos = 0;
		my $correct_letter = 0;

		for (my $i= (length($board) -1); $i>=0; $i--){
			if (substr($board, $i, 1) eq substr($guess, $i, 1)){
				$correct_pos++;
			}
		}
	
		my $temp = $guess;
		for (my $i= (length($board) -1); $i>=0; $i--){
			my $bl = substr($board, $i, 1);

			if ($temp=~s/$bl//){
				$correct_letter++;
			}
		}
	
		my $msg = "";
		my $points = $self->globalCookie('points');
		if ($points == 0){
			## none available - custom board
		}else{
			$points -= 1;
			$points = 1 if ($points <= 0 );
			$self->globalCookie('points', $points);
			$msg = "Current Value: $points";
		}

		my $recap = $self->globalCookie('recap');
		$self->globalCookie('recap', $recap . "[$correct_letter,$correct_pos]$guess  ");
		return "[$correct_letter,".RED."$correct_pos".NORMAL."] $guess: $correct_letter letters correct, with $correct_pos in the correct position. $msg";
	}

	##
	## recap
	##

	if ($self->hasFlag('recap')){
		my $recap = $self->globalCookie("recap");	
		if ($recap){
			return "Guesses so far: $recap";
		}else{	
			return "No guesses made.";
		}
	}

	##
	## reveal
	##

	if ($self->hasFlag('reveal')){
		my $ret = "The last board was: " .$self->globalCookie("board");	
		$self->globalCookie('board', ':none:');
		return $ret;
	}

	##
	##	 new board
	##

	if ($self->hasFlag('new')){

		my $do_scoring = 1;
		my $length = $self->s('length');
		if ($self->hasFlagValue('length')){
			$length = $self->hasFlagValue('length');
			$do_scoring = 0;
		}
		
		my @pieces = split "", $self->s('pieces');
		if ($self->hasFlagValue('pieces')){
			@pieces= split "",  uc($self->hasFlagValue('pieces'));
			$do_scoring = 0;
		}

		for (my $i=0; $i < $length; $i++){
			$board .= $pieces[int(rand(@pieces))];
		}

		$self->globalCookie('board', $board);
		$self->globalCookie('recap', '');

		my $ret = BOLD."New MasterMind Board Created.".NORMAL." $length letters total.  Possible letters: ". join ("", @pieces). ".  Guess with $self->{BotCommandPrefix}mm <guess>.  ";

		if ($do_scoring){
			$self->globalCookie('points', $self->s('initial_score'));
			$ret.="Current Value: ".$self->globalCookie('points');
		}else{
			$ret.="No points available for user defined boards.";
			$self->globalCookie('points', 0);
		}

		return $ret;
	}

	return $self->help($cmd);
}

sub settings{
	my $self = shift;

	$self->defineSetting({
		name=>'length',
		default=>'4',
		desc=>'The length of the board. (number of characters).'
	});

	$self->defineSetting({
		name=>'pieces',
		default=>'ABCDEF',
		desc=>'The string of characters to use on the board.'
	});

	$self->defineSetting({
		name=>'initial_score',
		default=>'10',
		desc=>'The initial score of the first board.  The score will drop by 1 point for each guess made.'
	});


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
	my @commands = [qw(mm)];

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
	$self->addHelpItem("[plugin_description]", "The game of MasterMind.  Guess the secret string using clues given by the bot. After each guess, you will be told how many letters are correct and how many letters are in the correct position. Note that not all letters need be used, and that letters can be used more than once.");
	$self->addHelpItem("[mm]", "Mastermind game. Use $self->{BotCommandPrefix}mm <guess> to make a guess. -new to get a new board.  -scores to see scores. -reveal will reveal (and kill) the current board.");
	$self->addHelpItem("[mm][-new]", "Get a new MasterMind game.  Use -length=# to specify the length of the board, else default.  Use -pieces=ABCD... to specify the pieces to use, else default.");
	$self->addHelpItem("[mm][-scores]", "Show the scores for the MasterMind game.");
	$self->addHelpItem("[mm][-clearscores]", "Clear the scores for the MasterMind game.");
	$self->addHelpItem("[mm][-reveal]", "Will reveal (and kill) the current board.");
	$self->addHelpItem("[mm][-recap]", "Show the guesses so far in short notation.");
}
1;
__END__
