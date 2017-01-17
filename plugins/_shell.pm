## The purpose of this file is to be a starting point for new plugins.
## You will likely end up deleting a lot of what's in here. Including these two lines.
package plugins::PACKAGENAME;

## Don't disable strict or warnings, improperly scoped variables can cause problems elsewhere
use strict;
use warnings;
## All plugins extend modules::PluginBaseClass.  You need this.
use base qw (modules::PluginBaseClass);
use modules::PluginBaseClass;
use Data::Dumper;

##
## This is run once per plugin, when the bot starts up.  Delete it if you don't need it.
##
sub onBotStart {
   my $self = shift;
}

##
## plugin_init() is called when the plugin is created, after PluginBaseClass->new() runs.
## This method overrides the plugin_init in PluginBaseClass.
##  Which means you can delete it if you dont need it
##
sub plugin_init {
   my $self = shift;
   return $self;    # if this function exists it needs to return $self.
}

##
##  getOutput() is the "main" block of your plugin.
## The CommandHandler will instantiate your class, set some variables, then call
##  PluginBaseClass->run().  The PBC->run() method will do some stuff then call this.
## You can create as many other subs as you'd like, but this is the entry point
##

sub getOutput {
   my $self = shift;

   ## This are listed for your convenience.  Feel free to delete if you don't
   ## need them, or if you'd prefer to use the $self->{terminology}

   my $cmd              = $self->{command};             # the command
   my $options          = $self->{options};             # everything else on the line, except flags
   my $options_unparsed = $self->{options_unparsed};    #with the flags intact
   my $channel          = $self->{channel};
   my $mask             = $self->{mask};                # the users hostmask, not including the username
   my $BotCommandPrefix = $self->{BotCommandPrefix};
   my $bot_name         = $self->{BotName};             # the name of this bot
   my $irc_event        = $self->{irc_event};           # the IRC event that triggered this call
   my $BotOwnerNick     = $self->{BotOwnerNick};
   my $nick             = $self->{nick};                # the nick of the person calling the command

   # if the person is logged in to an account, the calling nick may not be the same as the
   # account nick.
   my $accountNick = $self->accountNick();

   my $output = "";

   # text, action, runBotCommand, reloadPlugins, irc_yield, shutdown. default is "text".
   # most plugins will return "text".
   $self->returnType("text");

   # how your output will be paginated, if necessary. For instance, if you're returning
   # bullet-separated text, it will be more user friendly if you specify the bullet character
   # here. (Which is, incidentally, available as $self->BULLET.) Default is " ".
   $self->outputDelimiter(" ");

   # prepend the output lines with a nick?  Default is false
   $self->suppressNick("false");

   # if your return type is IRC yield, specify the IRC command here. (eg join, part)
   # $self->yieldCommand("join");
   # $self->yieldOptions("#RocksBot");

   ## Get options that were passed at plugin object instantiation time.
   ## These are from the [Plugin:YourPluginName] section of the config file
   ## Most plugins won't need these. Plugins can't write to the config file,
   ## and that's by design. You should be saving your info in the Collections
   ## database.
   #my $value = $self->getInitOption("Key");

   ## Try to use the help system to provide helpful use messages
   return ( $self->help($cmd) ) if ( $options eq '' );

   # (A note on help: You don't have to provide functionality for a -help flag. The system
   #  will handle that for you.)

   ##
   ## Flags  - the system has already parsed the flags for you & stuck them in $self->{FLAGS}.
   ## These are the flags your plugin cannot use:  help settings
   ##  (Each of these will be intercepted & processed by PluginBaseClass)
   ## You access flags like this:
   ##

   if ( $self->hasFlag("foo") ) {
      $output = "You supplied the -foo flag.  Good for you!";
   }

   if ( my $val = $self->hasFlagValue("foo") ) {
      $output .= "The value you entered using -foo=<blah> is $val";
   }

   $output .= "You supplied " . $self->numFlags() . " flags.";

   ##
   ## Simple database storage/retrieval using "cookies". (probably a poor name)
   ## $self->cookie() is accountNick specific.
   ## $self->globalCookie() is plugin-specific.
   ##
   $self->cookie( "favorite_album", "meddle" );    # creates or sets, current nick's favorite_album to "meddle"
   my $album = $self->cookie("favorite_album");    # retrieves the value for accountNicks' favorite_album
   $self->deleteCookie("favorite_album");          # deletes the cookie with key "favorite_album" for this user.

   my $runs = $self->globalCookie("num_runs");     # get the total # of times this plugin has been run. Not nick specific
   $self->globalCookie( "num_runs", $runs + 1 );   #increment the counter.
   $self->deleteGlobalCookie("num_runs");          # delete this key

   $self->deletePackageCookies();                  #delete all cookies this plugin has created. (that is all user cookies, all global cookies)

   ##
   ## Database access.  RocksBot calls a module's groups of data "collections".
   ## Collections are stored  under PluginName : CollectionName.  You can have as
   ## many collections as you wish, but it's polite to stick to your own namespace.
   ## So PluginName:settings, PluginName:$nick, PluginName:log, whatever.
   ##

   # Load up a collection based on nick using the special __PACKAGE__ variable.
   # my $c = $self->getCollection(__PACKAGE__, $collection_name);
   # Example: my $c = $self->getCollection(__PACKAGE__, $accountNick);
   # Example: load all collections for this plugin: #my $c = $self->getCollection(__PACKAGE__, '%');

   # Add a couple records to the collection
   #$c->add(val1, val2, val3, val4, val5, val6, val7, val8, val9, val10)
   #$c->add(val1, val2);

   # count number of total records
   #$c->numRecords();

   # an individual record entry looks like this:
   #{
   #       'collection_name' => 'planets',
   #       'row_id' => 247,
   #       'display_id' => 1,
   #       'val1' => 'mercury',
   #       'val2' => '35980000',
   #       'val3' => '57910000',
   #       'val4' => 'quicksilver',
   #       'val5' => undef,
   #       'val6' => undef,
   #       'val7' => undef,
   #       'val8' => undef,
   #       'val9' => undef
   #       'val10' => undef,
   #       'sys_creation_date' => '2013-03-13 22:28:05',
   #       'sys_update_date' => undef,
   #       'sys_creation_timestamp' => '1363213685',
   #       'sys_update_timestamp' => undef,
   #     }
   # get an array of hashrefs of all records in this collection.
   #my @records = $c->getAllRecords();

   # get an array of hashrefs for a subset of records.  exact match on field name
   #my @records = $c->matchRecords({val1=>'foo', val4=>'bar'});

   # now let's delete those records
   #foreach my $rec (@records){
   #   $c->delete($rec->{row_id});
   #}

   # you can also delete all records that match a particular pattern.
   #$c->deleteByVal({val1=>'foo', val2=>'bar'});

   # or delete all records in this collection.
   #$c->deleteAllRecords();

   # update a particular record by row_id. Only the specified fields will be changed.
   #$c->updateRecord($row_id, {val1=>'bah', val6=>'boo'})

   # search records (text search)
   #my @records = $c->searchRecords("search string", field number)
   # Example:  $c->searchRecords("foo bar", 1) # Matches (val1=~/foo/ || val1=~/bar/)
   # Example:  $c->searchRecords("+foo -bar", 2)  # Matches (val2=~/foo/ && val2!~/bar/)

   # get records by rec_id. this doesn't happen often. but it's there.
   #my @records = $c->getRecords("1,2,3");

   # some built in sorting of records, if you need it.
   # After calling this, matchRecords() et al will return sorted data
   #$c->sort({field=>"field name", type=> 'alpha' (or 'numeric'), order=>'desc' ( or 'asc')});

   # Publish an HTML page.
   #$self->publish("html content");

   # Get a page from somewhere on the web so you can parse it or whatnot
   #my $page = $self->getPage("http://www.urbandictionary.com/define.php?term=rocks");

   # shorten a URL for cleaner display
   #$self->getShortURL(url);

   # send a PM to a user
   #$self->sendPM($self->{nick}, "Shine on you crazy diamond");

   # Create handy delimited lists for pretty display.
   # Simple:
   # while (something){
   #       $self->addToList("item");
   # }
   # my $list = $self->getList();
   #
   # Advanced:
   # while (something){
   #       (it's item, separator, list name);
   #       $self->addToList("foo", $self->BULLET, "foos");
   #       $self->addToList("bar", $self->BULLET, "bars");
   #   }
   # my $list_of_foos = $self->getList("foos");
   # my $list_of_bars = $self->getList("bars");
   # (ps getList() clears the list, so you can only get it once.)

   ##  Find out if a particular command is registered with the bot.
   #if ($self->botCan("foo"));

   ##
   ##  Timer Events
   ##
   #my $args = {
   #  timestamp => '',     # When
   #  command => '',           # Command to execute.  Use _internal_echo for saying things
   #  options => '',           # Options to pass to the command
   #  desc => ''               # Just informational, internal only.
   #};
   #$self->scheduleEvent($args);

   ## CommandHandler will handle run permissions, but you may want to check if a user
   ## owns a particular data item before allowing him to update it. This is useful b/c it
   ## allows people without accounts to use your plugin, but enforces account security for
   ## people who do have accounts. Example, stick this before a block that does some updating:
   #return ("You don't have permission to do that.") if (!$self->hasPermission($nick));
   # There, you're asking if this person has permission to operate on data belonging
   # to $nick.  If $nick has an account, this will return 0 if this person isn't authed as that user.
   # If $nick doesn't have an account, it will return true, allowing anyone to operate on that
   # data.  See, maximum usability. All a person needs to do to protect their data from
   # meddlin' is create an account.

   ## Run another command after returning from this plugin.
   ## CH will preserve the state of this object.
   ## Make sure you know what you're doing or this will end poorly.
   ## You should probably just delete this whole thing right now, you don't need it.
   ## See Sleep for an example of how to use this
   #$self->setReentryCommand($command, $options);

   ##
   ## Speak to the world.  You can return a string (single message, will be paginated) or an array
   ##  (multiple messages, each will be paginated if necessary.)
   return $output;    # one message in $output
                      #return \@output;   # multiple messages in $output
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
sub settings {
   my $self = shift;

   # Call defineSetting for as many settings as you'd like to define.
   $self->defineSetting(
      {
         name           => 'setting name',
         default        => 'default value',
         allowed_values => [],                                 # enumerated list. leave blank or delete to allow any value
         desc           => 'Describe what this setting does'
      }
   );
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
sub listeners {
   my $self = shift;

   ##  Which commands should this plugin respond to?
   ## Command Listeners - put em here.  eg [qw (cmd1 cmd2 cmd3)]
   my @commands = [qw()];

   ## Values: irc_join irc_ping irc_part irc_quit
   ## Note that irc_quit does not send channel information, and that the quit message will be
   ## stuck in $options
   my @irc_events = [qw ()];

   ## Example:  ["/^$self->{BotName}/i",  '/hug (\w+)\W*'.$self->{BotName}.'/i' ]
   ## The only modifier you can use is /i
   my @preg_matches = [qw ()];

   ## Works in conjuntion with preg_matches.  Match patterns in preg_matches but not
   ## these patterns.  example: ["/^$self->{BotName}, tell/i"]
   my @preg_excludes = [qw()];

   ## Default permissions for these commands.
   #   UA_INTERNAL         (A command that only the bot should run.  Mostly reentry commands.
   #  UA_ADMIN             (Admininstrators only.  Full control.)
   #   UA_TRUSTED          (trusted users - by default they can do a bunch of admin stuff)
   #   UA_REGISTERED       (registered users)
   #  UA_UNREGISTERED  (world)
   #  If you don't specify any permissions, UA_UNREGISTERED is assumed.
   #   Use PLUGIN to set the default permission for the plugin as a whole. All commands will
   #       then require at least that level of access.
   #  There's a hiearchy.  Each user level can do everything that the levels below them can do.
   #  You can restrict commands by flag using the flag parameter.

   # Example 1:
   #     only registered users may run commands in this plugin, only admin may run foo
   # my $default_permissions =[
   # {command=>"PLUGIN", require_group => UA_REGISTERED},
   # {command=>"foo", require_group => UA_ADMIN},
   # ]

   # Example 2:
   #     anyone may run any command in the plugin, only admin can use flag -god with command foo
   # my $default_permissions =[
   # {command=>"PLUGIN", require_group => UA_UNREGISTERED},
   # {command=>"foo", flag=>"god", require_group => UA_ADMIN},
   # ]

   # Example 3:
   #     anyone may run any command in the plugin, only bot owner can use flag -god with command foo
   # my $default_permissions =[
   # {command=>"foo", flag=>"god", require_users=> ["$self->{BotOwnerNick}"]}
   # ]

   # Example 4:
   #  anyone may run any command in the plugin, only trusted users may use flag "super" with
   #     any command within the plugin, but make an exception for user cowbell and let him run
   #   the command too, even though he's not a member of trusted.
   # my $default_permissions =[
   # {command=>"PLUGIN", flag=>"super", require_group =>UA_TRUSTED, allow_users=>['cowbell']}
   # ]

   my $default_permissions = [
      { command => "PLUGIN",       require_group => UA_REGISTERED },
      { command => "some_command", require_group => UA_TRUSTED },
      { command => "some_command", flag          => 'someflag', require_group => UA_ADMIN },
      { command => "some_command", flag          => 'someflag', require_users => ["$self->{BotOwnerNick}"] },
      { command => "some_command", require_group => UA_ADMIN, allow_users => ['cowbell'] },
   ];

   return {
      commands      => @commands,
      permissions   => $default_permissions,
      irc_events    => @irc_events,
      preg_matches  => @preg_matches,
      preg_excludes => @preg_excludes
   };

}

##
## addHelp()
##  The help system will pull from here using PluginBaseClass->help(key).
##
sub addHelp {
   my $self = shift;
   $self->addHelpItem( "[plugin_description]", "Describe your plugin here." );
   $self->addHelpItem( "[command]",            "Usage: command <arguments>" );
   $self->addHelpItem( "[command][-flag]",     "Whatever." );
}
1;
__END__
