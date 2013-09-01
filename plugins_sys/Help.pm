package plugins_sys::Help;
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
use POSIX;


##
##	Note: The flags to help use --two hyphens so they're not confused with the flags to the command
##	Note: This plugin is a fucking mess.
##

sub getOutput {
	my $self = shift;
	my $output = "";

	my $options = $self->{options_unparsed} || "";
	my $cmd = $self->{command};
	my $nick = $self->{nick};
	my $bot_name = $self->{BotName};

	$self->suppressNick("true");

	#print Dumper ($self->{BotPluginInfo});
	my $plugins = $self->{BotPluginInfo};


	if ($cmd eq 'allhelp'){
		my @commands;
		my $html="<h2>$self->{BotName} help file</h2>";
		$html.="Generated on " . strftime "%F %T %Z", localtime $^T;	
		$html.="<p>$self->{BotName} is a <a href=\"http://is.gd/rocksbot\">RocksBot perl IRC bot</a> run by user $self->{BotOwnerNick}.  The command prefix is: $self->{BotCommandPrefix}</p>";
		$html.="<p>You don't need an account to do most things with $self->{BotName}. But if you register for an account, the bot will keep track of you & your data if your nick changes.  To get an account, type /msg $self->{BotName} register -password = your_chosen_password.  Passwords are hashed and do not appear in the bot log files. See the <a href=\"#UserOptions\">UserOptions</a> section of this document for a listing of account related functions.</p>";
		$html.="<p>Help is available via the $self->{BotCommandPrefix}help command.  Use $self->{BotCommandPrefix}help to get a list of plugins.  Use $self->{BotCommandPrefix}help PluginName to get a list of commands in each plugin. Use $self->{BotCommandPrefix}help command_name to see help for a particular command.  <i>Example:  $self->{BotCommandPrefix}help register.</i> Most commands work via PM as well. You don't need to use the command prefix ($self->{BotCommandPrefix}) in a PM window.</p>";
		$html.="<p>Below is a listing of the enabled plugins and the available help messages.</p><hr>";

		$html.="<b>Enabled Plugins</b><br>";
		$html.="<ul>";
		foreach my $k (sort keys $plugins){
			$html.="<li><a href=\"#$k\">$k</a></li>";
		}
		$html.="</ul>";
		$html.="<p>&nbsp;</p>";

		foreach my $k (sort keys $plugins){
			$html.="<a name=\"$k\"></a>";
			$html.="\n<p><b>$k</b>:\n";

			my $p = $plugins->{$k};
			my $o = $p->{package}->new($p->{init_options});
			$html.= $o->{HELP}->{'[plugin_description]'};

			$html.="\n<br><i>Commands: ";
			foreach my $command (@{$plugins->{$k}->{commands}}){
				if ($command !~/^_/ && $command ne $k){
					$self->addToList($command)
				}
			}
			my $temp = $self->getList();
			if ($temp){
				$html.=$temp;
			}else{
				$html.="No commands.";
			}
			$html.="</i></p>";
			

			$html.="<ul>";
			foreach my $h (sort keys $o->{HELP}){
				my $key = $h;
				my $text = $o->{HELP}->{$h};
				next if ($key eq '[plugin_description]');
				$text=~s/</&lt;/gis;
				$text=~s/>/&gt;/gis;
				$html.="<li>$h : $text</li>";
			}
			$html.="</ul>";

			$html.="<p>&nbsp;</p>";
		}

		my $link = $self->publish($html);
		return "Help file generated: $link";
	}



	if ($cmd eq 'allcommands'){
		my @commands;
		foreach my $k (sort keys $plugins){
			foreach my $command (@{$plugins->{$k}->{commands}}){
				if (!$self->hasFlag("all")){
					#print "ask for $k - $command\n";
					my ($p, $r) = $self->{UserAuthObj}->hasRunPermission($command, "", $plugins->{$k});
					#print "return is $p\n";
					next if (!$p);
				}

				if ($command !~/^_/){
					if ($self->hasFlag("fullname")){
						push @commands, "$k.$command";
					}else{
						push @commands, $command;
					}
				}
			}
		}

		@commands = sort (@commands);

		foreach my $command (@commands){
			$self->addToList($command);
		}

		my $list = $self->getList();
		my $size = @commands;
		return "$size commands match: " . $list;
	}

	if ($cmd eq 'allregex'){
		my @exp;
		foreach my $k (sort keys $plugins){
			foreach my $regex (@{$plugins->{$k}->{preg_matches}}){
				push @exp, "$k: $regex";
			}
		}

		@exp = sort (@exp);

		foreach my $regex (@exp){
			$self->addToList($regex, $self->BULLET);
		}

		my $list = $self->getList();
		my $size = @exp;

		my $ret = BOLD."$size regex matches: ".NORMAL . $list;

		my @exc;
		foreach my $k (sort keys $plugins){
			foreach my $regex (@{$plugins->{$k}->{preg_excludes}}){
				push @exc, "$k: $regex";
			}
		}

		@exc = sort (@exc);

		foreach my $regex (@exc){
			$self->addToList($regex, $self->BULLET);
		}

		$list = $self->getList();
		$size = @exc;
		
		$ret.=" ".BOLD."$size regex excludes: ".NORMAL . $list;

		return $ret;

	}



	##
	##	Begin Help
	##

	my $package;

	if ($self->hasFlag("-info")){
		$options =~s/\s*--info\s*//gis;
	}

	if ($self->hasFlag("-all")){
		$options =~s/\s*--all\s*//gis;
		#return "not yet";
	}

	$options=~s/ +/ /;

	my @tokens = split (/ /, $options);
	my $figureditout = "";		## used if the user doesnt enter the plugin name but we 
											##  figured out what they meant anyway.


	##
	## no options passed, list the modules
	##

	if (@tokens == 0){
		$output = "My Plugins:";
		foreach my $k (sort keys $plugins){
			$output.=" $k";
		}

		return $output;

	}


	## options supplied.  List the commands, but not the ones starting with an _
	## _underscore commands are used for reentry & other stuff you wanna keep private

	#if (@tokens == 1){
	if (1){

		## if this is a package name, return either a command listing, --all, or --info.
	
		my $testpackage = $tokens[0];

		if (defined($plugins->{$testpackage})){
			#yay, it's a package.  that makes things easy.
			
			## if we asked for a general info, return that.

			if ($self->hasFlag("-all")){
				my $p = $plugins->{$testpackage};
				my $o = $p->{package}->new($p->{init_options});
				#$output = "Plugin Description: ";
				$output .= $o->help('--all');
				return $output;
			} 
			
			if ($self->hasFlag("-info")){
				my $p = $plugins->{$testpackage};
				my $o = $p->{package}->new($p->{init_options});
				#$output = "Plugin Description: ";
				$output .= $o->help('--info');
				return $output;
			}

			# ok, it wasn't flag. so lets list the commands in that package.

			if (@tokens == 1){
				if (defined($plugins->{$testpackage}->{commands}) && @{$plugins->{$testpackage}->{commands}}){
					$output = "Commands in $testpackage: ";

					my $comma = "";
					foreach my $cmd (sort {lc($a) cmp lc($b)} @{$plugins->{$testpackage}->{commands}}){
						if ($cmd!~/^\_/ && $cmd ne $testpackage){
							$output.= $comma . "$cmd";
							$comma = ", ";
						}
					}

					return $output;
				}else{
					return "That package doesn't have any commands.  It provide other services, or the administrator may have disabled them.";
				}
			}else{
				# we found the package, but there are more arguments.
				$package = $testpackage;
			}
		}

		
		## ok, that first argument wasn't a package.  Maybe user typed a command. 
		## they should have typed the package first, but users rarely listen.
		## who can blame them, this is cumbersome. Let's have a looksee.

		if (!$package){
			my @found;
			#my $cmd = $testpackage;  #just to make this clearer # not
			foreach my $entry (keys $plugins){
				foreach my $cmd (@{$plugins->{$entry}->{commands}}){
					if ($cmd eq $testpackage){
						## found it. let's make sure it's the only one.
						push @found, $entry;
					}
				}
			}
				
			if (@found == 0){
				return ("I'd love to help you, but couldn't find that command ($testpackage) in any plugin.");

			}elsif(@found > 1){
				my $list;
				my $sample;

				foreach my $f (@found){
					if ($list){
							$list.=", $f";
						}else{
							$list = $f;
							$sample = $f;
						}
					}

					$output = "The '$cmd' command was found in these plugins: $list. ";
					$output .="Specify the plugin name to get help.  Example: help $sample $cmd";
					return ($output);
			}else{
				$figureditout = $found[0];
			}
		}
	}


	# if we made it this far, we either found the exact package name where tokens =1,
	# or we figured out what package the user was talking about by specifying a command.


	if ($package){
		print "Package $package specified\n";
		shift(@tokens);

	}elsif ($figureditout){
		print "package is $figureditout\n";
		$package = $figureditout;
	}else{
		$package = shift @tokens;
	}
	
	my $p;

	if ($plugins->{$package}){
		$p = $plugins->{$package};
	}else{
		return "an error happened in H.h.1";
	}

	$self->{'obj'} = $p->{package}->new($p->{init_options});

	if ($self->hasFlag("-info")){
		#$output = "Plugin Description: ";
		$output .= $self->{obj}->help('--info');

	}elsif ($self->hasFlag("-all")){
		$output = "ALL: ";

	}else{
		$output = $self->{obj}->help(@tokens);
	}

	if (!$output){
		$output = "I'd love to help you, but couldn't find the Plugin \"$package\".";
	}
	
	return $output;
}

sub listeners{
	my $self = shift;
	##Command Listeners - put em here.  eg ['one', 'two']
	my @commands = [qw(help allcommands allregex allhelp)];

   my $default_permissions = [{command=>'help', flag=>'admin', require_group=>UA_ADMIN} ,
		{command=>'allregex',  require_group=>UA_ADMIN} 
		];

   return {commands=>@commands, permissions=>$default_permissions};
}

##
## addHelp()
##	The help system will pull from here using PluginBaseClass->help(key).
##
sub addHelp{
	my $self = shift;
	$self->addHelpItem("[plugin_description]", "Help System. Note that flags to help use --two hyphens.  For admin commands, [--admin]");
	$self->addHelpItem("[help]", "Usage: help <plugin name> [<command> ...].  Use help --info <plugin name> to get general plugin information.  Use help --all to see all of the help. Use the allhelp command to view an HTML help file for this bot.");
	$self->addHelpItem("[help][-info]", "Get the plugin description.");
	$self->addHelpItem("[help][-all]", "See all help available for a particular plugin or command.");
	$self->addHelpItem("[allcommands]", "List all commands that $self->{BotName} will respond to. By default will only list the commands that the requesting user has permission to run.  Use -all to see all commands. Use -fullname to include the plugin name with each command.");
	$self->addHelpItem("[allregex]", "List all currently registered regex matches.");
	$self->addHelpItem("[allhelp]", "Create and publish an HTML document that lists all commands.");
	#$self->addHelpItem("[man]", "Usage: help <plugin name> [<command> ...].  Use help --info <plugin name> to get general plugin information.  Use help --all to see all of the help.");
	
}

1;
__END__
