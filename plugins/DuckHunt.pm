package plugins::DuckHunt;
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
# I ripped this idea off from Matthias Meusburger.
# His supybot plugin:  https://github.com/veggiematts/supybot-duckhunt/blob/master/plugin.py
#-----------------------------------------------------------------------------
use strict;         
use warnings;
use base qw (modules::PluginBaseClass);
use modules::PluginBaseClass;
use Data::Dumper;

use constant DUCK => '(o)<  ・゜゜・。。・゜゜HONK';
use constant PIG  => '~~(_ _)^: OINK';
use constant SEAL => '(ᵔᴥᵔ) BARK';

my $testing;    #launch animals every 8 seconds

sub plugin_init{
    my $self = shift;
    $self->{testing} = 0;
    $self->useChannelCookies();
    return $self;
}

sub getOutput {
    my $self = shift;

    my $cmd = $self->{command};         
    my $options = $self->{options}; 
    my $channel = $self->{channel};                 
    my $nick = $self->{nick};

    my $output = "";


    #   
    # bang bang bang
    #

    if ($cmd eq 'bang'){
        return "You can't do that via PM. Sorry, bud." if ($channel!~/^#/);

        if (!$self->globalCookie("hunt_on")){
            return "A game is not currently in progress.";
        }

        if (!$self->globalCookie("duck_launched")){
            $self->returnType("irc_yield");
            #$self->yieldCommand('kick');
            $self->yieldArgs([$self->{channel}, $nick, "There was no goose!"]);
            return "There was no goose, you fool!";
        }
        $self->globalCookie("duck_launched", 0);

        # shoot this duck
        my $ducks = $self->cookie("num_ducks");
        $ducks--;
        $self->cookie("num_ducks", $ducks);

        # schedule next duck
        $self->scheduleDuck();

        return "Way to go killer. You have shot " . abs($ducks) . " animals in $self->{channel}";
    }
    
    if ( ($cmd eq 'bef') || ($cmd eq 'befriend') ) { 
        return "You can't do that via PM. Sorry, bud." if ($channel!~/^#/);

        if (!$self->globalCookie("hunt_on")){
            return "A hunt is not currently in progress.";
        }

        if (!$self->globalCookie("duck_launched")){
            $self->returnType("irc_yield");
            #$self->yieldCommand('kick');
            $self->yieldArgs([$self->{channel}, $nick, "There was no goose!"]);
            return "There was no goose!";
        }
        $self->globalCookie("duck_launched", 0);

        # friend this duck
        my $ducks = $self->cookie("num_ducks");
        $ducks++;
        $self->cookie("num_ducks", $ducks);

        # schedule next duck
        $self->scheduleDuck();
        
        return "Nice work, you saved a " . $self->globalCookie("animal_launched") . ". You have saved $ducks animals in $self->{channel}";
            
            
    }
    

    #
    # start the hunt
    #

    if ($cmd eq 'start'){
        return "You can't do that via PM. Sorry, bud." if ($channel!~/^#/);
        if ($self->globalCookie("hunt_on")){
            return "A hunt is already in progress."
        }

        $self->scheduleDuck();
        $self->globalCookie("hunt_on", 1);
        return "Hunt started";
    }



    #
    # stop the hunt
    #

    if ($cmd eq 'stop'){
        return "You can't do that via PM. Sorry, bud." if ($channel!~/^#/);
        if (!$self->globalCookie("hunt_on")){
            return "A hunt is not currently in progress.";
        }

        $self->globalCookie("hunt_on", 0);
        return "Hunt ended";
    }


    #
    # launch a duck
    #

    if ($cmd eq '_launchduck'){

        return if (!$self->globalCookie("hunt_on"));

        if ($self->globalCookie("duck_launched")){
            # a duck is already launched.
            return;
        }

        $self->suppressNick("true");    
        $self->globalCookie("duck_launched", 1);
        my $rand = rand(20);
        print "Random animal number $rand\n";
        
        if ( $rand > 18 ) {
            
            $self->globalCookie("animal_launched", "seal");
            
            return BROWN . $self->SEAL . NORMAL;
                
        } elsif ( $rand > 15 ) {
                
            $self->globalCookie("animal_launched", "pig");
                
            return BROWN . $self->PIG . NORMAL;
                
        } else {
            
            $self->globalCookie("animal_launched", "goose");
            
            return BROWN . $self->DUCK . NORMAL;
            
        }
        
        
    }


    #
    # scores    
    #

    if ($cmd eq 'scores'){
        my @cookies = $self->allCookies();
        @cookies = sort {$b->{value} <=> $a->{value}} @cookies;
        #print Dumper (@cookies);

        foreach my $cookie (@cookies){
            next if ($cookie->{owner} eq ':package');
            $self->addToList("$cookie->{owner}: $cookie->{value}", $self->BULLET );
        }

        my $list = $self->getList();
        if ($list){
            $output = BOLD."DuckHunt Scores for $self->{channel}: ".NORMAL . $list;
        }else{
            $output = 'No one has shot any ducks in '.$self->{channel}.' yet.';
        }
        return $output;
    }

    #
    #   clear_scores
    #

    if ($cmd eq 'clear_scores'){
        $self->deletePackageCookies();
        return ("Scores cleared");
    }

}

sub scheduleDuck{
    my $self = shift;

    my $next_time;
    if ($self->{testing}){
        $next_time = time() + 8;
    }else{
        $next_time = time() + int(rand($self->s('duck_window'))) + $self->s('duck_delay');
    }

    print "now is " . time() . " next goose at " . $next_time . " which is in " . ($next_time - time ()) . " seconds\n";

    my $args = {
      timestamp => $next_time,  
      command => '_launchduck',
      options => '',
      internal => 1,
      desc => 'quack'   
    };

    $self->scheduleEvent($args);
}

    
sub listeners{
    my $self = shift;
    
    my @commands = [qw(bang bef befriend clear_scores _launchduck start stop scores)];

    my $default_permissions =[
        {command=>"_launchduck", require_group => UA_INTERNAL },
        {command=>"clear_scores", require_group => UA_TRUSTED},
    ];

    return { commands=>@commands,
        permissions=>$default_permissions,
    };
}

sub settings{
    my $self = shift;

    $self->defineSetting({
        name=>'duck_delay', 
        default=>60*5,
        desc=>'The minimum time (in seconds) until the next duck appears.'
    });

    $self->defineSetting({
        name=>'duck_window', 
        default=>60*15,
        desc=>'The window of time (in seconds) in which the next duck might appear.  We\'ll pick a random time in this window, following the duck_delay period.'
    });
}

sub addHelp{
    my $self = shift;
    $self->addHelpItem("[plugin_description]", "Goose Game");
   $self->addHelpItem("[bang]", "Command: bang.  Shoot a goose");
   $self->addHelpItem("[bef]", "Command: BEFriend.  Save a goose");
   $self->addHelpItem("[befriend]", "Command: BEFriend.  Save a goose");
   $self->addHelpItem("[clear_scores]", "clear the duck hunting scores");
}
1;
__END__
