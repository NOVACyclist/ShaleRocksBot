package plugins::Translate;
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
use strict;
use warnings;
use base qw (modules::PluginBaseClass);
use modules::PluginBaseClass;

use utf8;
use URI::Escape;
use Data::Dumper;
use HTTP::Request::Common qw(POST);
use HTML::Entities;

sub plugin_init{
   my $self = shift;

   #$self->returnType("action");    # text, action
   $self->returnType("text");    # text, action
   $self->suppressNick("true"); # show Nick: in the response?

   return $self;  #dont remove this line or RocksBot will cry
}

sub getOutput {
    my $self = shift;
    my $output = "";
    my $options = $self->{'options'};
    my $cmd = $self->{'command'};

    my $translation = "";
    my $translation_intro = "";

   if ( $options eq ''){
        return $self->help();
   }

    my $degrave = { af => 'canadian',
                        'boston' => 'boston',
                        'smurf' => 'smurf',
                        'ayb' => 'ayb',
                        'yoda' => 'yoda',
                        'valley' => 'valley',
                        'piglatin' => 'piglatin',
                        'l33t' => 'ultraleet',
                        'hax0r' => 'haxor',
    };

    my $rinkworks= { redneck => 'redneck', 
                            cockney => 'cockney',
                            fudd => 'fudd',
                            bork => 'bork',
                            jive => 'jive',
                            moron => 'moron'
    };

    my $google = {
                        english => 'en',
                        german => 'de',
                        french => 'fr',
                        spanish => 'es',
                        irish => 'ga',
                        italian => 'it',
                        arabic => 'ar',
                        armenian => 'hy',
                        chinese => 'zh-CN',
                        hebrew => 'iw',
                        japanese => 'ja',
                        polish  => 'pl',
                        russian => 'ru',
                        swedish => 'sv',
                        welsh       => 'cy',
                        norwegian=> 'no',
                        
    };

    if ($degrave->{$cmd}){
        my $url = "http://www.degraeve.com/cgi-bin/babel.cgi?d=".$degrave->{$cmd}."&w=" . uri_escape($options);
        my $page = $self->getPage($url);
        $page=~m#blockquote>(.+?)</blockquote#gis;
        my $stuff = $1; $stuff=~s/<.+?>//gis; $stuff=~s/\n//gis;
        $stuff = decode_entities($stuff);

        $translation_intro = "translates to $cmd for ".$self->{nick}.": "; 
        $translation = $stuff;
    }


    if ($rinkworks->{$cmd}){
        my $url = "http://www.rinkworks.com/dialect/dialectt.cgi";

        my $ua      = LWP::UserAgent->new();
        my $request = POST( $url, [ text => $options,
                                            dialect => $rinkworks->{$cmd} 
                     ] );
        my $content = $ua->request($request);
        $output = $content->content;
        $output=~m#<div class='dialectized_text'>(.+?)</div>#gis;
        $output = $1;
        $output=~s/\n//gis;
        $output=~s/<.+?>//gis;
        $output = decode_entities($output);

        $translation_intro = "translates to $cmd for ".$self->{nick}.": "; 
        $translation = $output;

    }

    if ($google->{$cmd}){
        my $url = "https://translate.google.com/?hl=".$google->{$cmd}."&ie=UTF8&text=" . uri_escape($options);
        my $page = $self->getPage($url);

        $page =~/.+?<span id=result_box class=".+?_text">(.+?)<\/div>.+?/;
        $output = $1;
        $output =~s/<.+?>//gis;

        $output = decode_entities($output);
        utf8::decode($output);
        $translation_intro = "translates to $cmd for ".$self->{nick}.": "; 
        $translation = $output;
    }

    if ($self->hasFlag("q")){
        $self->returnType("text");
        return $translation;
    }else{
        #return $translation_intro . $translation;
        return $translation;
    }

}

sub listeners{
   my $self = shift;

   my @commands = ['af','boston','smurf','ayb','yoda','valley','piglatin','l33t','hax0r',
                'redneck','cockney','fudd','bork','moron','jive', 
                'english','german','french','spanish', 'irish','italian','arabic', 'armenian',
                'chinese', 'hebrew','japanese','polish','russian','swedish','welsh','norwegian'];

   my $default_permissions =[ ];

   return {commands=>@commands, permissions=>$default_permissions};
}

sub addHelp{
   my $self = shift;
   $self->addHelpItem("[plugin_description]", "Translate text.  Usage: command <text>. See help Translator for a list of commands.  Use the -q option to quiet the intro text.");
}

1;
__END__
