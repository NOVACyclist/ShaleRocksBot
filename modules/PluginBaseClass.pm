package modules::PluginBaseClass;
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

use base 'Exporter';

our @EXPORT = qw(UA_ADMIN UA_TRUSTED UA_REGISTERED UA_UNREGISTERED UA_INTERNAL 
	UA_ADMIN_LEVEL UA_TRUSTED_LEVEL UA_REGISTERED_LEVEL UA_UNREGISTERED_LEVEL UA_INTERNAL_LEVEL
	BULLET DEGREE FLAG_ON NORMAL BOLD UNDERLINE REVERSE ITALIC FIXED WHITE BLACK
    BLUE GREEN RED BROWN PURPLE ORANGE YELLOW LIGHT_GREEN TEAL LIGHT_CYAN
    LIGHT_BLUE PINK GREY LIGHT_GREY );

BEGIN {
  $modules::PluginBaseClass::VERSION = '1.0';
}

use strict;
use warnings;

use modules::Collection;
use constant Collection => 'modules::Collection';
use modules::UserAuth;
use constant UserAuth => 'modules::UserAuth';
use modules::Utilities;
use modules::EventTimer;
use constant EventTimer => 'modules::EventTimer';

#use LWP;
#use URI::Escape;
use Data::Dumper;
use IRC::Utils ':ALL';
use HTML::Entities;
use HTTP::Request::Common qw(POST);
use LWP::UserAgent;
#use MIME::Base64;
use DBI;
use Text::ParseWords;
use Time::HiRes;

use constant{	
	BULLET => "\x{2022}",
	DEGREE => "\x{00B0}"
};


## These are from IRC::Utils.
## http://cpansearch.perl.org/src/HINRIK/IRC-Utils-0.12/lib/IRC/Utils.pm
## I put them here to make things easier.
use constant {
    # cancel all formatting and colors
    NORMAL      => "\x0f",

    # formatting
    BOLD        => "\x02",
    UNDERLINE   => "\x1f",
    REVERSE     => "\x16",

    # mIRC colors
    WHITE       => "\x0300",
    BLACK       => "\x0301",
    BLUE        => "\x0302",
    GREEN       => "\x0303",
    RED         => "\x0304",
    BROWN       => "\x0305",
    PURPLE      => "\x0306",
    ORANGE      => "\x0307",
    YELLOW      => "\x0308",
    LIGHT_GREEN => "\x0309",
    TEAL        => "\x0310",
    LIGHT_CYAN  => "\x0311",
    LIGHT_BLUE  => "\x0312",
    PINK        => "\x0313",
    GREY        => "\x0314",
    LIGHT_GREY  => "\x0315",
};

my $UserAuthObj;

my %HELP;
my %INIT_OPTIONS;
my %SETTINGS;

my $options_unparsed;
my $options;
my $command;
my $nick;
my $account_nick;
my $irc_event;
my $channel;
my $mask;
my $BotCommandPrefix;
my $PackageShortName;
my $BotDatabaseFile;
my $BotName;
my $FLAGS;
my $BotOwnerNick;
my $publish_module;
my $privacy_filter_enable;

my $BotPluginInfo;  #all the other plugins the bot knows about

my $yield_command;
my $yield_args;
my $reentry_command;
my $reentry_options;
my $no_flags;
my $no_pipes;

my $ReturnType;
my $SuppressNick;
my $OutputDelimiter;

my	$EventTimerObj;

my $pm_recipient;
my $pm_content;

my $sql_pragma_synchronous;
my $keep_stats; # see config file for info
my $keep_stats_start;
my @keep_stats_records;
my @keep_stats_collections;

my $cookies_channels;	#keep cookies channel specific 0 or 1 
my $cookies_c;   # collection, loaded only if necessary
my $settings_c;  # collection. loaded only if necessary

sub new {
	my ($class, @args) = @_;
	my $self = bless {}, $class;

	## We need to know this stuff now so it's available to plugin_init & help

	$self->{INIT_OPTIONS} = shift @args;
	$self->{UserAuthObj} = shift @args;

	$self->{account_nick} = $self->{UserAuthObj}->{nick};
	$self->{BotName} = $self->{INIT_OPTIONS}->{BotName};
	$self->{BotCommandPrefix} = $self->{INIT_OPTIONS}->{BotCommandPrefix};
	$self->{BotDatabaseFile} = $self->{INIT_OPTIONS}->{BotDatabaseFile};
	$self->{PackageShortName} = $self->{INIT_OPTIONS}->{PackageShortName};
	$self->{BotOwnerNick} = $self->{INIT_OPTIONS}->{BotOwnerNick};
	$self->{keep_stats} = $self->{INIT_OPTIONS}->{SpeedTraceLevel} || 0;
	$self->{sql_pragma_synchronous} = $self->{INIT_OPTIONS}->{sql_pragma_synchronous};
	$self->{publish_module}  = $self->{INIT_OPTIONS}->{publish_module};
	$self->{privacy_filter_enable}  = $self->{INIT_OPTIONS}->{privacy_filter_enable};

	$self->{options} = "";
	$self->{command} = "";
	$self->{no_flags} = 0;
	$self->{no_pipes} = 0;

	## The default options.  Plugin author should override in plugin if necessary.
	$self->returnType("text");
	$self->outputDelimiter(" ");
	$self->suppressNick("false");

	$self->{cookies_channels} = 0;

	$self->settings();
	$self->loadSettings();

	$self = $self->plugin_init(@args);

	## help comes last because plugin_init might generate the help entries.
	$self->addHelp();
		
	return $self;
}

## Override in your plugin if necessary.
sub plugin_init{
	my ($self, @args) = @_;
	return $self;
}

## Override in your plugin if necessary.
sub onBotStart{
	my $self = shift;
}

## Should override this in the plugin file. This is basically "main"
sub getOutput {
	my $self = shift;
	return $self->{output};
}

## Override in your plugin if necessary.
sub settings{
	my $self = shift;
}

## override this in your plugin. this tells the bot what the plugin listens for
sub listeners{
   my $self = shift;
	## Which commands should this plugin respond to?
	## Command Listeners - put em here.  eg [qw (cmd1 cmd2 cmd3)]
   my @commands = [qw()];

	## irc events to listen for. Values: irc_join
	my @irc_events = [qw () ];

	## Send lines that match these regexes to this plugin
	## Example:  ["/^$self->{BotName}/i",  '/hug (\w+)\W*'.$self->{BotName}.'/i' ]
	## The only modifier you can use is /i
	my @preg_matches = [qw () ];

	## Works in conjuntion with preg_matches.  Match patterns in preg_matches but not
	## these patters.  example: ["/^$self->{BotName}, tell/i"]
	my @preg_excludes = [ ];

	## Default permissions for these commands.  These can be changed by the bot owner
	## using the permissions command, bu these are the defaults.
	#  UA_INTERNAL       (A command that only the bot should run.  Mostly reentry commands.
	#  UA_ADMIN          (Admininstrators only.  Full control.)
	#  UA_TRUSTED        (trusted users - by default they can do some admin stuff)
	#  UA_REGISTERED     (registered users)
	#  UA_UNREGISTERED   (world)
	#  If you don't specify any permissions, UA_UNREGISTERED is assumed.
	#  Use PLUGIN to set the default permission for the plugin as a whole. All commands will
	#     then require at least that level of access.
	#  There's a hiearchy.  Each user level can do everything that the levels below them can do.
	#  You can restrict commands by flag using the flag parameter.
	
	# Example 1:
	#		only registered users may run commands in this plugin, only admin may run foo
	# my $default_permissions =[
	# {command=>"PLUGIN", require_group => UA_REGISTERED},
	# {command=>"foo", require_group => UA_ADMIN},
	# ]
	
	# Example 2:
	#		anyone may run any command in the plugin, only admin can use flag -god with command foo
	# my $default_permissions =[
	# {command=>"PLUGIN", require_group => UA_UNREGISTERED},
	# {command=>"foo", flag=>"god", require_group => UA_ADMIN},
	# ]

	# Example 3:
	#		anyone may run any command in the plugin, only bot owner can use flag -god with command foo
	# my $default_permissions =[
	# {command=>"foo", flag=>"god", require_users=> ["$self->{BotOwnerNick}"]}	
	# ]

	# Example 4:
	#  anyone may run any command in the plugin, only trusted users may use flag "super" with
	#     any command within the plugin, but make an exception for user cowbell and let him run
	#     the command too, even though he's not a member of trusted.
	# my $default_permissions =[
	# {command=>"PLUGIN", flag=>"super", require_group =>UA_TRUSTED, allow_users=>['cowbell']}  
	# ]
	
	my $default_permissions =[command=>'', flag=>'', require_group=>'', require_users=>[''], allow_users=>[''] ];


	# return the info
   return {	commands=>@commands, 
				permissions=>$default_permissions,
				irc_events=>@irc_events, 
				preg_matches=>@preg_matches,
				preg_excludes=>@preg_excludes
	};

}

## Override this in your plugin
sub addHelp{
	my $self=shift;
}

## accountNick may not be the same as current nick.
sub accountNick{
	my $self = shift;
	return $self->{account_nick};
}

sub getInitOption{
	my $self = shift;
	my $key = shift;

	return $self->{INIT_OPTIONS}->{$key};
}

## This function also appears in UserAuth.
sub getCollection{
	my $self = shift;
	my ($module_name, $collection_name) = @_;
	
	if (!$module_name || !$collection_name){
		print "ATTENTION: You're something wrong with your collection.\n";
		print "You need to supply both a module_name and a collection_name.\n";
		print "You specified module_name:$module_name  collection_name:$collection_name\n";
		exit;
	}

	$self->keepStats({a=>'start'});
	#my $c = $self->Collection->new($self->{BotDatabaseFile}, $module_name, $collection_name);

	$module_name=~s/^.+\:(\w+)$/$1/gis;
	my $c = $self->Collection->new({db_file=>$self->{BotDatabaseFile}, module_name=>$module_name, 
			collection_name=>$collection_name, keep_stats=>$self->{keep_stats}, 
		sql_pragma_synchronous=>$self->{sql_pragma_synchronous}});

	$c->load();
	$self->keepStats({a=>'end', data=>$module_name."->".$collection_name});
	push @{$self->{keep_stats_collections}}, $c;
	return $c;
}


##
## This is called by the CommandHandler
##

sub run{
	my $self = shift;

	$self->keepStats({a=>'start', id=>'run'});
	if (!defined($self->{BotDatabaseFile})){
		return "Error.  No BotDatabaseFile specified";
	}

	if (!$self->{UserAuthObj}){
		print "Error - where's the UserAuthObj?\n";
		return;
	}

	my $output;
	if ($self->{command} && $self->hasFlag("help")){
		$output= BOLD."Command help: ".NORMAL.$self->help($self->{command}) ." ";
		$output.= $self->BULLET .BLUE." Use ".$self->{BotCommandPrefix}."help $self->{command}";
		$output.=" --info for general plugin information.".NORMAL;
		return $output;

	}elsif($self->{command} && $self->hasFlag("settings")){
		$output = $self->modPluginSettings();

	}elsif($self->{command} ne $self->{PackageShortName}){
		$output = $self->getOutput();
	}

	if ($self->{keep_stats}){
		$self->keepStats({a=>'end', id=>'run', data=>''});

		my $count = 0;
		foreach my $c (@{$self->{keep_stats_collections}}){
			my @info = $c->getStats();
			push @{$self->{keep_stats_records}}, "\t+++ $count $c->{collection_name}";
			foreach my $i (@info){
				push @{$self->{keep_stats_records}}, "\t$i";
			}
			$count++;
		}
	}

	if ($output){
		if (ref($output) eq 'ARRAY'){
			return @{$output};

		}else{
			my @arr;
			push @arr, $output;
			return @arr;
		}
	}
}




sub outputFilter{
   my $self = shift;

	return $self->{UserAuthObj}->outputFilter();
}

sub yieldCommand{
   my $self = shift;
	my $x = shift;

	if ($x){
		$self->{yield_command} = $x;
	}else{
		return $self->{yield_command};
	}
}

sub yieldArgs{
   my $self = shift;
	my $x = shift;
	
	if ($x){
		$self->{yield_args} = $x;
	}else{
		return $self->{yield_args};
	}
}

sub setReentryCommand{
   my $self = shift;
   my $reentry_command= shift;
   my $reentry_options= shift;
	$self->{reentry_command} = $reentry_command;
	$self->{reentry_options} = $reentry_options;
}

sub getReentryCommand{
   my $self = shift;
	return $self->{reentry_command};
}

sub getReentryOptions{
   my $self = shift;
	return $self->{reentry_options};
}


sub clearReentryCommand{
   my $self = shift;
	delete ($self->{reentry_command});
	delete ($self->{reentry_options});
}

sub returnType{
	my $self = shift;
	my $v = shift;

	if ($v){
		$self->{ReturnType} = $v;
	}else{
		return $self->{ReturnType};
	}
}

sub outputDelimiter{
	my $self = shift;
	my $v = shift;

	if ($v){
		$self->{OutputDelimiter} = $v;
	}else{
		return $self->{OutputDelimiter};
	}
}
sub suppressNick{
	my $self = shift;
	my $v = shift;

	if ($v){
		$self->{SuppressNick} = $v;

	}else{
		if (lc($self->{SuppressNick}) eq "false"){
			return 0;
		}else{
			return 1;
		}
	}
}

sub hasPermission{
	my $self = shift;
	my $pnick = shift;

	if (!$pnick){
		print "PBC.hP.1 - not asking the right question.";
		return 0;
	}

	return $self->{'UserAuthObj'}->hasPermission($pnick);
}

sub isAuthed{
	my $self = shift;
	return ($self->{'UserAuthObj'}->isAuthed());
}

sub hasAccount{
	my $self = shift;
	return ($self->{'UserAuthObj'}->accountExists());
}


my %addToList_lists;
sub addToList{
	my $self = shift;
	my $item = shift;
	my $bullet = shift;
	my $list_id = shift;
		
	if (!$bullet){
		$bullet = ", ";
	}else{
		$bullet = " $bullet ";
	}
	
	$list_id = '_frumious_' if (!$list_id);
	
	if (defined($self->{addToList_lists}->{$list_id})){
		$self->{addToList_lists}->{$list_id} .= $bullet . $item;

	}else{
		$self->{addToList_lists}->{$list_id} = $item;
	}
}

sub getList{
	my $self = shift;
	my $list_id = shift;

	$list_id = '_frumious_' if (!$list_id);

	my $ret = $self->{addToList_lists}->{$list_id};
	delete ($self->{addToList_lists}->{$list_id});
	return $ret;
}


sub setValue{
   my $self = shift;

   my ($k, $v) = @_;

	# make a copy ????
	my $key = $k;
	my $value = $v;

	if ($value){
		# remove trailing & leading space

		if (!$self->{no_flags}){
			$value=~s/ +?$//;
			$value=~s/^ (\S)/$1/;
		}

		$self->{$key} = $value;

		## Parse options for flags
		#print "No flags is $self->{'no_flags'}\n";

		if ( ($key eq 'options') && (!$self->{no_flags}) ){
			$self->{options_unparsed} = $self->{options};

			my $out = parseFlags($self->{options});
			$self->{options} = $out->{options};
			$self->{FLAGS} = $out->{flags};
		}
	}
}

## Returns 1 if the flag was set, regardless of whether a value was specified
sub hasFlag{
	my $self = shift;
	my $flag = shift;

	if (defined($self->{FLAGS}->{$flag})){
		return 1;

	}else{
		return 0;
	}
}

## Gets a flag's value.  This will return 0 if the flag was set but not assigned a value.
#  Intended to be used when a flag requires a value, not just an "on"
sub hasFlagValue{
	my $self = shift;
	my $flag = shift;

	if (defined($self->{FLAGS}->{$flag})){
		if ($self->{FLAGS}->{$flag} eq $self->FLAG_ON){
			return 0;
		}else{
			return $self->{FLAGS}->{$flag};
		}

	}else{
		return 0;
	}
}

sub numFlags{
	my $self = shift;

	if ($self->{FLAGS}){
		my $c = keys ($self->{FLAGS});
		$c = $c / 2;
		return $c;
	}else{
		return 0;
	}
}

sub flagPosition{
	my $self = shift;
	my $flag = shift;

	if ($self->{FLAGS}->{$flag . '_pos'}){
		return $self->{FLAGS}->{$flag . '_pos'};
	}else{
		return 0;
	}
}

sub getValue {
   my $self = shift;
	my $key = shift;
	#print "getting $key\n";
	#print "value is " . $self->$key . "\n";

	if (defined($self->$key)){
		return ($self->$key);
	}else{
		#print "ERROR - not defined\n";
		return "";
	}
}


sub getStats{
	my $self = shift;

	if (defined($self->{keep_stats_records})){
		return @{$self->{keep_stats_records}};
	}else{
		return ();
	}
}


sub keepStats{
	my $self = shift;
	my $opts = shift;
	
	return if ($self->{keep_stats} < 3);

	my $id = $opts->{id} || 'default';

	if ($opts->{a} eq 'start'){
		$self->{keep_stats_start}->{$id} = Time::HiRes::time();
	}

	if ($opts->{a} eq 'end'){
		my $time = sprintf( "%.3f", Time::HiRes::time() - $self->{keep_stats_start}->{$id});
		my $parent = ( caller(1) )[3];
		$parent=~/PluginBaseClass::(.+?)$/;
		$parent = $1;
		my $line = "$time\t".$self->{PackageShortName}."->$parent\t" . $opts->{data};
		push @{$self->{keep_stats_records}}, $line;
	}
}


sub getPage {
	my $self = shift;
	my $url = shift;

	$self->keepStats({a=>'start'});

	my $ua = LWP::UserAgent->new;

	$ua->agent("Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1)");
	$ua->timeout(5);

	my $req = HTTP::Request->new(GET => $url);
	my $res = $ua->request($req);

	$self->keepStats({a=>'end', data=>$url});

	if ($res->is_success) {
		return decode_entities($res->content);
	}
	
	if ($res->is_error){
		print "error with lwp:\n";
		printf "[%d] %s\n", $res->code, $res->message;
	}

	return "";
}


sub publish{
	my $self = shift;
	my $content = shift;

	my $m = $self->{publish_module};

	eval "require $m";
	if ($@){
		print "ERROR $@\n";
		return "Error # pbc.p.1";
	}

	my $p = $m->new();
	my $link = $p->publish($content);

	if ($link=~/^http/){
		return $self->getShortURL($link);
	}else{
		return $link;
	}
}


sub getShortURL{
	my $self = shift;
	my $url = shift;
	
	my $shortlink = $self->getPage("http://is.gd/create.php?format=simple&url=" . $url);
	
	if ($shortlink=~/http/){
		return $shortlink;
	}else{
		return $url;
	}
}

sub help{
   my $self = shift;
   my @commands = @_;
	my $key;
	my $list;

	my $package = $self->{PackageShortName};
	
	foreach my $c (@commands){
		$key.="[$c]";
		$list.="$c ";
	}
	
	if (!@commands || $commands[0] eq '--info'){
		if ($self->{HELP}->{'[plugin_description]'}){
			return BOLD."Plugin name:".NORMAL." $package. " . $self->{HELP}->{'[plugin_description]'};
		}else{
			return "The $package plugin does not have a description. Sorry about that.";
		}
	}

	if ($commands[0] eq '--all'){
		#print Dumper($self->{HELP});
	}

	my $newpos;
	do {
		#print "Try key $key\n";

		if ($self->{HELP}->{$key}){
			return $self->{HELP}->{$key};
		}

		my $curpos = rindex($key, "]");
		$newpos = rindex($key, "]", $curpos-1);
		$key = substr($key, 0, $newpos+1);

	}while($newpos > 0);

	my $ret = "No help available for $package.$list. ";

	if ($self->{HELP}->{'[plugin_description]'}){
		$ret.="But all is not lost. Here is the plugin description: ";
		$ret.= $self->{HELP}->{'[plugin_description]'}
	}else{
		$ret .= "And the plugin doesn't have a description either.  Sorry about that.";
	}

	return $ret;
}


## this is misleadingly named it. it doesnt refresh anything. 
## it's called by CH to see if the bot needs to update the timer.

sub refreshTimer{
	my $self = shift;
	if ($self->{EventTimerObj}){
		return 1;
	}else{
		return 0;
	}
}


#$args = {
#	sec=> '',
#	min=> '',
#	hour=> '',
#	command => '',
#	options => ''
#  channel =>''
#}
sub scheduleCronJob{
	my $self = shift;
	my $args = shift;

	my $nick = $self->{nick};
	my $mask = $self->{mask};
	my $channel = $args->{channel} || $self->{channel};

	if (!$self->{EventTimerObj}){
		$self->{EventTimerObj} = EventTimer->new($self->{BotDatabaseFile}, $self->{PackageShortName});
	}
	
	my $cron_args = {
   	job_sec => $args->{sec},
   	job_min => $args->{min},
   	job_hour => $args->{hour},
   	command=> $args->{command},
   	options=> $args->{options},
   	nick => $nick,
   	mask => $mask,
   	channel => $channel,
	};

	$self->{EventTimerObj}->scheduleCronJob($cron_args);
}

#$args = {
#	timestamp => '',
#	command => '',
#	options => '',
#  internal => 0,  # run as internal user?
#	desc => ''
#}

sub scheduleEvent{
	my $self = shift;
	my $args = shift;

	my $nick = $self->{nick};
	my $mask = $self->{mask};

	if ($args->{internal}){
		$nick =  UA_INTERNAL;
		$mask= UA_INTERNAL;
	}

	my $channel = $args->{channel} || $self->{channel};

	if (!$self->{EventTimerObj}){
		$self->{EventTimerObj} = EventTimer->new($self->{BotDatabaseFile}, $self->{PackageShortName});
	}
	
	my $timer_args = {
   	event_time => $args->{timestamp},
  	 	event_type=> 'command',
   	module_name=> $self->{PackageShortName},
   	command=> $args->{command},
   	options=> $args->{options},
   	nick => $nick,
   	mask => $mask,
   	channel => $channel,
   	event_description=> $args->{desc}
	};

	return $self->{EventTimerObj}->scheduleEvent($timer_args);
}


sub botCan{
	my $self= shift;
	my $pcmd = shift;

	if (!$pcmd){
		return 0;
	}

	foreach my $k (keys $self->{BotPluginInfo}){
		foreach my $cmd (@{$self->{BotPluginInfo}->{$k}->{commands}}){
			if ($cmd eq $pcmd){
				return 1;
			}
		}
	}

   return 0;
}


sub botPluginCan{
	my $self= shift;
	my $pplugin = shift;
	my $pcmd = shift;

	return 0 if (!$pcmd);
	return 0 if (!$pplugin);

	foreach my $cmd (@{$self->{BotPluginInfo}->{$pplugin}->{commands}}){
		if ($cmd eq $pcmd){
			return 1;
		}
	}

   return 0;
}

sub sendPM{
	my $self=shift;
	my $nick = shift;
	my $msg = shift;

	if ($nick && $msg){
		$self->{pm_recipient} = $nick;
		$self->{pm_content} = $msg;
	}
}


sub hasPM{
	my $self = shift;
	if ($self->{pm_recipient}){
		return 1;
	}
	return 0;
}

sub getPM{
	my $self = shift;
	return {nick=>$self->{pm_recipient}, msg=>$self->{pm_content}} ;
}

sub useChannelCookies{
	my $self = shift;
	$self->{cookies_channels} = 1;
}

sub noChannelCookies{
	my $self = shift;
	$self->{cookies_channels} = 0;
}


sub globalCookie{
	my $self = shift;
	my $key = shift;
	my $value = shift;

	return $self->_cookie(':package', $key, $value);
}

sub cookie{
	my $self = shift;
	my $key = shift;
	my $value = shift;

	return $self->_cookie($self->accountNick(), $key, $value);
}


sub deleteCookie{
	my $self = shift;
	my $key = shift;
	return $self->_cookie($self->accountNick(), $key, ':delete');
}

sub deleteGlobalCookie{
	my $self = shift;
	my $key = shift;
	return $self->_cookie(':package', $key, ':delete');
}

sub deletePackageCookies{
	my $self = shift;
	my $key = shift;

	if (!$self->{cookies_c}){
		$self->{cookies_c} = $self->getCollection($self->{PackageShortName}, '::cookies::');
	}
	
	my @records;
	if ($self->{cookies_channels}){
		@records = $self->{cookies_c}->matchRecords({val4=>$self->{channel}});
	}else{
		@records = $self->{cookies_c}->getAllRecords();
	}

	$self->{cookies_c}->startBatch();
	foreach my $rec (@records){
		$self->{cookies_c}->delete($rec->{row_id});
	}
	$self->{cookies_c}->endBatch();
}
	
sub allCookies{
	my $self = shift;
	my $key = shift;

	if (!$self->{cookies_c}){
		$self->{cookies_c} = $self->getCollection($self->{PackageShortName}, '::cookies::');
	}

	my @records;
	if ($self->{cookies_channels}){
		@records = $self->{cookies_c}->matchRecords({val4=>$self->{channel}});
	}else{
		@records = $self->{cookies_c}->getAllRecords();
	}
	
	my @ret;
	foreach my $rec (@records){	
		push @ret, {owner=>$rec->{val1}, name=> $rec->{val2}, value=>$rec->{val3}, channel=>$rec->{val4}};
	}

	return @ret;
}	

sub _cookie{
	my $self = shift;
	my $val1 = shift;
	my $key = shift;
	my $value = shift;

	if (!$key){
		print "Cookie error in $self->{PackageShortName} - must supply key\n";
		return "";
	}

	if (!$self->{cookies_c}){
		$self->{cookies_c} = $self->getCollection($self->{PackageShortName}, '::cookies::');
	}

	my @records;
	if ($self->{cookies_channels}){
		@records = $self->{cookies_c}->matchRecords({val1=>$val1, val2=>$key, val4=>$self->{channel}});
	}else{
		@records = $self->{cookies_c}->matchRecords({val1=>$val1, val2=>$key, val4=>''});
	}

	if (defined($value) && $value eq ':delete'){
		$self->{cookies_c}->delete($records[0]->{row_id});
		return;

	}elsif (defined($value)){
		if (@records){
			$self->{cookies_c}->updateRecord($records[0]->{row_id}, {val3=>$value});
		}else{
			if ($self->{cookies_channels}){
				$self->{cookies_c}->add($val1, $key, $value, $self->{channel});
			}else{
				$self->{cookies_c}->add($val1, $key, $value);
			}
		}

		return $value;
	}

	if (defined ($records[0]->{val3})){
		return $records[0]->{val3};
	}else{
		return "";
	}
}

sub addHelpItem{
   my $self = shift;
	my ($key, $value) =   @_;
	$self->{HELP}->{$key} = $value;
}


##
##	Settings
##

sub loadSettings{
	my $self = shift;
	return if (!defined($self->{SETTINGS}));

	$self->{settings_c} = $self->getCollection($self->{PackageShortName}, '::settings::');
	my @records = $self->{settings_c}->getAllRecords();

	foreach my $rec(@records){
		my $name = $rec->{val1};
		my $current = $rec->{val2};

		if (defined($self->{SETTINGS}->{$name})){
			$self->{SETTINGS}->{$name}->{value} = $current;
		}
	}
}

sub s{
	my $self = shift;
	return $self->setting(@_);
}

sub hasSettings{
	my $self = shift;

	if (!defined($self->{SETTINGS})){
		return 0;
	}

	return 1;
}


sub setting{
	my $self = shift;
	my $key = shift;
	my $value = shift;

	if (defined($value)){
		$self->{SETTINGS}->{$key}->{value} = $value;
		return $value;
	}

	return $self->{SETTINGS}->{$key}->{value};
}


sub defineSetting{
	my $self = shift;
	my $opts = shift;

	my $name = $opts->{name};
	my $default = $opts->{default};
	my $desc = $opts->{desc};
	$opts->{value} = $default;
	$self->{SETTINGS}->{$name} = $opts;
}


sub modPluginSettings{
	my $self = shift;
	my $output;
	$self->suppressNick("true");

	if (!defined($self->{SETTINGS})){
		return "Plugin '$self->{PackageShortName}' has no configurable settings.";
	}
	
	if ($self->hasFlag("set")){
		my $value = $self->hasFlagValue("value");
		my $setting = $self->hasFlagValue("setting");

		if (!$setting && $self->{options}){
			($setting, $value) = split /=/, $self->{options};
			$setting=~s/^ +//gis;
			$value =~s/^ +//gis;
			$setting=~s/ +$//gis;
			$value=~s/ +$//gis;
		}

		if (!$setting || !$value){
			$output = "Usage: -set <setting> = <value>.  (Or, use -setting=<x>  -value=<x> flags.)";
			return $output;
		}

		if (!defined($self->{SETTINGS}->{$setting})){
			return "That is not a valid setting.";
		}

		if (defined($self->{SETTINGS}->{$setting}->{allowed_values}) 
		&& @{$self->{SETTINGS}->{$setting}->{allowed_values}}){
			if (!($value ~~ @{$self->{SETTINGS}->{$setting}->{allowed_values}})){
				$output = "That is not a valid value. ";
				foreach my $v (@{$self->{SETTINGS}->{$setting}->{allowed_values}}){
					$self->addToList($v);
				}
				$output.="Choose from: " . $self->getList();
				return $output;
			}
		}

		my @records = $self->{settings_c}->matchRecords({val1=>$setting});
		if (@records){
			$self->{settings_c}->updateRecord($records[0]->{row_id}, {val2=>$value});
		}else{
			$self->{settings_c}->add($setting, $value);
		}

		return "$setting has been set to $value. Thank you for choosing $self->{BotName}.";
	}


	if ($self->hasFlag("info")){
		my $k = $self->hasFlagValue("info");
		$k = $self->{options} if (!$k);

		if (!$k){
			return "What setting do you want info about?";
		}

		if (!defined($self->{SETTINGS}->{$k})){
			return "$k is not a valid setting.";
		}
		
		$output = BOLD."Plugin: ".NORMAL.$self->{PackageShortName}." ";
		$output .= BOLD."Setting: ".NORMAL."$k ".BOLD."Current Value: ".NORMAL;
		$output.= $self->{SETTINGS}->{$k}->{value} .BOLD." Description: ".NORMAL;
		$output.= $self->{SETTINGS}->{$k}->{desc}.BOLD." Default Value: ".NORMAL;
		$output.= $self->{SETTINGS}->{$k}->{default};

		if (defined($self->{SETTINGS}->{$k}->{allowed_values}) 
		&& @{$self->{SETTINGS}->{$k}->{allowed_values}}){
			$output.=BOLD." Allowed Values: ".NORMAL;
			foreach my $v (@{$self->{SETTINGS}->{$k}->{allowed_values}}){
				$self->addToList($v);
			}
			$output.= $self->getList();
		}
		return $output;
	}
	

	##
	##	Return a list of all settings
	##

	foreach my $k (keys %{$self->{SETTINGS}}){
		$self->addToList("$k = $self->{SETTINGS}->{$k}->{value}", $self->BULLET);
	}

	my $list = $self->getList();
	my $info = BLUE." (-info <setting> for info. -set <setting> = <value> to set.)";
	return "Settings for plugin '$self->{PackageShortName}': " . $list . $info;
}

1;
__END__
