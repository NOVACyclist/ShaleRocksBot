package plugins::Alias;
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

my @aliases;

sub onBotStart{
   my $self = shift;
    
    ## Add some default aliases

    if (!$self->globalCookie("first_run")){
        print "Adding default aliases...\n";
        my $c = $self->getCollection(__PACKAGE__, 'alias');

        if (!$self->botCan("which")){
            print "added which\n";
            $c->add('which', 'help $* --info', ':system');
        }

        if (!$self->botCan("g")){
            print "added g\n";
            $c->add('g', 'lucky $*', ':system');
        }

        if (!$self->botCan("gg")){
            print "added gg\n";
            $c->add('gg', 'google $*', ':system');
        }

        print "Set first_run cookie so this will never run again.\n";
        $self->globalCookie("first_run", 1);

    }else{
        print "Not adding default aliases\n";
    }
}

sub plugin_init{
    my $self = shift;
    my $c = $self->getCollection(__PACKAGE__, 'alias');
    my @records = $c->getAllRecords();

    foreach my $rec (@records){
        push @{$self->{aliases}}, {alias=>$rec->{val1}, command=>$rec->{val2}, created_by=>$rec->{val3}};
    }
    
    return $self;
}


sub getOutput {
    my $self = shift;

    my $cmd = $self->{command};         # the command
    my $options = $self->{options};     # everything else on the line
    my $options_unparsed = $self->{options_unparsed};  #with the flags intact
    my $channel = $self->{channel};                 
    my $mask = $self->{mask};               # the users hostmask, not including the username
    my $nick = $self->{nick};               

    my $output = "";

    
    if ($cmd eq 'alias'){

        ## Add a new alias
        if ($self->hasFlag("add")){
            my $pname = $self->hasFlagValue("name");
            my $pcommand = $self->hasFlagValue("command");
            return "-command is required" if (!$pcommand);
            return "-name is required" if (!$pname);

            if ($self->botCan($pname)){
                return "$self->{BotName} already has a command called $pname.";
            }

            my $c = $self->getCollection(__PACKAGE__, 'alias');
            if ($c->matchRecords({val1=>$pname})){
                return "Alias $pname already exists";
            }

            $c->add($pname, $pcommand, $self->accountNick());
            $self->returnType("reloadPlugins");
            return "$pname added.";
        }

        
        ## list aliases
        if ($self->hasFlag("list")){

            if (my $palias = $self->hasFlagValue("list")){
                foreach my $alias (@{$self->{aliases}}){
                    if ($alias->{alias} eq $palias){
                        return "$palias is defined as \"$alias->{command}";
                    }
                }
                return "$palias not found.";
            }
    
            foreach my $alias (@{$self->{aliases}}){
                $self->addToList($alias->{alias});
            }

            my $list = $self->getList();
            if ($list){
                return "Aliases: " . $list;
            }else{
                return "No aliases are defined.";
            }
        }


        ## delete an alias
        if (my $pname = $self->hasFlagValue("delete")){
            my $c = $self->getCollection(__PACKAGE__, 'alias');

            my @records = $c->matchRecords({val1=>$pname});

            if (@records){
                $c->delete($records[0]->{row_id});
                $self->returnType("reloadPlugins");
                return "Alias $pname deleted";
            }
            return "I couldn't find alias $pname.";
        }
    }

    ##
    ##  If we're here, we called an alias.  Figure it out.
    ##

    foreach my $alias (@{$self->{aliases}}){
        $options = $self->{options_unparsed};
        if ($alias->{alias} eq $cmd){
            my $acommand = $alias->{command};
            my @args;
            if ($options){
                @args = split / /, $options;
            }

            my $highest_req = 0;
            my $highest_opt = 0;

            while ($alias->{command}=~m/\$([0-9]+)/g){
                my $num = $1;
                if ($highest_req < $num  ){
                    $highest_req = $num ;
                }
            }

            if ($highest_req > @args){
                return "Alias $cmd requires $highest_req arguments";
            }

            while ($alias->{command}=~m/\$([0-9]+)/g){
                my $num = $1;
                $acommand=~s/\$$num/$args[$num-1]/g;
            }

            while ($alias->{command}=~m/\@([0-9]+)/g){
                my $num = $1;
                if ($highest_opt < $num  ){
                    $highest_opt = $num ;
                }

                if ( $num <= @args){
                    $acommand=~s/\@$num/$args[$num-1]/g;
                }else{
                    $acommand=~s/\@$num //g;
                }
            }

            my @remaining;
            if ($highest_opt){
                @remaining = @args[($highest_opt ) .. $#args];
            }else{
                @remaining = @args[($highest_req ) .. $#args];
            }

            my $r = join " ", @remaining;   
            $acommand=~s/\$\*/$r/;

            $self->returnType("runBotCommand");
            return "$acommand";
        }
    }

    return $self->help("alias");
}


sub listeners{
    my $self = shift;
    
    my @commands = ('alias');

    foreach my $alias (@{$self->{aliases}}){
        push @commands, $alias->{alias};
    }

    my @irc_events = [qw () ];

    my @preg_matches = [qw () ];

    my $default_permissions =[
        {command=>"PLUGIN", flag=>"add", require_group => UA_REGISTERED},
    ];

    return {commands=>\@commands, permissions=>$default_permissions, 
        irc_events=>@irc_events, preg_matches=>@preg_matches};
}

##
## addHelp()
##  The help system will pull from here using PluginBaseClass->help(key).
##
sub addHelp{
    my $self = shift;
    $self->addHelpItem("[plugin_description]", "Create aliases. When creating, use \$1, \$2, etc., to refer to required arguments.  Use \@3, \@4, etc., to refer to optional arguments.  Optional argument numbering starts where requirement argument numbering left off. Use \$* to refer to all arguments, or all remaining arguments.");
   $self->addHelpItem("[alias]", "Create a new alias: alias -add -name=<alias> -command=<command>.  List aliases: alias -list.  Show an alias definition: alias -list=<alias name>.  Delete an alias:  alias -delete=<alias>");
   $self->addHelpItem("[alias][-add]", "Create a new alias: alias -add -name=<alias> -command=<command>. When adding aliases, use \$1, \$2, etc., to refer to required arguments.  Use \@3, \@4, etc., to refer to optional arguments.  Optional argument numbering starts where requirement argument numbering left off.  Use \$* to refer to all arguments, or all remaining arguments.");

    foreach my $alias (@{$self->{aliases}}){
        $self->addHelpItem("[".$alias->{alias}."]", "The command '$alias->{alias}' is an alias to \"$alias->{command}\", and was created by $alias->{created_by}.");
    }
}
1;
__END__
