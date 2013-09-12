package plugins::Sleep;
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
#	
#	There's really no point to this plugin, just a way of playing around with 
#  threads. It also provides an example of using a reentryCommand. (rare)
#
use strict;
use warnings;

use base qw (modules::PluginBaseClass);
use modules::PluginBaseClass;

use Data::Dumper;

sub getOutput {
	my $self = shift;
	my $command = $self->{'command'};
	my $options = $self->{options};
	my $nick = $self->{nick};
   my $irc_event = $self->{irc_event};


	if ($command eq 'sleep'){ 
		if ($options=~/([0-9]+)/){
			my $tts= $1;
			$self->setReentryCommand("_sleep", $tts);
			return "Sleeping for $tts seconds";
		}else{
			return ($self->help("sleep"));
		}

	
	}elsif($command eq '_sleep'){
		$self->clearReentryCommand();
		my $tts;
		if ($self->{'options'}=~/([0-9]+)/){
			$tts= $1;
			sleep ($tts);
		}
		return "Done Sleeping for $tts seconds.";



	}elsif($command eq 'sleeptest'){
	
		my $line;

		if ($self->{options}=~/([0-9]+)/){
			$line = $1;
			sleep 3;
		}else{
			$line = 0;
			$self->{rn} = int(rand()*100);
		}

		my @lines = qw(one two three four five six seven eight nine ten);

		if ($line == (@lines-1)){
			print "Clearing ReentryCommand\n";
			$self->clearReentryCommand();

		}else{
			print "Setting entry for line $line + 1\n";
			$self->setReentryCommand($command, $line+1);
		}
		
		print "returning line $line\n";
		return ("RN: $self->{rn}.  Line " . $lines[$line] . " Doing reentry, sleeping 3. ".time());
	}
}

sub listeners{
	my $self = shift;

	my @commands = [qw(sleep sleeptest)];
	
	my @irc_events = [];

	my $default_permissions =[ 
		{command=>"PLUGIN", require_group => UA_ADMIN},
	];

	return {commands=>@commands, permissions=>$default_permissions,  irc_events=>@irc_events};
}

sub addHelp{
	my $self = shift;
	$self->addHelpItem("[plugin_description]", 
		"This module is pretty useless. You can use it to test out parallel command processing.");

	$self->addHelpItem("[sleep]", "Usage: sleep <seconds to sleep>");
	$self->addHelpItem("[sleeptest]", "This will print 10 lines, sleeping 3 seconds between each line.");
}
1;
__END__
