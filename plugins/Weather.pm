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
    my $ret;

    if (!$self->{API_KEY}){
        return ("The adminstrator need to set an API Key in the bot config file for this plugin to work.");
    }

   if ($options eq '' ){
        return $self->help($command);


    }elsif ( ($command eq 'forecast') || ($command eq 'weather')){

        my $options = $self->{'options'};
        my $detail = 0;

        if ($command eq 'weather'){
            $detail = 1;
        }
    
        my $URL = "http://api.wunderground.com/api/".$self->{API_KEY}."/forecast10day/q/" . $options . '.json';
        my $page = $self->getPage($URL);
        my $json  = JSON->new->allow_nonref;
        my $j = $json->decode($page);

        my $len = @{$j->{forecast}->{simpleforecast}->{forecastday}};

        if ($len == 0){
            return ("Couldn't find that place.  Be more specific, or try a zip code.");
        }

        my $ret="";

        if  ($detail){
            for (my $i=0; $i< 5; $i++){
                my $day = $j->{forecast}->{txt_forecast}->{forecastday}->[$i]->{title};
                my $detail = $j->{forecast}->{txt_forecast}->{forecastday}->[$i]->{fcttext};

                my $str = BOLD."$day: ".NORMAL."$detail\x{2022} ";

                $ret .= $str;
            }

        }else{

            for (my $i=0; $i< 5; $i++){
                my $day = $j->{forecast}->{simpleforecast}->{forecastday}->[$i]->{date}->{weekday};
                my $high = $j->{forecast}->{simpleforecast}->{forecastday}->[$i]->{high}->{fahrenheit};
                my $low = $j->{forecast}->{simpleforecast}->{forecastday}->[$i]->{low}->{fahrenheit};
                my $conditions= $j->{forecast}->{simpleforecast}->{forecastday}->[$i]->{conditions};
                my $pop = $j->{forecast}->{simpleforecast}->{forecastday}->[$i]->{pop};

                my $icon = $self->getIcon($conditions);
    
                my $pop_display;

                if ($pop){
                    $pop_display = "($pop%)";
                }else{
                    $pop_display="";
                }
                my $str = BOLD."$day:".NORMAL." $conditions $pop_display $icon H:$high\x{00B0} L:$low\x{00B0} \x{2022} ";

                $ret= $ret . $str;

            } 

            my $link = $self->getShortURL("http://api.wunderground.com/cgi-bin/findweather/getForecast?query=".$options);
            $ret .= "Full Forecast: ".UNDERLINE."$link".NORMAL;
        }
        
        return $ret;


    }elsif ($command eq 'almanac'){

        my $options = $self->{'options'};

        my $URL = "http://api.wunderground.com/api/".$self->{API_KEY}."/almanac/q/" . $options . '.json';
        my $page = $self->getPage($URL);
        my $json  = JSON->new->allow_nonref;
        my $j = $json->decode($page);


        my $high_normal = $j->{almanac}->{temp_high}->{normal}->{F};
        my $high_record= $j->{almanac}->{temp_high}->{record}->{F};
        my $high_record_year= $j->{almanac}->{temp_high}->{recordyear};

        my $low_normal= $j->{almanac}->{temp_low}->{normal}->{F};
        my $low_record= $j->{almanac}->{temp_low}->{record}->{F};
        my $low_record_year= $j->{almanac}->{temp_low}->{recordyear};

        if (!$high_normal){
            return ("Couldn't find that place.  Try to be a litte more specific.");
        }
        my $link = $self->getShortURL("http://api.wunderground.com/cgi-bin/findweather/getForecast?query=".$options);
        return "Weather Almanac for $options: Normal Temp: $high_normal".$self->DEGREE.".  Record High: $high_record".$self->DEGREE." (in $high_record_year)  Record Low: $low_record".$self->DEGREE." (in $low_record_year). Detail: $link";


   }else{

        my $URL = "http://api.wunderground.com/api/".$self->{API_KEY}."/astronomy/q/" . $self->{'options'} . '.json';
        my $page = $self->getPage($URL);
        my $json  = JSON->new->allow_nonref;
        my $j = $json->decode($page);

        my ($rhour, $rminute, $shour, $sminute);

        $rhour = $j->{moon_phase}->{sunrise}->{hour};
        $rminute = $j->{moon_phase}->{sunrise}->{minute};
        $shour = $j->{moon_phase}->{sunset}->{hour};
        $sminute = $j->{moon_phase}->{sunset}->{minute};

        if ($rhour > 12){
            $rhour = $rhour - 12;
        }

        $output = "Sunrise in ".$self->{'options'}." at $rhour:$rminute AM local time.  ";
        $output .= "Sunset in ".$self->{'options'}." at $shour:$sminute PM local time.  ";


        my $p= $j->{moon_phase}->{percentIlluminated};
            
        $output .= "The moon is $p% illuminated.";
        #return ("Error finding that location. Try using a zip code");

        $page = $self->getPage("http://api.wunderground.com/cgi-bin/findweather/getForecast?query=" . $self->{'options'} );

        if ($page=~m#<td>Moon</td>\s*+<td>(.+?)</td>\s*+<td>(.+?)</td>#gis){
            my $rise = $1;
            my $set = $2;
            $output .= " Moonrise: $rise. Moonset: $set.  ";

        }else{
            #$output = "Error finding that location. Try using a zip code";
        }

    }

    return $output;
}

sub getIcon{
    my $self=shift;
    my $conditions =shift;

    my $icon = "";

    if ($conditions eq "Thunderstorm"){ $icon=RED."\x{26A1}".NORMAL;
    }elsif($conditions eq "Chance of a Thunderstorm"){ $icon=PURPLE."\x{26A1}".NORMAL;
    }elsif($conditions eq "Chance of Rain"){ $icon=PURPLE."\x{2614}".NORMAL;
    }elsif($conditions eq "Rain"){ $icon=BLUE."\x{2614}".NORMAL;
    }elsif($conditions eq "Partly Cloudy"){ $icon=LIGHT_GREY."\x{2601}".NORMAL;
    }elsif($conditions eq "Mostly Cloudy"){ $icon=GREY."\x{2601}".NORMAL;
    }elsif($conditions eq "Chance of Snow"){ $icon=LIGHT_BLUE."\x{2744}".NORMAL;
    }elsif($conditions eq "Snow Showers"){ $icon=LIGHT_BLUE."\x{2744}".NORMAL;
    #}elsif($conditions eq "Ice Pellets"){ $icon=LIGHT_BLUE."\x{2745}".NORMAL;
    }elsif($conditions eq "Clear"){ $icon=YELLOW."\x{2600}".NORMAL;
    }

    return $icon;
}


sub listeners{
   my $self = shift;

   my @commands = ['weather', 'forecast', 'almanac', 'moon'];
   my $default_permissions =[ ];
   return {commands=>@commands, permissions=>$default_permissions};
}

sub addHelp{
   my $self = shift;
   $self->addHelpItem("[plugin_description]", "Get weather forecast & moon information from Weather Underground.");
    $self->addHelpItem("[weather]", "Usage: weather <zip code or place name>.  Get the current detailed weather forecast.");
   $self->addHelpItem("[forecast]", "Usage: forecast <zip code or place name>.  Get a 5 day summary forecast.");
   $self->addHelpItem("[moon]", "Usage: moon <zip code or place name>.  We like the moon. Coz it is good to us. (Bonus: Sun!)");
   $self->addHelpItem("[almanac]", "Usage: almanac <zip code or place name>.  Weather Almanac.");
}

1;
__END__
