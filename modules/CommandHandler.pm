package modules::CommandHandler;
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
use Data::Dumper;

use modules::Collection 1.0;
use constant Collection => 'modules::Collection';
use modules::UserAuth 1.0;
use constant UserAuth => 'modules::UserAuth';
use modules::Utilities 1.0;

use Config::Simple;
use Text::ParseWords;
use Module::Reload;
use Time::HiRes qw/ time /;

BEGIN {
  $modules::CommandHandler::VERSION = '1.0';
}


my $match;				# The matched command
my @match_arr;			# The matched commands
my @return_messages; # Stack em up, yo
my $obj;					# The plugin object will be created if matched
my @plugins;
my %plugin_info;			# Commands we're listening for. Populated startup in new()

my $init_options;		# Contains the cfg filename, which will be read when CH inits.
							# This only happens at bot startup

my $UserAuthObj;		# 

## From the config file
my $ConfigFile;
my $BotCommandPrefix;
my $BotDatabaseFile;	
my $BotName;		
my $EnablePipes;
my $BotOwnerNick;			
my $plugin_ignore_arr;
my $publish_module;
my $privacy_filter_enable;

## Some internal bookkeeping
my $filter_applied;
my $no_flags;
my $no_pipes;
my $origin;

my $sql_pragma_synchronous;
my $SpeedTraceLevel; # 0 off.  1 = CH command only.  2 CH command and regex matches 3. PluginBaseClass 4. Collections
my %run_stats;
my @run_stats_msgs;

my $num_runs;
my $num_commands;
my $num_regex;

sub new {
	my $class = shift;
	my $self = bless {}, $class;

	$self->{init_options} = shift;
	$self->{EnablePipes} = 0;
	$self->{num_runs} = 0;
	$self->{num_commands} = 0;
	$self->{num_regex} = 0;

	$self->cleanup();
	$self->readConfig();
	#$self->loadPluginInfo();
	return $self;
}


sub readConfig{
	my $self=shift;
	
	## Read Config File
	my $cfg = new Config::Simple();
	$cfg->read($self->{init_options}->{ConfigFile}) or die "Can't find config file";

	# while we're here....
	$self->{BotDatabaseFile} = $cfg->param("BotSettings.DatabaseFile");
	$self->{BotCommandPrefix} = $cfg->param("BotSettings.CommandPrefix") || '.';
	$self->{BotName} = $cfg->param("ConnectionSettings.nickname");
	$self->{EnablePipes} = $cfg->param("BotSettings.EnablePipes") || 1;
	$self->{BotOwnerNick} = $cfg->param("BotSettings.BotOwnerNick") || 'who knows';
	$self->{SpeedTraceLevel} = $cfg->param("BotSettings.SpeedTraceLevel") || 0;
	$self->{privacy_filter_enable} = $cfg->param("BotSettings.privacy_filter_enable");
	$self->{sql_pragma_synchronous} = $cfg->param("BotSettings.sql_pragma_synchronous");
	if (!defined($self->{sql_pragma_synchronous})){
		$self->{sql_pragma_synchronous} = 1;
	}
	$self->{publish_module} = $cfg->param("BotSettings.publish_module") || 'modules::Publish';

	my $ignore = $cfg->param("BotSettings.plugin_ignore_list");
	if(ref($ignore) eq 'ARRAY'){
		$self->{plugin_ignore_arr} = $ignore;
	}else{
		push @{$self->{plugin_ignore_arr}}, $ignore;
	}
}


sub loadPluginInfo{
	my $self=shift;
	#print "Enter loadPluginInfo\n";

	delete($self->{plugin_info});

	my $cfg = new Config::Simple();
	$cfg->read($self->{init_options}->{ConfigFile}) or die "Can't find config file";

	Module::Reload->check;

	my @ilist;
	foreach my $ex (@{$self->{plugin_ignore_arr}}){
		print "adding plugins::$ex to exclude list - will not be loaded\n";
		push @ilist, 'plugins::' . $ex; 
	}
	
	delete($self->{plugins});
	my @dirs = ('plugins', 'plugins_sys');
	foreach my $dir (@dirs){
		opendir(my $dh, $dir) || die "Can't open $dir: $!";
		while (readdir $dh){
			my $file = $_;
			next if ($file=~/^\_/);
			next if ($file=~/^\./);
			next if ($file!~/\.pm$/);
			next if ($file ~~ @ilist);
			$file =~s/\.pm//gis;
			push @{$self->{plugins}}, $dir .'::'. $file;
		}
		closedir ($dh);
	}
	
	foreach my $name (@{$self->{plugins}}){
		eval "CORE::require $name";
		if ($@){
			print "Error requiring $name - plugin not loaded\n$@\n";
			next;
		}else{
			#print "Plugin $name loaded\n";
		}

		my $short_name = (split(/:/, $name))[2];

		my $hash = $cfg->param(-block=>'Plugin:'.$short_name);
		$hash->{BotName} = $self->{BotName};
		$hash->{BotCommandPrefix} = $self->{BotCommandPrefix};
		$hash->{BotDatabaseFile} = $self->{BotDatabaseFile};
		$hash->{BotOwnerNick} = $self->{BotOwnerNick};
		$hash->{PackageShortName} = $short_name;
		$hash->{SpeedTraceLevel} = $self->{SpeedTraceLevel};
		$hash->{sql_pragma_synchronous} = $self->{sql_pragma_synchronous};
		$hash->{publish_module} = $self->{publish_module};
		$hash->{privacy_filter_enable} = $self->{privacy_filter_enable};

		$self->{UserAuthObj} = $self->UserAuth->new($self->{BotDatabaseFile}, 
				 UA_INTERNAL, UA_INTERNAL, $self->{sql_pragma_synchronous});

		#create object & get its listeners
		my $plugin = $name->new($hash, $self->{UserAuthObj});
		
		#my @listeners = $plugin->listeners();
		my $ret = $plugin->listeners();
		my $listeners = $ret->{commands} || [];
		my $permissions = $ret->{permissions} || [];
		my @irc_events = $ret->{irc_events} || [];
		my @preg_matches = $ret->{preg_matches} || [];
		my @preg_excludes = $ret->{preg_excludes} || [];
		
		## Make the plugin listen for its own name so it can process -help & -settings
		push @{$listeners}, $short_name;
	
		## Push the settings permissions flag for each plugin if not defined.
		my $found = 0;
		foreach my $p (@{$permissions}){
			if (defined ($p->{command}) && defined($p->{flag})){
				if ($p->{command} eq 'PLUGIN' && $p->{flag} eq 'settings'){
					$found = 1;
				}
			}
		}

		if (!$found){
			push @{$permissions}, {require_group=>UA_ADMIN, command=>'PLUGIN', flag=>'settings'}; 
		}

		$self->{plugin_info}->{$short_name} = 
		{commands=>$listeners, package=>$name, init_options=>$hash, 
			package_short_name=>$short_name, permissions=>$permissions, 
			irc_events=>@irc_events, preg_matches=>@preg_matches, 
			preg_excludes=>@preg_excludes, has_settings=>$plugin->hasSettings()};
	}

	$self->loadPluginPermissions();
	$self->cleanup();
	print "Plugin info loaded\n";
}



# CommandHandler|permissions|1$plugin|2require|3$command|4$flag|5$req_group|6$req_users
sub loadPluginPermissions{
	my $self = shift;
	my $c = $self->Collection->new({db_file=>$self->{BotDatabaseFile}, module_name=>'CommandHandler',
         collection_name=>'permissions', keep_stats=>$self->{SpeedTraceLevel},
			sql_pragma_synchronous=>$self->{sql_pragma_synchronous}  });
	$c->load();

	## Do REQUIRE permissions
	my @records = $c->matchRecords({val2=>"require"});
	
	foreach my $rec (@records){
		my $p = $rec->{val1};
		my $command = $rec->{val3};
		my $flag = $rec->{val4};
		my $group = $rec->{val5};
		my $users = $rec->{val6};
		my @users_arr = split /,/, $users;

		# we have not loaded this plugin
		next if (!defined($self->{plugin_info}->{$p}));

		my $matched =0;
		foreach my $ecommand (@{$self->{plugin_info}->{$p}->{permissions}}){
			if ($ecommand->{command} eq $command){

				if (defined($ecommand->{flag})){
					next if ($ecommand->{flag} ne $flag);
				}

				$ecommand->{require_group} = $group;

				$ecommand->{require_users} = \@users_arr;
				$matched = 1;
			}
		}

		# this permission didn't already exist, we have to create it.
		if (!$matched){
			push @{$self->{plugin_info}->{$p}->{permissions}}, 
				{command=>$command, require_group=>$group, require_users => \@users_arr};
		}
	}

	
	## Do ALLOW permissions
	@records = $c->matchRecords({val2=>"allow"});
	
	foreach my $rec (@records){
		my $p = $rec->{val1};
		my $command = $rec->{val3};
		my $flag = $rec->{val4};
		my $group = $rec->{val5};
		my $users = $rec->{val6};
		my @users_arr = split /,/, $users;

		# we have not loaded this plugin
		next if (!defined($self->{plugin_info}->{$p}));

		my $matched =0;
		foreach my $ecommand (@{$self->{plugin_info}->{$p}->{permissions}}){
			if ($ecommand->{command} eq $command){

				if (defined($ecommand->{flag})){
					next if ($ecommand->{flag} ne $flag);
				}

				$ecommand->{allow_users} = \@users_arr;
				$matched = 1;
			}
		}

		# this permission didn't already exist, we have to create it.
		if (!$matched){
			push @{$self->{plugin_info}->{$p}->{permissions}}, 
				{command=>$command, allow_group=>$group, allow_users => \@users_arr};
		}
	}


	##
	## Disable commands & plugins specified by user
	##

	$c = $self->Collection->new({db_file=>$self->{BotDatabaseFile}, module_name=>'CommandHandler',
         collection_name=>'disable', keep_stats=>$self->{SpeedTraceLevel}, 
			sql_pragma_synchronous=>$self->{sql_pragma_synchronous}});
	$c->load();
	@records = $c->getAllRecords();
	foreach my $rec (@records){
		if (defined($self->{plugin_info}->{$rec->{val1}})){

			if ($rec->{val2} eq '*'){
				delete ($self->{plugin_info}->{$rec->{val1}});

			}else{
				@{$self->{plugin_info}->{$rec->{val1}}->{commands}} = grep { $_ ne $rec->{val2}} @{$self->{plugin_info}->{$rec->{val1}}->{commands}};
			}
		}
	}
	
}


## do inital plugin initiation stuff.
## We do this here instead of in the new method because multiple CommandHandlers
## are started, and we only want to run this once.
## This is triggered by the irc_001 event.

sub doPluginBotStart{

	my $self = shift;

	#print "Enter doPluginBotStart\n";

	# this is kinda messy, but there's no way around it.  we ned to load the plugin info
	# to be able to instantiate each plugin.  but we'd also like onBotStart to run only 
	# once. so we will load the plugin info for just one command handler from the main
	# rocksbot file, do the onBotStart routine, then reload the info later, after we 
	# run onBotStart()

	$self->loadPluginInfo();

	$self->{UserAuthObj} = $self->UserAuth->new($self->{BotDatabaseFile}, 
			 UA_INTERNAL, UA_INTERNAL, $self->{sql_pragma_synchronous});

	foreach my $plugin_name (keys $self->{plugin_info}){
		print "==> Init $plugin_name\n";
		my $p = $self->{plugin_info}->{$plugin_name}->{package}->new(
			$self->{plugin_info}->{$plugin_name}->{init_options}, $self->{UserAuthObj}
		);
		$p->setValue("BotPluginInfo", $self->{plugin_info});
		print "==> Run onBotStart() for $plugin_name\n";
		$p->onBotStart();
	}

	$self->cleanup();
	print "doPluginBotStart completed.\n";
}


sub setValue{
   my $self = shift;
   my ($key, $value) = @_; 

	if ($value){
		$value=~s/ +$//;
   	$self->{$key} = $value;
   	#print "---> I set $key to |$value|\n";
	}
}  

sub getValue{
	my $self = shift;

	my $key = shift;

	if ($self->{'obj'}){
		return $self->{'obj'}->getValue($key);

	}else{
		return " ";
	}

}

sub getStats{
	my $self = shift;
	my $channel = shift;
	my $nick = shift;
	my $mask = shift;

	my $ret = {
			num_runs=>$self->{num_runs},	
			num_commands=>$self->{num_commands},	
			num_regex=>$self->{num_regex},
			channel=>$channel,
			nick=>$nick,
			mask=>$mask,
		};
	return $ret;
}

##
##	The main thingy
##

sub Execute {
	my $self = shift;
	my $ret;
	my $output;

	$self->{num_runs}++;

	if ($self->{SpeedTraceLevel}){
		delete ($self->{run_stats});
		delete ($self->{run_stats_msgs});
		$self->{run_stats}->{CH}->{'start'} = time();
	}

	if ($self->{command} eq '_internal_echo'){
		## This is here because we can't always expect a module to have an echo command.
		$ret = $self->returnMessage($self->{options});
		$self->cleanup();
		return $ret;

	##
	##	Reentry to get next line of output
	##
		
	}elsif ($self->{command} eq '_dump'){
		if ($self->{options}){
			print Dumper ($self->{plugin_info}->{$self->{options}});
		}else{
			print Dumper ($self->{plugin_info});
		}

	}elsif ($self->{command} eq '_CH_NEXT_msg_' && $self->{origin} eq 'internal'){

		my $ret = shift ($self->{return_messages});

		if (@{$self->{return_messages}} ){
			$ret->{reentry_command} = '_CH_NEXT_msg_';
		}else{
			$self->cleanup();
		}
		return $ret;


	##
	##	 If we were passed a command, the user has used $CommandPrefx.$command (irc_public)
	##  Process as a command & don't match on other events. (eg strings or irc events)
	##	 OR this came from a PM window (irc_msg) and CommandPrefix was not required.
	##

	}elsif ($self->{command}){

		$self->handleCommand();

	##
	##	IRC events.  We have a nick, mask, and channel
	## irc_join irc_ping irc_part irc_quit
	##

	}elsif( ($self->{irc_event} ne 'irc_msg') && ($self->{irc_event} ne 'irc_public') ){

		$self->handleEvent();
	}


	##
	##	if printing run stats
	##

	if ($self->{SpeedTraceLevel}){
		$self->{run_stats}->{CH}->{end} = time();

		my $total_time = sprintf("%.3f", $self->{run_stats}->{CH}->{end} - $self->{run_stats}->{CH}->{start});
		print "vvvvvvvvvvvvvvvvvvvvvvvvvvvvv\n";
		print "$total_time\tcommand: $self->{command}\tevent: $self->{irc_event}\n";

		my $out = "";

		if ($self->{SpeedTraceLevel} > 1){
			foreach my $k (sort keys $self->{run_stats}){
				next if ($k eq 'CH');
				my $total_time = sprintf("%.3f", $self->{run_stats}->{$k}->{end} - $self->{run_stats}->{$k}->{start});
				$out.= "$k: $total_time \t ";
			}
			print "regex and event matches:\n$out\n" if ($out);
		}

		foreach my $msg (@{$self->{run_stats_msgs}}){
			print "\t$msg\n";
		}
		print "^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^\n";
	}


	## the event handlers will pile return messages up in a queue. process the queue

	if (defined ($self->{return_messages})){
		if (@{$self->{return_messages}}){

			my $ret = shift @{$self->{return_messages}};

			if (@{$self->{return_messages}}){
				if (!$ret->{reentry_command}){
					$ret->{reentry_command} = '_CH_NEXT_msg_';
				}else{
					#this command will already reenter.  let it be for now & return t
					# the queued messsages later
				}

				return $ret;

			}else{

				if (!$ret->{reentry_command}){
					$self->cleanup();
				}

				return $ret;
			}

		}else{
			my $ret = $self->returnMessage("");
			$self->cleanup();
			return $ret;
		}

	}else{
		my $ret = $self->returnMessage("");
		$self->cleanup();
		return $ret;
	}
}


sub handleEvent{

	my $self = shift;
	my $ret;
	my $output;

	## look for plugin matches to regexes & irc_events. Only call each once, 
	##  even if multiple matches.

	foreach my $k (keys $self->{plugin_info}){

		my %matched_plugins;

		## Match IRC Events that plugins have registered for
		foreach my $event (@{$self->{plugin_info}->{$k}->{irc_events}}){
			if ($event eq $self->{irc_event}){
				my $short_name = $self->{plugin_info}->{$k}->{package_short_name};
				if (!$matched_plugins{$short_name}){
					push @{$self->{match_arr}}, $self->{plugin_info}->{$k};
					$matched_plugins{$short_name} = 1;
				}
			}
		}

		## Match regular expressions that plugins have registered for
		foreach my $exp (@{$self->{plugin_info}->{$k}->{preg_matches}}){
			my $preg = $exp;
			my $has_match = 0;
			# Strip leading slashie
			$preg=~s#^/##;
	
			# Match any regex flags. Only supports i right now.
			# Because using a variable as a modifier is messy as all git out,
			my $modifiers="";
			$modifiers= $1 if ($preg=~s#/(.*?)$##);

			## check for match
			if ($modifiers=~/i/){
				$has_match = 1 if ($self->{options}=~m/$preg/i);
			}else{
				$has_match = 1 if ($self->{options}=~m/$preg/);
			}

			## now check for excludes & unmatch if that happens
			foreach my $exp (@{$self->{plugin_info}->{$k}->{preg_excludes}}){
				my $preg = $exp;
				$preg=~s#^/##;
				my $modifiers="";
				$modifiers= $1 if ($preg=~s#/(.*?)$##);
				if ($modifiers=~/i/){
					$has_match = 0 if ($self->{options}=~m/$preg/i);
				}else{
					$has_match = 0 if ($self->{options}=~m/$preg/);
				}
			}

			## only add if has_match is true. we had a match & we had no excludes
			if ($has_match){
				my $short_name = $self->{plugin_info}->{$k}->{package_short_name};
				if (!$matched_plugins{$short_name}){
					push @{$self->{match_arr}}, $self->{plugin_info}->{$k};
					$matched_plugins{$short_name} = 1;
				}
			}
		}
	}

	## create user auth obj - only once
	$self->{'UserAuthObj'} = $self->UserAuth->new($self->{BotDatabaseFile}, 
		 $self->{'nick'}, $self->{'mask'}, $self->{sql_pragma_synchronous});

	while (my $match = shift @{$self->{match_arr}}){

		if ($self->{SpeedTraceLevel} > 1){
			$self->{run_stats}->{$match->{package_short_name}}->{start} = time();
		}

		# create plugin object
		my $p = $match->{'package'};
		$self->{'obj'} = $p->new($match->{init_options}, $self->{UserAuthObj});

		$self->{'obj'}->setValue("command", $self->{'command'});
		$self->{'obj'}->setValue("options", $self->{'options'});
		$self->{'obj'}->setValue("nick", $self->{'nick'});
		$self->{'obj'}->setValue("irc_event", $self->{irc_event});
		$self->{'obj'}->setValue("channel", $self->{'channel'});
		$self->{'obj'}->setValue("mask", $self->{'mask'});
		$self->{'obj'}->setValue("no_flags", $self->{'no_flags'});
		$self->{'obj'}->setValue("no_pipes", $self->{'no_pipes'});

		$self->{num_regex}++;

		my @output_arr = $self->{'obj'}->run();

		if ($self->{SpeedTraceLevel}){
			my @rstemp = $self->{obj}->getStats();
			if (defined($self->{run_stats_msgs})){
				@{$self->{run_stats_msgs}} =  ( @{$self->{run_stats_msgs}}, @rstemp);
			}else{
				@{$self->{run_stats_msgs}} =  @rstemp;
			}
		}

		while (my $output = shift @output_arr){

			$ret = {
				nick=>$self->{'nick'}, 
				mask=>$self->{'mask'}, 
				channel=>$self->{obj}->{'channel'}, 
				command=> $self->{'command'},
				delimiter => $self->{obj}->outputDelimiter(),
   			suppress_nick => $self->{obj}->suppressNick(),
   			return_type => $self->{obj}->returnType(),
				reentry_command => $self->{obj}->getReentryCommand(),
				reentry_options => $self->{obj}->getReentryOptions(),
				yield_command => $self->{obj}->yieldCommand(),
				yield_args => $self->{obj}->yieldArgs(),
				filter_applied => $self->{filter_applied},
				refresh_timer =>	$self->{obj}->refreshTimer(),
				output => $output
			};

			#print Dumper ($ret);

			## not checking for output before pushing in case a plugin wants
			## to trigger an event of some sort.  But these events can't call 
			## their own reeentry events, b/c CH will override them with 
			## a _CH_NEXT_msg_ event. At least not if there's more than one registered.

			push @{$self->{return_messages}}, $ret;

		}

		if ($self->{SpeedTraceLevel} > 1){
			$self->{run_stats}->{$match->{package_short_name}}->{end} = time();
		}
	}
}


sub isCommand{
	my $self = shift;
	my $pcmd = shift;

	foreach my $k (keys $self->{plugin_info}){
		foreach my $cmd (@{$self->{plugin_info}->{$k}->{commands}}){
			if ($cmd eq $pcmd){
				return 1;
			}
		}
	}

	return 0;
}

sub handleCommand{

	my $self = shift;
	my $ret;
	my $output;

	##	Match the command
	
	# check for Plugin.command notation
	my ($pcommand, $pplugin);

	#print "Command is $self->{command}\noptions is $self->{options}\n";

	if ($self->{command}=~/\./){
		($pplugin, $pcommand) = split /\./, $self->{command};
		print "after split, $pplugin $pcommand\n";
		if (defined($self->{plugin_info}->{$pplugin})){	
			foreach my $cmd (@{$self->{plugin_info}->{$pplugin}->{commands}}){
				if ($cmd eq $pcommand){
					#found it
					$self->{match} = $self->{plugin_info}->{$pplugin};
					$self->{command} = $pcommand;
				}
			}
		}
	}

	
	# regular command match, only if not already matched on Plugin.command notation.
	my @matches;
	if (!$self->{match}){
		foreach my $k (keys $self->{plugin_info}){
			foreach my $cmd (@{$self->{plugin_info}->{$k}->{commands}}){
				if ($cmd eq $self->{command}){
					push @matches, $self->{plugin_info}->{$k};
					## xyzzy check for collisions here
				}
			}
		}

		if (@matches == 1){
			$self->{'match'} = $matches[0];
		}
	}


	if ($self->{'match'}){

		if (!$self->{'UserAuthObj'}){
			## Since CH now handles UserAuth, we have to create the UserAuthObj here
			##  and pass it to the plugin. Doing it only after a command matches 
			##  so it's not created for every line matched.  Maybe add an object cache here.
			

			if (!$self->{UserAuthObj}){
				$self->{'UserAuthObj'} = $self->UserAuth->new($self->{BotDatabaseFile}, 
				 $self->{'nick'}, $self->{'mask'}, $self->{sql_pragma_synchronous});
			}
		}

		# determine if user has permission to run this plugin/command
		if ($self->{origin} ne 'internal'){
			my $flags =  parseFlags($self->{options})->{flags};
			my ($allowed, $reason) = $self->{UserAuthObj}->hasRunPermission($self->{command}, $flags, $self->{match});
		
			if (!$allowed){
				$ret = $self->returnMessage("You don't have permission to do that.");
				push @{$self->{return_messages}}, $ret;
				return;
				#$self->cleanup();
				#return $ret;
			}
		}

		if (!$self->{'obj'}){
			## Only create new object if we dont already have one. If we already have one,
			## this call should be via a reentry, so we'll reuse the same object to preserve
			## its state

			my $p = $self->{'match'}->{'package'};

			$self->{'obj'} = $p->new($self->{match}->{init_options}, $self->{UserAuthObj});
		}

		my @tokens;
		my $str = "";
		my $seen_pipe=0;
		my @parts;

		if ($self->{EnablePipes} && !$self->{no_pipes}){
			## Only process pipes that aren't in quotation marks
			my $fpw = $self->{options};
			$fpw =~s/'/_BITEME_PARSELINES_/gis;
			@tokens = parse_line('\s+|\|',"delimiters", $fpw);

			for (my $i=0; $i<@tokens; $i++){
				$tokens[$i]=~s/_BITEME_PARSELINES_/'/g;

				if ($tokens[$i] eq '|'){

					## figure out if next word is a valid command
					for (my $j = $i+1; $j < @tokens; $j++){
						next if ($tokens[$j]=~/ +/);
						next if ($tokens[$j] eq '');

						if ($self->isCommand($tokens[$j])){
							$seen_pipe = 1;
							push @parts, $str;
							$str="";
							last;
						}else{
							last;
							# the word following the pipe was not a valid command
						}
					}
	
					if ($seen_pipe){
						next;
					}
				}

				$str.=$tokens[$i];
			}
			push @parts, $str;
			$self->{options} = shift @parts;
			#print "options is $self->{options}\n";
		}

		## Run the Plugin 

		$self->{num_commands}++;

		$self->{'obj'}->setValue("command", $self->{'command'});
		$self->{'obj'}->setValue("options", $self->{'options'});
		$self->{'obj'}->setValue("nick", $self->{'nick'});
		$self->{'obj'}->setValue("irc_event", $self->{irc_event});
		$self->{'obj'}->setValue("channel", $self->{'channel'});
		$self->{'obj'}->setValue("mask", $self->{'mask'});
		$self->{'obj'}->setValue("no_flags", $self->{'no_flags'});
		$self->{'obj'}->setValue("no_pipes", $self->{'no_pipes'});
		$self->{'obj'}->setValue("BotPluginInfo", $self->{plugin_info});

		my @output_arr = $self->{'obj'}->run();

		if ($self->{SpeedTraceLevel}){
			my @rstemp = $self->{obj}->getStats();
			if (defined($self->{run_stats_msgs})){
				@{$self->{run_stats_msgs}} =  ( @{$self->{run_stats_msgs}}, @rstemp);
			}else{
				@{$self->{run_stats_msgs}} =  @rstemp;
			}
		}

		while (my $output = shift @output_arr){
			# no pipe
			if (!$seen_pipe){
				$ret = {
					nick=>$self->{'nick'}, 
					mask=>$self->{'mask'}, 
					channel=>$self->{obj}->{'channel'}, 
					command=> $self->{'command'},
					delimiter => $self->{obj}->outputDelimiter(),
   				suppress_nick => $self->{obj}->suppressNick(),
   				return_type => $self->{obj}->returnType(),
					reentry_command => $self->{obj}->getReentryCommand(),
					reentry_options => $self->{obj}->getReentryOptions(),
					yield_command => $self->{obj}->yieldCommand(),
					yield_args => $self->{obj}->yieldArgs(),
					filter_applied => $self->{filter_applied},
					refresh_timer =>  $self->{obj}->refreshTimer(),
					output => $output
				};

				if (my $filter = $self->{obj}->outputFilter()){
					if (!($self->{filter_applied}) && (
						($ret->{return_type} eq 'text') || ($ret->{return_type} eq 'action'))){
						$ret->{return_type} = 'runBotCommand';

						if ($filter=~/\|/){
							$filter=~s/\|/$ret->{output} |/;
						}else{
							$filter= $filter . " " . $ret->{output};
						}

						$ret->{output} = $filter;
						$ret->{filter_applied} = 1;
					}
				}
	
			#dere be pipes here
			}else{

				my $next_command;
				if ($self->{obj}->returnType() eq 'runBotCommand'){
					$next_command = $output . ' | ' . shift (@parts);
				}else{
					$next_command = shift (@parts) . " " . $output;
				}

				for(my $i=0; $i<@parts; $i++){
					$next_command .= " | " . $parts[$i];
				}
	
				$ret = {
					nick=>$self->{'nick'}, 
					mask=>$self->{'mask'}, 
					channel=>$self->{obj}->{'channel'}, 
					command=> $self->{'command'},
					delimiter => $self->{obj}->outputDelimiter(),
   				suppress_nick => $self->{obj}->suppressNick(),
   				return_type => 'runBotCommand',
					reentry_command => $self->{obj}->getReentryCommand(),
					reentry_options => $self->{obj}->getReentryOptions(),
					yield_command => $self->{obj}->yieldCommand(),
					yield_args => $self->{obj}->yieldArgs(),
					filter_applied => $self->{filter_applied},
					refresh_timer =>  $self->{obj}->refreshTimer(),
					output => $next_command 
				};
			}

			if ($self->{obj}->getReentryCommand()){
				$self->{obj}->clearReentryCommand();
			}else{
				#	$self->cleanup();
			}

			push @{$self->{return_messages}}, $ret;

		} ##end while

		if ($self->{obj}->hasPM()){
			my $pm = $self->{obj}->getPM();
			
			my $ret = {
				nick=>$self->{'nick'}, 
				mask=>$self->{'mask'}, 
				channel=>$pm->{nick},
				command=> "",
				delimiter => "",
	  			suppress_nick => 0,
  				return_type => "text",
				reentry_command => "",
				reentry_options => "",
				yield_command => "",
				yield_args => "",
				filter_applied => "",
				refresh_timer => 0,
				output => $pm->{msg}
			};
		
			push @{$self->{return_messages}}, $ret;
		}

	}elsif (@matches > 1){
		my $msg = "The command $self->{command} appears in more than one package: ";
		my $comma = "";

		foreach my $match (@matches){
			$msg.=$comma . "$match->{package_short_name}.$self->{command}";
			$comma = ", ";
		}
		$msg.=". Specify the one you want to run using the Plugin.command notation, as noted.";
		$ret = $self->returnMessage($msg);
		push @{$self->{return_messages}}, $ret;


	}else{

		#$output = "Command Not Matched: Did not match $self->{command}";
		$ret = $self->returnMessage("");
	}

	#return ($ret);

}

sub returnMessage{
	my $self = shift;
	my $message = shift;

	my $ret = {
			nick=>$self->{'nick'}, 
			mask=>$self->{'mask'}, 
			channel=>$self->{'channel'}, 
			command=> "",
			delimiter => "",
  			suppress_nick => 0,
  			return_type => "",
			reentry_command => "",
			reentry_options => "",
			yield_command => "",
			yield_args => "",
			filter_applied => "",
			refresh_timer => 0,
			output => $message
	};

	if ($message){
		$ret->{return_type} = 'text';
	}

	return $ret;
}


sub cleanup{
	my $self = shift;

	delete ($self->{'match'});
	delete ($self->{'match_arr'});
	delete ($self->{'obj'});
	delete ($self->{channel});
	delete ($self->{nick});
	delete ($self->{mask});
	delete ($self->{UserAuthObj});
	
	if (defined ($self->{return_messages})){
		delete ($self->{return_messages});
	}

	$self->{filter_applied} = 0;
	$self->{no_pipes} = 0;
	$self->{no_flags} = 0;
	$self->{options}="";
	$self->{command}="";
	$self->{origin}="";
	$self->{irc_event} = "";
	
	#print Dumper($self);
	#print "Cleaned up\n";
}

1;
__END__
