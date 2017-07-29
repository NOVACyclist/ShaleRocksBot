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
#API Info

#How it works: Do a post request to the create.php page. A URL of the published page will be returned.

#Page name: http://rocks.us.to/p/create.php
#GET options:
#type : type of file. Values: html, text, jpg, gif, png, css, js, zip*. Default: html
#*zip files - are unzipped & each file is associated w/ the html file. Uploaded zip files should contain exactly one (1) html file. Example: upload a zip file containing (index.html, page.css, and header.jpg). Links in the HTML page to /page.css and "page.css" will then both 'work' without you having to edit your html.
#hours : expiration time, in hours. Default: 24 * 30
#encoding : encoding type of the content field. Values: base64. You should encode binary content before posting to the server. Not always necessary, depending on server setup, but it's good practice.
#short_url: Return a short url from is.gd. Values: 0 or 1. Default: 0
#POST option: content : The content of the page
#You can POST the GET variables instead, if you want.
#Example URL to POST "content" to: http://rocks.us.to/p/create.php (uses default options)

#Example URL to POST "content" to: http://rocks.us.to/p/create.php?type=text&hours=1 (text document, will expire in 1 hour)

#Example cURL statement: curl --data-urlencode "content=<h1>hello world</h1>" 'http://rocks.us.to/p/create.php?type=html&hours=1'




BEGIN {
  $modules::Publish::VERSION = '1.0';
}

##  How to make your own publish module: Call it whatever you'd like.
##  It needs a new() (no args) and a publish() (accepts $content, returns $url).
## Specify this module as publish_module in the [BotSettings] section of the config file.
use strict;
use warnings;
use Data::Dumper;
use HTTP::Request::Common qw(POST);
use LWP::UserAgent;
use Digest::MD5 qw(md5 md5_hex md5_base64);

sub new{
    my ($class, @args) = @_;
    my $self = bless {}, $class;
    return $self;
}

sub publish{
    my $self = shift;
    my $html = shift;
    
    my $html_path_secure = '/usr/share/nginx/html/Shale/';
    
    my $html_path = '/usr/share/nginx/html/';
    
    my $filename = md5_base64(time) . ".html";
    
    $filename =~ s/\/|\+|//g;

    $html =~ s/\x{2022}/<br>/g;

    open(FILEHANDLE, ">" , $html_path . $filename) or warn $!;
    
    print FILEHANDLE $html;
    
    close(FILEHANDLE);
     
    return "http://ShaleRocksBot.us.to/" . $filename;
    
}
1;
__END__

