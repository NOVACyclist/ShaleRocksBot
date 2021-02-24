package plugins::Points;
#---------------------------------------------------------------------------
#    Copyright (C) 2013  egretsareherons@gmail.com
#    https://github.com/NOVACyclist/ShaleRocksBot
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

sub plugin_init{
my $self = shift;
    $self->returnType("text");    
    $self->outputDelimiter($self->BULLET);
    $self->suppressNick("true"); 
    return $self;              
}

sub getOutput {
    my $self = shift;
    my $output = "";
    my $options = $self->{'options'};
    my $cmd = $self->{'command'};

    #return $self->help(["plugin_description"]) if $self->hasFlag("help");

    my $c = $self->getCollection(__PACKAGE__, $self->accountNick());

    if ($cmd eq 'points'){

        if ($self->hasFlag("all")){
            if ($options){

                my $c = $self->getCollection(__PACKAGE__, '%');
                my @records = $c->matchRecords({val1=>$options});
                return ("No one has rated $options. Yet.") if (@records == 0);
                my @sorted = sort { $b->{val2} <=> $a->{val2} } @records;

                foreach my $rec (@sorted){
                    $self->addToList($rec->{'collection_name'} .": " . $rec->{'val2'}, $self->BULLET);
                }

                return  "How $options rates: " . $self->getList();
            }else{
                return "Usage: points -all <thing>";
            }
        }


        if ($self->hasFlag("posneg") || $self->hasFlag("toprankers") ||$self->hasFlag("total") ) {

            my $c = $self->getCollection(__PACKAGE__, '%');
            my @records = $c->getAllRecords();

            return ("No data. Yet.")  if (@records == 0);
    
            my (%total, %num, %ratio);

            foreach my $rec (@records){
                $total{$rec->{collection_name}} += $rec->{val2};
                $num{$rec->{collection_name}}++;
            }

            foreach my $n (keys %num){
                print "$n: $total{$n} / $num{$n} \n";
                $ratio{$n} = $total{$n} / $num{$n};
            }
        
            my %data;
            if ($self->hasFlag("posneg")){
                $output = "Positivity Rankings: ";
                %data = %ratio;
            }elsif ($self->hasFlag("toprankers")){
                $output = "People Rankings the Most Things: ";
                %data = %num;
            }elsif ($self->hasFlag("total")){
                $output = "Points given out: ";
                %data = %total;
            }

            foreach (sort { ($data{$b} <=> $data{$a}) } keys %data){
                if ($self->hasFlag("posneg")){
                    $self->addToList( "$_: ". sprintf("%.2f",$data{$_}), $self->BULLET);;
                }else{
                    $self->addToList( "$_: ". sprintf("%d",$data{$_}), $self->BULLET );;
                }
            }

            return $output . $self->getList();
        }


        if($self->hasFlag("delete")){
            # Make sure people who have an account have their stuff protected
            return ("You don't have permission to do that.") if (!$self->hasPermission($self->accountNick()));

            my $what;
            if (! ($what = $self->hasFlagValue("delete"))){
                return "Usage: $cmd -delete=<thing>. Or do -deleteeverything to delete everything.";
            }

            my @records = $c->matchRecords({val1=>$what});
            if (@records == 1){ 
                $c->delete($records[0]->{'row_id'});
                return ("$self->{'nick'}: deleted $what from your leaderboard");
            }else{
                return ("$self->{'nick'}: \"$what\" doesn't currently appear in your points list.");
            }
        }


        if ($self->hasFlag("deleteeverything")){
            # Make sure people who have an account have their stuff protected
            return ("You don't have permission to do that.") if (!$self->hasPermission($self->accountNick()));

            my @records = $c->getAllRecords();
            my @sorted = sort { $b->{display_id} <=> $a->{display_id} } @records;

            foreach my $rec (@sorted){
                $c->delete($rec->{'row_id'});
            }

            return "$self->{'nick'}: ALL of your points have been deleted. I hope you're happy.";
        }


        if ($self->hasFlagValue("nick") || $options){
            my $user = $self->hasFlagValue("nick") || $options;

            my $c = $self->getCollection(__PACKAGE__, $user);
            my @records = $c->getAllRecords();

            if (@records == 0){
                return ("$user hasn't assigned anything any points yet.");
            }

            $output = "According to $user: ";
        
            my @sorted = sort { $b->{val2} <=> $a->{val2} } @records;

            my $comma = "";
            foreach my $rec (@sorted){
                $self->addToList( $rec->{'val1'} .": " . $rec->{'val2'}, $self->BULLET);
            }
            return $output . $self->getList();


        }else{

            my @records = $c->getAllRecords();

            if (@records == 0){
                return ("You haven't assigned anything any points yet. Use addpoint & rmpoint to do that.");
            }

            $output = "$self->{'nick'}'s view: ";
        
            my @sorted = sort { $b->{val2} <=> $a->{val2} } @records;

            foreach my $rec (@sorted){
                $self->addToList( $rec->{'val1'} .": " . $rec->{'val2'}, $self->BULLET);
            }
            return $output . $self->getList();
        }
    }

    # Make sure people who have an account have their stuff protected
    return ("You don't have permission to do that.") if (!$self->hasPermission($self->accountNick()));
    
    my $is_are;
        
    if ($options =~ /^.*s$/i) {     # If it is likely plural, get it right most of the time.
        $is_are = "are";
    } else {
        $is_are = "is";
    }
        
    
    if ($cmd eq 'addpoint' || ($cmd eq 'rmpoint') && (lc($options) eq lc($self->{BotName}))){

        return "Usage: $cmd <whatever>" if ($options eq "");

        my @records = $c->matchRecords({val1=>$options});
        
        if (@records == 0){
            $c->add($options, 1);
            return ("$options $is_are now worth 1 in $self->{'nick'}'s eyes.");

        }else{
            my $counter_val = $records[0]->{'val2'};
            $counter_val++;
            if ($c->updateRecord($records[0]->{row_id}, {val2 => $counter_val} )){
                return ("$options $is_are now worth $counter_val in $self->{'nick'}'s eyes.");
            }else{
                return ("Something went wrong.  Let's just pretend this didn't happen.");
            }
        }

    }elsif($cmd eq 'rmpoint'){

        return "Usage: $cmd <whatever>" if ($options eq "");

        my @records = $c->matchRecords({val1=>$options});

        if (@records == 0){ 
            $c->add($options, -1);
            return ("$options $is_are now worth -1 in $self->{'nick'}'s eyes.");

        }else{
            my $counter_val = $records[0]->{'val2'};
            $counter_val--;
            if ($c->updateRecord($records[0]->{row_id}, {val2 => $counter_val} )){
                return ("$options $is_are now worth $counter_val in $self->{'nick'}'s eyes.");
            }else{
                return ("Something went wrong.  Let's just pretend this didn't happen.");
            }
        }

    }
    
    if ($cmd eq 'loadfromrae') {
        #$self->sendPM($self->{nick}, $map);
        $self->sendPM('RaeRockBot', ';points');
    }
    


    return $output;
}


sub listeners{
   my $self = shift;

   my @commands = [qw(addpoint rmpoint points)];

   my @irc_events = [qw () ];

   my @preg_matches = [qw () ];

   my $default_permissions =[ ];

   return {commands=>@commands, permissions=>$default_permissions,
      irc_events=>@irc_events, preg_matches=>@preg_matches};
}

sub addHelp{
   my $self = shift;
   $self->addHelpItem("[plugin_description]", "$self->{BotName} points system: This is your personal points collection.  You can assign and remove points as you see fit.  Commands: addpoint, rmpoint, points.");
   $self->addHelpItem("[addpoint]", "Give something a point. Usage: addpoint <something>");
   $self->addHelpItem("[rmpoint]", "Take a point away. Usage: rmpoint <something>");
   $self->addHelpItem("[points]", "See the points you've assigned. Flags: -nick=<nick> -all -delete=<thing> -deleteeverything -posneg -total ");
   $self->addHelpItem("[points][-delete]", "Delete a single item from your leaderboard. Usage: points -delete=\"<the thing>\"");
   $self->addHelpItem("[points][-deleteeverything]", "Delete everything from your leaderboard. Usage: points -deleteeverything");
   $self->addHelpItem("[points][-total]", "Rank the rankers by total points given out. Usage: points -total");
   $self->addHelpItem("[points][-posneg]", "Rank the rankers by positivity. Usage: points -posneg");
   #$self->addHelpItem("[points][-loadfromrae]", "Load your points from the RaeRockBot Database. Usage: points -loadfromrae");   
   #$self->addHelpItem("[points][-most]", "Rank the rankers by number of things ranked. Usage: points -most");
}

1;
__END__
