package plugins::Countdown;

use strict;			
use warnings;
## All plugins extend modules::PluginBaseClass.  You need this.
use base qw (modules::PluginBaseClass);
use modules::PluginBaseClass;
use Data::Dumper;
use Time::Local;

sub getOutput {
	my $self = shift;

	## This are listed for your convenience.  Feel free to delete if you don't
	## need them, or if you'd prefer to use the $self->{terminology}

	my $cmd = $self->{command};			# the command
	my $options = $self->{options};		# everything else on the line, except flags
	my $output = "";
	$self->returnType("text");		
	$self->suppressNick(1);	
	

	my $c = $self->getCollection(__PACKAGE__, 'timers');

	if ($self->hasFlag("create")){
		#my ($sec, $min, $hour, $day, $month, $year, $id, $title);
		my $sec = $self->hasFlagValue("sec");
		my $min = $self->hasFlagValue("min");
		my $hour = $self->hasFlagValue("hour");
		my $day = $self->hasFlagValue("day");
		my $month = $self->hasFlagValue("month");
		my $year = $self->hasFlagValue("year");
		my $id= $self->hasFlagValue("id");
		my $title= $self->hasFlagValue("title");

		return "You need to spcify -sec= " if (!$self->hasFlag("sec"));
		return "You need to spcify -min= " if (!$self->hasFlag('min'));
		return "You need to spcify -hour= " if (!$self->hasFlag('hour'));
		return "You need to spcify -day= " if (!$self->hasFlag('day'));
		return "You need to spcify -month= " if (!$self->hasFlag('month'));
		return "You need to spcify -year " if (!$self->hasFlag('year'));
		return "You need to spcify -id= " if (!$self->hasFlag('id'));
		return "You need to spcify -title= " if (!$self->hasFlag('title'));


		## check if id already exists
		my @records = $c->matchRecords({val1=>$id});
		return ("A counter with the ID $id already exists.  Delete it or pick another id.") if (@records > 0);


		## create countdown
		$c->add($id, $title, $sec, $min, $hour, $day, $month, $year, $self->accountNick());

		return "Countdown $title ($id) has been created.  Access it using ".$self->{BotCommandPrefix}."countdown $id, or create a handy alias";
	}
				

	if ($self->hasFlag("delete")){
		my $id= $self->hasFlagValue("delete") || return "You must specify an ID.";

		my @records = $c->matchRecords({val1=>$id});
		return ("A countdown with the ID $id does not exist") if (@records == 0);
		
		if (!$self->hasPermission($records[0]->{val9})){
			return "You don't have permission to do that.";
		}

		$c->delete($records[0]->{row_id});
		return "Countdown $id deleted.";

	}

	if ($self->hasFlag("list")){
		my @records = $c->getAllRecords();
		foreach my $rec (@records){
			$self->addToList("$rec->{val1} ($rec->{val2} by $rec->{val9})", $self->BULLET);
		}

		my $list = $self->getList();
		if ($list){
			return "A list of countdowns: " . $list;
		}else{
			return "No countdowns have been defined.";
		}
		
	}

	return $self->help($cmd) if (!$options);

	print "options is |$options|\n";
	my @records = $c->matchRecords({val1=>$options});
	return ("A countdown with the ID $options does not exist") if (@records == 0);

	my @today = localtime();
	my $time = timelocal(@today);

	my @et = ($records[0]->{val3}, $records[0]->{val4}, $records[0]->{val5}, $records[0]->{val6} , $records[0]->{val7} - 1, $records[0]->{val8});
	my $bbtime = timelocal(@et);
	
	my $tsecs = ($bbtime - $time);
	my $days = int($tsecs/(60*60*24));
	my $hours = int(($tsecs - ($days * 60 * 60 * 24)) / (60 * 60));
	my $minutes =  int(($tsecs -  (($days * 60 * 60 * 24) + $hours * 60 * 60)) / 60);
	my $secs = ($tsecs -  (($days * 60 * 60 * 24) + $hours * 60 * 60 + $minutes * 60)) ;

	return BOLD.RED."$days days $hours hours $minutes minutes $secs seconds until ".BLACK.$records[0]->{val2}.NORMAL;
}


sub listeners{
	my $self = shift;
	
	##	Which commands should this plugin respond to?
	## Command Listeners - put em here.  eg [qw (cmd1 cmd2 cmd3)]
	my @commands = [qw(countdown)];

	## Values: irc_join irc_ping irc_part irc_quit
	## Note that irc_quit does not send channel information, and that the quit message will be 
	## stuck in $options
	my @irc_events = [qw () ];

	## Example:  ["/^$self->{BotName}/i",  '/hug (\w+)\W*'.$self->{BotName}.'/i' ]
	## The only modifier you can use is /i
	my @preg_matches = [qw () ];

	## Works in conjuntion with preg_matches.  Match patterns in preg_matches but not
	## these patterns.  example: ["/^$self->{BotName}, tell/i"]
	my @preg_excludes = [ qw() ];

	my $default_permissions =[
	];

	return { commands=>@commands,
		permissions=>$default_permissions,
		irc_events=>@irc_events,
		preg_matches=>@preg_matches,
		preg_excludes=>@preg_excludes
	};

}

##
## addHelp()
##	The help system will pull from here using PluginBaseClass->help(key).
##
sub addHelp{
	my $self = shift;
	$self->addHelpItem("[plugin_description]", "Define countdown timers to different events.");
   $self->addHelpItem("[countdown]", "Usage: countdown <id>, countdown -list, countdown -delete=<id>, countdown -create -sec=<#> -min=<#> -hour=<#> -month=<#> -day=<#> -year=<#> id=<identifier> title=\"<title>\"");
}
1;
__END__
