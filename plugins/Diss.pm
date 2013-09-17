package plugins::Diss;
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

##
##	This module is an example of a module that can create new commands.
##	It also loads sample data using perl's special __DATA__ thingy.
##

use base qw (modules::PluginBaseClass);
use modules::PluginBaseClass;
use strict;
use warnings;

use Data::Dumper;

my @types;

sub onBotStart{
   my $self = shift;

	## Create default entries. Only do it the first time this plugin ever runs.

	my $c = $self->getCollection(__PACKAGE__, ':options');
	my @records = $c->matchRecords({val1=>'first_run_complete'});
	return if (@records);
	
	# mark as complete so we don't run this again.
	$c->add("first_run_complete");

	$c = $self->getCollection(__PACKAGE__, ':types');
	@records = $c->matchRecords({val1=>"diss"});
	if (!@records){
		$c->add('diss', 'action', $self->{BotName});
	}

	@records = $c->matchRecords({val1=>"pickup"});
	if (!@records){
		$c->add('pickup', 'text', $self->{BotName});
	}

	@records = $c->matchRecords({val1=>"miss"});
	if (!@records){
		$c->add('miss', 'action', $self->{BotName});
	}

	my @data = <DATA>;
	while (my $line = shift @data){
		chomp $line;
		my ($type, $text, $num) = split /\//, $line;
		next if (!$type || !$text || !$num);
		my $c = $self->getCollection(__PACKAGE__, $type);
		$c->add($text, $num, $self->{BotName});
		print "Diss module added data: type:$type, $text\n";
	}
}

sub plugin_init{
	my $self = shift;
	$self->returnType("text");
	$self->suppressNick(1);

	my $c = $self->getCollection(__PACKAGE__, ':types');

	my @records = $c->getAllRecords();

	foreach my $rec (@records){
		push @{$self->{types}}, {type=>$rec->{val1}, return_type=>$rec->{val2}};
	}

	return $self;	
}

sub getOutput {

	my $self = shift;
	my $output = "";
	my $options = $self->{'options'};
	my $cmd = $self->{command};
	my $type = $cmd;

	my $c = $self->getCollection(__PACKAGE__, $cmd);


	##
	##	Show specific #
	##

	if (my $num = $self->hasFlagValue("show")){

		my @records = $c->matchRecords({ display_id => $num});
		if (@records == 1){
			return ("[$num][added by ".$records[0]->{val3}."] " . $records[0]->{val1} );
	
		}else{
			return "Something went wrong.  Maybe that record ID doesn't exist?";
		}
   }


	##
	##	Search
	##

	if (my $term = $self->hasFlagValue("search")){

	#	if ( $options eq "" ){
	#		return $self->help($cmd);
	#	}
	
		my $num_records = $c->numRecords();

		my @records = $c->searchRecords($term, 1);

		if (!@records){
			return ("I know $num_records ".$type." and nothing matches.  Quit talkin jibberish.");
	
		}else{
			$output = "Matching records: ";
			foreach my $rec (@records){
				$output.= "[" .$rec->{display_id} . "]";
			}
			return $output;
		}
   }


	##
	## Add
	##

	if ($self->hasFlag("add")){

		if ( $options eq "" ){
			return $self->help($cmd);
		}

		my %nums;

		while ($options=~/\{([0-9]+)\}/gis){
			$nums{$1} = 1;
		}
		my @n = keys(%nums);
		my $count = @n;

		my $display_id = $c->add($options, $count, $self->accountNick());
		return "added #$display_id to the collection:  $options";
	}


	##
	##	Delete
	##

	if ($self->hasFlag("delete")){
	
		return $self->help($cmd, '-delete') if (!(my $num = $self->hasFlagValue("delete")));

		my @records = $c->matchRecords({ display_id => $num});

		if (@records == 1){

			if (!$self->hasPermission($records[0]->{val3})){
				return ("You can only delete records that you added");

			}else{
				$c->delete($records[0]->{row_id});
				return ("baleeted #$num. ($records[0]->{row_id})");
			}

		}else{
			return "Couldn't find that $type";
		}
   }

		
	##
	##	New Type
	##

	if (my $newtype =  $self->hasFlagValue("newtype")){
		#return $self->help($cmd, '-newtype');

		my $rt = $self->hasFlagValue("return_type");
		$rt = 'action' if ($rt ne 'text');

		foreach my $type (@{$self->{types}}){
			if ($newtype eq $type->{type}){
				return "That type already exists";
			}
		}

		if ($newtype =~/^\:/){
			return "Command must start with an alpha-numeric character.";
		}

		if ($newtype =~/^_/){
			if (!$self->hasFlag("force")){
				return "Command can't start with an underscore.";	
			}
		}


		my $c = $self->getCollection(__PACKAGE__, ':types');
		$c->add($newtype, $rt, $self->accountNick());

		$self->returnType("reloadPlugins");
		$output = "New type created. Now add something to the collection.  ";
		$output.= $self->{BotCommandPrefix}.$newtype." -add";
		return $output;
	}


	##
	##	Remove Type
	##

	if (my $rmtype =  $self->hasFlagValue("rmtype")){

		my $found = 0;
		foreach my $type (@{$self->{types}}){
			if ($rmtype eq $type->{type}){
				$found=1;
			}
		}

		if (!$found){
			return "That type doesn't appear to exist.";
		}

		my $c = $self->getCollection(__PACKAGE__, ':types');	
		my @records = $c->matchRecords({val1=>$rmtype});
		$c->delete($records[0]->{row_id});
	
		$c = $self->getCollection(__PACKAGE__, $rmtype);	
		@records = $c->getAllRecords();
		foreach my $rec (@records){
			$c->delete($rec->{row_id});
		}

		$self->returnType("reloadPlugins");
		$output = "$rmtype removed.";
		return $output;
	}



	##
	##	default
	##
	#if ($options!~/(.+?)$/ && !$self->hasFlag("force")){
	#	return $self->help($cmd);
	#}

	my $target;
	if ($options=~/(.+?)$/){
		$target = $1;
	}else{
		$target = "";
	}

	my $req = "";
	if ($target =~s/^#([0-9]+) //){
		$req = $1;
	}

	my @targets = split (/ and /, $target);
	my $num_targets = @targets;
	my $diss;

	if ($req){
		my @records = $c->matchRecords({display_id=>$req});
		if (@records){
			$diss = $records[0]->{val1};
		}else{
			return "Couldn't find that $type. Sorry. $target will have to wait.";
		}


	}else{
		my @records = $c->matchRecords({val2=>$num_targets});

		if (@records){
			my $rn = int(rand(@records));
			$diss = $records[$rn]->{val1};
		}else{
			if (@targets){
				return "I don't know nuthin bout dat.";
			}else{
				return $self->help($cmd);
			}
		}
	}

	for (--$num_targets; $num_targets >=0; $num_targets--){
		$diss=~s/\{$num_targets\}/$targets[$num_targets]/gis;
	}

	foreach my $t (@{$self->{types}}){
		if ($type eq $t->{type}){
			$self->returnType($t->{return_type});
		}
	}

	return $diss;
}



sub listeners{
	my $self = shift;
	my @commands = ();
   my @default_permissions;

	push @default_permissions, {command=>"PLUGIN", flag=>"newtype", require_group=>UA_TRUSTED};
	push @default_permissions, {command=>"PLUGIN", flag=>"rmtype", require_group=>UA_TRUSTED};
	push @default_permissions, {command=>"PLUGIN", flag=>"force", require_group=>UA_ADMIN};
	foreach my $type (@{$self->{types}}){
		push @commands, $type->{type};

		#push @default_permissions, {command=>$type->{type}, flag=>'newtype', require_group=>UA_ADMIN};
		#push @default_permissions, {command=>$type->{type}, flag=>'rmtype', require_group=>UA_ADMIN};
	}

   return {commands=>\@commands, permissions=>\@default_permissions};
}


sub addHelp{
   my $self = shift;
	
   $self->addHelpItem("[plugin_description]", "Compliment or Diss people.  Add new entries using the -add flag. Those with permission can create new types (and the associated new commands) using the -newtype flag.");

	foreach my $type (@{$self->{types}}){
		
		$self->addHelpItem("[$type->{type}]", "Usage: $type->{type} [#<number>] <target> [and <target>] Available flags: add, delete, show, search, newtype, rmtype");
	   $self->addHelpItem("[$type->{type}][-add]", "Usage example: $type->{type} -add makes yo mama jokes about {0}'s mother.  Use {0} {1}... to specify targets.");
		$self->addHelpItem("[$type->{type}][-delete]","Delete a $type->{type} from the $type->{type} database.  Usage: $type->{type} -delete=<diss number>");
		$self->addHelpItem("[$type->{type}][-show]","Show a $type->{type}.  Usage: $type->{type} -show=<number>");
		$self->addHelpItem("[$type->{type}][-search]","Usage: $type->{type} -search <text to search for>");
		$self->addHelpItem("[$type->{type}][-newtype]","Usage: $type->{type} -newtype=<trigger> -return_type=<text or action>.  Use -force to allow commands to start with an underscore.");
		$self->addHelpItem("[$type->{type}][-rmtype]","Remove a type from the system. This will delete all of the data associated with that type as well.  Usage: $type->{type} -rmtype=<trigger>");
	}
}

1;
__DATA__
diss/eats crackers in {0}'s bed./1
diss/tells yo mama jokes about {0}'s mama's mama./1
diss/knocks {0} and {1}'s heads together, Three Stooges style./2
diss/makes fun of {0}'s preferred operating system./1
miss/makes {0} a mixtape./1
miss/pines for {0}/1
miss/calls his local radio station and dedicates 'Wish You Were Here' to {0}/1
miss/writes poetry in {0}'s honor/1
miss/mopes about in his bathrobe, wondering what {0} is up to/1
miss/keeps checking {0}'s Facebook page for new activity/1
miss/composes a poem for {0} and sends it via SMS./1
pickup/{0}, you had me at "Hello World."/1
pickup/I just had to come over and talk to {0} and {1}. Sweetness is my weakness./2
pickup/My name isn't Elmo, but {0}, you can tickle me any time you want to./1
pickup/Are you lost {0}? Because heaven is a long way from here./1
pickup/I was wondering if you had an extra heart, {0}.   Mine seems to have been stolen./1
pickup/If I had a star for every time {0} brightened my day, I'd have a galaxy in my hand./1
pickup/If a thousand painters worked for a thousand years, they could not create a work of art as beautiful as {0}./1
pickup/Are you from Tennessee, {0}? Because you're the only ten I see!/1
pickup/Excuse me {0}, but I think you dropped something. MY JAW!/1
pickup/I'm not actually this tall, {0}. I'm sitting on my wallet./1
pickup/Were you in the Scouts, {0}? Because you sure have tied my heart in a knot./1
