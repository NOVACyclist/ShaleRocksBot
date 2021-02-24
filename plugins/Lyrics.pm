package plugins::Lyrics;
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
use strict;         
use warnings;
use base qw (modules::PluginBaseClass);
use modules::PluginBaseClass;
use Data::Dumper;
use URI::Escape;
use JSON;
use utf8;

sub getOutput {
    my $self = shift;
    my $cmd = $self->{command}; 
    my $options = $self->{options};
    
    ##
    ## hometown
    ##

    if ($cmd eq 'hometown'){
        my $artist = $self->hasFlagValue("artist");
        if (!$artist){
            $artist = $options;
        }
        return $self->help($cmd) if (!$artist);

        my $url = "http://lyrics.wikia.com/api.php?func=getHometown&fmt=realjson&artist=";
        $url .= uri_escape($artist);
        my $page = $self->getPage($url);
        my $json  = JSON->new->allow_nonref;
        my $j = $json->decode($page);
        if (!$j->{hometown}){
            return "No hometown found for $artist.";
        }
        return ($artist."'s hometown is $j->{hometown}, $j->{state}, $j->{country}.");
    }


    ##
    ## lyrics 
    ##

    if ($cmd eq 'lyrics'){

        my $artist = $self->hasFlagValue("artist");
        my $song = $self->hasFlagValue("song");

        if (!$artist){
            if ($options=~/ by /){
                ($song, $artist) = split / by /, $options;
            }else{
                return $self->help($cmd);
            }
        }

        my $url = "http://lyrics.wikia.com/api.php?artist=".uri_escape($artist);
        $url .= "&song=".uri_escape($song)."&fmt=realjson";
        my $page = $self->getPage($url);
        my $json  = JSON->new->allow_nonref;
        my $j = $json->decode($page);

        my $lyrics = $j->{lyrics};
        utf8::decode($lyrics);
        if ($lyrics eq 'Not found'){
            return "No lyrics found for artist = \"$artist\" song = \"$song\"";
        }

        my $b  = $self->BULLET;
        $lyrics =~s/\n\n/\n/gis;
        $lyrics =~s/\n/ $b /gis;
        $url = $self->getShortURL($j->{url});
        $self->suppressNick("true");    
        return BOLD."Lyrics! ".BLUE."$j->{song}".NORMAL." by ".BOLD."$j->{artist}".NORMAL.": $lyrics ".UNDERLINE.$url;
    }
}

sub listeners{
    my $self = shift;
    
    my @commands = [qw(lyrics hometown)];

    my $default_permissions =[ ];

    return { commands=>@commands, permissions=>$default_permissions };

}

sub addHelp{
    my $self = shift;
    $self->addHelpItem("[plugin_description]", "Get song lyrics or an artist's hometown.");
    $self->addHelpItem("[lyrics]", "Usage: lyrics <song> by <artist> or -song=<song> -artist=<artist>");
    $self->addHelpItem("[hometown]", "Get a musical artist's hometown.  Usage: hometown <artist> or -artist=<artist>");
}
1;
__END__
