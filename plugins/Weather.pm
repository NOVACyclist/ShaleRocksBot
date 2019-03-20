package plugins::Weather;
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
# You need an API key for this to work. Get one here:
# http://www.wunderground.com/weather/api/
# Add to your config file:
# [Plugin:Weather]
# APIKey = "<your api key>"
use base qw (modules::PluginBaseClass);
use modules::PluginBaseClass;
use strict;
use warnings;

use Data::Dumper;
use JSON;
use DateTime;

my $API_KEY;

sub plugin_init{
    my $self = shift;

    $self->{API_KEY} = $self->getInitOption("APIKey");

    return $self;
}

## yeah i threw this together pretty haphazardly. it could use some work.

sub getOutput {
    my $self = shift;
    my $command = $self->{'command'};
    my $options = $self->{options};
    my $output = "";

    if (!$self->{API_KEY}){
        return ("The adminstrator need to set an API Key in the bot config file for this plugin to work.");
    }

   if($command eq 'weather') {

        my $options         = $self->{'options'};
        my $detail          = 0;
        my $json            = JSON->new->allow_nonref;
        my $json_current;
        my $json_forcast;

        if ($command eq 'weather'){
            $detail = 1;
        }
        
        my $url = "https://api.openweathermap.org/data/2.5/weather?q=";
        
        $url = "https://api.openweathermap.org/data/2.5/weather?zip=" if ( $options =~ /\d{5}/ );
           
        my $page = $self->getPage($url.$options."&appid=".$self->{API_KEY});
        eval {
            $json_current = $json->decode($page);
        };

        if ($@){
            return ("Hmmm, couldn't find that place. Please try seaching for the location and country code, for example - Perth, AU");
        }

        if ($json_current->{cod} != "200") {
            return $json_current->{message};
        }

        my $location = $json_current->{name} . ', ' . $json_current->{sys}->{country};
        my $dt = DateTime->from_epoch(epoch => $json_current->{dt});

        my $output = BOLD . TEAL . "$location: " . NORMAL;
        #$output .= $dt->strftime('%Y-%m-%d %H:%M:%S') . " \x{2022} ";
        $output .= "Current Temperature: " . KtoC($json_current->{main}->{temp}) . "C/".KtoF($json_current->{main}->{temp})."F \x{2022} ";
        $output .= ucfirst($json_current->{weather}->[0]->{description}) . " \x{2022} ";

        $output .= "Min: " . KtoC($json_current->{main}->{temp_min}) . "C/".KtoF($json_current->{main}->{temp_min})."F \x{2022} ";
        $output .= "Max: " . KtoC($json_current->{main}->{temp_max}) . "C/".KtoF($json_current->{main}->{temp_max})."F \x{2022} ";
        $output .= "Humidity: " . $json_current->{main}->{humidity} . "% \x{2022} ";
        $output .= "Winds: " . $json_current->{wind}->{speed} . "M/s " . $json_current->{wind}->{deg} . "\x{00B0} \x{2022} ";
        $output .= "Pressure: " . $json_current->{main}->{pressure} . " hPa";

        return $output;

    }

    if($command eq 'forecast') {

        my $options         = $self->{'options'};
        my $detail          = 0;
        my $json            = JSON->new->allow_nonref;
        my $json_current;
        my $json_forcast;

        if ($command eq 'weather'){
            $detail = 1;
        }
           
        my $page = $self->getPage("https://api.openweathermap.org/data/2.5/forecast?q=".$options."&appid=".$self->{API_KEY});
        eval {
            $json_forcast = $json->decode($page);
        };

        if ($@){
            return ("Hmmm, couldn't find that place. Be more specific, or try a zip code.");
        }

        if ($json_forcast->{cod} != "200") {
            return $json_forcast->{message};
        }
        
        my $location = $json_forcast->{city}->{name} . ', ' . $json_forcast->{city}->{country};
        my $output = BOLD . TEAL . "$location" . NORMAL;

        for (my $i=0; $i<20; $i=$i+2) {
            $output .= BOLD  . " " . BULLET . " " . NORMAL . TEAL . $json_forcast->{list}->[$i]->{dt_txt} . ": " . NORMAL;
            $output .= KtoC($json_forcast->{list}->[$i]->{main}->{temp}) . "C/".KtoF($json_forcast->{list}->[$i]->{main}->{temp})."F ";
            $output .= ucfirst($json_forcast->{list}->[$i]->{weather}->[0]->{description});
        }

        return $output;

    }
        
    return $self->help($command);

}

sub KtoC {
    my $conditions = shift;
    return sprintf("%.1f", ($conditions - 273.15));
}

sub KtoF {
    my $conditions = shift;
    return sprintf("%.1f", ($conditions * (9/5) - 459.67));
}

sub listeners{

   my $self = shift;
   my @commands = ['weather', 'forecast'];
   my $default_permissions =[];

    return {
        commands=>@commands, 
        permissions=>$default_permissions
    };

}

sub addHelp{
    my $self = shift;
    $self->addHelpItem("[plugin_description]", "Get weather forecast & moon information from Weather Underground.");
    $self->addHelpItem("[weather]", "Usage: weather <zip code or place name>.  Get the current detailed weather forecast.");
    $self->addHelpItem("[forecast]", "Usage: forecast <zip code or place name>.  Get a 3 day summary forecast.");
    #$self->addHelpItem("[moon]", "Usage: moon <zip code or place name>.  We like the moon. Coz it is good to us. (Bonus: Sun!)");
}

1;
__END__
