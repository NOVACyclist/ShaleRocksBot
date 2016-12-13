package modules::PrivacyFilter;
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
use lib '/home/lunchbox/ShaleRocksBot/trunk';
use base qw (modules::PluginBaseClass);
use modules::PluginBaseClass;
use Data::Dumper;
use JSON;

my @filters;
my $c;
my $mode ; # replace remove censor kill
my $BotDatabaseFile;
my $SpeedTraceLevel;
my $sql_pragma_synchronous;

sub new{
    my $class = shift;
    my $opts = shift;
    my $self = bless {}, $class;
    $self->{BotDatabaseFile} = $opts->{BotDatabaseFile};
    $self->{keep_stats} = $opts->{SpeedTraceLevel};
    $self->{sql_pragma_synchronous} = $opts->{sql_pragma_synchronous};
    $self->{PackageShortName} = 'PrivacyFilter';
    $self->{mode} = 'replace';
    $self->init();
    return $self;
}

sub loadCollection{
    my $self = shift;
    return if ($self->{c});
    
    $self->{c} = $self->Collection->new({db_file=>$self->{BotDatabaseFile}, module_name=>'Admin',
        collection_name=>'privacy_filter', keep_stats=>$self->{SpeedTraceLevel},
        sql_pragma_synchronous=>$self->{sql_pragma_synchronous}  });
    $self->{c}->load();
}

sub init{
    my $self = shift;   
    delete($self->{c});
    delete($self->{filters});

    ##
    ##  Get our IP
    ##
    
    eval {
        my $page = $self->getPage("http://www.jsonip.com/");
        my $json_o  = JSON->new->allow_nonref;
        my $j = $json_o->decode($page);
        my $ip = $j->{ip};

        if ($ip){
            push @{$self->{filters}}, {str=>$ip, repl=>'8.8.8.8'};
        }else{
            print "Warning:  PrivacyFilter could not determine your IP address\n";
        }
    };

    if ($@){
        print "Warning:  PrivacyFilter could not determine your IP address\n";
    }


    ##
    ##  Load the filters & settings
    ##

    $self->loadCollection();
    my @records = $self->{c}->getAllRecords();
    foreach my $rec (@records){
        $self->{mode} = $rec->{val2} if ($rec->{val1} eq ':mode');

        if ($rec->{val1} eq ':pattern'){
            push @{$self->{filters}}, {str=>$rec->{val2}, repl=>$rec->{val3}};
        }
    }
}

sub rmFilter{
    my $self = shift;
    my $opts = shift;
    $self->loadCollection();

    my @records = $self->{c}->matchRecords({val1=>':pattern', val2=>$opts->{pattern}});
    if (!@records){
        return "Couldn't find that pattern: $opts->{pattern}";
    }

    $self->{c}->delete($records[0]->{row_id});
    return "Filter deleted.";
}

sub addFilter{
    my $self = shift;
    my $opts = shift;
    $self->loadCollection();
    my @records = $self->{c}->matchRecords({val1=>$opts->{pattern}});
    if (@records){
        return "That filter already exists.";
    }
    $self->{c}->add(':pattern', $opts->{pattern}, $opts->{replacement});
    return "Filter added.";
}

sub setMode{
    my $self = shift;
    my $mode= shift;
    $self->loadCollection();

    my @modes = (qw(replace remove censor kill));
    if ( ! ($mode ~~ @modes)){
        return "Invalid mode.  Pick from replace, remove, censor, kill.";
    }

    my @records = $self->{c}->matchRecords({val1=>':mode'});
    if (@records){
        $self->{c}->updateRecord($records[0]->{row_id}, {val2=>$mode});
    }else{
        $self->{c}->add(':mode', $mode);
    }
    return "Mode changed.";
}

sub filter{
    my $self = shift;
    my $line = shift;

    my $match = 0;
    foreach my $f (@{$self->{filters}}){
        my $str = $f->{str};
        my $repl = $f->{repl};


        if ( $line =~/$str/gis ){
            $match = 1;

            if ($self->{mode} eq 'remove'){
                $line =~s/$str//gis;

            }elsif ($self->{mode} eq 'replace'){
                $line =~s/$str/$repl/gis;

            }elsif ($self->{mode} eq 'censor'){
                $line =~s/$str/******/gis;
            }
        }
    }

    if ($match && ($self->{mode} eq 'kill')){
        return "";
    }else{
        return $line;
    }
}
1;
__END__
