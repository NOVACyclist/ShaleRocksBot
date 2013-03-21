package plugins::Is;
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
# inspired by the jenni factoids module
use strict;			
use warnings;
use base qw (modules::PluginBaseClass);
use modules::PluginBaseClass;
use Data::Dumper;


sub getOutput {
	my $self = shift;
	my $output = "";
	my $options = $self->{options};
	my $cmd = $self->{command};
	my $nick = $self->{nick};
	my $bot_name = $self->{BotName};
	my $ret;

   $self->suppressNick("true");

	my $c = $self->getCollection(__PACKAGE__, $self->{channel});

	if ($options=~/^$bot_name, (.+?) (is|are) part of (.+?)$/){
		my $what = $1;
		my $isare = $2;
		my $def = $3;

		my @records = $c->matchRecords({val1=>$what});

		if (!@records){
			return "I don't know anything about $what.";
		}

		@records = $c->matchRecords({val1=>$def});

		if (@records){
			my $isare = $records[0]->{val2};
			my $olddef = $records[0]->{val3};
	
			if ($olddef=~/, $what\b/){
				return "duh."
			}

			$olddef=~s/[\.\!\?]+$//gis;
				
			$c->delete($records[0]->{row_id});
			$c->add($def, $isare, $olddef . ', '. $what);
			return "duly noted.";

		}else{
			$c->add($def, $isare, $what);
			return "good to know.";
		}
	}

	if ($options=~/^$bot_name, (.+?) (is|are) not part of (.+?)$/){
		my $what = $1;
		my $isare = $2;
		my $def = $3;

		my @records = $c->matchRecords({val1=>$def});

		if (@records){
			my $isare = $records[0]->{val2};
			my $olddef = $records[0]->{val3};
			$olddef=~s/, $what\b//is;
				
			$c->delete($records[0]->{row_id});
			$c->add($def, $isare, $olddef);
			if ($isare eq 'are'){
				return "yeah, tbh i never thought really they were.";
			}else{
				return "yeah, i was never sure about that one.";
			}

		}else{
			return "what's $def?";
		}
	}


	if ($options=~/^$bot_name, (.+?) (is|are) also (.+?)$/){
		my $what = $1;
		my $isare = $2;
		my $def = $3;

		my @records = $c->matchRecords({val1=>$what});

		if (@records){
			my $isare = $records[0]->{val2};
			my $olddef = $records[0]->{val3};
			$olddef=~s/[\.\!\?]+$//gis;
				
			$c->delete($records[0]->{row_id});
			$c->add($what, $isare, $olddef . ', and '. $def);
			return "okay";

		}else{
			return "huh?";
		}
	}

	if ($options=~/^$bot_name, (.+?) (is|are) (.+?)$/){
		my $what = $1;
		my $isare = $2;
		my $def = $3;

		my @records = $c->matchRecords({val1=>$what});
		if (@records){
			return "But $what ".$records[0]->{val2}." " . $records[0]->{val3}."...";
		}else{
			$c->add($what, $isare, $def);
			return "ok.";
		}
	}
		
	if ($options=~/^$bot_name, no, (.+?) (is|are) (.+?)$/){
		my $what = $1;
		my $isare = $2;
		my $def = $3;

		my @records = $c->matchRecords({val1=>$what});

		if (@records){
			$c->delete($records[0]->{row_id});
			$c->add($what, $isare, $def);
			return "ah, gotcha.";

		}else{
			return "huh?";
		}
	}

	if ($options=~/^$bot_name, (.+?)\?$/i){
		my $what = $1;
		my @records = $c->matchRecords({val1=>$what});
		if (@records){
			return "$what ".$records[0]->{val2}." ". $records[0]->{val3};
		}else{
			return "i dunno...";
		}
	}

	if ($options=~/^$bot_name, forget (.+?)$/i){
		my $what = $1;
		my @records = $c->matchRecords({val1=>$what});
		if (@records){
			$c->delete($records[0]->{row_id});
			return "$what?  pffft, I don't even know what you're talking about.";
		}else{
			return "why?";
		}
	}
	
	if ($cmd eq 'isdb'){
		return $self->help($cmd) if (!$self->numFlags());

		if ($self->hasFlag("stats")){

			if (my $channel = $self->hasFlagValue("channel")){
				my $c = $self->getCollection(__PACKAGE__, $channel);
				my @records = $c->getAllRecords();
				if (@records){
					$ret="In $channel, I know somethin about ";
					my $comma="";
					foreach my $rec (@records){
						$ret.=$comma.$rec->{val1};
						$comma=", ";
					}
					return $ret;
				}else{
					return "I don't know nothin' in the $channel channel.";
				}

			}else{

				my $c = $self->getCollection(__PACKAGE__, '%');
				my @records = $c->getAllRecords();
				my $stats = {};
				$stats->{total_records} = 0;
				foreach my $rec (@records){
					$stats->{$rec->{collection_name}}++;
					$stats->{'total_records'}++;
				}

				$ret = "I know $stats->{total_records} things.  ";
				foreach my $k (keys $stats){
					next if $k eq 'total_records';
					$ret.="$k ($stats->{$k}) ";
				}  

				return $ret;
			}
		}

		if (my $channel = $self->hasFlagValue("clear")){
			my $c = $self->getCollection(__PACKAGE__, $channel);
			my @records = $c->getAllRecords();
			foreach my $rec(@records){	
				$c->delete($rec->{row_id});
			}

			return "Channel $channel database cleared.";
		}


		if ($self->hasFlag("copy")){
			if ((my $src = $self->hasFlagValue("src")) && (my $dst = $self->hasFlagValue("dst"))){
				my $sc = $self->getCollection(__PACKAGE__, $src);
				my $dc = $self->getCollection(__PACKAGE__, $dst);
				my @records = $sc->getAllRecords();

				foreach my $rec (@records){
					## delete old value if exists
					my @drec = $dc->matchRecords({val1=>$rec->{val1}});
					if (@drec){
						$dc->delete($drec[0]->{row_id});
					}
		
					## create new entry
					$dc->add($rec->{val1}, $rec->{val2}, $rec->{val3});
				}

				return "Merged $src into $dst";
			}

			return $self->help($cmd, '-copy');
		}

		return $self->help($cmd);
	}

	return;
}


sub listeners{
	my $self = shift;
	
	my @commands = [qw(isdb)];

	my @irc_events = [qw () ];

	my @preg_matches = [ "/^$self->{BotName}, /i" ];

	my @preg_excludes = [ "/^$self->{BotName}, tell /i" ];

	my $default_permissions =[ {command=>"isdb", require_group => UA_TRUSTED} ];

	return {commands=>@commands, permissions=>$default_permissions, irc_events=>@irc_events, preg_matches=>@preg_matches, preg_excludes=>@preg_excludes};

}

##
## addHelp()
##	The help system will pull from here using PluginBaseClass->help(key).
##
sub addHelp{
	my $self = shift;
	$self->addHelpItem("[plugin_description]", "$self->{BotName}, this is silly.  $self->{BotName}, no, this is not silly.  $self->{BotName}, this is also fun. $self->{BotName}, this is part of that. $self->{BotName}, this is not part of that. $self->{BotName}, forget this.");
   $self->addHelpItem("[isdb]", "Manage the is database.  Flags: -stats [-channel=], -copy -src= -dst=, -clear=<channel>");
   $self->addHelpItem("[isdb][-stats]", "Manage the is database.  Flags: stats, channel");
   $self->addHelpItem("[isdb][-copy]", "Usage: isdb -copy -src=#channel -dst=#channel.  Copy entries from one channel to another. Will retain unique values in dst, but collisions will be overwritten.");
   $self->addHelpItem("[isdb][-clear]", "Usage: isdb -clear=<#channel>.  Delete data for a channel.");
}
1;
__END__
