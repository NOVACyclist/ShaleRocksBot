package plugins::Counter;
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
use base qw (modules::PluginBaseClass);
use modules::PluginBaseClass;
use Data::Dumper;


sub getOutput {
	my $self = shift;
	
	my $c = $self->getCollection(__PACKAGE__, $self->accountNick());

	if (! $self->hasPermission($self->accountNick()) ){
		return ("You don't have permission to do that.");
	}

	##
	##  No Arguments - print counters
	##


	if ( $self->hasFlag("list") || !$self->numFlags()){
		
		@records = $c->getAllRecords();
		foreach $counter (@records){
			my $counter_name = $counter->{'val1'};
			my $counter_val = $counter->{'val2'};
			$self->addToList($counter_name.": ".$counter_val, $self->BULLET);
		}
			
		if (@records){
			return ("Your counters: " . $self->getList());

		}else{
			return ("You don't have any counters. Use ".$self->{BotCommandPrefix}."counter -add=<name> -value=<value> to add one.");
		}


	##
	## add a counter 
	## 

	}elsif(my $counter_name = $self->hasFlagValue("create")){

		my $counter_val = $self->hasFlagValue("value") || 1;

		if ($counter_val ne ($counter_val + 0 )){
			return ("That didn't look like a number. ('$counter_val') Usage: ,counter set <CounterName> <value>");
		}

		my @records = $c->matchRecords({val1=>$counter_name});

		if (@records > 0){
			return("Looks like you already have a counter by that name. Use delete or add/subract to it.");
		}

		if ($counter_name=~/\W/){
			return "You can't use special characters in your counter name. Only letters and numbers."
		}

		$c->add($counter_name, $counter_val);

		return "added counter '$counter_name' with a value of $counter_val for ". $self->{'nick'}.".";


	##
	## all - see all counters of a particular type
	##	 

	}elsif($self->{'options'}=~/^all\b/){

		if ($self->{'options'}=~/^all\s+(\w+)\b/){
			$counter_name = $1;
			my $oc = $self->getCollection(__PACKAGE__, '%');

			my @records;

			if ($counter_name eq "list"){
				@records = $oc->getAllRecords();

				my %counter_list;
				foreach $counter (@records){
					my $counter_name = $counter->{'val1'};
					$counter_list{$counter_name}++;
				}
		
				my $ret = "All user counters: ";

				foreach $k (sort keys %counter_list){
					$ret.= $k . "(".$counter_list{$k}.") ";
				}

				if (@records){
					return ($ret);

				}else{
					return ("No one has a counter!");
				}
		

			}else{

				@records = $oc->matchRecords({val1=>$counter_name});

				my $ret = "$counter_name counters: ";

				foreach $counter (@records){

					my $counter_user = $counter->{'collection_name'};
					my $counter_name = $counter->{'val1'};
					my $counter_val = $counter->{'val2'};

					$ret .= "$counter_user: $counter_val".". ";

				}

				if (@records){
					return ($ret);

				}else{
					return ("No one has a counter called $counter_name.");
				}
	
			}
			

		}else{
			return ("To see everyone's counter of a particular type, do ',counter all <CounterName>'. To list all counters, do ',counter all list'");
		}


	##
	## user - see another user's counters
	##	 

	}elsif(my $username = $self->hasFlagValue("nick")){

		my $oc = $self->getCollection(__PACKAGE__, $username);
		my @records = $oc->getAllRecords();

		foreach $counter(@records){
			my $counter_name = $counter->{'val1'};
			my $counter_val = $counter->{'val2'};
			$self->addToList("$counter_name: $counter_val", $self->BULLET);
		}
			
		if (@records){
			return ($username."'s counters: " . $self->getList());
		}else{
			return ($username. " doesn't have any counters.");
		}



	##
	## delete a counter
	##	 

	}elsif(my $counter_name = $self->hasFlagValue("delete")){

		my @records = $c->matchRecords({val1=>$counter_name});

		if (@records){
			$c->delete(@records[0]->{row_id});
			return "Deleted counter $counter_name";

		}else{
			return ("Can't find a counter for you with that name.");
		}



	##
	##  ADD or SUBTRACT
	##

	}elsif( $self->{'options'}=~/^(\+|\-)/ ){

		my $action = $1;
		my $amt = "";

		my $counter_name ="";

		if ($self->{'options'}=~/^(\+|\-) (.+?)\b/){
			$counter_name = $2;
			$amt = 1;

		}elsif ($self->{'options'}=~/^(\+|\-)([\.0-9]+) (.+?)\b/){
			$amt= $2;
			$counter_name = $3;

		}else{
			return ("Usage: ,counter $action <CounterName>");
		}
	

		my @records = $c->matchRecords({val1=>$counter_name});

		if (@records == 1){

			my $counter_val = @records[0]->{'val2'};

			if ($action eq '+'){
				$counter_val+=$amt;

			}elsif($action eq '-'){
				$counter_val-=$amt;
			}

			if ($c->updateRecord(@records[0]->{'id'}, {val2 => $counter_val} )){
				return ("Counter '$counter_name' set to $counter_val.");

			}else{
				return ("There was an error updating that counter.");
			}

		}elsif(@records > 1){
			print "POSSIBLE ERROR - MORE THAN ONE RECORD\n";
			return ("Whoops, something went wrong. #4rpo");

		}else{
			return ("Can't find a counter for you with that name.  Use ',counter list' to list your current counters.");
		}


	##
	## Set Counter
	## 

	}elsif(my $counter_val = $self->hasFlagValue("set")){

		my $counter_name = $self->hasFlagValue("name");
		if (!$counter_name){
			return "bah";
		}

		if ($self->{'options'}=~/^\w+? (.+?)\b/){
			$counter_name = $1;

			if ($self->{'options'}=~/^\w+? (.+?) (.+?)$/){
				$counter_val= $2;
			}

		}else{
			return ("Usage: ,counter set <CounterName> <value>");
		}
	
		if ($counter_val eq ""){
			return ("Usage: ,counter set <CounterName> <value>");
		}

		if ($counter_val ne ($counter_val + 0 )){
			return ("That didn't look like a number. ('$counter_val') Usage: ,counter set <CounterName> <value>");
		}

		my @records = $c->matchRecords({val1=>$counter_name});

		if (@records == 1){

			if ($c->updateRecord(@records[0]->{'id'}, {val2 => $counter_val} )){
				return ("Counter $counter_name set to $counter_val.");

			}else{
				return ("There was an error updating that counter.");
			}

		}elsif(@records > 1){
			print "POSSIBLE ERROR - MORE THAN ONE RECORD\n";
			return ("Whoops, something went wrong. #4rpo");

		}else{
			return ("Can't find a counter for you with that name.  Use ',counter list' to list your current counters.");
		}



	##
	## show single counter by name
	##

	}elsif($self->{'options'}=~/^(\w+)\b/){
		my $counter_name = $1;
	
		my $ret="";
		my @records = ();

		my @records = $c->getAllRecords();

		foreach $counter (@records){

			if ($counter->{'val1'} eq $counter_name){

				my $counter_val = $counter->{'val2'};
				$ret .= "$counter_name: $counter_val.  ";
			}
		}

		if ($ret){
			return ($ret);

		}else{
			return ("You don't have a counter by that name.  Type ',counter list' to list your counters.");
		}
	}

}

sub listeners{
   my $self = shift;

   my @commands = [qw(counter)];

   my @irc_events = [qw () ];

   my @preg_matches = [qw () ];

   my $default_permissions = [{command=>"counter", require_users => ["$self->{BotOwnerNick}"] }];

   return {commands=>@commands, permissions=>$default_permissions,
      irc_events=>@irc_events, preg_matches=>@preg_matches};


}


sub addHelp{
   my $self = shift;
   $self->addHelpItem("[plugin_description]", "Make counters for things. Increment them. Decrement them. Great fun.");
   $self->addHelpItem("[counter]", ""); 
	$self->addHelpItem("[counter][-create]", "Create a new counter.");
	$self->addHelpItem("[counter][-list]", "List your counters.");
	$self->addHelpItem("[counter][-/+]", "List your counters.");
	$self->addHelpItem("[counter][-set]", "Set a counter.");
	$self->addHelpItem("[counter][-delete]", "Delete a counter.");
	$self->addHelpItem("[counter][-nick]", "See another person's counters.");
	$self->addHelpItem("[counter][-all]", "See everyone's <counter name> counters.");
	$self->addHelpItem("[counter][-all][-list]", "List system-wide counters.");
}

1;
__END__
