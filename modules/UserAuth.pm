package modules::UserAuth;
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
#use strict;
#use warnings;

BEGIN {
  $modules::UserAuth::VERSION = '1.0';
}

our @EXPORT = qw( UA_ADMIN UA_TRUSTED UA_REGISTERED UA_UNREGISTERED UA_INTERNAL
	UA_ADMIN_LEVEL UA_TRUSTED_LEVEL UA_REGISTERED_LEVEL UA_UNREGISTERED_LEVEL UA_INTERNAL_LEVEL);

use Data::Dumper;
use modules::Collection;
use constant Collection => 'modules::Collection';
use Digest::SHA qw(sha256_hex);
use IRC::Utils ':ALL';

my $BotDatabaseFile;
my $nick;
my $current_mask;

my $mask_authed;
my $mask_auth_status;
my $authorized_mask_1;		
my $authorized_mask_2;	
my $authorized_mask_3;	
my @groups;		# {group_name = $n, group_level = x}

my %group_definitions;

my $sql_pragma_synchronous;
my $is_identified;
my $account_exists;

my $admin_override;  #can be set by admin module to gain access to user's account settings

my $output_filter;

use constant {
	UA_INTERNAL => ':internal',
	UA_INTERNAL_LEVEL => 1,
	UA_ADMIN => 'admin',
	UA_ADMIN_LEVEL => 2,
	UA_TRUSTED => 'trusted',
	UA_TRUSTED_LEVEL => 10,
	UA_REGISTERED => 'registered',
	UA_REGISTERED_LEVEL => 20,
	UA_UNREGISTERED => 'unregistered',
	UA_UNREGISTERED_LEVEL => 30,
};


# Collection mapping: 
# one of:
# UserAuth|$nick|account_settings|hashed_pass|mask_auth_on or mask_auth_off|mask1|mask2|mask3
# many of:
# UserAuth|group|$group_name|$group_level|$group type: system or user
#		system group types: admin trusted (registered unregistered = not in database, determined here)
# many more of:
# UserAuth|$nick|group|<group name>
#

sub new {
	my ($class, @args) = @_;
	my $self = bless {}, $class;

	my ($db_file, $nick, $current_mask, $sql_pragma_synchronous)  = @args;

	$self->{nick} = $nick;
	$self->{current_mask} = $current_mask;
	$self->{BotDatabaseFile} = $db_file;
	$self->{admin_override} = 0;
	$self->{sql_pragma_synchronous} = $sql_pragma_synchronous;

	# only use the part after the @
	if ($self->{'current_mask'}=~/\@/){
		$self->{'current_mask'}= (split(/\@/, $self->{'current_mask'}))[1];
	}

	$self->loadAccountSettings();

   return $self;
}


sub loadAccountSettings{
	my $self = shift;

	$self->{is_identified} = 0;
	$self->{account_exists} = 0;
	$self->{mask_authed} = 0;

	if ($self->{nick} eq UA_INTERNAL){
		$self->{is_identified} = 1;
		$self->{account_exists} = 1;
		$self->{mask_authed} = 1;
		push @{$self->{groups}},{group_name=> UA_INTERNAL, group_level=>UA_INTERNAL_LEVEL};
		return;
	}

	my $c = $self->getCollection(__PACKAGE__, $self->{nick});
	my @records = $c->matchRecords({val1=>'account_settings'});

	# if this nick was not found, check to see if we can auth on hostmask
	if (@records == 0 ){
		my $c_mask = $self->getCollection(__PACKAGE__, ':mask');
		my @mrecords = $c_mask->matchRecords({val1=>$self->{current_mask}});

		if (@mrecords){
			$c = $self->getCollection(__PACKAGE__, $mrecords[0]->{val2});


			@records = $c->matchRecords({val1=>'account_settings'});
			if ($records[0]->{val3} eq 'mask_auth_on'){
				$self->{mask_authed} = 1;
				$self->{nick} = $mrecords[0]->{val2};
			}else{
				## man this is ugly. 
				shift @records;
			}

			if (@mrecords > 1){
				print "Found more than one hostmask record for $self->{current_mask}\n";
				print "This part needs some work.\n";
			}
		}
	}

	if (@records == 1){
		#print $self->{current_mask} . "\n";
		$self->{mask_auth_status}  = $records[0]->{val3};
		$self->{authorized_mask_1} = $records[0]->{val4};
		$self->{authorized_mask_2} = $records[0]->{val5};
		$self->{authorized_mask_3} = $records[0]->{val6};
		$self->{is_identified} = 1 if ($self->{authorized_mask_1} eq $self->{current_mask});
		$self->{is_identified} = 1 if ($self->{authorized_mask_2} eq $self->{current_mask});
		$self->{is_identified} = 1 if ($self->{authorized_mask_3} eq $self->{current_mask});
		$self->{account_exists} = 1;
	}

	#regular auth. user using authed nick.
	if ($self->accountExists() && $self->isAuthed() ){
		push @{$self->{groups}},{group_name=> UA_REGISTERED, group_level=>UA_REGISTERED_LEVEL};

		## Load output filter.
		my @records = $c->matchRecords({val1=>'output_filter'});
		if (@records == 1){
			$self->{output_filter} = $records[0]->{val2};
		}
	
		## Load group memberships
		@records = $c->matchRecords({val1=>'group'});
		foreach my $rec (@records){
			push @{$self->{groups}},{group_name=> $rec->{val2}, group_level=>$rec->{val3}};
		}

	}else{
		push @{$self->{groups}},{group_name=> UA_UNREGISTERED, group_level=>UA_UNREGISTERED_LEVEL};
	}
}



sub maskAuthStatus{
	my $self = shift;
	my $action = shift;

	if (!$self->isAuthed()){
		return 0;
	}

	my $c_mask = $self->getCollection(__PACKAGE__, ':mask');

	if (!$action){
		if ($self->{mask_auth_status} eq 'mask_auth_on'){
			return 1;
		}else{
			return 0;
		}
	}

	my $c = $self->getCollection(__PACKAGE__, $self->{nick});
	my @records = $c->matchRecords({val1=>'account_settings'});

	if ($action eq "enable"){
		$self->{mask_auth_status} = 'mask_auth_on';
		$c->updateRecord($records[0]->{row_id}, {val3=>'mask_auth_on'});

	}else{
		$self->{mask_auth_status} = 'mask_auth_off';
		$c->updateRecord($records[0]->{row_id}, {val3=>'mask_auth_off'});
	}
}


# This is misleadingly named.
sub getHighestGroupLevel{
	my $self = shift;
	my $level = UA_UNREGISTERED_LEVEL;

	foreach my $g (@{$self->{groups}}){
		if ($g->{group_level} < $level && ($g->{group_level} >= UA_ADMIN_LEVEL) ){
			$level = $g->{group_level};
		}
	}
	return ($level);
}

sub adminOverride{
	my $self = shift;
	$self->{admin_override} = 1;
}

sub isAuthed{
	my $self = shift;
	
	if ($self->{admin_override}){
		return 1;
	}else{
		return $self->{is_identified};
	}
}

sub listGroups{
	my $self = shift;
	my @ret;
	foreach my $g (@{$self->{groups}}){
		push @ret, $g->{group_name};
	}
	return sort (@ret);
}

sub rmFromGroup{
	my $self = shift;
	my $group = shift;
	my $ret;

	return "Group '$group' doesn't exist." if ($self->groupExists($group) < 0 );

	my $c = $self->getCollection('UserAuth', $self->{nick});
	my @records = $c->matchRecords({val2=>$group});
	
	if (@records){
		$c->delete($records[0]->{row_id});
		return "$self->{nick} removed from $group";
	}else{
		$ret = "$self->{nick} is not a member of group $group.  ";
		if (!$self->accountExists()){
			$ret.="$self->{nick} doesn't even have an account with me.";
		}
		return $ret;
	}
}

sub addToGroup{
	my $self = shift;
	my $group = shift;
	my $group_level;

	return "Group '$group' doesn't exist." if (($group_level = $self->groupExists($group)) < 0 );
	return "You can't add members to the internal group." if ($group eq 'internal');
	return "$self->{nick} doesn't have an account with me." if (!$self->accountExists());

	foreach my $g (@{$self->{groups}}){
		if ($g->{group_name} eq $group){
			return "$self->{nick} is already member of group '$g->{group_name}'";
		}
	}

	my $c = $self->getCollection('UserAuth', $self->{nick});
	$c->add('group', $group, $group_level);
	
	return "Done.";
}



sub groupExists{
	my $self = shift;
	my $group = shift;
	return (0) if (!$group);

	my $c = $self->getCollection('UserAuth', ':group');
	my @records = $c->matchRecords({val1=>$group});

	if (@records == 1){
		return $records[0]->{val2};
	}else{
		return -1;
	}
}


sub outputFilter{
	my $self = shift;

	return $self->{output_filter};
}

sub listOutputFilter{
	my $self = shift;
	my $ret;

	if (!$self->isAuthed()){
		return "I don't recognize you. Login first.";
	}

	if ($self->{output_filter}){
		return $self->{output_filter};

	}else{
		return "You don't have an output filter set. To set one use the -s option.";
	}
}

sub setOutputFilter{
	my $self = shift;
	my $filter = shift;
	my $ret;

	if (!$self->isAuthed()){
		return "I don't recognize you. Login first.";
	}

	$self->clearOutputFilter();
	my $c = $self->getCollection(__PACKAGE__, $self->{nick});
	$c->add("output_filter", $filter);
		
	return "Output filter set to $filter";
	
}

sub clearOutputFilter{
	my $self = shift;
	my $ret;

	if (!$self->isAuthed()){
		return "I don't recognize you. Login first.";
	}

	if (!$self->{output_filter}){
		return "You don't have an output filter to clear";
	}

	my $c = $self->getCollection(__PACKAGE__, $self->{nick});
	my @records = $c->matchRecords({val1=>'output_filter'});

	$c->delete($records[0]->{'row_id'});
	
	return "Output filter cleared.";
}


sub listMasks{
	my $self = shift;
	my $ret;

	if (!$self->isAuthed()){
		return "I don't recognize you. Login first.";
	}

	my $c = $self->getCollection(__PACKAGE__, $self->{nick});
	my @records = $c->matchRecords({val1=>'account_settings'});

	if (@records == 1){
		$ret = "[1] $records[0]->{val4} ";
		if ($records[0]->{val5} ne ""){
			$ret .= "[2] $records[0]->{val5} ";
		}
		if ($records[0]->{val6} ne ""){
			$ret .= "[3] $records[0]->{val6} ";
		}
		return $ret;
		
	}else{
		return "Something is amiss in US-lm-1. Sorry.";
	}
}

sub deleteMask{
	my $self = shift;
	my $mask_num = shift;
	my $ret;

	if (!$self->isAuthed()){
		return "I don't recognize you. Login first.";
	}

	#my $c_mask = $self->getCollection(__PACKAGE__, ':mask');
	#my @records = $c_mask->matchRecords({val1=>$self->{current_mask}, val2=>$self->{nick}});

	#foreach my $rec (@records){
	#	$c_mask->delete($rec->{row_id});
	#}

	my $c = $self->getCollection(__PACKAGE__, $self->{nick});
	my @records = $c->matchRecords({val1=>'account_settings'});

	if (@records == 1){

		if ($mask_num == 3){
			$c->updateRecord($records[0]->{row_id}, {val6=>''});
			return "Success!";

		}elsif($mask_num == 2){
			my $val5 = $records[0]->{val6} || "";
			$c->updateRecord($records[0]->{row_id}, {val5=>$val5, val6=>''});
			return "Success!";

		}elsif($mask_num == 1){
			my $val4 = $records[0]->{val5} || "";
			my $val5 = $records[0]->{val6} || "";
			$c->updateRecord($records[0]->{row_id}, {val4=>$val4, val5=>$val5, val6=>''});

			return "Success!";
		}

		return "Not success. :(";
		

	}else{
		return "Whoa nelly!  What went wrong?  US-dM-1. Sorry.";
	}

}

sub logout{
	my $self = shift;
	my $password = shift;
	my $ret;

	if (!$self->isAuthed()){
		$ret="You're not logged in. But I'm still sad to hear that you're leaving. :(";
		return $ret;
	}

	my $c_mask = $self->getCollection(__PACKAGE__, ':mask');
	my @records = $c_mask->matchRecords({val1=>$self->{current_mask}, val2=>$self->{nick}});

	foreach my $rec (@records){
		$c_mask->delete($rec->{row_id});
	}
	
	return $self->deleteMask(1) if ($self->{current_mask} eq $self->{authorized_mask_1});
	return $self->deleteMask(2) if ($self->{current_mask} eq $self->{authorized_mask_2});
	return $self->deleteMask(3) if ($self->{current_mask} eq $self->{authorized_mask_3});
	
}


sub login{
	my $self = shift;
	my $nick = shift;
	my $password = shift;
	my $ret;

	if ($self->isAuthed()){
		$ret="You're already logged in, I recognize you based on your hostmask. ";
		$ret.="To manage the hostmasks I identify with you, use the hostmasks command.";
		return $ret;
	}

	if ($nick ne $self->{nick}){
		$self->{nick} = $nick;
		$self->loadAccountSettings();
	}

	return "$self->{nick} doesn't have an account with me." if (!$self->accountExists());

	return "Wrong password" if (!$self->checkPassword($password));

	my $c = $self->getCollection(__PACKAGE__, $self->{nick});
	my @records = $c->matchRecords({val1=>'account_settings'});

	if (@records == 0){
		return "You don't have an account to log in to.  Create one using the register command.";
	}

	if (@records == 1){
		## update record, rotate masks to keep the newest one listed first
		$c->updateRecord($records[0]->{row_id}, {
			val4=>$self->{current_mask},
			val5=>$records[0]->{val4},
			val6=>$records[0]->{val5} });

		my $c_mask = $self->getCollection(__PACKAGE__, ':mask');
		my @mrecords = $c_mask->matchRecords({val1=>$self->{current_mask}, val2=>$self->{nick}});

		if (!@mrecords){
			$c_mask->add($self->{current_mask}, $self->{nick});
		}

		return "Cool. You're all set. Go get'em, tiger.";

	}else{
		## this should never happen
		return "UA-login-1";
	}
}


sub deleteAccount{
	my $self = shift;
	my $password = shift;
	my $ret;

	if (!$self->checkPassword($password)){
		return "Wrong password. Account not deleted.";
	}
	
	my $c = $self->getCollection(__PACKAGE__, $self->{nick});
	my @records = $c->getAllRecords();

	if (@records == 0){
		return "You don't have an account to delete.";

	}else{
		foreach my $rec (@records){
			$c->delete($rec->{row_id});
			print "deleted $rec->{row_id}\n";
		}
		return "Account deleted.  No hard feelings.  Best wishes.";
	}

	return $ret;
}

sub register{
	my $self = shift;
	my $password = shift;
	my $ret;

	my $hashed_password = $self->hashPassword($password);

	if ($self->accountExists()){
		return "An account for $self->{nick} already exists.";
	}

	my $c = $self->getCollection(__PACKAGE__, $self->{nick});
	$c->add('account_settings', $hashed_password, 'mask_auth_on', $self->{current_mask});

	my $c_mask = $self->getCollection(__PACKAGE__, ':mask');
	my @mrecords = $c_mask->matchRecords({val1=>$self->{current_mask}, val2=>$self->{nick}});

	if (!@mrecords){
		$c_mask->add($self->{current_mask}, $self->{nick});
	}
	
	$ret = "Success! Your password is $password.  As long as you keep coming from ";
	$ret.= "$self->{current_mask} using the nick $self->{nick}, you won't have to login again. ";
	$ret.= "If you don't want that to happen, logout when you're done here.";

	$self->loadAccountSettings();
	return ($ret);
}


sub changePassword{
	my $self = shift;
	my $opassword = shift;
	my $npassword = shift;
	my $ret;

	return "You don't have an account with me." if (!$self->accountExists());
	return "Wrong password" if (!$self->checkPassword($opassword));

	my $hashed_password = $self->hashPassword($npassword);

	my $c = $self->getCollection(__PACKAGE__, $self->{nick});
	my @records = $c->matchRecords({val1=>'account_settings'});
	
	return "Something bad happened. UA-cp-1" if (@records != 1);

	$c->updateRecord($records[0]->{row_id}, {val2=>$hashed_password});
	if ($self->adminOverride()){
		return "That password has been changed.";
	}else{
		return "Success! Your password has been changed.";
	}
}


sub checkPassword{
	my $self = shift;
	my $password = shift;

	if ($self->{admin_override}){
		return 1;
	}

	my $c = $self->getCollection(__PACKAGE__, $self->{nick});
	my @records = $c->matchRecords({val1=>'account_settings'});

	if(@records == 1){
		if ($records[0]->{val2} eq $self->hashPassword($password)){
			return 1;
		}else{
			return 0;
		}
	}else{
		return 0
	}
}


sub accountExists{
	my $self = shift;

	return $self->{account_exists};

	#my $c = $self->getCollection(__PACKAGE__, $self->{nick});
	#my @records = $c->matchRecords({val1=>'account_settings'});
	#if (@records){
	#	return 1;
	#}else{
	#	return 0;
	#}
}

sub hashPassword{
	my $self = shift;
	my $plain_password = shift;
	
	my $hashed_password = sha256_hex($plain_password . $self->{nick} . "i <3 pink floyd");
	return $hashed_password;
}


sub removePermission{
   my $self = shift;
	my $user = shift;
	my $permission = shift;

	my $c = $self->getCollection(__PACKAGE__, $user);
	
	my @records = $c->matchRecords({val1=>$permission});

	if (@records == 0){
		return ("$user does not have permission $permission.");

	}elsif (@records == 1){
		$c->delete($records[0]->{'row_id'});
		return ("$permission removed from user $user.");

	}else{
		return ("Database problem. More than one entry exists. #p8kk");
	}
}

sub addPermission{
   my $self = shift;
	my $user = shift;
	my $permission = shift;

	my $c = $self->getCollection(__PACKAGE__, $user);
	
	my @records = $c->matchRecords({val1=>$permission});

	if (@records == 0){
		#
		# create new entry
		# 
	
		$c->add($permission, "1");

		return ("$permission added for user $user.");

	}elsif (@records == 1){
		return ("$user already has permission $permission.");

	}else{
		return ("Database problem. More than one entry exists.  #j8kp");
	}
}

sub listUsersWithPermission{
   my $self = shift;
	my $type = shift;

	my $c = $self->getCollection(__PACKAGE__, '%');

	return ($c->matchRecords({val1=>$type}));
}

sub listAllPermissions{
   my $self = shift;

	my $c = $self->getCollection(__PACKAGE__, '%');

	my @records = $c->searchRecords('^is_');
	my %ret;
	foreach my $rec (@records){
		$ret{$rec->{'val1'}}++;
	}

	return %ret;
}


sub groupLevel{
   my $self = shift;
	my $group = shift;

	print "GROUP is |$group|\n";
	if (!$self->{group_definitions}){
		my $c = $self->getCollection('UserAuth', ':group');
		my @records = $c->getAllRecords();

		foreach my $rec (@records){
			$self->{group_definitions}->{$rec->{val1}} = $rec->{val2};
		}
	}
	
	if($group eq ""){
		return -1;

	}elsif (defined($self->{group_definitions}->{$group})){
		return $self->{group_definitions}->{$group};

	}else{
		return 0;
	}
}



## determine if user has permission to access this command / module
sub hasRunPermission{
   my $self = shift;
	my $command = shift;
	my $flags = shift;
	my $match = shift;
	
	my $answer;

	my $plugin_run_allowed = 0;
	my $command_run_allowed = 0;
	
	my $plugin_group_requirement = -1;
	my $command_group_requirement = -1;
	my $plugin_group_name;
	my $command_group_name;
	my $plugin_flag_req = "";
	my $command_flag_req = "";
	my $plugin_user_requirement = [];		#ref to array of nicks
	my $command_user_requirement = []; 	#ref to array of nicks
	my $command_user_allow = []; 	#ref to array of nicks
	my $plugin_user_allow = []; 	#ref to array of nicks
	my $reason;
	
	my $cmd_flag_matched = 0;
	my $p_flag_matched = 0;

	foreach my $req (@{$match->{permissions}}){
		# check plugin level permission

		if ($req->{command} eq 'PLUGIN'){
			if ($req->{flag}){
				if ($flags->{$req->{flag}}){
					$plugin_group_name = $req->{require_group};
					$plugin_group_requirement = $self->groupLevel($req->{require_group});
					$plugin_user_requirement = $req->{require_users};
					$plugin_flag_req = $req->{flag};
					$plugin_user_allow = $req->{allow_users};	
					$p_flag_matched=1;
				}

			}elsif(!$p_flag_matched){

				if ($req->{require_group}){
					$plugin_group_name = $req->{require_group};
					$plugin_group_requirement = $self->groupLevel($req->{require_group});
				}

				if ($req->{require_users}){
					$plugin_user_requirement = $req->{require_users};
				}

				if ($req->{allow_users}){
					$plugin_user_allow = $req->{allow_users};
				}
			}
		}

		## this isn't quite right. if a command has multiple flags and if those
		## flags have different requirements, this may not match the highest required 
		## flag. oh well. it wont come up very often. if at all. someone should fix this.

		if ($req->{command} eq $command){

			if ($req->{flag}){
				if ($flags->{$req->{flag}}){
					$command_group_name = $req->{require_group};
					$command_group_requirement = $self->groupLevel($req->{require_group});
					$command_user_requirement = $req->{require_users};
					$command_flag_req = $req->{flag};
					$command_user_allow = $req->{allow_users};
					$cmd_flag_matched = 1;
				}

			}elsif(!$cmd_flag_matched){

				if ($req->{require_group}){
					$command_group_name = $req->{require_group};
					$command_group_requirement = $self->groupLevel($req->{require_group});
				}

				if ($req->{require_users}){
					$command_user_requirement = $req->{require_users};
				}

				if ($req->{allow_users}){
					$command_user_allow = $req->{allow_users};
				}
			}
		}
	}

	if ($plugin_group_requirement < 0){
		$plugin_group_name = UA_UNREGISTERED;
		$plugin_group_requirement = UA_UNREGISTERED_LEVEL;
	}

	if ($command_group_requirement < 0 ){
		$command_group_name = $plugin_group_name;
		$command_group_requirement = $plugin_group_requirement;
	}


	#print "pgr is $plugin_group_requirement\ncgr is $command_group_requirement\n";
	#print Dumper($self);

	my ($x_gpra, $x_gcra, $x_ncra, $x_npra, $x_ncre, $x_npre);

	## is authed isnt requried here b/c if the user isnt authed, they 
	## wont have any groups added to their userauthobj obj
	## Start by seeing if a hierarchical group works
	foreach my $group (@{$self->{groups}}){

		if ($group->{group_level} > 0  &&  $group->{group_level} <= $plugin_group_requirement){
			$x_gpra = 1;
			$plugin_run_allowed = 1;
		}

		if ($group->{group_level} > 0 && $group->{group_level} <= $command_group_requirement){
			$x_gcra = 1;
			$command_run_allowed = 1;
		}
	}

	##	OK, now for the 0 level groups. that's a "must be a member of that group"
	## sort of thing.  if that's the case, one of the run requirements is still 0 here.
	
	if ($plugin_group_requirement == 0){
		foreach my $group (@{$self->{groups}}){
			if ($group->{group_name} eq $plugin_group_name){
				$x_gpra = 1;
				$plugin_run_allowed = 1;
			}
		}
	}

	if ($command_group_requirement == 0){
		foreach my $group (@{$self->{groups}}){
			if ($group->{group_name} eq $command_group_name){
				$x_gcra = 1;
				$command_run_allowed = 1;
			}
		}
	}


	## Also, there may have been a user requirement.  If so, make sure that user
	##   is included in the require_user list

	if (@{$command_user_requirement} && $command_run_allowed){
		$command_run_allowed = 0;
		if ($self->isAuthed()){
			foreach my $allowed_user (@{$command_user_requirement}){
				if ($allowed_user eq $self->{nick}){
					$command_run_allowed = 1;
					$x_ncra=1;
				}
			}
		}
	}

	if (@{$plugin_user_requirement} && $plugin_run_allowed){
		$plugin_run_allowed = 0;
		if ($self->isAuthed()){
			foreach my $allowed_user (@{$plugin_user_requirement}){
				if ($allowed_user eq $self->{nick}){
					$plugin_run_allowed = 1 ;
					$x_npra = 1;
				}
			}
		}
	}

	##
	## Handle Allows.  Allowing a user to run a command overrides everything else
	##
	if (@{$plugin_user_allow}){
		if ($self->isAuthed()){
			foreach my $allowed_user (@{$plugin_user_allow}){
				if ($allowed_user eq $self->{nick}){
					$command_run_allowed = 1;
					$plugin_run_allowed = 1;
					$x_npre=1;
				}
			}
		}
	}

	if (@{$command_user_allow}){
		if ($self->isAuthed()){
			foreach my $allowed_user (@{$command_user_allow}){
				if ($allowed_user eq $self->{nick}){
					$command_run_allowed = 1;
					$plugin_run_allowed = 1;
					$x_ncre=1;
				}
			}
		}
	}


	##
	## Explaining
	##

	my $color;
	if ($x_gpra){ $color=GREEN; }else{ $color = PURPLE; }

	if ($plugin_flag_req){
		$reason.=$color."Plugin requires $plugin_group_name ($plugin_group_requirement) when used with flag $plugin_flag_req.".NORMAL." ";
	}else{
		$reason.=$color."Plugin requires $plugin_group_name ($plugin_group_requirement).".NORMAL." ";
	}

	if ($x_npra){ $color=GREEN; }else{ $color=PURPLE; }

	if (@{$plugin_user_requirement}){
		$reason.=$color."Plugin also requires that the user's nick be one of (";
		$reason .= join ",", @{$plugin_user_requirement} ;
		$reason .="). ".NORMAL;
	}

	if ($x_gcra){ $color=GREEN; }else{ $color=PURPLE; }

	if ($command_flag_req ){
		$reason.=$color."Command '$command', when used with flag '$command_flag_req', requires ";
		$reason.="$command_group_name ($command_group_requirement). ".NORMAL;
	}else{
		$reason.=$color."Command '$command' requires $command_group_name ";
		$reason.="($command_group_requirement). ".NORMAL;
	}

	if ($x_ncra){ $color=GREEN; }else{ $color=PURPLE; }

	if (@{$command_user_requirement}){
		$reason.=$color."'$command' also requires that the user's nick be one of (";
		$reason .= join ",", @{$command_user_requirement} ;
		$reason .="). ".NORMAL;
	}

	my $high=999;
	my $high_name;
	$reason.="$self->{nick} is a member of:";
	foreach my $group (@{$self->{groups}}){
		$reason.=" $group->{group_name}($group->{group_level})";

		if ( ($group->{group_level} < $high) && ($group->{group_level} > 0)){
			$high = $group->{group_level};
			$high_name = $group->{group_name};
		}
	}


	if ( $high <= $plugin_group_requirement){
		$reason.=". Membership in group '$high_name' allows plugin run. ";
	}elsif($plugin_group_requirement == 0){
		if ($x_gpra){
			$reason.=". Membership in group '$plugin_group_name' allows plugin run. ";
		}else{
			$reason.=". Not having membership in group '$plugin_group_name' prevents plugin run. ";
		}

	}else{
		$reason.=". $self->{nick} cannot run the plugin because of group membership levels. ";
	}

	if ( $high <= $command_group_requirement){
		$reason.="Membership in group '$high_name' allows command run. ";
	}elsif($command_group_requirement == 0){
		if ($x_gcra){
			$reason.="Membership in group '$command_group_name' allows command run. ";
		}else{
			$reason.="Not having membership in group '$command_group_name' prevents command run. ";
		}
	}else{
		$reason.="$self->{nick} cannot run the command because of group membership levels. ";
	}
	
	if (@{$plugin_user_requirement}){
		if ($x_npra){
			$reason.=GREEN."$self->{nick} is included in the require_users list, ";
			$reason.="so $self->{nick} is allowed to run the plugin.".NORMAL;
		}else{
			$reason.=RED."$self->{nick} is not included in the require_users list, ";
			$reason.="so $self->{nick} is not allowed to run the plugin.".NORMAL;
		}
	}
	
	if (@{$command_user_requirement}){
		if ($x_ncra){
			$reason.=GREEN."$self->{nick} is included in the require_users list, ";
			$reason.="so $self->{nick} is allowed to run the command.".NORMAL;
		}else{
			$reason.=RED."$self->{nick} is not included in the require_users list, ";
			$reason.="so $self->{nick} is not allowed to run the command.".NORMAL;
		}
	}

	if (@{$plugin_user_allow}){
		$reason.="However, the Plugin's allow_users setting makes an explicit exception for these users: (";
		$reason .= join ",", @{$plugin_user_allow} ;
		$reason .="). ";

		if ($x_npre){
			$reason .= GREEN."Since $self->{nick} is on this list, $self->{nick} can run all commands in this plugin.".NORMAL;
		}else{
			$reason .= PURPLE."Since $self->{nick} is not on this list, $self->{nick} cannot run this command.".NORMAL;
		}
	}
	if (@{$command_user_allow}){
		$reason.="However, the command's allow_users setting makes an explicit exception for these users: (";
		$reason .= join ",", @{$command_user_allow} ;
		$reason .="). ";

		if ($x_ncre){
			$reason .= GREEN."Since $self->{nick} is on this list, $self->{nick} can run the command.".NORMAL;
		}else{
			$reason .= PURPLE."Since $self->{nick} is not on this list, $self->{nick} cannot run the command.".NORMAL;
		}
	}
	
	#end explaining

	if ($plugin_run_allowed && $command_run_allowed){
		return (1, $reason);
	}else{
		return (0, $reason);
	}
	
}


sub hasPermission{
   my $self = shift;
	my $pnick = shift;


	# bad input
	return 0 if (!$pnick);
	
	# user is authed & using the nick we are asking about. easy.
	return 1 if ($self->isAuthed() && ($pnick eq $self->{nick}));
	
	# admins always have permission
	return 1 if ($self->getHighestGroupLevel() == UA_ADMIN_LEVEL );

	# if the person has an account, but this person aint that person, say no
	return 0 if ($self->accountExists());

	# This person does not have an account, so return 1 if their nick matches.
	# This lets people use bot functions without registering.
	return 1 if ($self->{nick} eq $pnick);

	# no.
	return 0;		
}


## This function also appears in PluginBaseClass
sub getCollection{
   my $self = shift;
   my ($module_name, $collection_name) = @_;

   if (!$module_name || !$collection_name){
      print "ATTENTION: You're something wrong with your collection.\n";
		print "You need to supply both a module_name and a collection_name.\n";
		print "You specified module_name:$module_name  collection_name:$collection_name\n";
      exit;
   }

   #my $c = $self->Collection->new($self->{BotDatabaseFile}, $module_name, $collection_name);
	my $c = $self->Collection->new({db_file=>$self->{BotDatabaseFile}, module_name=>$module_name,
         collection_name=>$collection_name, sql_pragma_synchronous=>$self->{sql_pragma_synchronous} });
   $c->load();
   return $c;
}


sub setValue{
   my $self = shift;

   my ($key, $value) = @_;

   $self->{$key} = $value;

   #print "I set $key to $value\n";
   return $self->{'options'};
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

1;
__END__
