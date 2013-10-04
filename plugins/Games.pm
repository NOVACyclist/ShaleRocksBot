package plugins::Games;
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

sub getOutput {
    my $self = shift;
    my $cmd = $self->{command};
    my $options = $self->{options};
    my $output;

    
    # 8 ball
    if ($cmd eq '8ball'){

        return $self->help($cmd) if ($options eq '');

        my @responses = ('It is certain', 'It is decidedly so', 'Without a doubt', 'Yes, definitely',
            'You may rely on it', 'As I see it, yes', 'Most likely', 'Outlook good', 'Yes',
            'Signs point to yes', 'Reply hazy, try again', 'Ask again later', 'Better not tell you now',
            'Cannot predict now', 'Concentrate and ask again', 'Don\'t count on it', 'My reply is no',
            'My sources say no', 'Outlook not so good', 'Very doubtful');

        my $pos = int(rand (@responses));

        return "\x{2787} " . $responses[$pos];
    }


    #fortune
    if ($cmd eq 'fortune'){

        unless (-e "/usr/games/fortune"){   
            return "Sorry, fortune is not installed on this machine.";
        }

        my $fortune = `/usr/games/fortune`;
        $fortune =~s/\n/ /gis;
        #return ($fortune x 40);    
        return $fortune;
    }


    # powerball numbers
    if ($cmd eq "powerball"){
        my @NUMBERS;
        my @WHITE;

        for (my $i=1; $i<=59; $i++){
            push @WHITE, $i;
        }

        my $i = @WHITE;
        while ( --$i ){
            my $j = int rand( $i+1 );
            @WHITE[$i,$j] = @WHITE[$j,$i];  
        }

        for (my $i=0; $i<5; $i++){
            push @NUMBERS, pop(@WHITE);
        }

        my $pb = int (rand(35 +1));

        @NUMBERS = sort{$a<=>$b} @NUMBERS;

        $output = "I picked these powerball numbers for you: ";
        foreach my $n (@NUMBERS){
            $output .= "$n "
        }

        $output .= " POWERBALL: $pb";

        return $output;
    }


    #random number
    if ($cmd eq "rand"){
        my $min = $self->hasFlagValue("min") || 1;
        my $max = $self->hasFlagValue("max") || 10;
        return int (rand(($max + 1) - $min) + $min);
    }


    #ask
    if ($cmd eq "ask"){
        return $self->help($cmd) if ($options eq '');
        $options=~s/\?$//gis;
        
        if ($options!~/ or /){
            my @choices = qw /yes yep no nope maybe perhaps/;
            return @choices[int(rand(@choices))];
        }

        my @choices = split / or /, $options;
        my $i = int(rand(@choices));
        return $choices[$i];
    }

    
    # Rock Paper Scissors
    if ($cmd eq 'rock' || $cmd eq 'paper' || $cmd eq 'scissors'){
        my $choice = ('rock', 'paper', 'scissors')[int(rand(3))];

        my $status = "";
        if ($choice eq $cmd){
            $status = "It's a tie!";

        }elsif($choice eq 'rock'){
            if ($cmd eq 'paper'){
                $status = "You win!";
            }else{
                $status = "I win!";
            }
        }elsif($choice eq 'paper'){
            if ($cmd eq 'scissors'){
                $status = "You win!";
            }else{
                $status = "I win!";
            }
        }elsif($choice eq 'scissors'){
            if ($cmd eq 'rock'){
                $status = "You win!";
            }else{
                $status = "I win!";
            }
        }

        my $my_score = $self->globalCookie("rps_me") || 0;
        my $world_score = $self->globalCookie("rps_world") || 0;
    
        if ($status eq 'You win!'){
            $self->globalCookie("rps_world", ++$world_score);
        }elsif($status eq 'I win!'){
            $self->globalCookie("rps_me", ++$my_score);
        }

        
        my $ret = NORMAL."You chose $cmd. I chose $choice.".BOLD." $status".NORMAL;
        $ret.=" ... ".RED."$self->{BotName}:".NORMAL." $my_score ".RED." World: ".NORMAL."$world_score";
        return $ret;
    }

    return $output;

}

sub listeners{
   my $self = shift;

   ##Command Listeners - put em here.  eg ['one', 'two']
   my @commands = ['8ball','fortune','powerball', 'rand', 'ask', 'rock','paper','scissors' ];
   my $default_permissions =[ ];

   return {commands=>@commands, permissions=>$default_permissions};
}

sub addHelp{
   my $self = shift;
   $self->addHelpItem("[plugin_description]", "Just some games. They may or may not be fun.");
   $self->addHelpItem("[8ball]", "Usage: 8ball <ask a question>");
   $self->addHelpItem("[fortune]", "Get a unix fortune, if fortune is installed on this machine.");
   $self->addHelpItem("[powerball]", "Have the bot pick some powerball numbers for you. Don't forget to share the winnings.");
   $self->addHelpItem("[rand]", "Get a random number. Usage: rand [-min=<x>][-max=<y>].  Default is 1-10");
   $self->addHelpItem("[ask]", "Ask an either/or question.  Example: ask meddle or animals or dark side?");
}

1;
__END__
