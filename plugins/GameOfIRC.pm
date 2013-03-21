package plugins::GameOfIRC;
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
use POSIX;
use Data::Dumper;

sub onBotStart{
   my $self = shift;
}

sub plugin_init{
	my $self = shift;

	$self->{winning_score} = 40;
	$self->{level_descriptions} = { 
				0 => 'n00b', 
				10=> 'script kiddie', 
				20=> 'magician',
				30=> 'sorcerer',
				40=> 'wizard',
	};

	$self->outputDelimiter($self->BULLET);
	$self->suppressNick(1);
	return $self;		
}

my $level_descriptions;
my $winning_score;
my $in_session;
my $round_start_time;
my $game_start_time;
my $game_num_rounds;
my $game_won;
my $plus_rule_pos;
my $minus_rule_pos;
my $desc_plus;
my $desc_minus;

sub getOutput {
	my $self = shift;
	my $cmd = $self->{command};			# the command
	my $options = $self->{options};		# everything else on the line
	my $options_unparsed = $self->{options_unparsed};  #with the flags intact
	my $mask = $self->{mask};				# the users hostmask, not including the username
	my $BotCommandPrefix = $self->{BotCommandPrefix};	
	my $nick = $self->{nick};				
	my $bot_name = $self->{BotName};		# the name of this bot
	my $irc_event = $self->{irc_event};	# the IRC event that triggered this call
	my $BotOwnerNick	= $self->{BotOwnerNick}; 
	my $output = "";
	my $game_won = 0;

	## determine this round's start time.
	my ($secs, $mins, $hours, $day, $month, $year, $dow, $dst)= localtime(time);
	$self->{round_start_time} = POSIX::mktime (0, 5, $hours, $day, $month, $year);
	#print "This session start time would be $self->{round_start_time}\n";

	my $num_rules = 69;

	## Define the rules
	my @RULES = ();
	for (my $i=1; $i<=$num_rules; $i++){
		my $sub = "rule_" . $i;
		#print "push $sub\n";
		push @RULES, $sub;
	}

	## Run the test rule if testing.
	if (my $num = $self->hasFlagValue("rule")){
		my $sub = $RULES[$num-1];
		my $subref = \&$sub;
		my $ret = &$subref($self, "plus");
		return "retval is $ret ($self->{desc_plus})";
	}
	
	## Should a round be in session?
	if ( $mins < 5 ){
		$self->{in_session} = 0;
	}else{
		$self->{in_session} = 1;
	}

	my $channel;
	if (! ($channel = $self->hasFlagValue("channel"))){
		$channel = $self->{channel};
	}
	
	## avoid starting games with PM widows
	if ($channel!~/^#/){
		return;
	}

	## 
	## Determine current state of the game
	##	
	my $c_sess = $self->getCollection(__PACKAGE__, $channel);
	my @records = $c_sess->matchRecords({val1=>'master_rec' });
	
	# 1. Is a current game running? Check for master record
	# 	 a. No master record exists, so no game is running.  Create the master record.
	if (!@records){
		$c_sess->add('master_rec', $self->{round_start_time}, 0, 'in_progress');
		$self->{game_start_time} = $self->{round_start_time};
		$self->{game_num_rounds} = 0;


	# b. A master record exists.  
	}elsif(@records == 1){
		
		# Game exists and is not marked as being won
		if ($records[0]->{val4}  eq 'in_progress'){
			$self->{game_start_time} = $records[0]->{val2};
			$self->{game_num_rounds} = $records[0]->{val3};
			#print Dumper (@records);

		## Someone has won, but it's not time for a new game to start yet.
		}elsif($records[0]->{val4} eq $self->{round_start_time}){
			$self->{in_session} = 0;
			$self->{game_start_time} = $records[0]->{val2};
			$self->{game_won} = 1;

		}elsif($self->{in_session}){
			my $last_game_id = $records[0]->{val2};

			## Time to clean up the old game info & start a new game.

			#delete the old scores
			@records = $c_sess->getAllRecords();
			foreach my $rec (@records){
				$c_sess->delete($rec->{row_id});
			}

			$c_sess->add('master_rec', $self->{round_start_time}, 0, 'in_progress');
			$self->{game_start_time} = $self->{round_start_time};
			$self->{game_num_rounds} = 0;

		}else{
			$self->{game_start_time} = $records[0]->{val2};
			$self->{game_won} = 1;
		}

	}else{
		# # of game records is > 1.  this is a problem.
		print "More than one game records.\n";
		print "returning\n";
		return "";
	}
	

	##
	##	 The command
	##

	if ($cmd eq "gstandings"){
		## Show the rules stats
	
		## Show stats about the different rules, how often each is hit, etc.
		if ($self->hasFlag("rules")){

			my $c_stats = $self->getCollection(__PACKAGE__, 'rule_stats');
			# goirc | rule_stats | 1rule_num | 2rule desc | 3num plays | 4num hits 
			#$c_stats->sort({field=>'val3', type=>'numeric', order=>'desc'});
			my @records = $c_stats->getAllRecords();

			my @stats;
			foreach my $rec (@records){
				my $hpp= sprintf("%.2f", ($rec->{val4} / $rec->{val3}));
				push @stats, {hpp=>$hpp, record=>$rec};
			}

			@stats = sort {$b->{hpp} <=> $a->{hpp}} @stats;
			$output = "Rules Rankings: ";
			my $bullet="";

			foreach my $s (@stats){
				my $rec = $s->{record};
				$output.= $bullet . "[#".$rec->{val1}."] ". $rec->{val2} .": ";
				$output.= "$rec->{val3} plays, $rec->{val4} hits, $s->{hpp} h/p.";
				$bullet = " " .$self->BULLET ." ";
			}

			return $output;
		}

		##Return last game standings.
		my $c_standings = $self->getCollection(__PACKAGE__, 'standings');
		
		#my $u = $c_standings->getUnique({val1=>$channel}, 'val2');
		#print Dumper ($u);

		my $last_game = $c_standings->getMax({val1=>$channel}, "val2");
		$c_standings->sort({field=>'val3', type=>'numeric', order=>'asc'});
		my @records = $c_standings->matchRecords({val1=>$channel, val2=>$last_game});
			
		my %standings;
		foreach my $rec (@records){
			$output.=RED.BOLD."First Place:".NORMAL." $rec->{val4} ($rec->{val6} points) " if (int($rec->{val3}) == 1);
			$output.=RED.BOLD."Second Place:".NORMAL." $rec->{val4} ($rec->{val6} points) " if (int($rec->{val3}) == 2);
			$output.=RED.BOLD."Third Place:".NORMAL." $rec->{val4} ($rec->{val6} points) " if (int($rec->{val3}) == 3);
			$output.=RED.BOLD."Fourth Place:".NORMAL." $rec->{val4} ($rec->{val6} points) " if (int($rec->{val3}) == 4);
			$output.=RED.BOLD."Fifth Place:".NORMAL." $rec->{val4} ($rec->{val6} points) " if (int($rec->{val3}) == 5);
		}

		if ($output){
			$output = "Last game's results: " . $output;
		}else{
			$output = "No games have been finished in $channel.";
		}
		return $output;
	}


	if ($cmd eq "gscores"){

		if ($self->{in_session} && !$self->hasFlag("force")){
			return "You can only check scores for the first 5 mins of each hour."
		}

		my $channel;
		if ( !($channel = $self->hasFlagValue("channel"))){
			$channel = $self->{channel};
		}

		if ($self->hasFlag('listchannels')){
			my $c = $self->getCollection(__PACKAGE__, '%');
			my @records = $c->matchRecords({val1=>'master_rec'});

			my $bullet = "";
			foreach my $rec (@records){
				$output .= $bullet . $rec->{collection_name} ." (Round #$rec->{val3})";
				$bullet = " " .$self->BULLET ." ";
			}
			return $output;
		}

		if (my $num = $self->hasFlagValue("lookup")){
			my $sub = $RULES[$num];
			my $subref = \&$sub;
			my $ret = &$subref($self, "admin");
			return $self->{desc_admin};
		}

		if (my $user = $self->hasFlagValue("nick")){
	# goirc | channel | 1game | 2 game_start_time | 3'user_score' | 4nick | 5total_score
	# goirc | channel | round_score_detail | 2 game_start_time | 3round_start_time | 4nick | 5:+1/-1 | 6: rule desc
			my $c = $self->getCollection(__PACKAGE__, $channel);
			my @records = $c->matchRecords({val1=>'game', val3=>'user_score', val4=>$user});
			return "That user has no score" if (!@records);
			$output.=BOLD."$user".NORMAL." has $records[0]->{val5} points in the ".GREEN.BOLD."GameOfIRC".NORMAL.". Scoring summary: " ;
			@records = $c->matchRecords({val1=>'round_score_detail', val4=>$user});
			my %scores;
			foreach my $rec (@records){
				if (!defined($scores{$rec->{val6}})){
					$scores{$rec->{val6}} = $rec->{val5};
					#print "Set equal $rec->{val3}\n";
				}else{
					$scores{$rec->{val6}} += $rec->{val5};
					#print "ADD $rec->{val5}\n";
				}
			}

			my $bullet = "";
			foreach my $k (keys %scores){
				if ($scores{$k} > 0){
					if ($scores{$k}!~/^\+/){
						$scores{$k} = '+' . $scores{$k};
					}
					$output.= $bullet . $k ." " .BOLD. $scores{$k}.NORMAL;
					$bullet= " " .$self->BULLET ." ";
				}elsif($scores{$k} < 0){
					$output.= $bullet . $k ." " .BOLD. $scores{$k}.NORMAL;
					$bullet= " " .$self->BULLET ." ";
				}
			}

			return $output;
		}

		my $c = $self->getCollection(__PACKAGE__, $channel);
		if (! $c->numRecords()){
			return "No games running in channel $channel";
		}

		$c->sort({field=>'val5', type=>'numeric', order=>'desc'});
		my @records = $c->matchRecords({val1=>'game', val3=>'user_score'});

		my ($sec, $min, $hour, $day,$month,$year) = (localtime($self->{game_start_time}))[0,1,2,3,4,5];
		my @months = ("Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec");
		my $t = sprintf('%s %d at %d:%02d', $months[$month], $day, $hour, $min);

			
		my $overall;	
		my $bullet = "";
		foreach my $rec (@records){
			if (int($rec->{val5}) > 0){
				$overall.= "$bullet" .$rec->{'val4'}.": +".$rec->{val5};
				$bullet= " " .$self->BULLET ." ";
			}elsif(int($rec->{val5}) < 0){
				$overall.= "$bullet" .$rec->{'val4'}.": ".$rec->{val5};
				$bullet= " " .$self->BULLET ." ";
			}
		}

		## First, figure out the last round
		my $last_round;
		my $last_round_num;
		$c->sort({field=>'val3', type=>'numeric', order=>'desc'});
		@records = $c->matchRecords({val1=>'round_rec'});

		if (!@records){
			#return "I have no data";

		}else{

			if ($records[0]->{val3} ne $self->{round_start_time}){
				$last_round = $records[0]->{val3};
				$last_round_num = $records[0]->{val6};
			}

			if (!$last_round && @records > 1){
				$last_round = $records[1]->{val3};
				$last_round_num = $records[1]->{val6};
			}

			if (!$last_round){
				#return "I couldn't find the previous round.";
			}
		}

		my $last;
		if ($last_round){
			$c->sort({field=>'val6', type=>'numeric', order=>'desc'});
			my @records = $c->matchRecords({val1=>'round_score', val3=>$last_round});

			my $bullet = "";

			foreach my $rec (@records){
				if (int($rec->{val6}) > 0){
					$last.= "$bullet" .$rec->{'val5'}.": +".$rec->{val6};
					$bullet= " " .$self->BULLET ." ";
				}elsif(int($rec->{val6}) < 0){
					$last.= "$bullet" .$rec->{'val5'}.": ".$rec->{val6};
					$bullet= " " .$self->BULLET ." ";
				}
			}
		}

		$output = GREEN."GameOfIRC".NORMAL." started in $channel on $t. ";

		if ($last && !$self->{game_won}){
			$output.=BOLD."Previous round (#$last_round_num):".NORMAL." $last. ";
		}

		if ($self->{game_won}){
			$output.=REVERSE." * This game is over * ".NORMAL;
		}

		if ($overall){
			$output .= BOLD." Overall scores:".NORMAL." $overall. ";
		}

		if (!$self->{game_won}){
			$output .= " ".$self->BULLET." ". GREEN."Game ends when someone reaches $self->{winning_score} points.".NORMAL." Use -nick=<nick> to see score detail.";
		}

		return $output;

	}

	########################################################################
	########################################################################
	##		End command handling, the rest is regex match scoring
	########################################################################
	########################################################################

	# goirc | rule_stats | rule_num | rule desc | num plays | num hits 
	# goirc | standings | 1channel | 2game_start_time | 3place | 4 nick | #5 round# | #6 score
	# goirc | channel | 1master_rec| 2 game_start_time |  3 #rounds  | 4 #winning round 
	# goirc | channel | 1round_rec | 2 game_start_time | 3round_start_time | 4+rule | 5-rule| 6-round
	# goirc | channel | 1game | 2 game_start_time | 3'user_score' | 4nick | 5total_score
	# goirc | channel | 1round_score | 2 game_start_time | 3round_start_time | 4'user_score' | 5nick | 6total_score
	# goirc | channel | round_score_detail | 2 game_start_time | 3round_start_time | 4nick | 5:+1/-1 | 6: rule desc


	# 2.  Should we be in a round?
	if (!$self->{in_session}){
		print "not in session: returning\n";
		return;
	}
	
	if ($self->{game_won}){
		print "game won. returning without scoring\n";
		return;
	}
	
	# 3.  We should be in a round.  Has the round been started yet?
	@records = $c_sess->matchRecords({val1=>'round_rec', val2=>$self->{game_start_time}, 
			val3=>$self->{round_start_time}});
	
	if (@records){
		# round already started.
		$self->{plus_rule_pos} = $records[0]->{val4};
		$self->{minus_rule_pos} = $records[0]->{val5};

		# sometimes two rounds get started. whoopsies.
		# delete the other round entries.  that's not messy, right? heh.
		if (@records > 1){
			$c_sess->delete($records[1]->{row_id});
		}

	}else{
		# start the round
		$self->{plus_rule_pos} = int(rand() * ($num_rules ));

		do {
			$self->{minus_rule_pos} = int(rand() * ($num_rules ));
		}while ($self->{minus_rule_pos} == $self->{plus_rule_pos});


		# increment the # of rounds counter
		my @records = $c_sess->matchRecords({val1=>'master_rec' });
		$self->{game_num_rounds} = $records[0]->{val3}+1;
		$c_sess->updateRecord($records[0]->{row_id}, {val3=>$self->{game_num_rounds}});

		# add the round record
		$c_sess->add('round_rec', $self->{game_start_time}, $self->{round_start_time}, 
				$self->{plus_rule_pos}, $self->{minus_rule_pos},  $self->{game_num_rounds});

		# add a stats entry
		my $c_stats = $self->getCollection(__PACKAGE__, 'rule_stats');
			#first for plus
		@records = $c_stats->matchRecords({val1=>$self->{plus_rule_pos}});
		if (@records){
			my $newval = int($records[0]->{val3}) + 1 ;
			$c_stats->updateRecord($records[0]->{row_id}, {val3=>$newval});
		}else{
			my $sub = $RULES[$self->{plus_rule_pos}];
			my $subref = \&$sub;
			my $ret = &$subref($self, "admin");
			my $desc = $self->{desc_admin};
			$c_stats->add($self->{plus_rule_pos}, $desc, 1, 0);
		}

			#then for minus
		@records = $c_stats->matchRecords({val1=>$self->{minus_rule_pos}});
		if (@records){
			my $newval = int($records[0]->{val3}) + 1 ;
			$c_stats->updateRecord($records[0]->{row_id}, {val3=>$newval});
		}else{
			my $sub = $RULES[$self->{minus_rule_pos}];
			my $subref = \&$sub;
			my $ret = &$subref($self, "admin");
			my $desc = $self->{desc_admin};
			$c_stats->add($self->{minus_rule_pos}, $desc, 1, 0);
		}
	}


	##
	##	Score each line
	##	

	my $round_rec;
	my $total_rec;
	my $round_score;
	my $total_score;

	## Get user's round record
	@records = $c_sess->matchRecords({val1=>'round_score', val2=>$self->{game_start_time}, 
			val3=>$self->{round_start_time}, val4=>'user_score', val5=>$self->{nick}});

	if (!@records){
		$c_sess->add('round_score', $self->{game_start_time}, $self->{round_start_time}, 'user_score', $self->{nick}, 0 );
		$round_score = 0;
		@records = $c_sess->matchRecords({val1=>'round_score', val2=>$self->{game_start_time}, 
			val3=>$self->{round_start_time}, val4=>'user_score', val5=>$self->{nick}});
		$round_rec = $records[0];

	}else{
		$round_score = $records[0]->{val6};
		$round_rec = $records[0];
	}

	## Get total game record
	@records = $c_sess->matchRecords({val1=>'game', val2=>$self->{game_start_time}, 
			val3=>'user_score', val4=>$self->{nick}});

	if (!@records){
		$c_sess->add('game', $self->{game_start_time}, 'user_score', $self->{nick}, 0 );
		$round_score = 0;
		@records = $c_sess->matchRecords({val1=>'game', val2=>$self->{game_start_time}, 
			val3=>'user_score', val4=>$self->{nick}});
		$total_rec = $records[0];

	}else{
		$total_score = $records[0]->{val5};
		$total_rec = $records[0];
	}


	{	## Run the Plus rule
		my $sub = $RULES[$self->{plus_rule_pos}];
		my $subref = \&$sub;
		my $ret = &$subref($self, "plus");
		if ($ret){
			print "Adding point for $self->{nick}\n";
			$round_score++;
			$total_score++;
			$c_sess->updateRecord($round_rec->{row_id}, {val6=>$round_score});
			$c_sess->updateRecord($total_rec->{row_id}, {val5=>$total_score});
			## add detail
			$c_sess->add( 'round_score_detail', $self->{game_start_time}, $self->{round_start_time},
				 $self->{nick}, '+1', $self->{desc_plus});

			# Update rule stats
			my $c_stats = $self->getCollection(__PACKAGE__, 'rule_stats');
			@records = $c_stats->matchRecords({val1=>$self->{plus_rule_pos}});
			my $newval = int($records[0]->{val4}) + 1 ;
			$c_stats->updateRecord($records[0]->{row_id}, {val4=>$newval});

			##check for game win
			if ($total_score >= $self->{winning_score} ){
				# Someone won

				# first, mark this game as won by setting the winning round number in the game record
				my @records = $c_sess->matchRecords({val1=>'master_rec', val4=>'in_progress'});
				$c_sess->updateRecord($records[0]->{row_id}, {val4=>$self->{game_start_time}});
				
				# now create a standings row

				$c_sess->sort({field=>'val5', type=>'numeric', order=>'desc'});
				@records = $c_sess->matchRecords({val1=>'game', val2=>$self->{game_start_time}, 
					val3=>'user_score'});

				my $i = 0;
				my $c_standings = $self->getCollection(__PACKAGE__, 'standings');

			# goirc | channel | 1game | 2 game_start_time | 3'user_score' | 4nick | 5total_score
			# goirc | standings | 1channel | 2game_start_time | 3place | 4 nick | #5 round# | #score

				foreach my $rec (@records){
					if ($i++ < 5){
						#print Dumper($rec);
						$c_standings->add($self->{channel}, $self->{game_start_time}, $i, $rec->{val4},
					 		$self->{game_num_rounds}, $rec->{val5});
					}
				}

				## Now announce it.
				$output = GREEN."Congratulations to $self->{nick} on winning the GameOfIRC! ".NORMAL;
				my $next = 60 - $mins + 5;
				$output.= "$self->{nick} was the first player to reach $self->{winning_score} points, ";
				$output.= "and did so in $self->{game_num_rounds} rounds. ";
				$output .="A new round will begin in $next minutes.  View the scores from the last ";
				$output .="round using the gscores command.";
				return $output;
			}
		}
	}

	{	## Run the Minus rule, floor zero
		my $sub = $RULES[$self->{minus_rule_pos}];
		my $subref = \&$sub;
		my $ret = &$subref($self, "minus");

		if ($ret){

			# Update rule stats
			my $c_stats = $self->getCollection(__PACKAGE__, 'rule_stats');
			@records = $c_stats->matchRecords({val1=>$self->{minus_rule_pos}});
			my $newval = int($records[0]->{val4}) + 1 ;
			$c_stats->updateRecord($records[0]->{row_id}, {val4=>$newval});

			if ( ($total_score - 1) >= 0){
				print "Subtracting point for $self->{nick}\n";
				$round_score--;
				$total_score--;
				$c_sess->updateRecord($round_rec->{row_id}, {val6=>$round_score});
				$c_sess->updateRecord($total_rec->{row_id}, {val5=>$total_score});
				$c_sess->add( 'round_score_detail', $self->{game_start_time}, $self->{round_start_time},
					 $self->{nick}, '-1', $self->{desc_minus});
			}
		}
		#print "ran minus rule $self->{desc_minus}\n";
	}

	#my $args = {
	#  timestamp => '',		# When
	#  command => '',			# Command to execute.  Use _internal_echo for saying things
	#  options => '',			# Options to pass to the command
	#  desc => ''				# Just informational, internal only. 
	#};
	#$self->scheduleEvent($args);

	return $output;
}


sub rule_1{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "speaking up at the right time.";
	my $time = time();
	if ($time=~/42$/){
		return 1;
	}
	return 0;
}

sub rule_2{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "starting things off right";
	my $letter = substr($self->{nick}, 0, 1);
	if ($self->{options}=~/^$letter/i){
		return 1;
	}
	return 0;
}

sub rule_3{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "second fiddle";
	my $letter = substr($self->{nick}, 1, 1);
	if ($self->{options}=~/^$letter/i){
		return 1;
	}
	return 0;
}

sub rule_4{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "startin up a posse";
	if ($self->{options}=~/(shit|fuck|satan|death|sex|drugs|rape)/i){
		return 1;
	}
	return 0;
}

sub rule_5{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "scarborough faire";
	if ($self->{options}=~/(parsely|sage|rosemary|thyme|time)/i){
		return 1;
	}
	return 0;
}

sub rule_6{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "ticket to ride";
	if ($self->{options}=~/(john|paul|george|ringo|star|beatle|beetle|lenin|penny|\blane\b|rocky|raccoon)/i){
		return 1;
	}
	return 0;
}

sub rule_7{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "behind the curtain";
	if ($self->{options}=~/$self->{BotOwnerNick}/i){
		return 1;
	}
	return 0;
}

sub rule_8{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "say my name";
	if ($self->{options}=~/$self->{BotName}/i){
		return 1;
	}
	return 0;
}

sub rule_9{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "o rly?";
	if ($self->{options}=~/\?$/i){
		return 1;
	}
	return 0;
}

sub rule_10{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "autocorrect is fro n00bs";
	if ($self->{options}=~/\bteh\b/i){
		return 1;
	}
	return 0;
}

sub rule_11{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "low profile";
	if ($self->{options} eq lc($self->{options})){
		return 1;
	}
	return 0;
}

sub rule_12{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "let it all out";
	if ($self->{options} eq uc($self->{options})){
		return 1;
	}
	return 0;
}

sub rule_13{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "stop drop and cap";
	my $str = join " ", map {ucfirst} split / /, lc($self->{options});
	print "STR is $str\n";
	if ($self->{options} eq $str){
		return 1;
	}
	return 0;
}

sub rule_14{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "more info, stat!";
	if ($self->{options}=~/[0-9]/i){
		return 1;
	}
	return 0;
}

sub rule_15{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "compute this";
	if ($self->{options}=~/(\+|\-|\/|\*|=)/i){
		return 1;
	}
	return 0;
}

sub rule_16{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "colorfully worded ";
	if ($self->{options}=~/( red |orange|yellow|green|blue|indigo|purple|violet|white|black)/i){
		return 1;
	}
	return 0;
}

sub rule_17{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "you are here.";
	if ($self->{options}=~/$self->{channel}\b/){
		return 1;
	}
	return 0;
}

sub rule_18{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "ride the short line";
	if (length($self->{options}) < 6){
		return 1;
	}
	return 0;
}

sub rule_19{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "long lines at the checkout";
	if (length($self->{options}) > 100 ){
		return 1;
	}
	return 0;
}

sub rule_20{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "sir linksalot";
	if ($self->{options}=~/ http\:/i ){
		return 1;
	}
	return 0;
}

sub rule_21{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "security conscious";
	if ($self->{options}=~/( https\:|ssh|pgp|crypt)/i ){
		return 1;
	}
	return 0;
}


sub rule_22{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "the password is password";
	if ($self->{options}=~/password/i ){
		return 1;
	}
	return 0;
}

sub rule_23{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "Slam Dunk";
	if (length($self->{options}) == 23 ){
		return 1;
	}
	return 0;
}

sub rule_24{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "double trouble";

	# thanks, JBH_mike!
	if ($self->{options}=~m/\b([A-Za-z]+) +\1\b/){
		return 1;
	}
	return 0;
}

sub rule_25{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "1000 words";
	if ($self->{options}=~m/\.(jpg|jpeg|png|gif|bmp)/i ){
		return 1;
	}
	return 0;
}

sub rule_26{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "bound by contract";
	if ($self->{options}=~m/\w'\w/i){
		return 1;
	}
	return 0;
}

sub rule_27{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "friendly fellow";
	if ($self->{options}=~m/\b(hi|hello|greetings|hey|hola|yo|sup)\b/i){
		return 1;
	}
	return 0;
}

sub rule_28{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "yolo";
	if ($self->{options}=~m/\b(yolo)\b/i){
		return 1;
	}
	return 0;
}

sub rule_29{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "workin' for a living";
	if ($self->{options}=~m/\b(working|work|boss|employer|employed|unemployed|job|overtime|manager)\b/i){
		return 1;
	}
	return 0;
}

sub rule_30{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "sick and tired";
	if ($self->{options}=~m/\b(sick|doctor|hospital|flu|a cold|medicine|tired|sleep|sleepy)\b/i){
		return 1;
	}
	return 0;
}

sub rule_31{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "dellsbells";
	if ($self->{options}=~m/\.\.\./i){
		return 1;
	}
	return 0;
}

sub rule_32{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "rock on";
	if ($self->{options}=~m/\b(bon|jovi|journey|reo|speed|wagon|kansas|foreign|foreigner|fog|hat|chicago|u2|asia|survive|survivor|toto|boston)\b/i){
		return 1;
	}
	return 0;
}

sub rule_33{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "me me me";
	if ($self->{options}=~m/$self->{nick}/i){
		return 1;
	}
	return 0;
}

sub rule_34{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "rule 34";
	if ($self->{options}=~m/(porn|naked|penis|boobs|tits|nude|porno|sex|fluff)/i){
		return 1;
	}
	return 0;
}

sub rule_35{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "star killer";
	if ($self->{options}=~m/youtube|dailymotion|video/i){
		return 1;
	}
	return 0;
}

sub rule_36{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "desperately seeking";
	if ($self->{options}=~m/google|bing|yahoo|dogpile|duck/i){
		return 1;
	}
	return 0;
}

sub rule_37{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "pyramid";
	
	my @words = split / /, $self->{options};

	my $len = 0;

	if (@words < 3){
		return 0;
	}

	foreach my $w (@words){
		if (length ($w) <= $len){
			return 0;
		}
		$len = length($w);
	}
	return 1;
}

sub rule_38{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "funnel";
	
	my @words = split / /, $self->{options};

	my $len = 99;

	if (@words < 3){
		return 0;
	}

	foreach my $w (@words){
		if (length ($w) >= $len){
			return 0;
		}
		$len = length($w);
	}
	return 1;
}

sub rule_39{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "first half";
	
	my $str = lc($self->{options});
	
	return 0 if (length($str) < 6);
	
	$str=~s/\W//g;
	$str=~s/[a-l]//gis;

	return 0 if ($str);
	return 1;
}


sub rule_40{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "second half";
	
	my $str = lc($self->{options});
	
	return 0 if (length($str) < 6);
	
	$str=~s/\W//g;
	$str=~s/[m-z]//gis;

	return 0 if ($str);
	return 1;
}

sub rule_41{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "emotical soul";
	if ($self->{options}=~m/(\:\)|\:\(|\:D|\:P|\:\>|\;\)|\;\()/){
		return 1;
	}
	return 0;
}

sub rule_42{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "get with the program";
	if ($self->{options}=~m/(perl|python|c\+\+|java|cobol|shell|\bc\b|script|html|compile|debug|\bbug\b|cocoa)/i){
		return 1;
	}
	return 0;
}

sub rule_43{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "call me maybe";
	if ($self->{options}=~m/(android|iphone|blackberry|phone)/i){
		return 1;
	}
	return 0;
}

sub rule_44{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "fanboy";
	if ($self->{options}=~m/(apple|\bpc\b|microsoft|linux|windows)/i){
		return 1;
	}
	return 0;
}

sub rule_45{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "adios amigo";
	if ($self->{options}=~m/(bye|c ya|see ya|later|adios|goodnight|good night)/i){
		return 1;
	}
	return 0;
}

sub rule_46{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "fritter and waste";
	if ($self->{options}=~m/(time|hour|minute|second|day|year|clock|date|watch)/i){
		return 1;
	}
	return 0;
}

sub rule_47{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "personally speaking";
	if ($self->{options}=~m/\b(i|me|my|mine|you|your|yours|we|us|our|ours|he|him|his|she|her|hers|it|its|they|them|their|theirs)\b/i){
		return 1;
	}
	return 0;
}

sub rule_48{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "happy to be here";
	if ($self->{options}=~m/\b(am|is|are|was|were|be|being|been)\b/i){
		return 1;
	}
	return 0;
}

sub rule_49{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "all good things";
	if ($self->{options}=~m/(\.|\?|\!)$/i){
		return 1;
	}
	return 0;
}


sub rule_50{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "it's a crime";
	if ($self->{options}=~m/(\$)/i){
		return 1;
	}
	return 0;
}

sub rule_51{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "symbolically speaking";
	if ($self->{options}=~m/(\!|\@|\#|\$|\%|\^|\&|\*|\(|\)|\_|\+|\=|\{|\}|\[|\])/i){
		return 1;
	}
	return 0;
}

sub rule_52{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "the first rule of bot club";
	my $n = $self->{BotName};
	my $opts = $self->{options};
	my @c = split //, $n;
	foreach  $n (@c){
		$opts=~s/$n//i;
	}

	if ($self->{options} eq $opts){
		return 1;
	}
	return 0;
}

sub rule_53{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "not a fighter";
	if ($self->{options}=~m/(love|\<3|\<\/3)/i){
		return 1;
	}
	return 0;
}

sub rule_54{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "namecaller";
	if ($self->{options}=~m/(asshole|dickhead|dick|fucker|jerk|idiot|moron|stupid|fuckhead|asshat|cunt)/i){
		return 1;
	}
	return 0;
}

sub rule_55{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "cliff hanger";
	if ($self->{options}=~m/(\-|\.\.\.)/i){
		return 1;
	}
	return 0;
}

sub rule_56{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "yay sports";
	if ($self->{options}=~m/(nfl|mlb|nhl|nba|basketball|football|baseball|hockey|soccer|team)/i){
		return 1;
	}
	return 0;
}

sub rule_57{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "quizzical";
	if ($self->{options}=~m/(q|z)/i){
		return 1;
	}
	return 0;
}

sub rule_58{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "Eh?";
	if ($self->{options}=~m/(colour|behaviour|calibre|cancelled|centre|cheque|favour|harbour|honour|humour|kilometre|labour|metre|neighbour|odour|syrup)/i){
		return 1;
	}
	return 0;
}

sub rule_59{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "miss manners";
	if ($self->{options}=~m/(please|thanks|thank you|ty|\bpls\b|you're wecome)/i){
		return 1;
	}
	return 0;
}

sub rule_60{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "what else should i be?";
	if ($self->{options}=~m/(sorry|apolog)/i){
		return 1;
	}
	return 0;
}

sub rule_61{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "yes master";
	if ($self->{options}=~m/^(\.|\,|\~|\;)/i){
		return 1;
	}
	return 0;
}

sub rule_62{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "like the wolf";
	if ($self->{options}=~m/(hungry|\beat\b|dinner|breakfast|supper|lunch|snack)/i){
		return 1;
	}
	return 0;
}

sub rule_63{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "squeaky clean";
	if ($self->{options}=~m/\b(shower|wash|bath|bathe|clean)\b/i){
		return 1;
	}
	return 0;
}

sub rule_64{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "right on";
	if ($self->{options}=~m/\b(awesome|cool|neato)\b/i){
		return 1;
	}
	return 0;
}

sub rule_65{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "taken";
	if ($self->{options}=~m/\b(wife|husband|bf|gf|boyfriend|girlfriend|spouse|s\.o\.)\b/i){
		return 1;
	}
	return 0;
}

sub rule_66{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "serenity";
	if ($self->{options}=~m/(fire|fly|mal|zoe|wash|cob|jane|jayne|tam|book|you can't|take the|\bsky\b|from me)/i){
		return 1;
	}
	return 0;
}

sub rule_67{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "homesick";
	if ($self->{options}=~m/(basement|medicine|pavement|government|trench coat|laid off|bad cough|paid off|look out|god knows|duck down|alley way|new friend|big pen|fleet foot|black soot|heat put|bed but|no doz|clean nose|plain clothes|weather man|wind|blows|get sick|get well|ink well|ring bell|get barred|try hard|losers|cheaters|theaters|whirlpool|follow|leaders|watch|parking|meters)/i){
		return 1;
	}
	return 0;
}

sub rule_68{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "state of mind";

	if ($self->{options}=~m/AL|AK|AZ|AR|CA|CO|CT|DE|FL|GA|HI|ID|IL|IN|IA|KS|KY|LA|ME|MD|MA|MI|MN|MS|MO|MT|NE|NV|NH|NJ|NM|NY|NC|ND|OH|OK|OR|PA|RI|SC|SD|TN|TX|UT|VT|VA|WA|WV|WI|WY/i){
		return 1;
	}
	return 0;
}

sub rule_69{
	my $self = shift;
	my $mode = shift;
	$self->{'desc_' . $mode} = "sprinkled";

	my @chars = split //, $self->{nick};

	foreach my $c (@chars){
		if ($self->{options}!~m/$c/i){
			return 0;
		}
	}
	return 1;
}




sub listeners{
	my $self = shift;
	
	##	Which commands should this plugin respond to?
	## Command Listeners - put em here.  eg [qw (cmd1 cmd2 cmd3)]
	my @commands = [qw(gscores gstandings)];

	## Values: irc_join
	my @irc_events = [qw () ];

	my @preg_matches = ["/./" ];


	my $default_permissions =[
		{command=>"gscores", flag=>'force', require_group => UA_ADMIN},
		{command=>"gscores", flag=>'channel', require_group => UA_ADMIN},
		{command=>"gscores", flag=>'rule', require_group => UA_ADMIN},
		{command=>"gscores", flag=>'listchannels', require_group => UA_ADMIN},
		{command=>"gscores", flag=>'lookup', require_group => UA_ADMIN},
		{command=>"gstandings", flag=>'rules', require_group => UA_ADMIN},
	];

	return {commands=>@commands, permissions=>$default_permissions, 
		irc_events=>@irc_events, preg_matches=>@preg_matches};
}

sub addHelp{
	my $self = shift;
	$self->addHelpItem("[plugin_description]", "Welcome to The Game of IRC, where you are always playing, even if you don't want to.  Here's how it works: There are hundreds of rules, but only two rules are in effect at any given time.  If you do something specified by the first rule, you gain a point.  If you do something specified by the second rule, you lose a point. You also don't get to know what the rules are or which two rules are in effect.  The rules can be as simple as mentioning a color or typing a line of a particular length, or as complex as using a pattern of words of a particular type or length, sometimes on multiple lines. The two rules are the same for everyone playing, but there may be user-specific variations.  For example, one rule might be 'player must use every letter of his/her nick in single irc line.'  So, same rule, but the exact execution would vary from player to player.  Each round lasts for 55 minutes and starts 5 minutes after the hour. You can only check the scores between rounds, though $self->{BotName} may occassionally announce when a player levels up or down.  Oh, and the leveling messages might be randomly time-delayed.  When you check the scores (using the 'gscores' command), you can request a detailed view, that might give you some clues. A game runs in rounds of 55 mins each and ends when someone reaches $self->{winning_score} points.  Got it?  Good. Have fun!");
   $self->addHelpItem("[gscores]", "The Game of IRC. You're playing now. See the plugin info for details. (help GameOfIRC --info) Use -nick=<nick> for a user's score detail.");
   $self->addHelpItem("[admin][options]", "-force -listchannels -channel= ");
}
1;
__END__
