package plugins::Badges;

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
# This plugin is a mess. Sorry about that.
use strict;
use warnings;
use base qw (modules::PluginBaseClass);
use modules::PluginBaseClass;
use Data::Dumper;
use Date::Manip;

sub getOutput {
   my $self    = shift;
   my $options = $self->{options};
   my $output;

   my $c = $self->getCollection( __PACKAGE__, $self->accountNick() );

   ##
   ##  No Arguments - print Badges
   ##

   if (
      ( $self->numFlags() == 0 && $options eq '' )    # If no other flags exist and there are no -options passed
      || $self->hasFlag("list")                       # Or if the user specifies "list"
      )
   {

      my @records = $c->getAllRecords();              # Get all Badges for $nick

      $output = "Your badges: ";

      foreach my $badge (@records) {
         my $badge_name          = $badge->{'val1'};
         my $badge_date          = $badge->{'val2'};
         my $badge_dollar        = $badge->{'val3'};
         my $badge_unit          = $badge->{'val4'};
         my $badge_unit_position = $badge->{'val5'};

         if ( $self->hasTime($badge_date) ) {
            $output .= $self->timeSince($badge_date) . " with $badge_name";

            if ($badge_dollar) {
               my $saved = $badge_dollar * $self->daysSince($badge_date);
               $saved = commify($saved);
               if ( $badge_unit_position eq "AFTER" ) {
                  $output .= ' (' . $saved . $badge_unit . ' saved)';

               }
               else {
                  $output .= ' (' . $badge_unit . $saved . ' saved)';

               }

            }
            $output .= ".  ";

         }
         else {
            $output .= "On day " . $self->daysSince($badge_date) . " with $badge_name";

            if ($badge_dollar) {
               my $saved = $badge_dollar * $self->daysSince($badge_date);
               $saved = commify($saved);
               if ( $badge_unit_position eq "AFTER" ) {
                  $output .= ' (' . $saved . $badge_unit . ' saved)';

               }
               else {
                  $output .= ' (' . $badge_unit . $saved . ' saved)';

               }

            }

            $output .= ".  ";
         }

      }    # End: foreach my $badge (@records)

      if (@records) {
         return ($output);
      }
      else {
         return ( "You don't have any badges. " . $self->help('badge') );
      }

      ##
      ## add a badge
      ##

   }
   elsif ( $self->hasFlag("add") ) {

      if ( !$self->hasPermission( $self->accountNick() ) ) {
         return ("You don't have permission to do that.");
      }

      my ( $badge_date, $badge_name );

      if ( !( $badge_name = $self->hasFlagValue("name") ) ) {
         return ("A badge name is required.  Example: -name = QuitSmoking  Example: -name=\"Quit Smoking\"");
      }

      if ( !( $badge_date = $self->hasFlagValue("date") ) ) {
         return (
"A date is required.  Example: -date=\"10/31/2012\"  Example: -date=\"January 4, 2013\"  Example: -date=\"4 days ago\"  Example: -date=\"last tuesday\""
         );
      }

      my $date = new Date::Manip::Date;

      my $err;
      eval { $err = $date->parse($badge_date); };

      if ($@) {
         return ("Whoops.  An error occurred.");
      }

      if ($err) {
         print "ERROR PARSING DATE : $err\n";
         return ("There was an error parsing that date. Badge not added");
      }

      my $date_db = $date->value();

      #print "Date value is " . $date_db . "\n";
      my $date_printable = $date->printf("%m/%d/%Y");

      my @records = $c->matchRecords( { val1 => $badge_name } );

      if ( @records > 0 ) {
         return ("Looks like you already have a badge by that name. Use delete or reset.");
      }

      my $temp = $badge_name;
      $temp =~ s/[A-Za-z0-9 ]//g;
      if ($temp) {
         return "'$temp' You can't use special characters in your badge name. Only letters and numbers, and spaces if you must.";
      }

      $c->add( $badge_name, $date_db );

      return "added badge '$badge_name' with a date of $date_printable for user " . $self->{'nick'} . ".";

      ##
      ## all - see all badges of a particular type
      ##

   }
   elsif ( $self->hasFlag("all") ) {

      my $badge_name;

      my $oc = $self->getCollection( __PACKAGE__, '%' );

      if ( $badge_name = $self->hasFlagValue("name") ) {
         my @records = $oc->matchRecords( { val1 => $badge_name } );
         my $ret = "$badge_name badges: ";
         foreach my $badge (@records) {
            my $badge_user = $badge->{'collection_name'};
            my $badge_name = $badge->{'val1'};
            my $badge_date = $badge->{'val2'};

            if ( $self->hasTime($badge_date) ) {
               $ret .= "$badge_user: " . $self->timeSince($badge_date) . ". ";

            }
            else {
               $ret .= "$badge_user: " . $self->daysSince($badge_date) . " Days. ";
            }
         }

         return ($ret) if (@records);
         return ("No one has a badge called $badge_name.");

      }
      else {
         my @records = $oc->getAllRecords();

         my %badge_list;
         foreach my $badge (@records) {
            my $badge_name = $badge->{'val1'};
            $badge_list{$badge_name}++;
         }

         my $ret = "All user badges: ";

         foreach my $k ( sort keys %badge_list ) {
            $ret .= $k . "(" . $badge_list{$k} . ") ";
         }

         return ($ret) if (@records);
         return ("No one has a badge!  Man, you guys are L-A-M-E.");
      }

      ##
      ## user - see another user's badge
      ##

   }
   elsif ( ( my $nick = $self->hasFlagValue("nick") ) ) {

      my $oc      = $self->getCollection( __PACKAGE__, $nick );
      my @records = $oc->getAllRecords();
      my $ret     = $nick . "'s badges: ";

      foreach my $badge (@records) {
         my $badge_name          = $badge->{'val1'};
         my $badge_date          = $badge->{'val2'};
         my $badge_dollar        = $badge->{'val3'};
         my $badge_unit          = $badge->{'val4'};
         my $badge_unit_position = $badge->{'val5'};

         if ( $self->hasTime($badge_date) ) {
            $ret .= $self->timeSince($badge_date) . " with $badge_name";

            if ($badge_dollar) {
               my $saved = $badge_dollar * $self->daysSince($badge_date);
               $saved = commify($saved);

               if ( $badge_unit_position eq "AFTER" ) {
                  $ret .= ' (' . $saved . $badge_unit . ' saved)';

               }
               else {
                  $ret .= ' (' . $badge_unit . $saved . ' saved)';

               }
            }
            $ret .= ". ";

         }
         else {
            $ret .= "On day " . $self->daysSince($badge_date) . " with $badge_name";

            if ($badge_dollar) {
               my $saved = $badge_dollar * $self->daysSince($badge_date);
               $saved = commify($saved);

               if ( $badge_unit_position eq "AFTER" ) {
                  $ret .= ' (' . $saved . $badge_unit . ' saved)';

               }
               else {
                  $ret .= ' (' . $badge_unit . $saved . ' saved)';

               }

            }
            $ret .= ". ";
         }
      }

      return ($ret) if (@records);
      return ( $nick . " doesn't have any badges." );

      ##
      ##  dollar amounts
      ##

   }
   elsif ( $self->hasFlag("cost") ) {
      if ( !$self->hasPermission( $self->accountNick() ) ) {
         return ("You don't have permission to do that.");
      }

      my $ret = "";
      my ( $badge_name, $badge_cost, $badge_unit, $badge_unit_position );

      if ( !( $badge_name = $self->hasFlagValue("name") ) ) {
         return "You must specify a badge name.  Example:  -name = \"QuitSmoking\" ";
      }

      if ( !( $badge_cost = $self->hasFlagValue("cost") ) ) {
         return "You must specify a daily cost.  Example:  -cost = 15.99.  To clear the cost, use -cost = none";
      }

      $badge_cost =~ s/^(\D+)|(\D+)$//;    #remove the unit if there is one and save it.

      if ( defined $1 ) {
         $badge_unit          = $1;
         $badge_unit_position = "BEFORE";

      }
      elsif ( defined $2 ) {
         $badge_unit          = $2;
         $badge_unit_position = "AFTER";

      }
      else {
         $badge_unit = $badge_unit_position = undef;

      }

      if ( $badge_cost eq "none" ) {
         $badge_cost = 0;
      }

      my @records = $c->matchRecords( { val1 => $badge_name } );

      if ( @records == 1 ) {
         if (
            $c->updateRecord(
               $records[0]->{'row_id'},
               {
                  val3 => $badge_cost,
                  val4 => $badge_unit,
                  val5 => $badge_unit_position
               }
            )
            )
         {
            if ( $badge_unit_position eq "AFTER" ) {
               return "Badge $badge_name updated. $badge_cost$badge_unit / day";

            }
            else {
               return "Badge $badge_name updated. $badge_unit$badge_cost / day";

            }

         }
         else {
            return "Whoops.  Something went wrong. (#3pr)";
         }

      }
      elsif ( @records > 1 ) {
         print "POSSIBLE ERROR - MORE THAN ONE RECORD\n";
         return ("Whoops, something went wrong.");

      }
      else {
         return ("Can't find a badge for you with that name.");
      }

      ##
      ## delete a badge
      ##

   }
   elsif ( $self->hasFlag("delete") ) {
      if ( !$self->hasPermission( $self->accountNick() ) ) {
         return ("You don't have permission to do that.");
      }

      my $ret = "";
      my $badge_name;
      if ( !( $badge_name = $self->hasFlagValue("name") ) ) {
         return "You must specify a badge name.  Example:  -name = \"QuitSmoking\" ";
      }

      my @records = $c->matchRecords( { val1 => $badge_name } );

      if ( @records == 1 ) {
         $c->delete( $records[0]->{'row_id'} );
         return "Deleted badge $badge_name";

      }
      elsif ( @records > 1 ) {
         print "POSSIBLE ERROR - MORE THAN ONE RECORD\n";
         return ("Whoops, something went wrong.");

      }
      else {
         return ( "Can't find a badge for you with that name.  Use '" . $self->{BotCommandPrefix} . "badge list' to list your current badges." );
      }

      ##
      ## Reset Badge
      ##

   }
   elsif ( $self->hasFlag("update") ) {

      if ( !$self->hasPermission( $self->accountNick() ) ) {
         return ("You don't have permission to do that.");
      }

      my ( $badge_name, $badge_date );

      if ( !( $badge_name = $self->hasFlagValue("name") ) ) {
         return ("A badge name is required.  Example: -name = QuitSmoking  Example: -name=\"Quit Smoking\"");
      }

      if ( !( $badge_date = $self->hasFlagValue("date") ) ) {
         return (
"A date is required.  Example: -date=\"10/31/2012\"  Example: -date=\"January 4, 2013\"  Example: -date=\"4 days ago\"  Example: -date=\"last tuesday\""
         );
      }

      my @records = $c->matchRecords( { val1 => $badge_name } );

      if ( @records == 1 ) {
         my $date = new Date::Manip::Date;

         if ($badge_date) {
            my $err;
            eval { $err = $date->parse($badge_date); };
            if ($@) { return ("Whoops.  An error occurred."); }

            if ($err) {
               print "ERROR PARSING DATE : $err\n";
               return ("There was an error parsing that date. Badge not updated");
            }

         }
         else {

            if ( $self->hasTime( $records[0]->{'val2'} ) ) {
               $date->parse("now");
            }
            else {
               $date->parse("today");
            }
         }

         my $date_db        = $date->value();
         my $date_printable = $date->printf("%m/%d/%Y");

         if ( $c->updateRecord( $records[0]->{'row_id'}, { val2 => $date_db } ) ) {
            return ("Badge $badge_name updated to $date_printable.");

         }
         else {
            return ("There was an error updating that badge.");
         }

      }
      elsif ( @records > 1 ) {
         print "POSSIBLE ERROR - MORE THAN ONE RECORD\n";
         return ("Whoops, something went wrong. #4rpo");

      }
      else {
         return ("Can't find a badge for you with that name.");
      }

      ##
      ## show single badge by name
      ##

   }
   elsif ( $self->hasFlag("name") || $self->{'options'} =~ /^(\w+)\b/ ) {
      my $badge_name;

      if ( !( $badge_name = $self->hasFlagValue("name") ) ) {
         $badge_name = $1;
      }

      my $ret     = "";
      my @records = $c->getAllRecords();

      foreach my $badge (@records) {

         if ( $badge->{'val1'} eq $badge_name ) {

            my $badge_date          = $badge->{'val2'};
            my $badge_dollar        = $badge->{'val3'};
            my $badge_unit          = $badge->{'val4'};
            my $badge_unit_position = $badge->{'val5'};

            if ( $self->hasTime($badge_date) ) {
               $ret .= $self->timeSince($badge_date) . " with $badge_name";

               if ($badge_dollar) {
                  my $saved = $badge_dollar * $self->daysSince($badge_date);
                  $saved = commify($saved);
                  if ( $badge_unit_position eq "AFTER" ) {
                     $ret .= ' (' . $saved . $badge_unit . ' saved)';

                  }
                  else {
                     $ret .= ' (' . $badge_unit . $saved . ' saved)';

                  }
               }

               $ret .= ".  ";

            }
            else {
               $ret .= "On day " . $self->daysSince($badge_date) . " with $badge_name";

               if ($badge_dollar) {
                  my $saved = $badge_dollar * $self->daysSince($badge_date);
                  $saved = commify($saved);

                  if ( $badge_unit_position eq "AFTER" ) {
                     $ret .= ' (' . $saved . $badge_unit . ' saved)';

                  }
                  else {
                     $ret .= ' (' . $badge_unit . $saved . ' saved)';

                  }
               }

               $ret .= ".  ";
            }
         }
      }

      if ($ret) {
         return ($ret);

      }
      else {
         return ( "You don't have a badge by that name. " . $self->help('badge') );
      }
   }
}

sub hasTime {
   my $self = shift;
   my $date = shift;

   if ( $date =~ /00:00:00/ ) {
      return 0;
   }
   else {
      return 1;
   }

}

sub daysSince {
   my $self     = shift;
   my $date_str = shift;

   my $date = new Date::Manip::Date;
   my $err  = $date->parse($date_str);

   my $now = new Date::Manip::Date;
   $now->parse("today");

   my $date_printable = $date->printf("%m/%d/%Y");

   my $delta = $date->calc($now);

   my @dv = $delta->value();

   my $days = int( $dv[4] / 24 );

   my $ret;
   if ( $days >= 0 ) {
      $ret = $days + 1;
   }
   else {
      $ret = $days;
   }

   return $ret;
}

sub timeSince {
   my $self     = shift;
   my $date_str = shift;

   my $date = new Date::Manip::Date;
   my $err  = $date->parse($date_str);

   my $now = new Date::Manip::Date;
   $now->parse("now");

   my $date_printable = $date->printf("%m/%d/%Y");

   my $delta = $date->calc($now);

   my @dv = $delta->value();

   my $hours   = $dv[4];
   my $minutes = $dv[5];
   my $seconds = $dv[6];

   my $days = int( $dv[4] / 24 );

   if ( $days > 2 ) {
      return $days + 1 . " days";

   }
   elsif ( $days >= 1 ) {
      return "$days days, " . ( $hours % 24 ) . " hours";

   }
   elsif ( $hours >= 1 ) {
      return "$hours hours";

   }
   elsif ( $minutes >= 1 ) {
      return "$minutes minutes";

   }
   elsif ( $seconds > 0 ) {
      return "$seconds seconds";

   }
   elsif ( $hours > -48 ) {
      return "$hours hours ";

   }
   else {
      return $days . " days ";
   }

   my $ret = "hours: $hours  min: $minutes  sec: $seconds";

   return $ret;
}

sub commify {
   local $_ = shift;
   s{(?<!\d|\.)(\d{4,})}
    {my $n = $1;
     $n=~s/(?<=.)(?=(?:.{3})+$)/,/g;
     $n;
    }eg;
   return $_;
}

sub listeners {
   my $self = shift;

   my @commands = [qw(badge)];

   ## Values: irc_join
   my @irc_events = [qw ()];

   my @preg_matches = [qw ()];

   my $default_permissions = [];

   return {
      commands     => @commands,
      permissions  => $default_permissions,
      irc_events   => @irc_events,
      preg_matches => @preg_matches
   };
}

##
## addHelp()
## The help system will pull from here using PluginBaseClass->help(key).
##

sub addHelp {
   my $self = shift;
   $self->addHelpItem( "[plugin_description]", "Badges. Get a date-based \"days since\" badge for whatever." );
   $self->addHelpItem( "[badge]",
"Use $self->{BotCommandPrefix}badge to list your badges. Flags: -add -delete -update -cost, with -name=\"Badge Name\" -date=\"a date string\".  Use -all to see all users' badges, use -all -name=\"Badge Name\" to see all badges of a particular type for all users. Use -nick=SomeGuy to see SomeGuy's badges"
   );
   $self->addHelpItem( "[badge][-add]", "Create a badge.  Usage: $self->{BotCommandPrefix}badge -add -name=\"Badge Name\" -date=\"some date\"" );
   $self->addHelpItem( "[badge][-update]",
      "Change the date on a badge.  Usage: $self->{BotCommandPrefix}badge -update -name=\"Badge Name\" -date=\"some date\"" );
   $self->addHelpItem( "[badge][-delete]", "Usage: $self->{BotCommandPrefix}badge -delete -name=\"Badge Name\"" );
   $self->addHelpItem( "[badge][-cost]",
"Set a daily cost for a badge. Example: $self->{BotCommandPrefix}badge -cost =(\$, \£, kcal, A\$, C\$ etc.)5.25 -name=\"Badge Name\". To clear a cost, use -cost = none"
   );
   $self->addHelpItem( "[badge][-all]",
"See system wide badges.  Usage: $self->{BotCommandPrefix}badge -all.  To see all badges of a particular type, use $self->{BotCommandPrefix}badge -all -name=\"Badge Name\""
   );
   $self->addHelpItem( "[badge][-nick]", "See another users badges.  Usage: $self->{BotCommandPrefix}badge -nick = someguy" );
   $self->addHelpItem( "[badge][-name]", "See a particular badge.  Usage: $self->{BotCommandPrefix}badge -name = \"Badge Name\"" );

}
1;
__END__
