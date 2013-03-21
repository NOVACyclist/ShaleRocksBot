package plugins_sys::More;
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
	my $output = "";
	my $options = $self->{'options'};
	my $cmd = $self->{command};

	if ($cmd eq '_saveMore'){	
		$self->saveLines($self->{options_unparsed});
		return;
	}

	my $c = $self->getCollection(__PACKAGE__, $self->{nick});

	my @records = $c->matchRecords({val1 => $self->{channel}});

	if (!@records){
		return ("More of what?  You don't have any lines waiting.");
	}
	
	my $line = $records[0]->{val2};
	$c->delete ($records[0]->{row_id});
	return $line;
}

sub saveLines {
	my $self = shift;
	my $line = shift;

	my $c = $self->getCollection(__PACKAGE__, $self->{nick});

	my @records = $c->matchRecords({val1 => $self->{channel}});

	## delete old line
	if (@records){
		$c->delete ($records[0]->{row_id});
	}

	## save new line
	if ($line){
		$c->add($self->{channel}, $line);
	}

	## cleanup old entries
	my $sql = "delete from collections where module_name = 'More' and sys_creation_date < date('now', '-5 day')";
	$c->runSQL($sql);

}

sub listeners{
   my $self = shift;

   ##Command Listeners - put em here.  eg ['one', 'two']
   my @commands = [qw(more _saveMore)];
   my $default_permissions =[ 
		{command=>"_saveMore", require_group => UA_INTERNAL},
	];

   return {commands=>@commands, permissions=>$default_permissions};
}

sub addHelp{
   my $self = shift;
   $self->addHelpItem("[plugin_description]", "Paginates output text use 'more' to get more lines.");
   $self->addHelpItem("[more]", "Use 'more' get more lines output.");
}
1;
__END__
