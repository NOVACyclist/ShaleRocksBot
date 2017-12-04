package plugins::Seen;
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
    my $mask = $self->{mask};  
    my $channel;
    my $ignore_channel_re = "stopdrinking";

    if (! ($channel = $self->hasFlagValue("channel"))){
        $channel = $self->{channel};
    }

   $self->suppressNick(1);

    ##
    ## Log irc_join Event
    ##

    if ($irc_event eq 'irc_join'){
        return if ($self->s("log_joins") eq 'no');
        my $c = $self->getCollection(__PACKAGE__, ':joins:');
        my @records = $c->matchRecords({val1=>$nick, val2=>$mask});
        if (!@records){
            $c->add($nick, $mask, $self->{channel});
        }
        return;
    }


    ##
    ## Joins
    ##

    if ($cmd eq 'joins'){
        my $c = $self->getCollection(__PACKAGE__, ':joins:');
        my @records;
        my $desc;

        if ($self->hasFlag('all')){
            @records = $c->getAllRecords();
            $desc = "All records";

        }elsif($options){
            $desc = "Matches for $options";
            @records = $c->searchRecords($options, 1);
            my @r2 = $c->searchRecords($options, 2);
            foreach my $rec2 (@r2){
                my $found = 0;
                foreach my $rec (@records){
                    if ($rec->{row_id} eq $rec2->{row_id}){
                        $found =1;
                    }
                }

                if (!$found){
                    push @records, $rec2;
                }
            }
        
        }else{
            return $self->help($cmd);
        }

        foreach my $rec(@records){
            my $str = $rec->{val1} . " " . $rec->{val2};
            if ($self->hasFlag("dates")){
                $str.=" ($rec->{sys_creation_date})";
            }
            if ($self->hasFlag("html")){
                $self->addToList($str, '<br>');
            }else{
                $self->addToList($str, $self->BULLET);
            }
        }

        my $list = $self->getList();
        
        if ( $channel !~ /$ignore_channel_re/ ) {
            if ($list){
                return "$desc: $list";
            }else{
                return "No $desc.";
            }
        }

        return;
    }
    
        
    ##
    ##  Seen
    ##


    if ($cmd eq 'seen'){
        return $self->help($cmd) if (
                                       ($options eq '')              #No nick passed to lookup
                                       &&                            #And NOT trying to hide/unhide
                                       !(
                                          ($self->hasFlag('hide'))
                                          ||
                                          ($self->hasFlag('unhide'))
                                        )
                                    );
        

        if ($self->hasFlag('hide')){

            my $c = $self->getCollection(__PACKAGE__, $nick);
            my $hchannel = $self->hasFlagValue("channel") || $self->{channel};
            my @records = $c->matchRecords({val1=>$hchannel});

            if ( @records ) {
                if ( $records[0]->{val3} eq 'Hidden' ) { #using val3 for privacy filter.
                    #my $date = $records[0]->{sys_update_date} || $records[0]->{sys_creation_date};
                    return "$nick is already hidden from $self->{BotCommandPrefix}seen in $hchannel.";
                }else{
                    $c->updateRecord($records[0]->{row_id}, {val3=>'Hidden'});
                    return "$nick will no longer be recognized by $self->{BotCommandPrefix}seen in $hchannel.";
                } # end else
            } else {
                return "Either you've not been seen in $hchannel or you need to provide a valid [-channel=<#channel>] to hide from.";
            }

        }

        if ($self->hasFlag('unhide')){
            my $c = $self->getCollection(__PACKAGE__, $nick);
            my $hchannel = $self->hasFlagValue("channel") || $self->{channel};
            my @records = $c->matchRecords({val1=>$hchannel});

            if ( @records ) {
                if ( $records[0]->{val3} eq 'Hidden' ) { #using val3 for privacy filter.
                    #my $date = $records[0]->{sys_update_date} || $records[0]->{sys_creation_date};
                    $c->updateRecord($records[0]->{row_id}, {val3=>'NotHidden'});
                    return "$nick will no longer be hidden from $self->{BotCommandPrefix}seen in $hchannel.";
                }else{
                    return "$nick is already recognized by $self->{BotCommandPrefix}seen in $hchannel";
                }
            } else {
                return "Either you've not been seen in $hchannel or you need to provide a valid [-channel=<#channel>] to unhide from.";
            }
        }
        
        ###
        ###Primary function
        ###

        my $c = $self->getCollection(__PACKAGE__, $options);
        my @records = $c->matchRecords({val1=>$channel});

        if ( ( @records ) && ( $records[0]->{val3} ne 'Hidden' ) ) { #using val3 for privacy filter.
            my $date = $records[0]->{sys_update_date} || $records[0]->{sys_creation_date};
            return "I last saw $options in $channel on $date saying \"$records[0]->{val2}\".";

        }else{
            return "I haven't seen $options around.";
        }

    }

    ##
    ##  tell
    ##

    #if ( $cmd eq 'tell' ){
    if ( ($cmd eq 'tell') || ($options=~/^$self->{BotName}, tell /) ){
        #Seen|:tell|1:who|2:what|3:nick

        ## list the tells
        if ($self->hasFlag("list")){
            my $c = $self->getCollection(__PACKAGE__, ":tell");
            my @records = $c->getAllRecords();
            return "I'm not waiting to tell anyone anything. :(" if (!@records);

            foreach my $rec(@records){
                #$self->addToList("[#$rec->{row_id}] $rec->{val1}: <$rec->{val3}> $rec->{val2}", $self->BULLET);
                $self->addToList("[#$rec->{display_id}] $rec->{val1}: <$rec->{val3}> $rec->{val2}", $self->BULLET);
            }
            return "I can't wait to tell these people these things: " . $self->getList();
        }


        ## delete a tell
        if (my $num = $self->hasFlagValue("delete")){
            my $c = $self->getCollection(__PACKAGE__, ":tell");
            my @records = $c->matchRecords({display_id=>$num});

            return "I couldn't find that record."  if (!@records);
        
            if ($self->hasPermission($records[0]->{val3})){
                $c->deleteByVal({display_id=>$num});
                return "Deleted.";
            }else{
                return "You can only delete tells that you created.";
            }
            
        }

        # no flags. add a tell.
        # first argument should be a username
        #  but it might be botname, tell.  we were matching in /./ anyway, so why not?
        ##       scratch that. because Is matches too.  that's why not.
        $options =~s/$self->{BotName}, tell //gis;

        $options=~s/^(.+?) //gis;
        $self->{options_unparsed}=~s/^(.+?)\s+//;
        my $who = $1;
        my $what = $self->{options_unparsed};

        return "Tell who what now?" if (!$who);
        return "Tell $who what?" if (!$what);

        my $c = $self->getCollection(__PACKAGE__, ":tell");

        my @records = $c->matchRecords({val1=>$who});
        if (@records > 4){
            return "$who already has 4 messages waiting. Don't you think that's enough?";
        }

        if ($self->hasPermission($self->accountNick())){
            $c->add($who, $what, $nick);
            return "Ok, $nick, I will pass that on when $who is around.";
        }else{
            return "Hold on there, tiger.  I don't recognize you.  /msg $self->{BotName} login -password=<password>";
        }
        
    }   


    ##
    ##  seendb
    ##

    if ($cmd eq 'seendb'){

        my $c = $self->getCollection(__PACKAGE__, '%');
        $c->sort({field=>"collection_name", type=>'alpha', order=>'asc'});
        my @records = $c->matchRecords({val1=>$channel});
        
        if ($self->hasFlag("cleardatabase")){

            foreach my $rec (@records){
                $c->delete($rec->{row_id});
            }
            return "Database cleared for $self->{channel}";
        }


        my $count = @records;
        $output = "I have seen a total of $count users in $channel. ";

        if ($self->hasFlag("listusers")){
            foreach my $rec (@records){
                $self->addToList($rec->{collection_name});
            }

            if ($self->hasFlag("publish")){
                my $url = $self->publish($self->getList());
                $output.="List published at $url";
            }else{
                $output.=$self->getList();
            }
        }

        return $output;
    }


    ##
    ##  Preg Match - save row
    ##

    my $c = $self->getCollection(__PACKAGE__, $self->{nick});
    my @records = $c->matchRecords({val1=>$self->{channel}});

    if (@records){
        $c->updateRecord($records[0]->{row_id}, {val2=>$options});

    }else{
        $c->add($self->{channel}, $options);
    }


    ##
    ##  Do I have something to tell this person?
    ##

    #Seen|:tell|1:who|2:what|3:nick
    $c = $self->getCollection(__PACKAGE__, ":tell");
    @records=$c->matchRecords({val1=>$self->{nick}});

    if (@records){
        my @ret;
        foreach my $rec (@records){
            push @ret, "$nick: <$rec->{val3}> $rec->{val2} (Sent at $rec->{sys_creation_date})";
            $c->delete($rec->{row_id});
        }
        
        return \@ret;
    }

    return;
}


sub settings{
   my $self = shift;

   $self->defineSetting({
      name=>'log_joins',
      default=>'no',
        allowed_values=>[qw(yes no)],
      desc=>'Log irc_join events'
   });

}


sub listeners{
    my $self = shift;
    
    my @commands = [qw(seen seendb tell joins)];

    my @irc_events = [qw (irc_join) ];

    my @preg_matches = [ "/./" ];

    my $default_permissions =[ 
        {command=>"seendb", flag=>'cleardatabase', require_group=>UA_ADMIN},
        {command=>"joins", require_group=>UA_ADMIN}
    ];

    return {commands=>@commands, permissions=>$default_permissions, irc_events=>@irc_events, preg_matches=>@preg_matches};

}

sub addHelp{
    my $self = shift;
    $self->addHelpItem("[plugin_description]", "Keeps track of when a nick was last seen in this channel. ");
    $self->addHelpItem("[seen]", "Usage: seen <nick> [-channel=<#channel>].  Find out when a nick was last seen in this channel. Use $self->{BotCommandPrefix}seen -hide [-channel=<#channel>] or $self->{BotCommandPrefix}seen -unhide [-channel=<#channel>] to opt in or out respectively.");
    #hiding who database
    #$self->addHelpItem("[seendb]", "Some stats about who's been seen.  Usage: seendb.  Available flags: -listusers,  -cleardatabase -publish");
    #$self->addHelpItem("[seendb][-publish]", "publish the list to a temporary html page. Only applicable when used with -listusers.");
    $self->addHelpItem("[tell]", "Tell someone something. Use -list to see what I'm waiting to say to whom. Use -delete=<number> to delete. (soon: Use -pm to tell that person via PM, otherwise they'll be told in-channel.");
    $self->addHelpItem("[joins]", "Search the list of irc_join events.  Usage: joins <string>.  Flags: -all (show all)  -dates (include date of first join event) -html (use <br> instead of bullets as delimiters)");
}
1;
__END__
