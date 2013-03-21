package plugins::Welcome;
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

sub getOutput {
	my $self = shift;
	my $output = "";

	my $options = $self->{options};
	my $cmd = $self->{command};
	my $nick = $self->{nick};
	my $irc_event = $self->{irc_event};

   $self->suppressNick("true");

	## Join Event
	if ($irc_event eq 'irc_join'){
		$self->returnType("action");
		if ($self->s("welcome_all") eq 'yes'){
			return ("welcomes $nick to the room");
		}
		return;
	}


	## Handle some regex matches that we signed up for.
	if (!$cmd){
		return $self->doRegexMatches();
	}

	if ($cmd eq 'herald'){
		return "soon";
	}
}


##
##	Custom sub added to make the getOutput more clear	
##

sub doRegexMatches{
	my $self = shift;
	my $options = $self->{options};
	my $nick = $self->{nick};

	## Regex match for ^$self->{BotName}
	if ($options=~/^$self->{BotName}/i){

		return "$nick!" if ($options=~/^$self->{BotName}!$/i);
		return "$nick?" if ($options=~/^$self->{BotName}\?$/i);
		return "$nick..." if ($options=~/^$self->{BotName}\.\.\.$/i);

		if ($options=~/^$self->{BotName} hates (.+?)$/i){
			return ("That's not true, $nick. I love everything.");
		}

		if ($options=~/^$self->{BotName} is (.+?)[\.]*$/i){
			return ("You're $1 too, $nick.");
		}
	}


	## Everyone loves hugs
	if ($options=~/^hug (\w+)/i){
		my $target = $1;
		$self->returnType("action");
		if ($target eq "me"){
			return "hugs $nick";
		}else{
			return "hugs $target";
		}
	}
	
	## party party
	if ($options=~/^everybody dance now/i){
		$self->returnType("action");
		return ("dances");
	}

	if ($options=~/^stop/i){
		$self->suppressNick("true");
		return  BOLD.YELLOW."HAMMER TIME!".NORMAL;
	}
		
	if ($options=~/i love $self->{BotName}/i){
		$self->suppressNick("true");
		return "I ".RED."L\x{2764}ve".NORMAL." you too, $nick";
	}

	if ($options=~/^(\w+) (\w+)\W*$self->{BotName}/i){
		my $action = $1;
		my $target = $2;
		$self->returnType("action");
		if ($target eq 'me'){
			return $action."s $nick";
		}else{
			return $action."s $target";
		}
	}
}


sub settings{
	my $self = shift;

	# Call defineSetting for as many settings as you'd like to define.
	$self->defineSetting({
		name=>'welcome_all',
		default=>'yes',
		allowed_values=>[qw(yes no)],
		desc=>'Should '.$self->{BotName}.' welcome everyone to the room? Set to "yes" or "no".' 
	});
}


###
###	listeners
###

sub listeners{
	my $self = shift;
	
	my @commands = [qw(herald)];
	my @irc_events = [qw (irc_join irc_part irc_quit) ];
	my @preg_matches = ["/^$self->{BotName}/i", 
								'/hug (\w+)\W*'.$self->{BotName}.'/i',
								'/everybody dance now/i',
								'/^stop\W*$/i',
								"/^i love $self->{BotName}/i",
								'/^(\w+) (\w+)\W*'.$self->{BotName}.'$/i',
								
	];

	my $default_permissions =[ ];

	return {commands=>@commands, permissions=>$default_permissions, 
		irc_events=>@irc_events, preg_matches=>@preg_matches };

}


###
###	help 
###

sub addHelp{
	my $self = shift;
	$self->addHelpItem("[plugin_description]", "Welcomes people to the room.");
	$self->addHelpItem("herald", "Welcomes people to the room, or set a custom welcome message for a particular user. Flags: -nick=<nick> -channel=<#channel> -add=<message> -list -delete=<#>");
	$self->addHelpItem("herald_settings", "Enable or disable herald options. -channel=<#channel>" );
}
1;
__END__
