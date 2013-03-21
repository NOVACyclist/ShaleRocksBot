package plugins::Time;
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
use modules::EventTimer;
use constant EventTimer => 'modules::EventTimer';
use Date::Manip;
use POSIX;

use Data::Dumper;

sub getOutput {
	my $self = shift;
	my $output = "";
	my $options = $self->{options};
	my $cmd = $self->{command};
	my $nick = $self->{nick};
	my ($num, $unit, $sched_command, $sched_options, $seconds);

	my $mult = { second=> 1, minute=>60, hour=>3600, day=>86400};

	#return ($self->help($cmd)) if ($options eq '');

	##
	## cron - manage scheduled recurring jobs
	##

	if ($cmd eq 'cron'){
		my $secs = $self->hasFlagValue("seconds");
		my $mins = $self->hasFlagValue("minutes");
		my $hours = $self->hasFlagValue("hours");
		my $cmdstr = $self->hasFlagValue("command");
		my $channel = $self->hasFlagValue("channel") || $self->{channel};

		## creating this with this name will trigger the bot to reload the EventTimer data
		$self->{EventTimerObj} = EventTimer->new($self->{BotDatabaseFile}, 'Time');

		##
		## list existing jobs
		##
		if ($self->hasFlag("list")){
			my @jobs = $self->{EventTimerObj}->getCronJobs();

			foreach my $j (@jobs){
				$output.='['.$j->{job_id}.'] '. "secs=$j->{job_sec} mins=$j->{job_min} hours=$j->{job_hour} ";
				$output.="command=\"$j->{command} $j->{options}\" ";
				$output.="channel=$j->{channel}  ";
			}

			return $output;
		}


		##
		## add a new cron job
		##
		if ($self->hasFlag("add")){
			return "You need to use the -seconds=<seconds> flag" if (!defined($secs));
			return "You need to use the -minutes=<minutes> flag" if (!defined($mins));
			return "You need to use the -hours=<hours> flag" if (!defined($hours));
			return "You need to use the -command=<command> flag" if (!$cmdstr);

			my ($jcommand, $jopts) = split / /, $cmdstr, 2;

			my $args = {
			  sec=> $secs,
			  min=> $mins,
			  hour=> $hours,
			  command => $jcommand,
			  options => $jopts,
			  channel => $channel
			};

			$self->scheduleCronJob($args);
	
			return "Job scheduled";
		}


		##
		##	delete a cron job
		##
		if (my $num = $self->hasFlagValue("delete")){
			if ($self->{EventTimerObj}->deleteCronJob($num) == 1){
				return "Deleted cron job #$num";
			}else{
				return "Error deleting cron job #$num. Are you sure it exists?";
			}
		}
		
		return $self->help($cmd);
	}



	##
	## in - remind peeps of things in a certain amount of time
	##

	if ($cmd eq 'in'){
		
		if ($options!~s/^([0-9]+) +//){
			return $self->help($cmd);
		}
		$num = $1;

		if ($options!~s/^(hour|minute|second|day)(s*)\b//){
			return $self->help($cmd);
		}

		$unit= $1;
		my $s = $2;
		
		$seconds = $num * $mult->{$unit};
		my $now = time();

		my $date = new Date::Manip::Date;
		$date->parse("epoch " . ($now + $seconds) );
		my $when;
		if ($seconds > 60 * 60 * 24){
			$when = $date->printf("%i:%M:%S %p (%Z), %B %e, %Y");
		}else{
			$when = $date->printf("%i:%M:%S %p %Z");
		}

		$when=~s/^ //;

		if (my $cmdstr = $self->hasFlagValue("command")){
			($sched_command, $sched_options) = split / /, $cmdstr, 2;
			$output = "OK, $nick. Will run $sched_command in $num $unit$s. ($when)";

		}else{
			$sched_command = '_internal_echo';
			$sched_options = $options;
			$output = "OK, $nick. Will remind you in $num $unit$s. ($when)";
		}
	
		my $timer_args = {
			timestamp => ($now + $seconds),
			command => $sched_command,
			options => $sched_options,
			desc => 'via "in" command.'
		};

		$self->scheduleEvent($timer_args);

		return $output;
	}



	##
	## at - remind peeps of things at a certain time
	##

	if ($cmd eq 'at'){
		
		if ($options!~s/^([0-9]+):([0-9]+)//){
			return $self->help($cmd);
		}
		my $sched_hour = $1;
		my $sched_min = $2;
		
		my $now = time();

		my ($secs, $mins, $hours, $day, $month, $year, $dow, $dst)= localtime(time);
		
		## assume today, but if that time has already passed, assume tomorrow
		my $at  = POSIX::mktime (0, $sched_min, $sched_hour, $day, $month, $year);

		if ($now > $at){
			$at += 60*60*24;
		}

		my $verify_text;
		my $diff = int(($at - $now) / 60);

		if ($diff > 120){
			my $hours = int($diff / 60);
			my $minutes =  $diff % 60;
			$verify_text = "($hours hours and $minutes minutes from now.)";
		}else{
			$verify_text = "($diff minutes from now)";
		}
	
		if (my $cmdstr = $self->hasFlagValue("command")){
			($sched_command, $sched_options) = split / /, $cmdstr, 2;
			$output = "OK, $nick. Will run $sched_command at $sched_hour:$sched_min. $verify_text";

		}else{
			$sched_command = '_internal_echo';
			$sched_options = $options;
			$output = "OK, $nick. Will remind you at $sched_hour:$sched_min. $verify_text";
		}
	
		my $timer_args = {
			timestamp => $at,
			command => $sched_command,
			options => $sched_options,
			desc => 'via "in" command.'
		};

		$self->scheduleEvent($timer_args);

		return $output;
	}



	##
	##	tock
	##
	
	if ($cmd eq 'tock'){
		my $url = "http://tycho.usno.navy.mil/cgi-bin/timer.pl";
		my $short_url = "http://is.gd/usnotime";
		my $page = $self->getPage($url);
		my @lines = split /\n/, $page;
		my $ss;

		if ($options){
			$ss = $options;	
		}else{
			$ss = "Central";	
		}

		foreach my $line (@lines){
			if ($line=~/$ss/i){
				$line=~s/<.+?>//gis;
				$line=~s/\s+?/ /gis;
				return $line . ", according to ".UNDERLINE.$short_url.NORMAL;
			}
		}

		if ($options){
			return ("Couldn't find that time zone. I'm looking here: ".UNDERLINE.$short_url.NORMAL);
		}else{
			return ("Hmm. No data. Maybe there was a problem contacting ".UNDERLINE.$short_url.NORMAL);
		}
	}

	##
	##	time
	##
	
	if ($cmd eq 'time'){
		my $date = new Date::Manip::Date;
		$date->parse("now");
		return "Official $self->{BotName} time is " . $date->printf("%i:%M:%S %p (%Z), %B %e, %Y");
	}

	##
	##	yi
	##

	if ($cmd eq "yi"){

		my $c = $self->getCollection(__PACKAGE__, 'yi');
		my @records = $c->getAllRecords();

		my $quads = int(time() / 1753200);
		my $remainder = time() % 1753200;
		my $raels = $quads * 4;
		my $extraraels = int($remainder / 432000);

		if ($extraraels != 4){
			if (@records){
				$self->returnType("reloadPlugins");
				foreach my $rec (@records){
					$c->delete($rec->{row_id});
				}
			}

			return "Not yet..."
		}

		if (!@records){
			$c->add("yi");
			$self->returnType("reloadPlugins");
		}

		return "Yes! PARTAI!";
	}


	##
	##	boobies
	##

	if ($cmd eq "boobies"){

		my $c = $self->getCollection(__PACKAGE__, 'yi');
		my @records = $c->getAllRecords();
		my $quads = int(time() / 1753200);
		my $remainder = time() % 1753200;
		my $raels = $quads * 4;
		my $extraraels = int($remainder / 432000);

		if ($extraraels != 4){
			if (@records){
				$self->returnType("reloadPlugins");
				foreach my $rec (@records){
					$c->delete($rec->{row_id});
				}
			}
			return "nope";
		}

		return "Usage: boobies <some text>" if (!$self->{options});

		my $boob = "\x{2299}";
		$options=~s/o/$boob/gis;
		$options=~s/0/$boob/gis;

		return $options;

	}

	##
	##	benchmark - do speed tests
	##
	
	if ($cmd eq "benchmark"){
		$self->setReentryCommand("_benchmark");
		return "Performing speed benchmarks...";
	}

	if ($cmd eq "_benchmark"){
		$self->clearReentryCommand();
		$self->suppressNick("true");

		use Time::HiRes qw/ time sleep /;
		my $num_inserts = 20;

		$output = "(sql_pragma_synchronous is $self->{sql_pragma_synchronous}) ";
		my $c = $self->getCollection(__PACKAGE__, '::temp::');

		# do inserts
		my $start = time();
		for (my $i = 0; $i < $num_inserts; $i++){
			$c->add('test record');
		}
		my $time =  sprintf("%.4f", time() - $start);
		my $each = sprintf("%.4f", $time / $num_inserts);
		$output .= BOLD."$num_inserts db inserts:".NORMAL." $time sec ($each sec/ea). ";

		
		# do collection loads 
		$start = time();
		for (my $i = 0; $i < $num_inserts; $i++){
			my $c = $self->getCollection(__PACKAGE__, '::temp::');
		}
		$time =  sprintf("%.4f", time() - $start);
		$each = sprintf("%.4f", $time / $num_inserts);
		$output .= BOLD."$num_inserts collection loads:".NORMAL." $time sec ($each sec/ea). ";
		

		# do updates  
		$start = time();
		my @records = $c->getAllRecords();
		foreach my $rec (@records){
			$c->updateRecord($rec->{row_id}, {val1=>'hey good lookin', val2=>'whatcha got cookin'});
		}
		$time =  sprintf("%.4f", time() - $start);
		$each = sprintf("%.4f", $time / $num_inserts);
		$output .= BOLD."$num_inserts db updates:".NORMAL." $time sec ($each sec/ea). ";


		# do deletes
		$start = time();
		@records = $c->getAllRecords();
		foreach my $rec (@records){
			$c->delete($rec->{row_id});
		}
		$time =  sprintf("%.4f", time() - $start);
		$each = sprintf("%.4f", $time / $num_inserts);
		$output .= BOLD."$num_inserts db deletes:".NORMAL." $time sec ($each sec/ea). ";

	
		# get pages
		$start = time();
		my @pages = ('www.google.com', 'www.yahoo.com', 'www.wikipedia.org', 'www.amazon.com');
		foreach my $url (@pages){
			my $page = $self->getPage('http://' . $url);
		}
		$time =  sprintf("%.4f", time() - $start);
		$each = sprintf("%.4f", $time / @pages);
		$output .= BOLD.@pages." http:// page grabs:".NORMAL." $time sec ($each sec/ea). ";
		

		# calculate pi
		$start = time();
		my ($cycles, $i, $yespi, $pi) = (0,0,0,0);
		$cycles = 1000000;
		while ($i < $cycles) {
			my ($x, $y, $cdnt) = 0;
			$x = rand;
			$y = rand;
			$cdnt = $x**2 + $y**2;
			if ($cdnt <= 1) {
				++$yespi;
			}
			++$i;
		}	
	
		$time =  sprintf("%.4f", time() - $start);
		$pi = ($yespi / $cycles) * 4;
		$output .= BOLD."Calculate \x{03C0} (Monte Carlo method), $cycles iterations".NORMAL." $time sec (ans: $pi).";
		
		return $output;

	}
}


sub listeners{
	my $self = shift;
	
	##	Which commands should this plugin respond to?
	## Command Listeners - put em here.  eg [qw (cmd1 cmd2 cmd3)]
	my $commands = [qw(at in tock time yi cron benchmark)];

	my @irc_events = [qw () ];

	## Example:  ["/^$self->{BotName}/i",  '/hug (\w+)\W*'.$self->{BotName}.'/i' ]
	## The only modifier you can use is /i
	my @preg_matches = [qw () ];

	my $default_permissions =[ {command=>"cron", require_group => UA_ADMIN},
		{command=>'_benchmark', require_group => UA_INTERNAL}
	];

	my $quads = int(time() / 1753200);
	my $remainder = time() % 1753200;
	my $raels = $quads * 4;
	my $extraraels = int($remainder / 432000);
	if ($extraraels == 4){
		push @$commands, 'boobies';
	}

	return {commands=>$commands, permissions=>$default_permissions, irc_events=>@irc_events, preg_matches=>@preg_matches};

}

##
## addHelp()
##	The help system will pull from here using PluginBaseClass->help(key).
##
sub addHelp{
	my $self = shift;
	$self->addHelpItem("[plugin_description]", "Some time related functions.");
   $self->addHelpItem("[in]", "Perform a task in the future.  Usage: in <number> <seconds|minutes|hours|days> <what you want to be reminded about>  (or [-command=\"<command>\"]).  If you don't specify a command, $self->{BotName} will assume you wanted a reminder.");
   $self->addHelpItem("[at]", "Perform a task in the future.  Usage: at HH:MM <what you want to be reminded about> (or [-command=\"<command>\"]).  If you don't specify a command, $self->{BotName} will assume you wanted a reminder.");
 #  $self->addHelpItem("[scheduled_tasks]", "View the scheduled tasks.");
   $self->addHelpItem("[time]", "Get the current time and date.");
   $self->addHelpItem("[tock]", "Get the current time and date from the USNO Master Clock. Usage: tock [<U.S. time zone>]");
   $self->addHelpItem("[cron]", "Schedule recurring jobs. flags: -list -add -delete=<job_id>. When creating, use -seconds=<seconds> -minutes=<minutes> -hours=<hours> -channel=<channel> -command=\"commmand and arguments\".  Time format can be a number, * (for all), or a comma separated list, ala 0,20,40.  Cron jobs run as the system user, NOT as the user who created them.");
   $self->addHelpItem("[benchmark]", "benchmark: Perform bot speed benchmarks.");
}
1;
__END__
