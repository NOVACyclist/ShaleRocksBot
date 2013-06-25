package plugins::TFW;
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
use modules::PluginBaseClass;
use strict;
use warnings;

use Data::Dumper;


sub plugin_init{
	my $self = shift;

	return $self;
}


sub getOutput {
	my $self = shift;
	my $command = $self->{'command'};
	my $options = $self->{options};
	my $output = "";
	my $ret;

   if ($options eq '' ){
		return $self->help($command);


	}else{

		my $options = $self->{'options'};

	
		my $URL = "http://thefuckingweather.com/?where=". $options ;
		my $page = $self->getPage($URL);
	
		$page =~/<span id="locationDisplaySpan" class="small">(.+?)<\/span>/;
		my $place = $1;

		$page=~/<span class="temperature".+?>(.+?)<\/span>/gis;	
		my $temp = $1;
		
		$page =~/<p class="remark">(.+?)<\/p>/gis;
		my $comment = $1;

		
		if ($place){
			return "The Fucking Weather for $place: $temp".$self->DEGREE."F  $comment";
		}else{	
			return "Couldn't find that fucking place!";
		}

	}
}

sub listeners{
   my $self = shift;

   my @commands = ['tfw'];
   my $default_permissions =[ ];
   return {commands=>@commands, permissions=>$default_permissions};
}

sub addHelp{
   my $self = shift;
   $self->addHelpItem("[plugin_description]", "Get the fucking weather forecast.");
	$self->addHelpItem("[tfw]", "Usage: tfw <zip code>");
}

1;
__END__
