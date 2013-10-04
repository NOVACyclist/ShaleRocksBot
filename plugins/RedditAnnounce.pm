package plugins::RedditAnnounce;
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
use JSON;
use Data::Dumper;


sub getOutput {
    my $self = shift;
    my $cmd = $self->{command};         # the command
    my $options = $self->{options};     # everything else on the line
    my $nick = $self->{nick};               
    my @output;

    if ($cmd eq 'newRedditPosts'){

        my $channel = $self->hasFlagValue("channel");
        my $subreddit = $self->hasFlagValue("subreddit");

        return "-channel=<#channel> is required." if (!$channel);
        return "-subreddit=<subreddit> is required." if (!$subreddit);
 
        $self->suppressNick("true");    

        ## For redirecting the output  
        $self->{channel} = $channel;

       ## Get the two collections
    # plugin | channel 1: subreddit | 2:id | 3:author |  4: title 
    # plugin | stats | 1:channel | 2:subreddit 3: num_runs |4: num_announces
    my $c_links = $self->getCollection(__PACKAGE__, lc($channel));
    my $c_stats = $self->getCollection(__PACKAGE__, ':stats');

    ## Keep stats
    my @stats = $c_stats->matchRecords({val1=>lc($channel), val2=>$subreddit});
    if (@stats){
        $c_stats->updateRecord($stats[0]->{row_id}, {val3=> (int($stats[0]->{val3})+1)});
    }else{
        $c_stats->add(lc($channel), $subreddit, 1, 0);
    }

    ## Get the json
    my $page = $self->getPage("http://www.reddit.com/r/$subreddit/new/.json?sort=new");

        if (!$page){
            ## timeout error, probably.  silently ignore
            print "suspected timeout error with lwp in RedditAnnounce. (#r4a). Skipping processing.";
            return;
        }

    my $json_o  = JSON->new->allow_nonref;
    $json_o = $json_o->pretty(1);
    my $j = $json_o->decode($page);

    ## process each link
    my $new_count = 0;
    for (my $i=0; $i<@{$j->{data}->{children}}; $i++){
        my $story = $j->{data}->{children}[$i];
        my $title = $story->{data}->{title};
        my $author =  $story->{data}->{author};
        my $id =  $story->{data}->{id};

        next if (!$id); # i dunno if this ever happens.


        ## if it's been seen before, don't announce it.
        my @records = $c_links->matchRecords({val1=>$subreddit, val2=>$id});

        if (@records){
            next;
            
        }else{
            my $message = BOLD."New Post ".NORMAL."to $subreddit:".BOLD.PURPLE." $title".NORMAL.PINK;
            $message.=" by $author ".NORMAL.UNDERLINE."http://redd.it/$id".NORMAL;

            if (++$new_count < 5){
                push @output, $message;
            }

                ## sleeping 1 here because i want the time fields to be 1 second apart for sorting reasons.
                ## I don't trust row_id for some reason.  I dunno, it's probably silly of me.
            $c_links->add($subreddit, $id, $author, $title);
                sleep(1);
            my @stats = $c_stats->matchRecords({val1=>lc($channel), val2=>$subreddit});
            $c_stats->updateRecord($stats[0]->{row_id}, {val4=> (int($stats[0]->{val4})+1)});
            print "RedditAnnounce: $channel\t$subreddit\t$id\t$title\n";
        }
    }

    if ($new_count > 5){
        my $message = "... there were ".($new_count-5)." additional new posts, but I decided to not trouble you with them.";
        push (@output, $message);
    }

    ## clean out the old links records. no reason to keep them around forever.
    $c_links->sort({field=>"sys_creation_timestamp", type=>'numeric', order=>'desc'});
    my @records = $c_links->matchRecords({val1=>$subreddit});

    if (@records > 50){
        for (my $i=50; $i<@records; $i++){
            $c_links->delete($records[$i]->{row_id});
        }
    }
    return \@output;
   }
}


sub listeners{
    my $self = shift;
    
    my @commands = [qw(newRedditPosts)];

    my @irc_events = [qw () ];

    my @preg_matches = [qw () ];

    my $default_permissions =[
        {command=>"PLUGIN", require_group => UA_ADMIN},
    ];

    return {commands=>@commands, permissions=>$default_permissions, 
        irc_events=>@irc_events, preg_matches=>@preg_matches};

}

##
## addHelp()
##  The help system will pull from here using PluginBaseClass->help(key).
##
sub addHelp{
    my $self = shift;
    $self->addHelpItem("[plugin_description]", "Check reddit for new things & announce them in a channel.  Plugin keeps a small database of seen items so they're not re-announced. You probably want to run these things via the bot's cron command.");
   $self->addHelpItem("[newRedditPosts]", "Checks a subreddit & announces new posts (since the last time it checked).  Intended to be run via bot's cron command. Usage: newRedditPosts -channel=<#output channel> -subreddit=<subreddit name, don't include the /r/>.   See help newRedditPosts --info for more info");
}
1;
__END__
