package plugins_sys::UserOptions;
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

sub plugin_init{
	my $self = shift;
	return $self; 
}

sub getOutput {
	my $self = shift;
	my $output = "";
	my $options = $self->{'options'};
	my $cmd = $self->{command};
	my $nick = $self->{nick};

	##
	##	Whoami
	##

	if ($cmd eq 'whoami'){

		#print Dumper($self->{'UserAuthObj'});

		my $believe = 0;
		my $ret = "You say you are $nick. ";
		
		if ($self->hasAccount()){

			if ($self->{UserAuthObj}->{mask_authed}){
				$ret.="And while no one named $nick has an account with me, ";
				$ret.="based on your hostmask I think you are ".$self->accountNick().'. ';
			}else{
				$ret.="You do have an account with me. ";

				if ($self->isAuthed()){	
					$ret.="And I do believe you are who you say you are, ";
					$ret.="because I recognize the hostmask you're using. ";

				}else{
					$ret.="But the hostmask you're using isn't one that I recognize. ";
					$ret.="Login with me using the login command";

					if ($self->{channel} eq $self->{nick}){
						$ret.='.';
					}else{
						$ret.=" in a PM window. (type /msg $self->{BotName} login).";
					}
				}
			}

		}else{
			$ret.="And you do not have an account with me. That's OK, you don't really need ";
			$ret.="one to do most things. But if you want one, register. ";

			if ($self->{channel} ne $self->{nick}){
				$ret.="Type /msg $self->{BotName} register";
			}
		}
	
		return ($ret);
	}

	##
	##	Registration
	##

	if ($cmd eq 'register'){
		if (!$self->hasFlag("force") && $self->{channel} =~m/^#/){
			return "You need to be in a private chat session to run this command. ";
		}

		return $self->help($cmd) if (! (my $password = $self->hasFlagValue("password")));
		return "You're not supposed to include the <> part." if ($password=~/^<.+?>$/);
		return $self->{UserAuthObj}->register($password);

	}

	##
	##	delete account
	##

	if ($cmd eq 'delete_account'){
		if (!$self->hasFlag("force") && $self->{channel} =~m/^#/){
			return "You need to be in a private chat session to run this command. ";
		}
		return "You need to be logged in to use this command." if (!$self->isAuthed());
		return $self->help($cmd) if (! (my $password = $self->hasFlagValue("password")));
		return $self->{UserAuthObj}->deleteAccount($password);
	}

	##
	##	mask_auth setting
	##
	if ($cmd eq 'mask_auth'){
		return "You need to be logged in to use this command." if (!$self->isAuthed());

		if ($self->hasFlag("enable")){
			$self->{UserAuthObj}->maskAuthStatus("enable");
			return "ok.";
		}

		if ($self->hasFlag("disable")){
			$self->{UserAuthObj}->maskAuthStatus("disable");
			return "ok.";
		}

		if ($self->{UserAuthObj}->maskAuthStatus()){
			return "Mask auth is currently enabled for this account.  Disable it with the -disable flag.";
		}else{
			return "Mask auth is currently disabled for this account. Enable it with the -enable flag.";
		}
	}


	##
	## Change Password
	##
	if ($cmd eq 'change_password'){
		if (!$self->hasFlag("force") && $self->{channel} =~m/^#/){
			return "You need to be in a private chat session to run this command. ";
		}
		return "You need to be logged in to use this command." if (!$self->isAuthed());
		return $self->help($cmd) if (! (my $opass = $self->hasFlagValue("old_password")));
		return $self->help($cmd) if (! (my $npass = $self->hasFlagValue("new_password")));
		return $self->{UserAuthObj}->changePassword($opass, $npass);
	}

	##
	## Login & logout
	##
	if ($cmd eq 'login'){

		if (!$self->hasFlag("force") && $self->{channel} =~m/^#/){
			return "You need to be in a private chat session to run this command. ";
		}

		return $self->help($cmd) if (! (my $pass = $self->hasFlagValue("password")));

		my $loginnick = $self->{nick};
		if ($self->hasFlagValue("nick")){
			$loginnick = $self->hasFlagValue("nick");
		}

		return $self->{UserAuthObj}->login($loginnick, $pass);
	}

	if ($cmd eq 'logout'){
		return $self->{UserAuthObj}->logout();
	}

	##
	## Hostmasks
	##

	if ($cmd eq 'hostmasks'){
		return $self->help($cmd) if ( $self->hasFlag("h"));	
		return $self->help($cmd) if ( $options );	
		if (my $val = $self->hasFlagValue("delete")){
			return $self->{UserAuthObj}->deleteMask($val);

		}else{
			return $self->{UserAuthObj}->listMasks();
		}
	}

	##
	## Groups
	##

	if ($cmd eq 'groups'){
		return $self->help($cmd) if ( $self->hasFlag("h"));	
		return $self->help($cmd) if ( $options );	

		my @groups = $self->{UserAuthObj}->listGroups();
		if (@groups==1){return("You are member of one group: ". join " ", @groups);}
		if (@groups>1){ return ("You are member of these groups: ". join ", ", @groups);}
		return "You are not a member of any groups.";
	}



	##
	##	Output filter
	##

	if ($cmd eq 'output_filter'){
		return "You need to be logged in to use this command." if (!$self->isAuthed());
		if ( $self->hasFlag("c")){
			return $self->{UserAuthObj}->clearOutputFilter();

		}elsif(my $val = $self->hasFlagValue("s")){
			return $self->{UserAuthObj}->setOutputFilter($val);

		}else{
			#return $self->{UserAuthObj}->listOutputFilter();
			if (my $f = $self->{UserAuthObj}->outputFilter()){
				return "Your current output filter is $f.  To clear it, use the -c flag";
			}else{
				return "You don't have an output filter set. To set one, use the -s flag";
			}
		}
	}

	if ($cmd eq 'finger'){
		return $self->help($cmd) if ( !$options);	
		my $c = $self->getCollection(__PACKAGE__, $options);
		my @records = $c->matchRecords({val1=>'finger_info'});
		if (@records){
			return "$options finger information: " . $records[0]->{val2};
		}else{
			return ($self->{'options'} ." has no finger information, but can set some using the chfn command.");
		}
	}

	if ($cmd eq 'chfn'){
		return $self->help($cmd) if ( !$options);	
		
		if (! $self->hasPermission($self->accountNick()) ){
			return "You don't have permission to do that.";
		}

		$self->suppressNick(1);
		my $c = $self->getCollection(__PACKAGE__, $self->accountNick());
		my @records = $c->matchRecords({val1=>'finger_info'});

		if (@records){
			$c->updateRecord($records[0]->{row_id}, {val2=>$options});
		}else{
			$c->add('finger_info', $options);
		}
		return "Your finger information was updated";
	
	}

}


sub listeners{
   my $self = shift;

   ##Command Listeners - put em here.  eg ['one', 'two']
   my @commands = [qw(whoami register delete_account change_password login 
				logout hostmasks output_filter groups finger chfn mask_auth)];

	my $default_permissions = [];

   return({commands=> @commands, permissions=>$default_permissions});
}

sub addHelp{
   my $self = shift;
   $self->addHelpItem("[plugin_description]", "User Options.");
   $self->addHelpItem("[whoami]", "Find out who $self->{BotName} thinks you are.");
   $self->addHelpItem("[register]", "Usage: register -password=<password>. Register your current nick using supplied password. Your password will be hashed before being saved.");
   $self->addHelpItem("[delete_account]", "Usage: delete_account -password=<password>. Delete your $self->{BotName} account.  This will delete you from the user table, but some plugins may still have data tied to your nick.");
   $self->addHelpItem("[change_password]", "Usage: change_password -old_password=<old> -new_password=<new>. ");
   $self->addHelpItem("[login]", "Usage: login -password=<password> [-nick=<nick>]");
   $self->addHelpItem("[logout]", "Usage: logout");
   $self->addHelpItem("[output_filter]", "$self->{BotName} will send all communiques with you through an output filter.  [-c] to clear your output filter.  [-s <filter>] to set a filter]");
   $self->addHelpItem("[output_filter][-s]", "Set an output filter.  Usage: output_filter -s <filter>");
   $self->addHelpItem("[output_filter][-c]", "Clear your output filter. Usage: output_filter -c ");
   $self->addHelpItem("[hostmasks]", "See the hostmasks that $self->{BotName} identifies you with. To see a list, just do \"hostmasks\".  To add a new one, login while using that mask.  To delete one, use -delete=<#id>");
   $self->addHelpItem("[hostmasks][-delete]", "Delete a recognized hostmask from your account.  Usage: hostmasks -delete=<#id>");
   $self->addHelpItem("[groups]", "Shows you the groups you currently belong to.");
   $self->addHelpItem("[finger]", "Finger a user.  Usage: finger <nick>");
   $self->addHelpItem("[chfn]", "Update your finger information.  Usage: chfn <new info>");
   $self->addHelpItem("[mask_auth]", "$self->{BotName} can try to identify you based on your hostmask.  So when you /nick around, it still knows who you are. Turn that on & off here.");
}
1;
__END__
