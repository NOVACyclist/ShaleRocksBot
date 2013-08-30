package plugins_sys::Admin;
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
use modules::PrivacyFilter;
use constant PrivacyFilter => 'modules::PrivacyFilter';

sub onBotStart{
	my $self = shift;
	
	#Let's make sure we have an admin user.	
	my $OwnerNick = $self->getInitOption("OwnerNick");
	my $InitialOwnerPassword = $self->getInitOption("InitialOwnerPassword");

	##Create systems groups if necessary
	print "Checking for default user groups...\n";
	$self->createGroup(UA_INTERNAL, UA_INTERNAL_LEVEL);
	$self->createGroup(UA_ADMIN, UA_ADMIN_LEVEL);
	$self->createGroup(UA_TRUSTED, UA_TRUSTED_LEVEL);
	$self->createGroup(UA_REGISTERED, UA_REGISTERED_LEVEL);
	$self->createGroup(UA_UNREGISTERED, UA_UNREGISTERED_LEVEL);

	# List the admins
	print $self->listGroupMembers('admin') ."\n";
	
	my $numMembers = $self->numGroupMembers('admin');
	# If no admins defined, define one 
	if (!$numMembers){
		print "This bot has no admins defined. Will add $OwnerNick as an admin.\n";

		my $ua = $self->UserAuth->new($self->{BotDatabaseFile}, $OwnerNick, '', $self->{sql_pragma_synchronous});
		$ua->adminOverride();

		#If the account exists, just add it to a group.
		if ($ua->accountExists()){
			print "$OwnerNick already has an account.\n";


		}else{
		#account doesn't exist. create it.
			print "Created account $OwnerNick with password $InitialOwnerPassword.\n";
			print "You should change that using the change_password command.\n";
			$ua->register($InitialOwnerPassword);
		}	

		## Add to admin group
		$ua->addToGroup('admin');
		print "Added $OwnerNick to the admin group\n";	

	}

	print $self->listGroupMembers('trusted') ."\n";;
}



sub getOutput {
	my $self = shift;
	my $cmd = $self->{command};
	my $options = $self->{options};
	my $output = "";

	my $plugins = $self->{BotPluginInfo};

	## 
	## Joining, parting , kicking, and ops
	##

	if ($cmd eq 'join'){
		return $self->help($cmd) if (!$options);
		$self->returnType("irc_yield");
		$self->yieldCommand('join');
		$self->yieldArgs([$options]);
		return "Joining channel $options";
	}

	if ($cmd eq 'part'){
		return $self->help($cmd) if (!$options);
		$self->returnType("irc_yield");
		$self->yieldCommand('part');
		$self->yieldArgs([$options]);
		return "Parting channel $options";
	}

	if ($cmd eq 'kick'){
		return $self->help($cmd) if (!$options);
		$self->returnType("irc_yield");
		$self->yieldCommand('kick');
		
		if ($options =~/^(.+?) (.+?)$/){
			$self->yieldArgs([$1, $2]);
		}else{
			$self->yieldArgs([$self->{channel}, $options]);
		}
		return "I'll try...";
	}


	if ($cmd eq 'ban'){
		return $self->help($cmd) if (!$options);
		#$self->returnType("irc_yield");
		#$self->yieldCommand('ban');
		#$self->yieldArgs([$self->{channel}, '+b', '*!*@'.$host]);
		return "Not implemented...";
	}


	if ($cmd eq 'giveops'){
		return $self->help($cmd) if (!$options);
		$self->returnType("irc_yield");
		$self->yieldCommand('mode');
		if ($options =~/^(.+?) (.+?)$/){
			$self->yieldArgs([$1 . ' +o', $2]);
		}else{
			$self->yieldArgs([$self->{channel} . ' +o', $options]);
		}
		return "I'll try...";
	}

	if ($cmd eq 'takeops'){
		return $self->help($cmd) if (!$options);
		$self->returnType("irc_yield");
		$self->yieldCommand('mode');

		if ($options =~/^(.+?) (.+?)$/){
			$self->yieldArgs([$1 . ' -o', $2]);
		}else{
			$self->yieldArgs([$self->{channel} . ' -o', $options]);
		}
		return "I'll try...";
	}

	if ($cmd eq 'reload_plugins'){
		$self->returnType("reloadPlugins");
		return "You've got it.";
	}


	if ($cmd eq 'shutdown'){
		return "This will shut the bot down.  Use shutdown -now if you're sure." if (!$self->hasFlag('now'));

		$self->returnType("shutdown");
		print "shutting down\n";
		return "bye";
	}


	## 
	## User Management
	##

	if ($cmd eq 'change_user_password'){
		return $self->help($cmd) if (!(my $p = $self->hasFlagValue("password")));
		return $self->help($cmd) if (!(my $n = $self->hasFlagValue("nick")));
		my $ua = $self->UserAuth->new($self->{BotDatabaseFile}, $n, 'ADMIN_ACCESS', $self->{sql_pragma_synchronous});
		$ua->adminOverride();

		if ($ua->getHighestGroupLevel() < $self->{UserAuthObj}->getHighestGroupLevel()){
			return "You can't change the password of an account that has a higher level of access than you do.";
		}else{
			return $ua->changePassword("bonjovi",$p);
		}
	}

	if ($cmd eq 'delete_user_account'){
		return $self->help($cmd) if (!(my $n = $self->hasFlagValue("nick")));
		my $ua = $self->UserAuth->new($self->{BotDatabaseFile}, $n, 'ADMIN_ACCESS', $self->{sql_pragma_synchronous});
		$ua->adminOverride();
		return $ua->deleteAccount("journey");
	}


	##
	## Groups 
	##
	if ($cmd eq 'admin_groups'){

		my $nick = $self->hasFlagValue("nick");
		my $group = $self->hasFlagValue("group");

		if ($self->hasFlag("list")){
			#list groups;
			return ($self->listGroups());
		}

		if ($self->hasFlag("adduser")){
			return $self->help($cmd) if (!($nick && $group));
			my $ua = $self->UserAuth->new($self->{BotDatabaseFile}, $nick, '', $self->{sql_pragma_synchronous});
			$ua->adminOverride();
			return ($ua->addToGroup($group));
		}

		if ($self->hasFlag("addgroup")){
			return $self->help($cmd) if (!$group);
			return $self->help($cmd) if (!$self->hasFlag("level"));
			my $level = $self->hasFlagValue("level");
			return ($self->addGroup($group, $level));
		}

		if ($self->hasFlag("rmgroup")){
			return $self->help($cmd) if (!$group);
			return $self->rmGroup($group);
		}

		if ($self->hasFlag("show")){
			return $self->help($cmd) if (! ($nick || $group));
			
			if ($nick){
				my $ua = $self->UserAuth->new($self->{BotDatabaseFile}, $nick, '', $self->{sql_pragma_synchronous});
				$ua->adminOverride();
				my @groups = $ua->listGroups();
				if (@groups){return($nick."'s  groups: ". join ", ", @groups);}
				else{ return "$nick is not a member of any groups.";}

			}elsif($group){
				return $self->listGroupMembers($group);
			}
		}

		if ($self->hasFlag("rmuser")){
			return $self->help($cmd) if (!($nick && $group));
			my $ua = $self->UserAuth->new($self->{BotDatabaseFile}, $nick, '', $self->{sql_pragma_synchronous});
			$ua->adminOverride();
			return ($ua->rmFromGroup($group));
		}

		return $self->help($cmd);
	}


	##
	##	disable / enable
	##

	# CommandHandler|disable|1$plugin|2:$command

	if ($cmd eq 'disable'){
		my $c = $self->getCollection('CommandHandler', 'disable');

		if ($self->hasFlag("view")){
			my @records = $c->getAllRecords();
			return "No plugins or commands are currently disabled." if (!@records);
			foreach my $rec (@records){
				$self->addToList($rec->{val1}.'.'.$rec->{val2});
			}
			return "Disabled commands & plugins: " . $self->getList();
		}

		my $pplugin = $self->hasFlagValue("plugin");
		my $pcommand = $self->hasFlagValue("command");

		if ($pplugin eq 'Admin'){
			return "You can't disable enable." if ($pcommand eq 'enable');
			return "You can't disable disable, funny guy." if ($pcommand eq 'disable');
			return "You can't disable the Admin module." if ($pcommand eq '*');
		}

		if ($pplugin eq 'More'){
			return "You can't disable 'More'. Things will break. I'm not kidding.";
		}

		return $self->help($cmd) if (!$pplugin || !$pcommand);

		my @records = $c->matchRecords({val1=>$pplugin, val2=>$pcommand});
		return "That command is already disabled" if (@records);
	
		$c->add($pplugin, $pcommand);		
		$self->returnType("reloadPlugins");
		return "$pplugin.$pcommand disabled";
	}


	if ($cmd eq 'enable'){
		my $pplugin = $self->hasFlagValue("plugin");
		my $pcommand = $self->hasFlagValue("command");

		return $self->help($cmd) if (!$pplugin && !$pcommand);

		my $c = $self->getCollection('CommandHandler', 'disable');
		my @records = $c->matchRecords({val1=>$pplugin, val2=>$pcommand});
		return "That command is not currently disabled" if (!@records);
	
		$c->delete($records[0]->{row_id});	

		$self->returnType("reloadPlugins");
		return "$pcommand enabled";
	}

	##
	##	Settings
	##
		
	# this seems kind of pointless.

	if ($cmd eq 'settings'){
		$self->suppressNick(1);
		foreach my $p (keys %{$plugins}){
			if ($plugins->{$p}->{has_settings}){
				$self->addToList($p);
			}
		}
		my $list = $self->getList();
		if ($list){
			$output = "The following plugins have configurable settings. ";
			$output .=BLUE."(Use ".$self->{BotCommandPrefix}."<PluginName> -settings to manage them.) ".NORMAL;
			return $output . $list;
		}else{
			return "None of the currently loaded plugins make use of the bot's settings feature.";
		}
	}
		
	##
	##	Privacy Filter
	##

	if ($cmd eq 'privacy_filter'){

		if ($self->{channel} =~m/^#/){
			return "You need to be in a private chat session to run this command. ";
		}

		my $c = $self->getCollection('Admin', 'privacy_filter');
		my $f = PrivacyFilter->new({ BotDatabaseFile=>$self->{BotDatabaseFile},
            sql_pragma_synchronous=>$self->{sql_pragma_synchronous},
            SpeedTraceLevel => $self->{keep_stats} });

		if ($self->hasFlag("status")){
			return "Privacy filter is enabled, using mode $f->{mode}." if ($self->{privacy_filter_enable});
			return "Privacy filter is disabled.";
		}

		if ($self->hasFlag("list")){
			my @list = @{$f->{filters}};
			foreach my $item (@list){
				$self->addToList("[$item->{str} => $item->{repl}]");
			}

			return "Aaaand the current filters are... " . $self->getList();
		}

		if (my $mode = $self->hasFlagValue("mode")){
			$self->returnType("reloadPrivacyFilter");
			return $f->setMode($mode);
		}

		if ($self->hasFlag("add")){
			my $pattern = $self->hasFlagValue("pattern");
			my $replacement= $self->hasFlagValue("replacement");
			return "You need to use -pattern=<pattern>" if (!$pattern);
			return "You need to use -replacement=<replacement>" if (!$replacement);
			$self->returnType("reloadPrivacyFilter");
			return $f->addFilter({pattern=>$pattern, replacement=>$replacement});
		}

		if ($self->hasFlag("delete")){
			my $pattern = $self->hasFlagValue("pattern");
			return "You need to use -pattern=<pattern>" if (!$pattern);
			$self->returnType("reloadPrivacyFilter");
			return $f->rmFilter({pattern=>$pattern} );
		}

		return $self->help($cmd);
	}



	##
	##	Permissions
	##

	# CommandHandler|permissions|1$plugin|2require|3$command|4$flag|5$req_group|6$req_users
	if ($cmd eq 'permissions'){

		##
		##	Reset defaults
		##	
		if ($self->hasFlag("reset_defaults")){
			my $pplugin = $self->hasFlagValue("plugin");

			my $c = $self->getCollection('CommandHandler', 'permissions');
			if ($pplugin){
				return "'$pplugin' is not a valid plugin." if (!defined($plugins->{$pplugin}));
				$c->deleteByVal({val1=>$pplugin});
				$self->returnType("reloadPlugins");
				return ("Plugins '$pplugin' reset to default permissions.");

			}else{
				$c->sort({field=>"display_id", type=>'numeric', order=>'desc'});
				my @records=$c->getAllRecords();
				foreach my $rec (@records){
					$c->delete($rec->{row_id});
				}
				$self->returnType("reloadPlugins");
				return ("All plugins reset to default permissions.");
			}
		}

		##
		## Set stuff
		##

		if ($self->hasFlag("set")){

			if (!$self->hasFlag("require") && !$self->hasFlag("allow") ){
				return "You have to use either the -require or -allow flag with -set.";
			}

			my $type;
			$type = 'require' if ($self->hasFlag("require"));
			$type = 'allow' if ($self->hasFlag("allow"));

			my $pplugin = $self->hasFlagValue("plugin");
			my $pcommand = $self->hasFlagValue("command");
			my $pflag = $self->hasFlagValue("flag");
			my $pgroup = $self->hasFlagValue("group");
			my $pnicks = $self->hasFlagValue("nicks");

			return "You have to specify a plugin" if (!$pplugin);
			return "'$pplugin' is not a valid plugin." if (!defined($plugins->{$pplugin}));
			
			my $c = $self->getCollection('CommandHandler', 'permissions');

			# Setting plugin permissions
			if (!$pcommand){
				if ($type eq 'require'){
					return "You have to specify a single -group or list,of,-nicks" if (!$pgroup && !$pnicks);
				}else{
					return "You have to specify a list,of,-nicks" if (!$pnicks);
					return "You can't allow groups, only -nicks" if ($pgroup);
				}

				if ($pgroup && ($self->{UserAuthObj}->groupExists($pgroup) < 0)){
					return "Group '$pgroup' doesn't exist." ;
				}

				foreach my $perm (@{$plugins->{$pplugin}->{permissions}}){
					if ($perm->{command} eq 'PLUGIN' && $perm->{require_group} eq UA_INTERNAL){
						return ("Don't mess with the internal commands, you'll screw things up.");
					}
				}

				$c->deleteByVal({val1=>$pplugin, val2=>$type, val3=>'PLUGIN', val4=>$pflag?$pflag:""});
				$c->add($pplugin, $type, 'PLUGIN', $pflag?$pflag:"", $pgroup?$pgroup:"", $pnicks?$pnicks:"");
				$self->returnType("reloadPlugins");
				return ("Done.");
			}

			# setting command permissions
			if ($pcommand){
				if ($type eq 'require'){
					return "You have to specify a single -group or list,of,-nicks" if (!$pgroup && !$pnicks);
				}else{
					return "You have to specify a list,of,-nicks" if (!$pnicks);
					return "You can't allow groups, only -nicks" if ($pgroup);
				}


				if ($pgroup && ($self->{UserAuthObj}->groupExists($pgroup) < 0)){
					return "Group '$pgroup' doesn't exist." ;
				}

				foreach my $perm (@{$plugins->{$pplugin}->{permissions}}){
					if ($perm->{command} eq $pcommand && $perm->{require_group} eq UA_INTERNAL){
						return ("Don't mess with the internal commands, you'll screw things up.");
					}
				}

				$c->deleteByVal({val1=>$pplugin, val2=>$type, val3=>$pcommand, val4=>$pflag?$pflag:""});
				$c->add($pplugin, $type, $pcommand, $pflag?$pflag:"", $pgroup?$pgroup:"", $pnicks?$pnicks:"");
				$self->returnType("reloadPlugins");
				return ("done");
			}

			# setting command permissions
	
			return "soon?";	# i dunno why this is here
		}


		##
		## show stuff
		##

		if (my $p = $self->hasFlagValue("plugin")){

			if (!defined($plugins->{$p})){
				return "Sorry buddy, there's no plugin called $p";
			}

			## first, snag the PLUGIN entry
			my $perm_plugin_group;
			my $perm_plugin_users;

			$self->suppressNick(1);

			## Get plugin info
			foreach my $perm (@{$plugins->{$p}->{permissions}}){
				if ($perm->{command} eq 'PLUGIN'){
					$output .= "[";
					if ($perm->{flag}){
						$output .="flag=$perm->{flag} ";
					}
					if ($perm->{require_group}){
						$output .="require_group=$perm->{require_group} ";
					}
					if ($perm->{require_users}){
						$output .="require_users=(". join( ", ", @{$perm->{require_users}} ) .")" ;
					}
					$output .= "] ";
				}
			}

			if ($output){
				$output = BOLD."Plugin '$p' permissions: ".NORMAL . $output;
			}else{
				$output = "Plugin '$p' requies no special permissions.";
			}

			$output .= " ".$self->BULLET." ";
			my $output2;
			if (my $pcmd = $self->hasFlagValue("command")){
				foreach my $perm (@{$plugins->{$p}->{permissions}}){
					if ($perm->{command} eq $pcmd){
						$output2 .= "[";
						if ($perm->{flag}){
							$output2 .="flag=$perm->{flag} ";
						}
						if ($perm->{require_group}){
							$output2 .="require_group=$perm->{require_group} ";
						}
						if ($perm->{require_users}){
							$output2 .="require_users=(". join( ", ", @{$perm->{require_users}} ) .") " ;
						}
						if ($perm->{allow_users}){
							$output2 .="allow_users=(". join( ", ", @{$perm->{allow_users}} ) .") " ;
						}
						$output2 .= "] ";
					}
				}
				if ($output2){
					$output.=BOLD."Command '$pcmd' has the following permissions:".NORMAL." $output2";
				}else{
					$output.="Command '$pcmd' has no additional permissions. ";
				}

			}else{
				$output.=BOLD."Commands within $p: ".NORMAL;
				foreach my $command (@{$plugins->{$p}->{commands}}){
					next if ($command=~/^_/);
					next if ($command eq $p);
					
					my $has = 0;
					foreach my $perm (@{$plugins->{$p}->{permissions}}){
						if ($perm->{command} eq $command){
							$has = 1;
						}
					}
					if ($has){
						$output .=" ". UNDERLINE."$command".NORMAL;
					}else{
						$output .= " $command";
					}
				}
			}
			return $output;
		}



		##
		## list plugins - default action
		##

		foreach my $k (sort keys $plugins){
			if (@{$plugins->{$k}->{permissions}}){
				my $found = 0;
				no warnings;
				foreach my $pl (@{$plugins->{$k}->{permissions}}){
		
					if ( ($pl->{command} eq 'PLUGIN') && ( $pl->{flag} eq 'settings')
					&& ($pl->{require_group} eq UA_ADMIN) )
					{
						next;
					}
					$found = 1;
				}
				use warnings;

				if ($found){
					$output.=" ".UNDERLINE."$k".NORMAL;	
				}else{
					$output.=" $k";
				}

			}else{
				$output.=" $k";
			}
		}

		$self->suppressNick(1);
		return BOLD."My Plugins: ".NORMAL.$output;
		
	}



	##
	## Can a user run a command?
	##

	if ($cmd eq "canrun"){
		my $pplugin = $self->hasFlagValue("plugin");
		my $pcommand = $self->hasFlagValue("command");
		my $pflags = $self->hasFlagValue("flags");
		my $pnick = $self->hasFlagValue("nick");

		return "You need to specify a plugin" if (!$pplugin);
		return "You need to specify a command" if (!$pcommand);
		return "You need to specify a nick" if (!$pnick);

		return "'$pplugin' is not a valid plugin." if (!defined($plugins->{$pplugin}));

		if (!$self->botPluginCan($pplugin, $pcommand)){
			return "command '$pcommand' is not a part of plugin '$pplugin'.";
		}

		my $ua = $self->UserAuth->new($self->{BotDatabaseFile}, $pnick, '', $self->{sql_pragma_synchronous});
		my $match = $plugins->{$pplugin};

		my @f = split /,/, $pflags;
		my $flags_h;

		foreach my $f (@f){
			$flags_h->{$f} = 1
		}

		my ($allowed, $reason) = $ua->hasRunPermission($pcommand, $flags_h, $match);
		if ($allowed){
			return "Yes. $reason";
		}else{
			return "No. $reason";
		}
	}	
}



##
##	Group Functions
##

sub listGroups{
	my $self = shift;
	my $ret;

	my $c = $self->getCollection('UserAuth', ':group');
	$c->sort({field=>"val2", type=>'numeric', order=>'asc'});
	my @records = $c->getAllRecords();

	my $bullet = "";
	foreach my $rec (@records){
		next if ($rec->{val1} eq 'internal');
		next if ($rec->{val2} == 0);

		$ret.=$bullet."[$rec->{val2}] $rec->{val1}";
		if ($rec->{val1} ne 'unregistered'){
			$ret.=" (". $self->numGroupMembers($rec->{val1})." members)";
		}
		$bullet = " " . $self->BULLET ." ";
	}

	foreach my $rec (@records){
		next if ($rec->{val2} != 0);
		$ret.=$bullet."[$rec->{val2}] $rec->{val1}";
		$ret.=" (". $self->numGroupMembers($rec->{val1})." members)";
		$bullet = " " . $self->BULLET ." ";
	}
	
	return $ret;
}

# i have two of these functions now. whoops
sub addGroup{
	my $self = shift;
	my $group_name = shift;
	my $level = shift;

	my $c = $self->getCollection('UserAuth', ':group');
	my @records = $c->matchRecords({val1=>$group_name});

	if (@records){
		return "That group already exists";
	}

	if ($level == 1){
		return "Level can't be 1. That level is reserved for internal processes."; 
	}

	if ($level > 100){
		return "Level can't be greater than 100.";
	}

	if ($group_name){
	}

	$c->add($group_name, $level, "user_defined");

	return "Group added";
}

sub rmGroup{
	my $self = shift;
	my $group_name = shift;
	my $c = $self->getCollection('UserAuth', ':group');
	my @records = $c->matchRecords({val1=>$group_name});

	if (!@records){
		return "That group doesn't exist";
	}

	if ($records[0]->{val3} eq "system"){
		return "Can't remove a system group";
	}

	## delete the group
	$c->delete($records[0]->{row_id});
	
	## delete all entries putting a user into that group
	$c = $self->getCollection('UserAuth', '%');
	@records = $c->matchRecords({val1=>'group', val2=>$group_name});
		
	my $count=0;
	foreach my $rec (@records){
		$count++;
		$c->delete ($rec->{row_id});
	}
	return "Group $group_name has been deleted. $count users were removed from the group.";
}

sub numGroupMembers{
	my $self = shift;
	my $group_name = shift;

	#if ($self->{UserAuthObj}->groupExists($group_name) < 0){
	#	return "Group $group_name doesn't exist";
	#}

	my @records;
	if ($group_name ne 'registered'){
		my $c = $self->getCollection('UserAuth', '%');
		@records = $c->matchRecords({val1=>'group', val2=>$group_name});
	}else{
		my $c = $self->getCollection('UserAuth', '%');
		@records = $c->matchRecords({val1=>'account_settings'});
	}
	return $#records + 1;
}


sub listGroupMembers{
	my $self = shift;
	my $group_name = shift;
	my @list;
	my $ret;

	if ($self->{UserAuthObj}->groupExists($group_name) < 0 ){
		return "Group $group_name doesn't exist";
	}

	if ($group_name eq 'unregistered'){
		return "About 6 billion.  Too many to list.";
	}

	my $c = $self->getCollection('UserAuth', '%');

	my @records;

	if ($group_name eq 'registered'){
		@records = $c->matchRecords({val1=>'account_settings'});
		
	}else{
		@records = $c->matchRecords({val1=>'group', val2=>$group_name});
	}

	foreach my $rec (@records){
		push @list, $rec->{'collection_name'};	
	}

	if (@list){
		$ret="Members of $group_name: " . join ", ", @list;
	}else{
		$ret="Members of $group_name: None";
	}
	
	return $ret;
}


sub createGroup{
	my $self=shift;
	my $group_name = shift;
	my $group_level = shift;
	my $group_type = 'user_defined';

	return (0) if (!$group_name);
	
	my $system_groups = {UA_INTERNAL=>UA_INTERNAL_LEVEL, UA_ADMIN=>UA_ADMIN_LEVEL,
		 UA_TRUSTED=>UA_TRUSTED_LEVEL, UA_REGISTERED=>UA_REGISTERED_LEVEL,
		 UA_UNREGISTERED=>UA_UNREGISTERED_LEVEL};

	if (defined($system_groups->{$group_name}) ){
		$group_type = 'system';
		$group_level = $system_groups->{$group_name};
	}

	my $c = $self->getCollection('UserAuth', ':group');
	my @records = $c->matchRecords({val1=>$group_name});

	if (@records == 0){
		$c->add($group_name, $group_level, $group_type);
	}
	
	return 1;
}



#########################################
#########################################
sub listeners{
   my $self = shift;

   ##Command Listeners - put em here.  eg ['one', 'two']
   my @commands = [ qw(join part kick ban giveops takeops change_user_password delete_user_account reload_plugins admin_groups shutdown permissions canrun disable enable privacy_filter settings)];

	my $default_permissions = [
		{command=>"PLUGIN", require_group => UA_TRUSTED},
		{command=>"join", require_group => UA_ADMIN},
		{command=>"part", require_group => UA_ADMIN},
		{command=>"ban", require_group => UA_ADMIN},
		{command=>"reload_plugins", require_users => ["$self->{BotOwnerNick}"]},
		{command=>"admin_groups",  require_group => UA_ADMIN},
		{command=>"shutdown",  require_group => UA_ADMIN},
		{command=>"permissions",  require_group => UA_ADMIN},
		{command=>"disable",  require_group => UA_ADMIN},
		{command=>"enable",  require_group => UA_ADMIN},
		{command=>"privacy_filter",  require_users => ["$self->{BotOwnerNick}"]},
	];

   return ({commands=>@commands, permissions=>$default_permissions});
}

sub addHelp{
   my $self = shift;
   $self->addHelpItem("[plugin_description]", "Bot Administrator stuff.");
   $self->addHelpItem("[join]", "Usage: join <#channel>");
   $self->addHelpItem("[part]", "Usage: part <#channel>");
   $self->addHelpItem("[kick]", "Usage: kick [<#channel>] <nick>");
   $self->addHelpItem("[giveops]", "Usage: giveops [<#channel>] <nick>");
   $self->addHelpItem("[takeops]", "Usage: takeops [<#channel>] <nick>");
   $self->addHelpItem("[change_user_password]", "Usage: change_user_password -nick=<nick> -password=<password>");
   $self->addHelpItem("[delete_user_account]", "Usage: delete_user_account -nick=<nick>");
   $self->addHelpItem("[reload_plugins]", "Reload bot plugins.");
   $self->addHelpItem("[admin_groups]", "[-list] all groups  [-adduser] a user to a group [-addgroup][-level=#] add a group  [-show] members of a group or groups a nick belongs to  [-rmuser] from a group  [-rmgroup] remove a group  [<-nick=nick>] [<-group=group>]  ");
   $self->addHelpItem("[canrun]", "Tells you if a user can run a particular command, based on current permission levels.  Usage: canrun -nick=<nick> -plugin=<plugin> -command=<command> -flags=<flag1,flag2>");
   $self->addHelpItem("[permissions]", "Manage the permissions of plugins & commands. Flags: -plugin=<plugin> -command=<command> -flags=<flag1,flag2> -set [-require | -allow] -group=<group> -nicks=<nick1,nick2> -reset_defaults");
   $self->addHelpItem("[disable]", "Disable a command.  Usage: disable -plugin=<plugin> -command=<command>. Use -command=* to disable the entire plugin.  Use disable -view to view disabled commands.");
   $self->addHelpItem("[enable]", "Enable a command.  Usage: enable -plugin=<plugin> -command=<command>.  (Use disable -view to view disabled commands.)");
   $self->addHelpItem("[shutdown]", "This will shut the bot down. That is, it will exit. Completely. It will disappear from here and anywhere else it happens to be.");
   $self->addHelpItem("[settings]", "Manage plugin settings, if supported by the plugin.");
   $self->addHelpItem("[privacy_filter]", "Manage the bot's privacy filter. This will filter output lines that contain your IP address as well as any other user defined strings. Flags:  -status -list -mode=[replace|remove|censor|kill] -add -remove -pattern=<str> -replacement=<str>. Modes: replace will the string with replacement. remove will remove the string & replace it with nothing. censor will replace the string with *****.  kill will prevent a line matching any filter from displaying at all.");
}

1;
__END__
