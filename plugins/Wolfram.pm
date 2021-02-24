package plugins::Wolfram;
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
#   Obtain a WolframAlpha API key and add these lines to your config file:
#   [Plugin:Wolfram]
#   AppID = "your app id"
#
use strict;         
use warnings;
use base qw (modules::PluginBaseClass);
use modules::PluginBaseClass;

use WWW::WolframAlpha;
use Data::Dumper;

my $AppID;


sub plugin_init{
    my $self = shift;

    $self->{AppID} = $self->getInitOption("AppID");

    return $self;               
}

sub getOutput {
    my $self = shift;

    my $cmd = $self->{command};         # the command
    my $options = $self->{options};     # everything else on the line
    my $channel = $self->{channel};                 
    my $nick = $self->{nick};               
    my $output = "";

    if (!$self->{AppID}){
        return "The bot owner needs to set an API key before this plugin will work";
    }
    return ($self->help($cmd)) if ($options eq '');
   
    my $wa = WWW::WolframAlpha->new (
        appid => $self->{AppID},
    );
    
    my $query = $wa->query(
        input => $options,
    );
        
    my @result;
    my $i = 0;
    if ($query->success) {
        foreach my $pod (@{$query->pods}) {
            $i++;

            #print "-------------------------------\n";
            #print $pod->title . "\n";
            #print "-------------------------------\n";
            #print Dumper($pod);

            if ($self->hasFlag("pod")){
                if (my $showpod = $self->hasFlagValue("pod")){
                    if ($i==$showpod){
                        foreach my $p (@{$pod->{subpods}}){
    
                            my $r = $p->{plaintext};
                            $r=~s/\n/ /gis;
                            push @result, $r;
                        }
                    }
                }else{
                    push @result, "[$i] " . $pod->title;
                }
            
            }else{
                if ($pod->title eq 'Result'){
                    foreach my $p (@{$pod->{subpods}}){
                        my $r = $p->{plaintext};
                        $r=~s/\n/ /gis;
                        push @result, $r;
                    }
                }

                if ($pod->title eq 'Average result'){
                    foreach my $p (@{$pod->{subpods}}){
                        my $r = $p->{plaintext};
                        $r=~s/\n/ /gis;
                        push @result, $r;
                    }
                }
            }
        }

        ## no 'results' section found.  try globbing all the text.
        if (!@result || $self->hasFlag("all")){
            foreach my $pod (@{$query->pods}) {
                foreach my $p (@{$pod->{subpods}}){
                    my $r = $p->{plaintext};
                    $r=~s/\n/ /gis;
                    my $char = "\x{2219}";
                    $r=~s/\|/$char/gis;
                    if ($r){
                        $r = BOLD . $pod->title . NORMAL .": $r";
                        push @result, $r;
                    }
                }
            }
    
        }

        $output = join " ".BULLET." ",  @result;
    }

    if (!$output){
        $output = "No results that I could understand.";
    }

    return $output;
}


sub listeners{
    my $self = shift;
    
    my @commands = [qw(wa)];

    ## Values: irc_join
    my @irc_events = [qw () ];

    my @preg_matches = [qw () ];

    my $default_permissions =[ ];

    return {commands=>@commands, permissions=>$default_permissions, irc_events=>@irc_events, preg_matches=>@preg_matches};

}

sub addHelp{
    my $self = shift;
    $self->addHelpItem("[plugin_description]", "Interface with Wolfram Alpha.");
   $self->addHelpItem("[wa]", "Query Wolfram Alpha.  Usage: wa <whatever> [-pod [=<number>]] [-all]");
}
1;
__END__
