package plugins::Reddit;
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


    if ($cmd eq 'subscribers'){

        return $self->help($cmd) if (!$options);

        my $subreddit = $options;
    ## Get the json
    my $page = $self->getPage("http://www.reddit.com/r/$subreddit/about.json");

    my $json_o  = JSON->new->allow_nonref;
    $json_o = $json_o->pretty(1);
    my $j;

        eval{
            $j = $json_o->decode($page);
        };

        if ($@){
            return "Couldn't find that subreddit.";
        }

        return "r/$subreddit has $j->{data}->{subscribers} subscribers, of which $j->{data}->{accounts_active} recently visited.";

   }
}


sub listeners{
    my $self = shift;
    
    my @commands = [qw(subscribers)];

    my @irc_events = [qw () ];

    my @preg_matches = [qw () ];

    my $default_permissions =[
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
    $self->addHelpItem("[plugin_description]", "Reddit stuff");
   $self->addHelpItem("[subscribers]", "Usage: subscribers <subreddit>. Get the number of subscribers to a particular subreddit.");
}
1;
__END__
