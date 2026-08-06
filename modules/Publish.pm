package modules::Publish;
#---------------------------------------------------------------------------
#    Copyright (C) 2013  egretsareherons@gmail.com
#    https://github.com/NOVACyclist/ShaleRocksBot
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
    my ($class, $options) = @_;
    my $self = bless {}, $class;
    $self->{options} = (ref($options) eq 'HASH') ? $options : {};
    return $self;
}

##  Unguessable page name: 16 bytes from the kernel CSPRNG, hex encoded.
##
##  The previous scheme was md5_base64(time), which is a pure function of the
##  current epoch second. Anyone could compute the name of every page ever
##  published by iterating timestamps, and two publishes in the same second
##  silently overwrote each other. Published pages can contain `seen` history
##  and arbitrary user text, so enumerability was an information leak.
sub _random_token{
    my $bytes;
    open(my $ur, '<:raw', '/dev/urandom') or return undef;
    my $got = read($ur, $bytes, 16);
    close($ur);
    return undef if (!defined($got) || $got != 16);
    return unpack('H*', $bytes);    # 32 lowercase hex chars
}

sub publish{
    my $self = shift;
    my $html = shift;

    my $opts = $self->{options} || {};

    ##  Config-driven, with defaults matching the nginx vhost. Not
    ##  /usr/share/nginx/html: that is package-owned and an nginx upgrade can
    ##  replace it.
    my $html_path = $opts->{publish_path}     || '/var/www/shalerocksbot/publish/';
    my $base_url  = $opts->{publish_base_url} || 'https://shalerocksbot.us.to/';

    ##  Never hand out a plain-http link. The vhost redirects http->https, but
    ##  relying on that means the first request goes out in the clear, carrying
    ##  the page address -- and published pages can contain `seen` history.
    ##  Upgrade here so the link is https from the moment it is printed.
    $base_url =~ s{^http://}{https://}i;

    $html_path .= '/' if ($html_path !~ m{/$});
    $base_url  .= '/' if ($base_url  !~ m{/$});

    my $token = _random_token();
    if (!defined($token)){
        warn "Publish: couldn't read /dev/urandom, refusing to publish\n";
        return "Error: couldn't generate a page name.";
    }

    ##  Name is generated here, never taken from user input, and is plain hex --
    ##  no separators, so there is nothing to traverse with.
    my $filename = $token . ".html";

    $html =~ s/\x{2022}/<br>/g;

    $html =~ s/\:/\:<br>/;

    #if ( $html =~ /Matches\ for/ ) { 
    #   
    #    $html =~ s/\s/\<\/td\>\<td\>/g;
    #    $html =~ s/^(.)/$1\<tr\>\<td\>/g;
    #    $html =~ s/(.)$/$1\<\/td\>\<\/tr\>/g;
    #    $html =~ "<table>" . $html . "</table>";
    #
    #}

    ##  Raw write, deliberately: the bot hands us a mix of byte strings and
    ##  wide-character strings, and perl already emits valid UTF-8 for the
    ##  latter. Adding an :encoding layer here would double-encode the former.
    my $full_path = $html_path . $filename;

    my $fh;
    if (!open($fh, ">", $full_path)){
        ##  Previously this only warn()ed and then handed the user a URL to a
        ##  page that was never written. Fail visibly instead.
        warn "Publish: can't write $full_path: $!\n";
        return "Error: couldn't write the published page.";
    }

    print $fh $html;

    if (!close($fh)){
        warn "Publish: can't close $full_path: $!\n";
        return "Error: couldn't write the published page.";
    }

    ##  Owner read/write, group (www-data, via the setgid publish dir) read
    ##  only. nginx never needs to modify what it serves.
    chmod 0640, $full_path;

    return $base_url . $filename;
}
1;
__END__

