package plugins::NFLFF;
use strict;         
use warnings;
use base qw (modules::PluginBaseClass);
use modules::PluginBaseClass;
use Data::Dumper;

sub getOutput {
    my $self = shift;
    my $cmd = $self->{command};         # the command
    my $options = $self->{options};     # everything else on the line, except flags
    my $options_unparsed = $self->{options_unparsed};  #with the flags intact
    my $channel = $self->{channel};                 
    my $mask = $self->{mask};               # the users hostmask, not including the username
    my $BotCommandPrefix = $self->{BotCommandPrefix};   
    my $bot_name = $self->{BotName};        # the name of this bot
    my $irc_event = $self->{irc_event}; # the IRC event that triggered this call
    my $BotOwnerNick    = $self->{BotOwnerNick}; 
    my $nick = $self->{nick};   # the nick of the person calling the command
    my $accountNick = $self->accountNick(); 
    my $output = "";
    $self->suppressNick("true");    
    
    if (!$options){
        return $self->help($cmd);
    }

    my $page = $self->getPage($options);

    if ($page=~/<ul class="ss ss-6">(.+?)<\/ul>/s){
        my $match = $1;
        my $bullet = $self->BULLET;
        $match=~s/<\/li>/ $bullet /gis;
        $match=~s/<.+?>//gis;
        $output = $match;
    }else{
        $output  =  "Scores not found.";
    }
                                
    $output .= " " . GREEN . $self->getShortURL($options).NORMAL;   
    return $output; # one message in $output
}


##
##  Settings
##  You can define settings for your plugin.  The user will be able to manage these
## settings using the -settings flag with any command in your plugin, or via the 
## plugin name itself.  
## Access these settings in your code like so: $self->settings('setting name');
## As a shortcut, you can also use $self->s('setting name').
## The settings function is a getter/setter, so if you (for some reason) need to 
## change a setting, you can use $self->settings('setting name', 'new value');
##
sub settings{
    my $self = shift;

    # Call defineSetting for as many settings as you'd like to define.
    $self->defineSetting({
        name=>'setting name',    
        default=>'default value',
        allowed_values=>[],     # enumerated list. leave blank or delete to allow any value
        desc=>'Describe what this setting does'
    });
}


##
## listeners() and addHelp()
##  Note: these functions will be called after plugin_init, which runs few times.
## 1: When the bot starts up, it will instantiate each plugin to get this info.
## 2. When an IRC user uses your plugin. (which is what you'd expect.)
## 3. When a user asks for help using the help system.
## What this means is that if you're doing anything in here like dynamically generating
## help messages or command names, you need to do that in plugin_init(), not getOutput().
## See Diss.pm for an example of dynamically generated help & commands.
## 
sub listeners{
    my $self = shift;
    
    ##  Which commands should this plugin respond to?
    ## Command Listeners - put em here.  eg [qw (cmd1 cmd2 cmd3)]
    my @commands = [qw(nflff)];

    ## Values: irc_join irc_ping irc_part irc_quit
    ## Note that irc_quit does not send channel information, and that the quit message will be 
    ## stuck in $options
    my @irc_events = [qw () ];

    ## Example:  ["/^$self->{BotName}/i",  '/hug (\w+)\W*'.$self->{BotName}.'/i' ]
    ## The only modifier you can use is /i
    my @preg_matches = [qw () ];

    ## Works in conjuntion with preg_matches.  Match patterns in preg_matches but not
    ## these patterns.  example: ["/^$self->{BotName}, tell/i"]
    my @preg_excludes = [ qw() ];


    my $default_permissions =[
    ];

    return { commands=>@commands,
        permissions=>$default_permissions,
        irc_events=>@irc_events,
        preg_matches=>@preg_matches,
        preg_excludes=>@preg_excludes
    };

}

##
## addHelp()
##  The help system will pull from here using PluginBaseClass->help(key).
##
sub addHelp{
    my $self = shift;
    $self->addHelpItem("[plugin_description]", "Get matchups and scores for nfl.com fantasy football.  It's best to set up an alias specifying your league url.");
   $self->addHelpItem("[nflff]", "Usage: nflff <url>");
}
1;
__END__
