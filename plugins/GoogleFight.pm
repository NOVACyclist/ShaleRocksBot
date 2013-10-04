package plugins::GoogleFight;
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
use base qw (modules::PluginBaseClass);
use strict;
use warnings;

use URI::Escape;
use Data::Dumper;


sub parseOptions {
    my $self = shift;

    if ( ($self->{'options'} !~/ vs /i)  &&
        ($self->{'options'} !~/ vs\. /i)  &&
        ($self->{'options'} !~/ v\. /i)  &&
        ($self->{'options'} !~/ v /i)  
        ){
        $self->{'bad_input'} = 1;

    }else{
        $self->{'options'} =~s/ vs\. / vs /i;
        $self->{'options'} =~s/ v\. / vs /i;
        $self->{'options'} =~s/ v / vs /i;
        ($self->{'term1'}, $self->{'term2'}) = split / vs /, $self->{'options'};
    }
    return $self->{'options'};
}

sub getOutput {
    my $self = shift;
    my $cmd = $self->{command};
    my ($term1, $term2, $r1_num, $r2_num, $big_number, $small_number, $winner, $loser, $r1, $r2, $winner_text); 

    $self->parseOptions();

    if ($self->{'bad_input'}){
        return $self->help($cmd);
    }

    $term1 = $self->{'term1'};
    $term2 = $self->{'term2'};

    $r1 = $r1_num = $self->getResults($term1);
    $r2 = $r2_num = $self->getResults($term2);

    $r1_num =~s/,//gis;
    $r2_num =~s/,//gis;

    if ($r1_num > $r2_num){
        $winner = $term1;
        $loser = $term2;
        $big_number = $r1_num;
        $small_number = $r2_num;

    }elsif($r1_num < $r2_num){
        $winner = $term2;
        $loser = $term1;
        $big_number = $r2_num;
        $small_number = $r1_num;
    }else{
        $big_number = $r1_num;
        $small_number = $r2_num;
    }

    $winner = uc($winner);

    if ($small_number == $big_number){
        $winner_text = "It's a tie!";

    }elsif (($small_number / $big_number) > .99){
        $winner_text = "$winner barely squeaks one out against $loser - you can't get much closer than that!";

    }elsif (($small_number / $big_number) > .95){
        $winner_text = "$winner barely edges out $loser - it was close!";

    }elsif (($small_number / $big_number) > .8){
        $winner_text = "$winner beats $loser.";

    }elsif (($small_number / $big_number) > .5){
        $winner_text = "$winner easily beats $loser.";

    }elsif (($small_number / $big_number) > .3){
        $winner_text = "$winner whoops $loser!";

    }elsif (($small_number / $big_number) > .1){
        $winner_text = "$winner stomps on $loser!";

    }elsif (($small_number / $big_number) > .01){
        $winner_text = "$winner crushes $loser!";

    }elsif (($small_number / $big_number) > .01){
        $winner_text = "$winner destroys $loser!";

    }elsif (($small_number / $big_number) > .001){
        $winner_text = "$winner obliterates $loser!";

    }else{
        $winner_text = "It wasn't even a fair fight.  $winner all the way!";
    }

    return ("$term1 ($r1) vs. $term2 ($r2) - $winner_text");
}


sub getResults{
    my $self = shift;
    my $term = shift;

    my $url = "https://www.google.com/search?hl=en&safe=off&q=" . uri_escape('"' . $term . '"');
    my $page = $self->getPage($url);

    #"<div id="resultStats">About 5,800 results</div>";
    #No results found for <b>

    if ($page=~m#No results found for <b>#){
        return 0;
    }

    if ($page=~m#<div id="resultStats">About (.+?) results</div>#){
        return $1;
    }elsif ($page=~m#<div id="resultStats">(.+?) results</div>#){
        return $1;
    }else{
        return 0;
    }
}

sub listeners{
   my $self = shift;

   my @commands = [qw(gf)];
   my @irc_events = [qw () ];
   my @preg_matches = [qw () ];
   my $default_permissions =[ ];

   return {commands=>@commands, permissions=>$default_permissions, irc_events=>@irc_events, preg_matches=>@preg_matches};

}

sub addHelp{
   my $self = shift;
   $self->addHelpItem("[plugin_description]", "Googlefight - which term has more results?");
   $self->addHelpItem("[gf]", "Google fight.  Usage: gf <term 1> vs <term 2>");
}
1;
__END__
