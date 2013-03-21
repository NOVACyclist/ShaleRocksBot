package modules::Publish;
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

BEGIN {
  $modules::Publish::VERSION = '1.0';
}

##	How to make your own publish module: Call it whatever you'd like.
##	It needs a new() (no args) and a publish() (accepts $content, returns $url).
## Specify this module as publish_module in the [BotSettings] section of the config file.
use strict;
use warnings;
use Data::Dumper;
use HTTP::Request::Common qw(POST);
use LWP::UserAgent;
use MIME::Base64;

sub new{
	my ($class, @args) = @_;
	my $self = bless {}, $class;
	return $self;
}

sub publish{
	my $self = shift;
	my $html = shift;
	
	my $url = "http://htmlpaste.com/index.php";
	my $ua      = LWP::UserAgent->new();
	my $request = POST( $url, [ 'code' => $html , newcont => "true" ] );
	my $content = $ua->request($request)->as_string();
	$content=~m#target="_blank">(http:.+?)</a>#;
	my $link = $1;
   return $link;
	
}
1;
__END__
