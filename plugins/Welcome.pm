package plugins::Welcome;
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
use Data::Dumper;

sub getOutput {
    my $self = shift;
    my $output = "";

    my $options = $self->{options};
    my $cmd = $self->{command};
    my $nick = $self->{nick};
    my $irc_event = $self->{irc_event} ||'';

   $self->suppressNick("true");

    ## Join Event
    if ($irc_event eq 'irc_join'){
        $self->useChannelCookies();

        ## dont welcome people when they change hosts
        return if ($self->cookie('last_welcome') > time() - $self->s('last_welcome_timeout'));
    
        my @wchannels = split (/ /, $self->s('herald_channels'));
        
        if ($self->{channel} ~~ @wchannels){
            my ($greeting, $type) = $self->getGreeting();

            if ($type eq 'action'){
                $self->returnType("action");

            }elsif ($type eq 'command'){
                $self->returnType("runBotCommand");
            }

            $self->cookie('last_welcome', time());
            return $greeting;
        }

        return;
    }

    ## Handle some regex matches that we signed up for.
    if (!$cmd){
        return $self->doRegexMatches();
    }

    if ($cmd eq 'herald'){

        my $hnick = $self->hasFlagValue("nick");
        my $hchannel = $self->hasFlagValue("channel") || $self->{channel};
        my $hmessage = $self->hasFlagValue("message");

        my $c = $self->getCollection(__PACKAGE__, 'herald');
        my @records;

        if ($self->hasFlag("add")){
            return "You have to use the -nick=<nick> flag." if (!$hnick);
            return "You have to use the -message=\"<message>\" flag." if (!$hmessage);

            my $type = 'text';
            $type = 'action' if ($self->hasFlag("action"));
            $type = 'command' if ($self->hasFlag("command"));
            
            #@records = $c->matchRecords({val1=>$hchannel, val3=>$hnick});

            #if (@records){
            #   $c->delete($records[0]->{row_id});
            #}

            # Channel | type | nick | message | set by nick
            $c->add($hchannel, $type, $hnick, $hmessage, $self->accountNick());
            return "Added welcome message \"$hmessage\" for $hnick in $hchannel.";
        }


        if ($self->hasFlag("list")){

            if ($hnick){
                @records = $c->matchRecords({val1=>$hchannel, val3=>$hnick});
                return "$hnick has no welcome messages in $hchannel" if (!@records);

                foreach my $rec (@records){
                    $self->addToList("[".$rec->{display_id}."] ".$rec->{val4}.GREEN." as \"$rec->{val2}\", set by $rec->{val5}".NORMAL, $self->BULLET);
                }
                return ("Welcome messages for $hnick in $hchannel: " . $self->getList());
    

            }else{
                @records = $c->matchRecords({val1=>$hchannel});
                return "No users have herald messages in $hchannel." if (!@records);
                my %list;
                foreach my $rec (@records){
                    $list{$rec->{val3}}++;
                }

                foreach my $k (sort keys %list){
                    $self->addToList("$k ($list{$k})", $self->BULLET);
                }
                return "Users with herald messages in $hchannel: " . $self->getList();
            }


        }


        if ($self->hasFlag("delete")){
            my $id = $self->hasFlagValue("id"); 
            return "-id=<#> flag is required." if (!$id);

            @records = $c->matchRecords({display_id=>$id});
            return "Can't find that record. (#$id)" if (!@records);

            my $can_delete = 0;

            if ( $self->hasPermission($records[0]->{val3})){
                $can_delete = 1;
            }

            if ($self->hasPermission($records[0]->{val5})){
                $can_delete = 1;
            }
        
            if (!$can_delete){
                return "You don't have permission to delete that message. Messages can only be deleted by the nick who created them and the target nick.";
            }

            $c->delete($records[0]->{row_id});
            return "Deleted welcome message #" . $id;
        }

#       if ($options){
#           my @records= $c->matchRecords({val1=>$ch, val3=>$options});
#           return "$options has no welcome message set in $ch" if (!@records);
#           return "$options welcome message for $ch: $records[0]->{val4} (type is $records[0]->{val2}, set by $records[0]->{val5})";
#       }

        return $self->help($cmd);
    }
}

sub getGreeting{
    my $self = shift;
    my $c = $self->getCollection(__PACKAGE__, 'herald');
    my @records = $c->matchRecords({val1=>$self->{channel}, val3=>$self->accountNick()});
    my $rec;
    if (@records){
        $rec = @records[int(rand(@records))];
        return ($rec->{val4}, $rec->{val2});
    }else{
        return ("welcomes $self->{nick} to the room.", "action");
    }

    # Channel | type | nick | message | set by nick
}

##
##  Custom sub added to make the getOutput more clear   
##

sub doRegexMatches{
    my $self = shift;
    my $options = $self->{options};
    my $nick = $self->{nick};

    ## Regex match for ^$self->{BotName}
    if ($options=~/^$self->{BotName}/i){

        return "$nick!" if ($options=~/^$self->{BotName}!$/i);
        return "$nick?" if ($options=~/^$self->{BotName}\?$/i);
        return "$nick..." if ($options=~/^$self->{BotName}\.\.\.$/i);

        if ($options=~/^$self->{BotName} hates (.+?)$/i){
            return ("That's not true, $nick. I love everything.");
        }

        if ($options=~/^$self->{BotName} is (.+?)[\.]*$/i){
            return ("You're $1 too, $nick.");
        }
    }


    ## Everyone loves hugs
    if ($options=~/^hug (\w+)/i){
        my $target = $1;
        $self->returnType("action");
        if ($target eq "me"){
            return "hugs $nick";
        }else{
            return "hugs $target";
        }
    }
    
    ## party party
    if ($options=~/^everybody dance now/i){
        $self->returnType("action");
        return ("breakdances");
    }

    if ($options=~/^stop/i){
        $self->suppressNick("true");
        return  BOLD.ORANGE."IN THE NAME OF LOVE!".NORMAL;
    }
        
    if ($options=~/i love $self->{BotName}/i){
        $self->suppressNick("true");
        return "I ".RED."L\x{2764}ve".NORMAL." you too, $nick";
    }

    if ($options=~/^(\w+) (\w+)\W*$self->{BotName}/i){
        my $action = $1;
        my $target = $2;
        $self->returnType("action");
        if ($target eq 'me'){
            return $action."s $nick";
        }else{
            return $action."s $target";
        }
    }
}


sub settings{
    my $self = shift;

    $self->defineSetting({
        name=>'herald_channels',
        default=>'#soberfriends #stopdrinking #stopdrinkingsocial',
        desc=>'A space separated list of channels that the herald should operate in.  If a channel is not listed here, the herald will not welcome users in that channel.'
    });

    $self->defineSetting({
        name=>'last_welcome_timeout',
        default=>'60',
        desc=>'Sometimes people change hosts when their cloak is applied, resulting in a double welcome. This will not welcome someone if they have been welcomed to the room in the previous X seconds.  You may want to set this to longer to avoid repeatedly welcoming people experiencing connectivity issues.'
    });
    
}


###
### listeners
###

sub listeners{
    my $self = shift;
    
    my @commands = [qw(herald)];
    my @irc_events = [qw (irc_join) ];
    my @preg_matches = ["/^$self->{BotName}/i", 
                        '/hug (\w+)\W*'.$self->{BotName}.'/i',
                        '/everybody dance now/i',
                        '/^stop\W*$/i',
                        "/^i love $self->{BotName}/i",
                        '/^(\w+) (\w+)\W*'.$self->{BotName}.'$/i',
                                
    ];

    my $default_permissions =[
            {command=>"herald",  flag=>'command', require_group => UA_ADMIN },
 ];

    return {commands=>@commands, permissions=>$default_permissions, 
        irc_events=>@irc_events, preg_matches=>@preg_matches };

}


###
### help 
###

sub addHelp{
    my $self = shift;
    $self->addHelpItem("[plugin_description]", "Welcomes people to the room. Set custom welcome messages for users.");
    $self->addHelpItem("[herald]", "Welcomes people to the room, or set a custom welcome message for a particular user. Flags: -add -list -delete, with -nick=<nick> [-channel=<#channel>] -message=\"message\" [-command] [-action] [-id=<#>]");
    $self->addHelpItem("[herald][-add]", "Add a herald message for a nick.  Use -command to indicate that the message should be executed as a command.  Use -action to indicate that the message should be announced as an action. (e.g. /me).  Example: herald -add -nick=\"SomeGuy\" -channel=\"#somechannel\"  -message=\"hello there!\" ");
}
1;
__END__
