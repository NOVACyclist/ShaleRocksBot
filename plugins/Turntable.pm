package plugins::Turntable;
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

sub getOutput {
	my $self = shift;

	##
	##	Admin can set URL
	##
	if (my $url = $self->hasFlagValue("set")){
		my $c = $self->getCollection(__PACKAGE__, 'settings');
		my @records = $c->matchRecords({val1=>"url", val2=>$self->{channel}});

		if (@records){
			$c->updateRecord($records[0]->{row_id}, {val3=>$url});
		}else{
			$c->add("url", $self->{channel}, $url);
		}
		return ("Turntable.fm URL Set.");
	}


	##
	##	Output a link to the room & name the currently playing song, if any.
	##

	$self->suppressNick(1);

	my $c = $self->getCollection(__PACKAGE__, 'settings');
	my @records = $c->matchRecords({val1=>"url", val2=>$self->{channel}});
	if (!@records){
		return "The admin has not set a turntable.fm room for this channel.  $self->{BotOwner} can do so using the tt -set=\"url\" command";
	}
	
	my $url = $records[0]->{val3};

	my $page = $self->getPage($url);

	my $title;
	my $artist;

	if ($page=~m#<div id="title">(.+?)</div>#s){
		$title= $1;
	}

	if ($page=~m#<div id="artist">(.+?)</div>#s){
		$artist= $1;
	}

	my $msg = "Play some music for the room: ".UNDERLINE.GREEN.$self->getShortURL($url).NORMAL;

	if ($title && $artist){
		$msg.=" Currently playing:  $title by $artist";
	}
		
	return $msg;
}

sub listeners{
   my $self = shift;
   my @commands = [qw(tt)];
   my @irc_events = [qw () ];
   my @preg_matches = [qw () ];
   my $default_permissions =[
      {command=>"tt", flag=>'set', require_group => UA_ADMIN},
   ];

   return {commands=>@commands, permissions=>$default_permissions, 
      irc_events=>@irc_events, preg_matches=>@preg_matches};
}


sub addHelp{
   my $self = shift;
   $self->addHelpItem("[plugin_description]", "Publish what's playing in a turntable.fm room.");
   $self->addHelpItem("[tt]", "See what's playing in the channel's turntable.fm room. Admin option: -set=<url>");
   $self->addHelpItem("[tt][-set]", "Set the room url.  Usage: tt -set=<url>");
}

1;
__END__
