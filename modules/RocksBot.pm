package modules::RocksBot;
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
use File::Basename;
use Fcntl qw(LOCK_EX LOCK_NB);
use modules::CommandHandler;
use modules::EventTimer;
use constant EventTimer => 'modules::EventTimer';
use modules::PrivacyFilter;
use constant PrivacyFilter => 'modules::PrivacyFilter';
use modules::UserAuth 1.0;
use constant UserAuth => 'modules::UserAuth';
use Config::Simple;
use POE qw(Component::IRC);
use POE::Component::IRC::Plugin::NickServID;
use POE::Component::Generic;
use POE qw(Component::IRC::State Component::IRC::Plugin::AutoJoin);
use IRC::Utils ':ALL';
use URI::Escape;
use HTML::Entities;
use Data::Dumper;
use URI::Escape;
use Time::HiRes qw/ time sleep /;

BEGIN {
	$modules::RocksBot::VERSION = '1.0';
}

our $VERSION = '1.0';

our $config_file;
our $BotName;
our $username;
our $ircname;
our $server;
our $nickserv_password;
our @channels;
our $BotCommandPrefix;
our $num_worker_threads; 
our $BotDatabaseFile;
our $BotOwnerNick;
our $FloodProtectionDisabled;
our $daemonize;
our $daemon_logfile;
our $daemon_pidfile;
our $command_window;
our $command_max;
our $EventTimerObj;
our $PrivacyFilter;
our $privacy_filter_enable;
our $sql_pragma_synchronous;
our $SpeedTraceLevel;

our $irc;
our @CH;

# this is for the rate limiter
our %user_commands;

sub new {
	my ($class, @args) = @_;
	my $self = bless {}, $class;

	$config_file = shift @args;
	$self->loadConfig();
	$self->init();
	return $self;
}

sub loadConfig{
	my $self = shift;

	##
	##	Read Configuration File
	##

	my $cfg = new Config::Simple();
	$cfg->read($config_file) or die "Can't find config file";

	$BotName = $cfg->param("ConnectionSettings.nickname");
	$username = $cfg->param("ConnectionSettings.username") || $BotName;
	$ircname = $cfg->param("ConnectionSettings.ircname") || $BotName;
	$server = $cfg->param("ConnectionSettings.server");
	$nickserv_password = $cfg->param("ConnectionSettings.nickserv_password") || "";
	@channels = $cfg->param("ConnectionSettings.channels");
	$BotCommandPrefix = $cfg->param("BotSettings.CommandPrefix") || '.';
	$num_worker_threads = $cfg->param("BotSettings.NumWorkerThreads") || 4;
	$BotDatabaseFile = $cfg->param("BotSettings.DatabaseFile");
	$BotOwnerNick = $cfg->param("BotSettings.BotOwnerNick") || 'japh';
	$FloodProtectionDisabled = $cfg->param("BotSettings.FloodProtectionDisabled") || 0;
	$daemonize = $cfg->param("BotSettings.daemonize") || 0;
	$daemon_logfile = $cfg->param("BotSettings.daemon_logfile");
	$daemon_pidfile = $cfg->param("BotSettings.daemon_pidfile");
	$command_window = $cfg->param("BotSettings.command_limit_window") || 60;
	$command_max = $cfg->param("BotSettings.command_limit_max") || 20;
	$SpeedTraceLevel= $cfg->param("BotSettings.SpeedTraceLevel");
	$sql_pragma_synchronous= $cfg->param("BotSettings.sql_pragma_synchronous");
	$privacy_filter_enable = $cfg->param("BotSettings.privacy_filter_enable");

}

sub init{
	my $self = shift;

	## Create the timer
	$EventTimerObj = EventTimer->new($BotDatabaseFile, 'RocksBot');

	##	Create the PrivacyFilter
	if ($privacy_filter_enable){
		$PrivacyFilter = PrivacyFilter->new({ BotDatabaseFile=>$BotDatabaseFile,
				sql_pragma_synchronous=>$sql_pragma_synchronous,
				SpeedTraceLevel => $SpeedTraceLevel });
	}

	##
	##	Create the IRC object
	##
	$irc = POE::Component::IRC->spawn(
		username => $username, 
   	nick => $BotName,
	   ircname => $ircname,
  	 server  => $server,
		Flood => $FloodProtectionDisabled
	) or die "Couldn't start POE::IRC. wtf? $!";

	##
	##	Create an array of CommandHandler threads
	##

	# the options to pass the CH on creation
	my $ch_options = {
		ConfigFile => $config_file
	};

	for (my $i=0; $i<$num_worker_threads; $i++){
		my $ch = POE::Component::Generic->spawn(
			package => 'modules::CommandHandler',
			object_options => [$ch_options],
			alias => "ch$i",
			debug => 0,		
			verbose => 1,	#Shows child's stderr
			options => { trace => 0 },
		) or die "cant create CH!";

		push @CH, {available=>0, alias=> "ch$i", ch=>$ch };
	}

	##
	## Auth with NickServ if nickserv password was supplied
	##
	if ($nickserv_password){
		$irc->plugin_add( 'NickServID', POE::Component::IRC::Plugin::NickServID->new(
   		  Password => $nickserv_password
		));
	}

	##
	## Join channels after authenticating with NickServ
	## 
	$irc->plugin_add('AutoJoin', POE::Component::IRC::Plugin::AutoJoin->new( Channels => \@channels ));
	$irc->yield(register => qw(join));
	$irc->yield(connect => { } );


	##
	##	Create the IRC POE session
	##

	POE::Session->create(
   	 package_states => [
      	  $self => [ qw(_default _start irc_001 irc_public irc_msg irc_ping irc_join 
						irc_part irc_quit irc_ctcp_version irc_ctcp_action 
						ch_result ch_output ch_startup_complete ch_plugin_loaded 
						ch_stats timerTick _stop ) ],
	    ],
   	 heap => { irc => $irc },
	);

	##
	##	Daemonize
	##

	if ($daemonize){
		open(SELFLOCK, "<$0") or die("Couldn't open $0: $!\n");
		flock(SELFLOCK, LOCK_EX | LOCK_NB) or die("Aborting: another instance is already running\n");
		open(STDOUT, ">>", $daemon_logfile) or die("Couldn't open logger output file: $!\n");
		open(STDERR, ">&STDOUT") or die("Couldn't redirect STDERR to STDOUT: $!\n");
		$| = 1; 
		chdir('/');
		exit if (fork());
		exit if (fork());
		sleep 1 until getppid() == 1;
		my @t = localtime(time);
		print "\n\n=====================================================\n";
		printf("pid $$ started at %02d:%02d on %d-%02d-%02d\n", $t[2], $t[1], $t[5]+1900, $t[4]+1, $t[3] );
		print "=====================================================\n";
		open hOUT, ">$daemon_pidfile";
		print hOUT "$$\n";
		close hOUT;
	}


	##
	## Run the POE kernel
	##

	$poe_kernel->run();


	##
	## See ya, suckers
	##

	exit;
}

sub timerTick{
	my $now = time();

	if ($EventTimerObj->tick()){

		my $events = $EventTimerObj->getEvents();

		foreach my $e (@{$events}){

			my $opts = {
				command => $e->{command},
				options => $e->{options},
				channel => $e->{channel},
				nick	  => $e->{nick},
				mask	  => $e->{mask},
				origin  => $e->{origin}
			};

			runBotCommand( $opts );
		}
	}

	$_[KERNEL]->delay(timerTick => 1);
}

sub irc_join{
	my ($event, $args) = @_[ARG0 .. $#_];
	my ($nick, $mask) =  split /!/, $event;
	my $channel = $args;

	print theTime() . "irc_join Who: $event Channel:$args\n";

	return if ($nick eq $BotName);

	my $opts = {
		irc_event => 'irc_join',
		options => "",
		channel => $channel,
		nick	  => $nick,
		mask	  => $mask
	};

	runBotCommand( $opts );
}

sub irc_ping{
	my ($sender, $who, $where, $what) = @_[SENDER, ARG0 .. ARG2];

	my $opts = {
		irc_event => 'irc_ping',
		options => "",
		channel => '',
		nick	  => UA_INTERNAL,
		mask	  => UA_INTERNAL 
	};

	runBotCommand( $opts );

}

sub irc_quit{
	my ($event, $args) = @_[ARG0 .. $#_];
	my ($nick, $mask) =  split /!/, $event;
	print theTime() . "irc_quit Who: $event Message:$args\n";

	my $opts = {
		irc_event => 'irc_quit',
		options => "$args",
		channel => '',
		nick	  => $nick,
		mask	  => $mask
	};

	runBotCommand( $opts );
}

sub irc_part{
	my ($event, $args) = @_[ARG0 .. $#_];
	my ($nick, $mask) =  split /!/, $event;
	print theTime() . "irc_part Who: $event Channel:$args\n";

	my $opts = {
		irc_event => 'irc_part',
		options => "",
		channel => $args,
		nick	  => $nick,
		mask	  => $mask
	};

	runBotCommand( $opts );

}

sub _stop{
	print theTime() . "STOP\n";
	#print Dumper (@_);
	print $@;
}

sub _start {
   my $heap = $_[HEAP];

    # retrieve our component's object from the heap where we stashed it
    $irc = $heap->{irc};

    $irc->yield( register => 'all' );
    $irc->yield( connect => { } );

    return;
}

sub irc_001 {
	my $sender = $_[SENDER];

	# Since this is an irc_* event, we can get the component's object by
	# accessing the heap of the sender. Then we register and connect to the
	# specified server.

	my $irc = $sender->get_heap();

	print "Connected to ", $irc->server_name(), "\n";

	## Do inital plugin startup stuff

	$CH[0]->{ch}->doPluginBotStart({event=>'ch_startup_complete'});

	return;
}

sub ch_startup_complete {
	print "All Plugins have run onBotStart(). Only once.\n";

	for (my $i=0; $i<@CH; $i++){
		$CH[$i]->{ch}->loadPluginInfo({event=>'ch_plugin_loaded'});
	}
}

sub ch_plugin_loaded{
	my ($kernel, $sender, $heap, $ref, $result) = @_[KERNEL, SENDER, HEAP, ARG0, ARG1];
	my ($alias) = $kernel->alias_list($sender);
	print "CH $alias has loaded plugin info and is reporting for duty.\n";
	freeCommandHandler($alias, 'init');
	
	#start the timer
	$_[KERNEL]->delay(timerTick => 5);
}


##
##  Private Message Handling
##	 Funnel all PM's through runBotCommand as if they were commands.
##  (i.e. no command prefix required)
##

sub irc_msg {
	my ($sender, $who, $where, $what) = @_[SENDER, ARG0 .. ARG2];
	my $nick = ( split /!/, $who )[0];
	my $mask = ( split /!/, $who )[1];

	# for PM's, the channel is the botname
	my $channel = $where->[0];

	## don't print lines containing "password" to stdout. privacy, yo.
	if ($what=~/pass/){
		print theTime() . "PM: pass* containing line from $who\n";
	}else{
		print theTime() . "PM: $channel | who: $who | what: $what\n";
	}

	## Strip the command prefix, if included
	$what=~s/^\Q$BotCommandPrefix\E//;

	# the first word is treated as a command
	if ($what=~/^([a-zA-Z0-9._]+)\b/){
		my $cmd = $1;
		my $options = "";

		# anything following first word is an option
		if ($what=~/^$cmd (.+?)$/){
			$options = $1;
		}
	
		my $opts = {
			command => $cmd,
			irc_event => 'irc_msg',
			options => $options,
			channel => $nick,
			nick	  => $nick,
			mask	  => $mask,
			filter_applied => 0
		};

		runBotCommand( $opts );
	}
}

sub ch_stats{
	my ($kernel, $sender, $heap, $ref, $result) = @_[KERNEL, SENDER, HEAP, ARG0, ARG1];
	my ($alias) = $kernel->alias_list($sender);

	my $output = BOLD.$alias . ": ".NORMAL;
	$output.= "Total Runs: " . $result->{num_runs};
	$output.= " Commands: " . $result->{num_commands};
	$output.= " Regex: " . $result->{num_regex};

		my $opts = {
			channel => $result->{channel},
			nick	  => $result->{nick},
			output  => $output,
			delimiter=> " ",
			suppress_nick => 1,
			mask=> $result->{mask}
		};

		printOutput($opts);
}

sub irc_public {
	my ($sender, $who, $where, $what) = @_[SENDER, ARG0 .. ARG2];
	my $nick = ( split /!/, $who )[0];
	my $mask = ( split /!/, $who )[1];
	my $channel = $where->[0];

	print theTime() . "$channel| who: $who | what: $what\n";

	## 
	## Command Prefix Commands
	##

	# if it starts with the CP followed by a word, it's a command

	if ($what eq $BotCommandPrefix . 'chstats'){
		foreach my $ch (@CH){
			$ch->{ch}->getStats({event=>'ch_stats'}, $channel, $nick, $mask);
		}
	}

	if ($what=~/^\Q$BotCommandPrefix\E([a-zA-Z0-9._]+)\b/){

		my $cmd =  $1;
		my $options = "";

		# anything following first word is an option
		if ($what=~/^\Q$BotCommandPrefix\E$cmd (.+?)$/){
			$options = $1;
		}

		my $opts = {
			command => $cmd,
			irc_event => 'irc_public',
			options => $options,
			channel => $channel,
			nick	  => $nick,
			mask	  => $mask,
			filter_applied => 0
		};

		runBotCommand( $opts );

		return;  
	}

	return if ($nick eq $BotName);

	## run each line through a CH to do preg matches and whatnot
	my $opts = {
		irc_event => 'irc_public',
		options => $what,
		channel => $channel,
		nick	  => $nick,
		mask	  => $mask
	};

	runBotCommand( $opts );
			
}


# We registered for all events, this will produce some debug info.
sub _default {
	my ($event, $args) = @_[ARG0 .. $#_];
	my @output = ( "$event: " );

     for my $arg (@$args) {
         if ( ref $arg eq 'ARRAY' ) {
             push( @output, '[' . join(', ', @$arg ) . ']' );
         }
         else {
             push ( @output, "'$arg'" );
         }
     }
     print theTime() . join ' ', @output, "\n";
		
     return;
}


sub irc_ctcp_action{
	my ($sender, $who, $where, $what) = @_[SENDER, ARG0 .. ARG2];
	my $nick = ( split /!/, $who )[0];
}


sub irc_ctcp_version{
	my ($sender, $who, $where, $what) = @_[SENDER, ARG0 .. ARG2];
	my $nick = ( split /!/, $who )[0];

	$irc->yield(notice=> $nick=> "RocksBot v".$VERSION." Perl IRC Bot. http://is.gd/rocksbot");
}




## 
## OUTPUT - CTCP Actions
##

sub printOutputAction{
	my $opts = shift;
	my $channel = $opts->{channel};
	my $nick = $opts->{nick};
	my $output = $opts->{output};
	my $mask = $opts->{mask};

	if ($privacy_filter_enable){
		my $filtered = $PrivacyFilter->filter($output);
		if ($filtered eq ''){
			print "Killing output line per PrivacyFilter rules: $output\n";
			return;
		}
		$output = $filtered;
	}

	
	$irc->yield(ctcp => $channel => 'ACTION ' . $output);
}

## 
## Output - Regular irc_msg.   split it if necessary
##

sub printOutput{
	my $opts = shift;
	
	my $channel = $opts->{channel};
	my $nick = $opts->{nick};
	my $output = $opts->{output};
	my $delimiter = $opts->{delimiter} || " ";
	my $suppress_nick = $opts->{suppress_nick};
	my $mask = $opts->{mask};

	if ($privacy_filter_enable){

		if ($channel!~m/^#/ && ($nick eq $BotOwnerNick)){
			# do not filter bot owner's commands in PM's. Otherwise there'd
			# be no way to view the filter stuff.
		}else{
		
			my $filtered = $PrivacyFilter->filter($output);
			if ($filtered eq ''){
				print "Killing output line per PrivacyFilter rules: $output\n";
				return;
			}
			$output = $filtered;
		}
	}

	
	## use bytes / no bytes used b/c counting unicode and ~s// are at odds

	## Max length of a raw IRC message is 512,
	## POE::Component shortens them to 450 - length(nick)
	## We can never be sure how long the user@mask string will be
	## Length of _{X more line} message is usually 15 chars 
	## When we include the nick prefix, we should shorten by that amt plus 2

	my $max_length = 400;

	if (!$suppress_nick){
		$max_length -= (length($nick) +2);
	}

	my $mm_length = 15;
	my $mystr = "";
	my @msgs = ();
	my $line_num=0;

	if ($delimiter && $output=~/\Q$delimiter/){
		my @lines = split /\Q$delimiter/, $output;

		use bytes;	
		for (my $i=0; $i<@lines;$i++){
			if (  (length($mystr) + length ($lines[$i])) > $max_length) {
				$mystr=~s/ +$//;

				my $ss = quotemeta($delimiter);
				$mystr=~s/$ss$//;
				push(@msgs, $mystr);
				$mystr = $lines[$i];

			}else{
				if ($mystr){
					$mystr .= $delimiter . $lines[$i];
				}else{
					$mystr =  $lines[$i];
				}
			}
		}
		no bytes; 

		$mystr=~s/ +$//;
		my $ss = quotemeta($delimiter);
		$mystr=~s/$ss$//;
		$mystr=~s/^$ss//;
		push(@msgs, $mystr);
	
	}else{
		use bytes;
		for (my $i=0; $i<length($output); $i++){
			my $mychar = substr($output, $i, 1);

			if ($mychar eq " " ){
				if (length($mystr) > $max_length){
					push(@msgs, $mystr);
					$mystr = "";
				}
			}
			$mystr .= $mychar;
		}
		no bytes;
		push(@msgs, $mystr);
	}

	my $line = shift (@msgs);

	use bytes;
	if (@msgs){
		if (@msgs == 1){
			if (length($msgs[0]) <= $mm_length){
				$line .= $delimiter . shift @msgs;
			}else{
				$line .= " {".(@msgs)." ".$BotCommandPrefix."more line}";
			}
		}else{
			$line .= " {".(@msgs)." ".$BotCommandPrefix."more lines}";
		}
	}

	if ($suppress_nick){
		$irc->yield( privmsg => $channel => "$line" );

	}else{
		$irc->yield( privmsg => $channel => "$nick: $line" );
	}

	
	if (@msgs){
		my $message = "";

		foreach $line (@msgs){
			$message .= $delimiter . $line;
		}

		my $opts = {
			command => '_saveMore',
			options => $message,
			channel => $channel,
			nick	  => $nick,
			mask	  => $mask,
			no_flags=> 1,
			no_pipes=>1,
			filter_applied => 0,
			origin => "internal"
		};

		runBotCommand( $opts );
	}
}

##
## Called when CommandHandler Returns Data
##
sub ch_output{
	my ($kernel, $sender, $heap, $ref, $result) = @_[KERNEL, SENDER, HEAP, ARG0, ARG1];

	#print "\n------printing output OUTPUT--------------\n";
	#print Dumper($result);

	#print "----------------- ref -------------------------\n";
	#print Dumper ($ref);

	my ($alias) = $kernel->alias_list($sender);

	my $channel =	$result->{channel};
	my $nick = 		$result->{nick};
	my $mask = 		$result->{mask};
	my $command = 		$result->{command};
	my $output = $result->{output};
	my $delimiter = $result->{delimiter};
	my $suppress_nick = $result->{suppress_nick};
	my $return_type = $result->{return_type};
	my $reentry_command= $result->{reentry_command} || '';
	my $reentry_options= $result->{reentry_options} || '';
	my $yield_command= $result->{yield_command} || '';
	my $yield_args = $result->{yield_args} || '';
	my $filter_applied = $result->{filter_applied} || '';
	my $refresh_timer = $result->{refresh_timer} || 0;

	#print "Sender is $alias\n";
	#print "Channel is $channel\n";
	#print "Nick is $nick\n";
	#print "----------------- end -------------------------\n";

	## free the command handler if it doesnt have a waiting reentry command.
	if (!$reentry_command){
		freeCommandHandler($alias, $command);
	}

	if ($refresh_timer){
		print "------> Refreshing timer\n";
		$EventTimerObj->update();
	}
	
	if ($output){
		if ($return_type eq 'action'){
			my $opts = {
				channel => $channel,
				nick	  => $nick,
				output  => $output,
				mask	  => $mask
			};
			printOutputAction($opts);

		}elsif ($return_type eq 'text'){
			my $opts = {
				channel => $channel,
				nick	  => $nick,
				output  => $output,
				delimiter=> $delimiter,
				suppress_nick => $suppress_nick,
				mask=> $mask
			};

			printOutput($opts);

		}elsif ($return_type eq 'irc_yield'){
			print "Executing command $yield_command\n";
			print "Args:\n";
			#print Dumper ($yield_args);
    		$irc->yield( $yield_command => @{$yield_args} );

			my $opts = {
				channel => $channel,
				nick	  => $nick,
				output  => $output,
				delimiter=> $delimiter,
				suppress_nick => $suppress_nick,
				mask => $mask
			};

			printOutput($opts);


		}elsif ($return_type eq 'shutdown'){
			my $opts = {
				channel => $channel,
				nick	  => $nick,
				output  => $output,
				delimiter=> $delimiter,
				suppress_nick => $suppress_nick,
				mask => $mask
			};

			printOutput($opts);
	
			my @t = localtime(time);
			print "\n\n=====================================================\n";
			printf("pid $$ stopped at %02d:%02d on %d-%02d-%02d\n", $t[2], $t[1], $t[5]+1900, $t[4]+1, $t[3] );
			print "=====================================================\n";
			if ($daemonize){
				unlink $daemon_pidfile;
			}
			exit;

		}elsif ($return_type eq 'reloadPrivacyFilter'){

			if ($privacy_filter_enable){
				$PrivacyFilter->init();
			}

			my $opts = {
				channel => $channel,
				nick	  => $nick,
				output  => $output,
				delimiter=> $delimiter,
				suppress_nick => $suppress_nick,
				mask => $mask
			};

			printOutput($opts);

		}elsif ($return_type eq 'reloadPlugins'){
			# Should probably check these to make sure they're not busy, huh?
			# Meh, it'll probably be fine.  We'll see.
			for (my $i=0; $i<@CH; $i++){
				$CH[$i]->{ch}->loadPluginInfo({event=>'ch_result'});
			}

			my $opts = {
				channel => $channel,
				nick	  => $nick,
				output  => $output,
				delimiter=> $delimiter,
				suppress_nick => $suppress_nick,
				mask => $mask
			};

			printOutput($opts);

		
		}elsif ($return_type eq 'runBotCommand'){
			my $options = $output;
			$options=~s/^ +//;
			$options=~s/^(\w+)\b//;
			my $cmd = $1;

			print "RUNNING CMD:$cmd, OPTIONS:$options\n";

			my $opts = {
				command => $cmd,
				options => $options,
				channel => $channel,
				nick	  => $nick,
				mask	  => $mask,
				origin  => 'internal',
				filter_applied => $filter_applied
			};

			runBotCommand( $opts );
		}
	}

	## We didn't free the CH if $reentry_command was set, just so this can happen.
	if ($reentry_command){
		my $ch = getCommandHandler($alias);
		$ch->setValue({event=>'ch_result'},"command", $reentry_command);
		$ch->setValue({event=>'ch_result'},"options", $reentry_options);
		$ch->setValue({event=>'ch_result'},"origin", 'internal');
		$ch->Execute({event=>'ch_output'});
	}
}

##
## Generic callback.
##
sub ch_result{
	my ($kernel, $sender, $heap, $ref, $result) = @_[KERNEL, SENDER, HEAP, ARG0, ARG1];

	if( $ref->{error} ) {
		#die join(' ', @{ $ref->{error} } . "\n");
	}

	#print "ch_result: $result\n";
}


##
##	Manage the Command Handlers
##
sub freeCommandHandler{
	#my $self = shift;
	my $alias = shift;
	my $command = shift;

	for (my $i=0; $i<@CH; $i++){
		if ($CH[$i]->{alias} eq $alias){
			$CH[$i]->{available} = 1;
			return 1;
		}
	}

	print "Could not mark $alias as available\n";
	return 0;
}

sub getCommandHandler{
	#my $self = shift;
	my $alias = shift;

	for (my $i=0; $i<@CH; $i++){

		# if asking by name, return that one
		# dont check the available flag, assume caller know what it's doing
		# b/c this called by reentry commands
		if ($alias){
			if ($CH[$i]->{alias} eq $alias){
				$CH[$i]->{available} = 0;
				return $CH[$i]->{ch};
			}

		#else return next available handler
		}else{
			if ($CH[$i]->{available}){
				$CH[$i]->{available} = 0;
				return $CH[$i]->{ch};
			}
		}
	}
	return 0;
}


##
##	Pass the command to a CommandHandler
##
sub runBotCommand{
	#my $self = shift;
	my $opts = shift;
	my $cmd = $opts->{command};
	my $options = $opts->{options};
	my $channel =$opts->{channel};
	my $nick = $opts->{nick};
	my $mask = $opts->{mask};
	my $filter_applied = $opts->{filter_applied} || 0 ;
	my $no_flags = $opts->{no_flags} || 0;
	my $no_pipes = $opts->{no_pipes} || 0;
	my $origin = $opts->{origin} || 'public';
	my $irc_event = $opts->{irc_event} || '';

	my $output = "";

	my ($limit, $limit_msg) = rateLimit($opts);
	if ($limit){
		my $popts = {
			channel => $channel,
			nick	  => $nick,
			output  => $limit_msg,
			mask    => $mask
		};

		printOutput($popts);

		return; 
	}

	eval{

		my $ch = getCommandHandler();

		if (!$ch){

			$output = "I'm busy now.";

			my $opts = {
				channel => $channel,
				nick	  => $nick,
				output  => $output,
				mask    => $mask
			};

			if ($cmd){
				printOutput($opts);
			}

			return;
		}

		## First arg must be a hashref for POE to work

		$ch->setValue({event=>'ch_result'}, "no_flags", $no_flags);
		$ch->setValue({event=>'ch_result'}, "irc_event", $irc_event);
		$ch->setValue({event=>'ch_result'}, "no_pipes", $no_pipes);
		$ch->setValue({event=>'ch_result'}, "command", $cmd);
		$ch->setValue({event=>'ch_result'}, "options", $options);
		$ch->setValue({event=>'ch_result'}, "channel", $channel);
		$ch->setValue({event=>'ch_result'}, "nick", $nick);
		$ch->setValue({event=>'ch_result'}, "mask", $mask);
		$ch->setValue({event=>'ch_result'}, "filter_applied", $filter_applied);
		$ch->setValue({event=>'ch_result'}, "origin", $origin);

		$output = $ch->Execute({event=>'ch_output'});
	};

	if ($@){
		print $@;

		my $opts = {
			channel => $channel,
			nick	  => $nick,
			output  => $output,
		};
		printOutput($opts);

		return 1;
	}
}

sub rateLimit{
	my $opts = shift;

	## Don't subject non-commands to rate limiting. (ie regex matches & irc events)
	if (!$opts->{command}){
		return (0, "");
	}

	# Don't subject internal commands to rate limiting. This applies to timer events,
	# saveMore, and also to any user-entered command coming via pipe. The pipe thing
	# might not be the best idea, but whaddyagonnado
	if (defined($opts->{origin}) && $opts->{origin} eq 'internal'){
		return 0;
	}

	if (!defined($user_commands{$opts->{nick}})){
		$user_commands{$opts->{nick}} = [];
	}

	# remove entries older than time window
	my @newarr;
	foreach my $entry (@{$user_commands{$opts->{nick}}}){
		if ($entry->{timestamp} > (time() - $command_window)){
			# remove this entry
			push @newarr, $entry;
		}
	}
	$user_commands{$opts->{nick}} = \@newarr;

	# add this entry
	my $copy = $opts;
	$copy->{timestamp} = time();
	push @{$user_commands{$opts->{nick}}}, $copy;
	
	# special: if the command is login, timeout sooner.
	if ($opts->{command} eq 'login'){
		my $count = 0;
		foreach my $entry (@{$user_commands{$opts->{nick}}}){
			$count++ if ($entry->{command} eq 'login');
		}
		return (1, "You've tried to login too many times. Wait a minute before trying again.") if ($count > 4);
	}
	
	my $count = @{$user_commands{$opts->{nick}}};
	if ($count > $command_max){
		print theTime() . "Rate limiting user $opts->{nick} in channel $opts->{channel}. ";
		print "$count commands in the past $command_window seconds.\n";
		return (1, "You've sent me more than $command_max commands in the past $command_window seconds. Don't do that.");
	}else{
		return (0, "");
	}
}


sub theTime{
	my @t = localtime(time);
	return sprintf("[%02d:%02d:%02d] ", $t[2], $t[1], $t[0]);
}
1;
