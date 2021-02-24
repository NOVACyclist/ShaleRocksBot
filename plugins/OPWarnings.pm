package plugins::OPWarnings;

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

#This is a quick & dirty hack of the Points module.

use strict;
use warnings;
use base qw (modules::PluginBaseClass);
use modules::PluginBaseClass;

use Data::Dumper;

sub plugin_init {
   my $self = shift;
   $self->returnType("text");
   $self->outputDelimiter( $self->BULLET );
   $self->suppressNick("true");
   return $self;
}

sub getOutput {
   my $self    = shift;
   my $output  = "";
   my $options = $self->{'options'};
   my $cmd     = $self->{'command'};

   #return $self->help(["plugin_description"]) if $self->hasFlag("help");

   my $c = $self->getCollection( __PACKAGE__, $self->accountNick() );

   if ( $cmd eq 'warnings' ) {

      if ( $self->hasFlag("all") ) {
         if ($options) {

            my $c = $self->getCollection( __PACKAGE__, '%' );
            my @records = $c->matchRecords( { val1 => $options } );
            return ("No one has warned $options... Yet.") if ( @records == 0 );
            my @sorted = sort { $b->{val2} <=> $a->{val2} } @records;

            my $op_count;

            foreach my $rec (@sorted) {
               $self->addToList( $rec->{'collection_name'} . ": " . $rec->{'val2'}, $self->BULLET );
               $op_count++;
            }

            if ( $op_count > 1 ) {
               return "$options has been warned by the following op(s) : " . $self->getList();
            }
            else {
               return "$options has been warned by : " . $self->getList();
            }

         }
         else {
            return "Usage: warnings -all <nick>";
         }
      }

      if ( $self->hasFlag("posneg") || $self->hasFlag("toprankers") || $self->hasFlag("total") ) {

         my $c = $self->getCollection( __PACKAGE__, '%' );
         my @records = $c->getAllRecords();

         return ("No data. Yet.") if ( @records == 0 );

         my ( %total, %num, %ratio );

         foreach my $rec (@records) {
            $total{ $rec->{collection_name} } += $rec->{val2};
            $num{ $rec->{collection_name} }++;
         }

         foreach my $n ( keys %num ) {
            print "$n: $total{$n} / $num{$n} \n";
            $ratio{$n} = $total{$n} / $num{$n};
         }

         my %data;
         if ( $self->hasFlag("posneg") ) {
            $output = "Positivity Rankings: ";
            %data   = %ratio;
         }
         elsif ( $self->hasFlag("toprankers") ) {
            $output = "People Rankings the Most Things: ";
            %data   = %num;
         }
         elsif ( $self->hasFlag("total") ) {
            $output = "warnings given out: ";
            %data   = %total;
         }

         foreach ( sort { ( $data{$b} <=> $data{$a} ) } keys %data ) {
            if ( $self->hasFlag("posneg") ) {
               $self->addToList( "$_: " . sprintf( "%.2f", $data{$_} ), $self->BULLET );
            }
            else {
               $self->addToList( "$_: " . sprintf( "%d", $data{$_} ), $self->BULLET );
            }
         }

         return $output . $self->getList();
      }

      if ( $self->hasFlag("delete") ) {

         # Make sure people who have an account have their stuff protected
         return ("You don't have permission to do that.") if ( !$self->hasPermission( $self->accountNick() ) );

         my $what;
         if ( !( $what = $self->hasFlagValue("delete") ) ) {
            return "Usage: $cmd -delete=<thing>. Or do -deleteeverything to delete everything.";
         }

         my @records = $c->matchRecords( { val1 => $what } );
         if ( @records == 1 ) {
            $c->delete( $records[0]->{'row_id'} );
            return ("$self->{'nick'}: deleted $what from the warnings list");
         }
         else {
            return ("$self->{'nick'}: \"$what\" doesn't currently appear in your warnings list.");
         }
      }

      if ( $self->hasFlag("deleteeverything") ) {

         # Make sure people who have an account have their stuff protected
         return ("You don't have permission to do that.") if ( !$self->hasPermission( $self->accountNick() ) );

         my @records = $c->getAllRecords();
         my @sorted = sort { $b->{display_id} <=> $a->{display_id} } @records;

         foreach my $rec (@sorted) {
            $c->delete( $rec->{'row_id'} );
         }

         return "$self->{'nick'}: ALL of your warnings have been deleted. I hope you're happy.";
      }

      if ( $self->hasFlagValue("nick") || $options ) {
         my $user = $self->hasFlagValue("nick") || $options;

         my $c = $self->getCollection( __PACKAGE__, $user );
         my @records = $c->getAllRecords();

         if ( @records == 0 ) {

            if ($options) {

               my $c = $self->getCollection( __PACKAGE__, '%' );
               my @records = $c->matchRecords( { val1 => $options } );
               return ("No one has warned $options... Yet.") if ( @records == 0 );
               my @sorted = sort { $b->{val2} <=> $a->{val2} } @records;

               my $op_count;

               foreach my $rec (@sorted) {
                  $self->addToList( $rec->{'collection_name'} . ": " . $rec->{'val2'}, $self->BULLET );
                  $op_count++;
               }

               if ( $op_count > 1 ) {
                  return "$options has been warned by the following op(s) : " . $self->getList();
               }
               else {
                  return "$options has been warned by : " . $self->getList();
               }

            }

            #return ("$user hasn't assigned anything any warnings yet.");
         }

         $output = "According to $user: ";

         my @sorted = sort { $b->{val2} <=> $a->{val2} } @records;

         my $comma = "";
         foreach my $rec (@sorted) {
            $self->addToList( $rec->{'val1'} . ": " . $rec->{'val2'}, $self->BULLET );
         }
         return $output . $self->getList();

      }
      else {

         my @records = $c->getAllRecords();

         if ( @records == 0 ) {
            return ("You haven't assigned anyone any warnings yet. Use warn to do that.");
         }

         $output = "$self->{'nick'}'s view: ";

         my @sorted = sort { $b->{val2} <=> $a->{val2} } @records;

         foreach my $rec (@sorted) {
            $self->addToList( $rec->{'val1'} . ": " . $rec->{'val2'}, $self->BULLET );
         }
         return $output . $self->getList();
      }
   }

   # Make sure people who have an account have their stuff protected
   return ("You don't have permission to do that.") if ( !$self->hasPermission( $self->accountNick() ) );

   if ( $cmd eq 'warn' || ( $cmd eq 'rmwarn' ) && ( lc($options) eq lc( $self->{BotName} ) ) ) {

      return "Usage: $cmd <whatever>" if ( $options eq "" );

      my @records = $c->matchRecords( { val1 => $options } );

      if ( @records == 0 ) {
         $c->add( $options, 1 );
         return ("$options has been warned 1 time by $self->{'nick'}.");

      }
      else {
         my $counter_val = $records[0]->{'val2'};
         $counter_val++;
         if ( $c->updateRecord( $records[0]->{row_id}, { val2 => $counter_val } ) ) {
            return ("$options has been warned $counter_val times by $self->{'nick'}.");
         }
         else {
            return ("Something went wrong.  Let's just pretend this didn't happen.");
         }
      }

   }
   elsif ( $cmd eq 'rmwarn' ) {

      return "Usage: $cmd <whatever>" if ( $options eq "" );

      my @records = $c->matchRecords( { val1 => $options } );

      if ( @records == 0 ) {
         $c->add( $options, -1 );
         return ("$options has been warned -1 time by $self->{'nick'}.");

      }
      else {
         my $counter_val = $records[0]->{'val2'};
         $counter_val--;
         if ( $c->updateRecord( $records[0]->{row_id}, { val2 => $counter_val } ) ) {
            return ("$options has been warned $counter_val times by $self->{'nick'}.");
         }
         else {
            return ("Something went wrong.  Let's just pretend this didn't happen.");
         }
      }

   }

   return $output;
}

sub listeners {
   my $self = shift;

   my @commands = [qw(warn rmwarn warnings)];

   my @irc_events = [qw ()];

   my @preg_matches = [qw ()];

   my $default_permissions = [ { command => "warn", require_group => UA_TRUSTED }, { command => "rmwarn", require_group => UA_TRUSTED } ];

   return {
      commands     => @commands,
      permissions  => $default_permissions,
      irc_events   => @irc_events,
      preg_matches => @preg_matches
   };
}

sub addHelp {
   my $self = shift;
   $self->addHelpItem( "[plugin_description]",
"$self->{BotName} warnings system: This is your personal warnings collection.  You can assign and remove warnings as you see fit.  Commands: warn, rmwarn, warnings."
   );
   $self->addHelpItem( "[warn]",              "Note that a user has been warned in channel. Usage: warn <something>" );
   $self->addHelpItem( "[rmwarn]",            "Used to remove an accidental warning. Usage: rmwarn <something>" );
   $self->addHelpItem( "[warnings]",          "See the warnings you've assigned. Flags: -nick=<nick> -all -delete=<thing> -deleteeverything -posneg -total " );
   $self->addHelpItem( "[warnings][-delete]", "Delete a single item from your list. Usage: warnings -delete=\"<the thing>\"" );
   $self->addHelpItem( "[warnings][-deleteeverything]", "Delete everything from your leaderboard. Usage: warnings -deleteeverything" );
   $self->addHelpItem( "[warnings][-total]",            "Rank the rankers by total warnings given out. Usage: warnings -total" );
   $self->addHelpItem( "[warnings][-posneg]",           "Rank the rankers by positivity. Usage: warnings -posneg" );

   #$self->addHelpItem("[warnings][-loadfromrae]", "Load your warnings from the RaeRockBot Database. Usage: warnings -loadfromrae");
   #$self->addHelpItem("[warnings][-most]", "Rank the rankers by number of things ranked. Usage: warnings -most");
}

1;
__END__
