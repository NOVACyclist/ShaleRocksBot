package plugins::SportsScores;
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
use base qw (modules::PluginBaseClass);
use strict;
use warnings;

use modules::PluginBaseClass;

use URI::Escape;
use Data::Dumper;
use JSON;

sub plugin_init{
    my $self = shift;

    $self->outputDelimiter($self->BULLET); 
    $self->suppressNick("true");    

    return $self;          
}


sub getOutput {
    my $self = shift;
    my $cmd = $self->{command};
    my $output = "";
    my $options=$self->{options};

    if ($self->hasFlag("h") || $self->hasFlag("help")){
        $self->suppressNick("false");
        return $self->help($cmd);
    }

    my $urls={
        ncaab=>"http://sports.espn.go.com/ncb/bottomline/scores",
        ncaaf=>"http://sports.espn.go.com/ncf/bottomline/scores",
        nhl => "http://sports.espn.go.com/nhl/bottomline/scores",
        nfl => "http://sports.espn.go.com/nfl/bottomline/scores",
        mlb => "http://sports.espn.go.com/mlb/bottomline/scores",
        nba => "http://sports.espn.go.com/nba/bottomline/scores"
    };

    my $page;

    if (($self->s("is_march_madness") eq 'yes') && ($cmd eq 'ncaab')){
        return $self->MM();

    }else{
        $page = $self->getPage($urls->{$cmd});
    }

    my @games_raw = split /&/, $page;
    my @games;
    my @mgames;


    #print "--->Games raw has " . @games_raw . "Entries\n";
    #print "--->Games has " . @games . "Entries\n";

    foreach my $game (@games_raw){
        next if ($game!~/_lef/);
        $game =  uri_unescape($game);
        my ($junk, $game) = split /=/, $game;
        $game=~s/ +/ /gis;
        push @games, $game;
    }
    
    if ($self->hasFlag("live")){
        foreach my $g (@games){
            if ($g!~/FINAL|ET/){
                push @mgames, $g;
            }
        }

        $output = join " ". BULLET." ", @mgames;
        if ($output){
            return $output;
        }else{
            return "No live games right now";
        }
    }

    if ($options){
        print "Searching...$options\n";
        foreach my $g (@games){
            if ($g=~/$options/i){
                push @mgames, $g;
            }
        }

        $output = join " ". BULLET." ", @mgames;
        if ($output){
            return $output;
        }else{
            return "No matching games.";
        }
    }

    $output = join " ". BULLET." ", @games;

    if ($output){
        if ($self->hasFlag("publish")){
            $output = join " <br> ", @games;
            my $url = $self->publish($output);
            return "Listing generated: $url";
        }else{
            return $output;
        }
    }else{
        return "No scores found";
    }
}


##
##  Function to handle march madness since the ESPN feed doesn't work for MM.
##  This MSNBC feed returns a json structure containing broken XML.
## So we don't use the XML parser to parse it, we do it manually.
##
sub MM{
    my $self = shift;

    my $plus = 0;

    if ($self->hasFlag("tomorrow")){
        $plus = 60*60*24;
    }

    if ($self->hasFlag("yesterday")){
        $plus = -60*60*24;
    }

    if (my $num = $self->hasFlagValue("d")){
        $plus = 60*60*24 * $num;
    }

    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time() + $plus);

    my $datestr = sprintf("%d%02d%02d", (1900+ $year), $mon+1 ,$mday);
    my $url = "http://scores.nbcsports.msnbc.com/ticker/data/gamesMSNBC.js.asp?jsonp=true&sport=CBK&period=$datestr";
    my $page = $self->getPage($url);
    $page=~s/shsMSNBCTicker.loadGamesData\(//gis;
    $page=~s/\);$//gis;
    my $json  = JSON->new->allow_nonref;
    $json = $json->pretty(1);
    my $j = $json->decode($page);

    foreach my $e (@{$j->{games}}){
        my $xml;
        $e=~/home-team display_name="(.+?)".+? score="(.*?)"/;
        my $teamh = $1;
        my $scoreh = $2;

        $e=~/visiting-team display_name="(.+?)".+? score="(.*?)"/;
        my $teamv = $1;
        my $scorev = $2;

        $e=~/<gamestate status=".+?" display_status1="(.+?)".+?display_status2="(.*?)"/;
        my $status1 = $1;
        my $status2 = $2;

        my $str;
        if ($scoreh && $status2){
            $str = "$teamh $scoreh vs. $teamv $scorev ($status1 $status2)";
        }elsif ($scoreh ){
            $str = "$teamh $scoreh vs. $teamv $scorev ($status1)";
        }else{
            $str = "$teamh vs. $teamv ($status1)";
        }

        if ($self->{options}){
            if ($str=~/$self->{options}/i){
                $self->addToList($str);
            }
        }else{
            $self->addToList($str);
        }
    }
    
    my $list = $self->getList();
    if ($list){
        return $list;
    }else{
        return "No games listed.";
    }
}

sub settings{
   my $self = shift;

   $self->defineSetting({
        name=>'is_march_madness',
        default=>'no',
        allowed_values=>[qw(yes no)],
        desc=>'The regular sports feed doesn\'t work for March Madness.  Set this flag to use a different score provider for the ncaab command during March Madness.'
   });
}

sub listeners{
    my $self = shift;

    my @commands = [qw(ncaaf ncaab mlb nfl nhl nba)];
    my $default_permissions =[ ];

    return {commands=>@commands, permissions=>$default_permissions};
}

sub addHelp{
   my $self = shift;
   $self->addHelpItem("[plugin_description]", "Sports Scores.  Flags available: -live -search term -publish (with no other args). The main sports feed doesn't work for March Madness, so there's a setting to enable March Madness mode. ");
    if ($self->s("is_march_madness") eq 'yes'){
       $self->addHelpItem("[ncaab]", "NCAA basketball scores, March Madness mode. Provide arguments to search. flags: -tomorrow -yesterday -d=<number> (in number of days)");
    }else{
       $self->addHelpItem("[ncaab]", "NCAA basketball scores, regular season mode. Provide arguments to search. flags: -live, -publish");
    }

   $self->addHelpItem("[ncaaf]", "NCAA football scores. Provide arguments to search. flags: -live, -publish");
   $self->addHelpItem("[mlb]", "MLB baseball scores. Provide arguments to search. flags: -live, -publish.");
   $self->addHelpItem("[nfl]", "NFL football scores. Provide arguments to search. flags: -live, -publish.");
   $self->addHelpItem("[nhl]", "NHL hockey scores. Provide arguments to search.  flags: -live, -publish.");
}


1;
__END__
