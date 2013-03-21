package plugins::Convert;
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
use Data::Dumper;

sub getOutput {
	my $self = shift;
	my $cmd = $self->{command};			# the command
	my $options = $self->{options};		# everything else on the line
	my $channel	= $self->{channel};					
	my $mask = $self->{mask};				# the users hostmask, not including the username
	my $nick = $self->{nick};				
	my $output;

	return ($self->help($cmd)) if ($options eq '');
   
	#convert "http://www.google.com/ig/calculator?hl=en&q=1USD=?EUR";
	#query "http://www.google.com/ig/calculator?hl=en&q=4*4";
	my $url = "http://www.google.com/ig/calculator?hl=en&q=";
	
	if ($cmd eq 'calc'){
		$url = $url . "$options";
		my $page=$self->getPage($url);

		print $page;
		if ($page=~/lhs: "(.+?)",rhs:\s*"(.+?)"/){
			$output = "$1 = $2";
		}else{
			$output = "Error";
		}

		return $output;
	}
	
}


sub listeners{
	my $self = shift;
	
	my @commands = [qw(convert calc)];

	## Values: irc_join
	my @irc_events = [qw () ];

	my @preg_matches = [qw () ];

	my $default_permissions =[ ];

	return {commands=>@commands, permissions=>$default_permissions, irc_events=>@irc_events, preg_matches=>@preg_matches};

}

##
## addHelp()
##	The help system will pull from here using PluginBaseClass->help(key).
##
sub addHelp{
	my $self = shift;
	$self->addHelpItem("[plugin_description]", "Google Calculator interface.");
   $self->addHelpItem("[calc]", "Usage: calc <something>");
}
1;
__END__
