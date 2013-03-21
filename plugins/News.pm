package plugins::News;
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

use XML::Feed;
use URI::Escape;
use Data::Dumper;
#use HTML::Entities;

sub getOutput {
	my $self = shift;
	my $output = "";

	my $URL;
	my $term;

   if ($self->{'options'} eq '' ){
		$URL = "http://news.google.com/news?ned=us&topic=h&output=rss";
   }else{
		$term = uri_escape($self->{'options'});
		$URL = "http://news.google.com/news?q=".$term."&output=rss";
	}

	my $feed = XML::Feed->parse(URI->new($URL))
		or return "Error retriving news about that. " . XML::Feed->errstr;
	
	#for my $entry ($feed->entries) {
		#print "----------------------------\n";
		#print Dumper($entry);
		#print $entry->{'entry'}->{'title'} . "\n";
		#my $shorturl = $self->getShortURL($entry->{'entry'}->{'link'});
		#print $shorturl . "\n";
		#print "----------------------------\n";
	#}
	
	if ($feed->entries > 2){
		for (my $i=0; $i<5; $i++){
			my $title = ($feed->entries)[$i]->{'entry'}->{'title'};
			my $link = ($feed->entries)[$i]->{'entry'}->{'link'};
			my $shorturl = $self->getShortURL($link);
			if ($i > 0){
				$output .= " ".BULLET." ";
			}
			$output .= "$title ".UNDERLINE."$shorturl".NORMAL;
		}
	}else{
		$output = "No news found for " . $self->{'options'}.".";
	}

	return $output;
}

sub listeners{
	my $self = shift;

	my @commands = [qw(news)];

   return {commands=>@commands};
}

sub addHelp{
	my $self = shift;
	$self->addHelpItem("[plugin_description]", "Google News Search");
	$self->addHelpItem("[news]", "Usage: news [<search term>]");
}

1;
__END__
