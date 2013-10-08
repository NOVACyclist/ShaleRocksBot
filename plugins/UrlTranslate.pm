package plugins::UrlTranslate;
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

    my $options = $self->{options};
    my $cmd = $self->{command};
    my $nick = $self->{nick};
    my $channel = $self->{channel};
    my $irc_event = $self->{irc_event} ||'';
    $self->suppressNick("true");
    my @ret;

    ## return if off
    return if ($self->s('mode') eq 'off');

    my @channels = split (/ /, $self->s('channels'));

    ## return if channel should be ignored
    if ($self->s('mode') eq 'exclude'){
        return if ('all' ~~ @channels);
        if (! ('none' ~~ @channels)){
            return if ($channel ~~ @channels);
        }

    }elsif($self->s('mode') eq 'include'){
        return if ('none' ~~ @channels);
        if (! ('all' ~~ @channels)){
            return if ('none' ~~ @channels);
            return if ( !($channel ~~ @channels));
        }
    }

    ## return if nick appears in ignore list
    my @ignore_nicks = split (/ /, $self->s('ignore_nicks'));
    return if ($nick ~~ @ignore_nicks);

    while($options=~m#(https?://.+?)(\s|$)|$#gi){
        my $url = $1;
        next if (!$url);
        my $page = $self->getPage($url);
        my $site= $self->{getPage_last_url};
        $site =~s#https?://(.+?)/.+$#$1#i;

        if ($page=~m#<title.*?>(.+?)</title>#is){
            my $title = $1;
            $title=~s/^ +//gis;
            $title=~s/ +$//gis;
            $title=~s/\n//gis;
            print "push\n";
            push @ret, "Title: $title".BLUE." at $site.".NORMAL;
        }
    }

    return \@ret;
}

sub settings{
    my $self = shift;

    $self->defineSetting({
        name=>'mode',
        default=>'exclude',
        allowed_values=>['off', 'include', 'exclude'],
        desc=>'If set to include, the URL Translator will only operate in the channels listed in the "channels" setting.  If set to exclude, the URL Translator will operate in all channels except for those listed in channels. If set to off, URL translator will not run at all.'
    });

    $self->defineSetting({
        name=>'channels',
        default=>'none',
        desc=>'A space-separated list of channels. To be used as specified in the "mode" setting. You can also set this to "all" or "none".'
    });

    $self->defineSetting({
        name=>'ignore_nicks',
        default=>'none',
        desc=>'A space-separated list of nicks to ignore. You can also set this to "none".'
    });
}


###
### listeners
###

sub listeners{
    my $self = shift;
    
    my @commands = [qw()];
    my @irc_events = [qw () ];
    my @preg_matches = ["/http/i" ];

    my $default_permissions =[ ];

    return {commands=>@commands, permissions=>$default_permissions, 
        irc_events=>@irc_events, preg_matches=>@preg_matches };

}


###
### help 
###

sub addHelp{
    my $self = shift;
    $self->addHelpItem("[plugin_description]", "Get the title tag of URL's as they're mentioned.  See the settings for, um, settings.");
}
1;
__END__
