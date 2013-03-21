package plugins::UrbanDictionary;
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
use URI::Escape;

sub plugin_init{
	my $self = shift;

	$self->suppressNick("true");	# show Nick: in the response?
	return $self;						#dont remove this line or RocksBot will cry
}


sub getOutput {
	my $self = shift;
	my $cmd = $self->{command};			# the command
	my $options = $self->{options};		# everything else on the line
	my $channel	= $self->{channel};					
	my $nick = $self->{nick};				
	my $output = "";

	return $self->help($cmd) if (!$options);
	my $url = "http://www.urbandictionary.com/define.php?term=" . uri_escape($options);
	my $page = $self->getPage($url);

	$page=~ tr/\015//d;

	my @defs;

	while ($page=~m#<div class="definition">(.+?)\n#gis){
		my $def = $1;
		my $example;


		if ($def=~s#<div class="example">(.+?)</div>##gis){
			$example = $1;		
		}
	
		$def=~s/<.+?>//gis;
		$example=~s/<.+?>//gis;
		push @defs, {def=>$def, example=>$example};
	}

	my $def_num;
	if (my $num = $self->hasFlagValue("n")){
		if (defined($defs[$num-1])){
			$def_num = $num-1;
		}else{
			$def_num = 0;
		}
	}else{
		$def_num = 0;
	}

	if (@defs){
		$output = "UrbanDictionary.com on ".BOLD.$options.NORMAL.". [".($def_num+1)."/".(@defs)."] ".BLUE."Definition:".NORMAL." $defs[$def_num]->{def}  ".BLUE."Example:".NORMAL." $defs[$def_num]->{example}";
	}else{
		$output = "No hip definitions found for \"$options\"";
	}
	return $output;
}


## listeners() and addHelp()
##	Note: these functions will be called after plugin_init, which runs few times.
## 1: When the bot starts up, it will instantiate each plugin to get this info.
## 2. When an IRC user uses your plugin. (which is what you'd expect.)
## 3. When a user asks for help using the help system.
## What this means is that if you're doing anything in here like dynamically generating
## help messages or command names, you need to do that in plugin_init().
## See Diss for an example of dynamically generated help & commands.
##
sub listeners{
	my $self = shift;
	
	##	Which commands should this plugin respond to?
	## Command Listeners - put em here.  eg [qw (cmd1 cmd2 cmd3)]
	my @commands = [qw(ud)];

	## Values: irc_join
	my @irc_events = [qw () ];

	## Example:  ["/^$self->{BotName}/i",  '/hug (\w+)\W*'.$self->{BotName}.'/i' ]
	## The only modifier you can use is /i
	my @preg_matches = [qw () ];

	my $default_permissions =[ ];

	return {commands=>@commands, permissions=>$default_permissions, 
		irc_events=>@irc_events, preg_matches=>@preg_matches};

		
}

##
## addHelp()
##	The help system will pull from here using PluginBaseClass->help(key).
##
sub addHelp{
	my $self = shift;
	$self->addHelpItem("[plugin_description]", "Interface to UrbanDictionary.com.");
   $self->addHelpItem("[ud]", "Usage: ud <query> [ -n=<definition number> ]");
}
1;
__END__
