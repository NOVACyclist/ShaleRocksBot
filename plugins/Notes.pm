package plugins::Notes;
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
	my $options = $self->{options};
	my $nick = $self->{nick};
	my $ret;

	my $c = $self->getCollection(__PACKAGE__, $self->accountNick());
	$c->load();

	##
	##  No Arguments - print notes
	##

	if (!$self->numFlags()){

		my @records = $c->getAllRecords();

		if (@records){
			$ret = "your notes: ";
			foreach my $note (@records){
				$ret = $ret . '[#'.$note->{'display_id'}.'] '.$note->{'val1'}.' ';
			}

			return ($ret);
		}
		return ("You don't have any notes. Use 'notes -add <note> to add one.");

	}

	##
	## add a note
	## 

	if ($self->hasFlag("add")){

	#	if (! $self->hasPermission() ){
   #      return ("You don't have permission to do that.");
   #  }

		my $id = $c->add($options);

		return "added note #$id to your personal collection.";


	}

	##
	## delete a note
	##	 

	if (my $num = $self->hasFlagValue("delete")){
	
     #if (! $self->hasPermission() ){
     #    return ("You don't have permission to do that.");
     #}

		my @records = $c->matchRecords({display_id=>$num});
		if (@records){
			$c->delete($records[0]->{row_id});
			return "Deleted note #$num";
		}else{
			return "Couldn't find that note number in your collection.";
		}

	}


	##
	## Search notes
	## 

	if (my $terms = $self->hasFlagValue("search")){
	
		#return ("For simple search, ',notes search term1 term2' returns all matching notes (OR implied).  For advanced search, ',notes search +term1 +term2 -term3' does AND on +terms and NOT on -terms.");
		#}

		my @records = $c->searchRecords($terms);

		if (@records){
			foreach my $note (@records){
				$ret .=  '[#'.$note->{'display_id'}.'] '.$note->{'val1'}.' ';
			}

			return ($ret);
		}

		return ("No matching notes.");

	}

	##
	## renumber notes
	##

	if ($self->hasFlag("renumber")){
		
		$c->renumber();

		return ("Notes have been renumbered .");
	}

	##
	## print note by number
	##

	if (my $id = $self->hasFlagValue("id")){
		my $nums = $self->{'options'};
		
		my @records = $c->matchRecords({display_id=>$id});

		if (@records){
			$ret = $ret . '[#'.$records[0]->{'display_id'}.'] '.$records[0]->{'val1'}.' ';
			return ($ret);
		}else{
			return ("No matching notes.");
		}
	}

=pod
	##
	## Search ALL notes
	## 

	if ($self->hasFlag("searchall")){

		#	return ("For simple search, ',notes search term1 term2' returns all matching notes (OR implied).  For advanced search, ',notes search +term1 +term2 -term3' does AND on +terms and NOT on -terms.");

		my $oc = $self->getCollection(__PACKAGE__, $self->{nick});
		$oc->load();

		@records = $oc->searchRecords($str);
		$ret="";
		foreach $note (@records){
			$ret = $ret . '['.$note->{'collection_name'}.' #'.$note->{'display_id'}.'] '.$note->{'val1'}.' ';
		}

		if (@records){
			return ($ret);

		}else{
			return ("No matching notes.");
		}

	##
	##  show another user's notes.  This has to come last
	## 

=cut

	if(my $other_user = $self->hasFlagValue("nick")){

		my $oc = $self->getCollection(__PACKAGE__, $other_user);
		$oc->load();

		my @records;
		@records = $oc->getAllRecords();
	
		if (@records == 0){
			return "User $other_user doesn't have any notes.";
		}

		$ret=$other_user."'s notes: ";

		foreach my $note (@records){
			$ret = $ret . '[#'.$note->{'display_id'}.'] '.$note->{'val1'}.' ';
		}

		return ($ret);
	}

}


sub listeners{
   my $self = shift;

   my @commands = [qw(notes)];

   my @irc_events = [ ];

   my @preg_matches = [ ];

   my $default_permissions =[ ];

   return {commands=>@commands, permissions=>$default_permissions, irc_events=>@irc_events, preg_matches=>@preg_matches};

}


sub addHelp{
   my $self = shift;
   $self->addHelpItem("[plugin_description]", "Keep notes.");
   $self->addHelpItem("[notes]", "Usage: notes  Flags: -add -search -delete -nick -search -renumber");
   $self->addHelpItem("[command][subcommand]", "Whatever.");
}
1;
__END__
