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
#use strict;
#use warnings;
use base qw (modules::PluginBaseClass);
use modules::PluginBaseClass;
use Data::Dumper;
use POSIX qw(strftime);

sub getOutput {
    my $self = shift;
    my $cmd = $self->{command};

    my $c = $self->getCollection(__PACKAGE__, $self->accountNick());

    if (! $self->hasPermission($self->accountNick()) ){
        return ("You don't have permission to do that.");
    }

    ##
    ## create a counter 
    ## 

    if(my $counter_name = $self->hasFlagValue("create")){

        my $counter_val = $self->hasFlagValue("value") || 1;

        return ("That didn't look like a number. ('$counter_val')") if ($counter_val ne ($counter_val + 0 ));

        my @records = $c->matchRecords({val1=>$counter_name});

        return("Looks like you already have a counter by that name.") if (@records);
        return "You can only use letters and numbers in a counter name." if ($counter_name=~/\W/);

        $c->add($counter_name, $counter_val, $self->theTime());

        return "added counter '$counter_name' with a value of $counter_val for ". $self->accountNick().".";


    ##
    ## all - see all counters of a particular type
    ##   

    }elsif($self->hasFlag("all")){

        my $oc = $self->getCollection(__PACKAGE__, '%');

        if ( (my $counter_name = $self->hasFlagValue("all")) eq 0){
            my @records = $oc->getAllRecords();
            my %counter_list;
            foreach $counter (@records){
                my $counter_name = $counter->{'val1'};
                $counter_list{$counter_name}++;
            }
        
            foreach $k (sort keys %counter_list){
                $self->addToList($k . " (".$counter_list{$k}.") ", $self->BULLET);
            }

            return ('All user counters: '. $self->getList()) if (@records);
            return ("No one has a counter!");
        
        }else{

            my @records = $oc->matchRecords({val1=>$counter_name});
            foreach $counter (@records){
                my $counter_user = $counter->{'collection_name'};
                #my $counter_name = $counter->{'val1'};
                my $counter_val = $counter->{'val2'};

                $self->addToList("$counter_user: $counter_val", $self->BULLET);
            }

            return ("$counter_name counters: " . $self->getList())  if (@records);
            return ("No one has a counter called $counter_name.");
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
            
        return ($username."'s counters: " . $self->getList()) if (@records);
        return ($username. " doesn't have any counters.");



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



    }elsif($self->hasFlag("lastupdate")){
        my $counter_name = $self->{options};
        return $self->help($cmd, '-lastupdate') if (!$counter_name);

        my @records = $c->matchRecords({val1=>$counter_name});

        if (@records == 1){
            return "Counter \"$counter_name\" was last updated on $records[0]->{val3}";
        }

        return "Could not find a counter for you named $counter_name. Sorry bro.";
        
    
    
    ##
    ##  ADD or SUBTRACT
    ##

    }elsif( $self->{'options'}=~/^(\+|\-)/ ){

        my $action = $1;
        my $amt = "";

        my $counter_name ="";

        if ($self->{'options'}=~/^(\+|\-)\s+(.+?)\b/){
            $counter_name = $2;
            $amt = 1;

        }elsif ($self->{'options'}=~/^(\+|\-)([\.0-9]+)\s+(.+?)\b/){
            $amt= $2;
            $counter_name = $3;

        }else{
            return ($self->help($cmd));
        }
    

        my @records = $c->matchRecords({val1=>$counter_name});

        if (@records == 1){

            my $counter_val = @records[0]->{'val2'};

            if ($action eq '+'){
                $counter_val+=$amt;

            }elsif($action eq '-'){
                $counter_val-=$amt;
            }

            if ($c->updateRecord(@records[0]->{'row_id'}, {val2 => $counter_val, val3=>$self->theTime() } )){
                return ("Counter '$counter_name' set to $counter_val.");

            }else{
                return ("There was an error updating that counter.");
            }


        }elsif(@records > 1){
            print "POSSIBLE ERROR - MORE THAN ONE RECORD\n";
            return ("Whoops, something went wrong. #pcpm1");

        }else{
            return ("Can't find a counter for you with that name.");
        }


    ##
    ## Set Counter
    ## 

    }elsif($self->hasFlag("set")){

        my ($counter_name, $counter_val);

        if ($self->{'options'}=~/^(.+?)\s+(.+?)\b/){
            $counter_name = $1;
            $counter_val= $2;

        }else{
            return ($self->help($cmd, '-set'));
        }

        return ("That doesn't look like a number. ('$counter_val')") if ($counter_val ne ($counter_val + 0 ));

        my @records = $c->matchRecords({val1=>$counter_name});

        if (@records == 1){

            if ($c->updateRecord(@records[0]->{'row_id'}, {val2 => $counter_val, val3=>$self->theTime()} )){
                return ("Counter $counter_name set to $counter_val.");

            }else{
                return ("There was an error updating that counter.");
            }

        }elsif(@records > 1){
            print "POSSIBLE ERROR - MORE THAN ONE RECORD\n";
            return ("Whoops, something went wrong. #4rpo");

        }else{
            return ("Can't find a counter for you with that name. ('$counter_name')");
        }

    }


    if ($self->hasFlag("last_updated")){
        my $counter_name = $self->{options};

        my @records = $c->matchRecords({val1=>$counter_name});

        if (@records){
            return "$counter_name as last updated on $records[0]->{sys_update_date}" if ($records[0]->{sys_update_date});
            return "$counter_name as last updated on $records[0]->{sys_creation_date}";
        }
        return "You don't have a counter called '$counter_name'.";
    }

    ##
    ## show single counter by name
    ##

    if ($self->{'options'}=~/^(\w+)\b/){
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
            return ("You don't have a counter by that name. ('$counter_name')");
        }
    }

    ##
    ##  No Arguments - print counters
    ##

    my @records = $c->getAllRecords();
    foreach my $counter (@records){
        my $counter_name = $counter->{'val1'};
        my $counter_val = $counter->{'val2'};
        $self->addToList($counter_name.": ".$counter_val, $self->BULLET);
    }
            
    if (@records){
        return ("Your counters: " . $self->getList());

    }else{
        return ("You don't have any counters. Use ".$self->{BotCommandPrefix}."counter -create=<name> -value=<value> to add one.");
    }
}

sub theTime{
    my $self = shift;
    #my @t = localtime(time);
    #return sprintf("%02d-%02d %02d:%02d:%02d ", $t[4]+1, $t[3], $t[2], $t[1], $t[0]);
    return strftime "%a %b %e %H:%M:%S %Y %Z", localtime;
}


sub listeners{
   my $self = shift;

   my @commands = [qw(counter)];

   my @irc_events = [qw () ];

   my @preg_matches = [qw () ];

   my $default_permissions = [ ];

   return {commands=>@commands, permissions=>$default_permissions,
      irc_events=>@irc_events, preg_matches=>@preg_matches};


}


sub addHelp{
   my $self = shift;
   $self->addHelpItem("[plugin_description]", "Make counters for things. Increment them. Decrement them. Great fun.");
   $self->addHelpItem("[counter]", "Maintain counters. counter + <counter_name> to add.  counter - <counter_name> to subtract. Other flags:  -create -set -delete -nick -all -lastupdate.  help counter <-flag> for flag help"); 
    $self->addHelpItem("[counter][-create]", "Usage: counter -create=<counter_name> -value=<initial_value>.  Create a new counter.");
    $self->addHelpItem("[counter][-set]", "Usage: counter -set <counter_name> <new_value>.  Set a counter to a particular value.");
    $self->addHelpItem("[counter][-delete]", "counter -delete=<counter_name>. Delete a counter.");
    $self->addHelpItem("[counter][-nick]", "counter -nick=<nick>.  See another person's counters.");
    $self->addHelpItem("[counter][-lastupdate]", "counter <counter_name> -lastupdate. See a counter's last update date.");
    $self->addHelpItem("[counter][-all]", "counter -all [=<counter_name>].  See everyone's counters. Use -all or -all=<counter_name>");
}

1;
__END__
