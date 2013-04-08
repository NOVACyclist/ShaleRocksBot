package plugins::CatFacts;
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
#--
use strict;			
use warnings;
use base qw (modules::PluginBaseClass);
use modules::PluginBaseClass;
use Data::Dumper;
use JSON;

sub getOutput {
	my $self = shift;
	my $output = "";
	
	$self->suppressNick(1);
	my $page = $self->getPage("http://facts.cat/getfact");
	my $json  = JSON->new->allow_nonref;
	my $j = $json->decode($page);
	return "Cat Fact #".$j->{id}.": ".$j->{factoid};
}


sub listeners{
	my $self = shift;
	
	my @commands = [qw(catfact)];

	my @irc_events = [qw () ];

	my @preg_matches = [qw () ];

	my @preg_excludes = [ qw() ];

	my $default_permissions =[ ];

	return { commands=>@commands,
		permissions=>$default_permissions,
		irc_events=>@irc_events,
		preg_matches=>@preg_matches,
		preg_excludes=>@preg_excludes
	};

}

##
## addHelp()
##	The help system will pull from here using PluginBaseClass->help(key).
##
sub addHelp{
	my $self = shift;
	$self->addHelpItem("[plugin_description]", "Cat Facts. Facts about cats.");
   $self->addHelpItem("[catfact]", "Usage: catfact");
}
1;
__END__
