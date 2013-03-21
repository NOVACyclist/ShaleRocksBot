#!/usr/bin/perl

## This is just a hack thing for testing plugins at the command line. 
## It's not complete, but useful for testing.  Pardon my goto.

$channel = "#test";
$nick = "someguy";
$mask = "mask\@/user/mask";
$ConfigFile = "./rocksbot.cfg";

#################################
use modules::CommandHandler;
use Data::Dumper;

print "Enter a command: ";

$filter_applied = 0;

if (@ARGV){
	$last_args = join " ", @ARGV;
}

while (<STDIN>){

	$args = $_;
	chomp ($args);
	

	if ($args){
		$last_args = $args;
	}else{
		$args = $last_args;
	}
	
	$filter_applied = 0;
BEGIN:
	($cmd, $opts) = split( " ", $args, 2);


	my $ch_options = {
 	  ConfigFile => $ConfigFile
	};

	$ch  = modules::CommandHandler->new($ch_options);
	$ch->loadPluginInfo();
	$ch->setValue("command", $cmd);
	$ch->setValue("options", $opts);
	$ch->setValue("nick", $nick);
	$ch->setValue("channel", $channel);
	$ch->setValue("mask", $mask);
	$ch->setValue("filter_applied", $filter_applied);
	$output = $ch->Execute();
		
	#print Dumper ($output);

	$filter_applied = $output->{filter_applied};

	if ($output->{output}){
		if ($output->{return_type} eq 'action'){
			print "RocksBot $output->{output}\n";

		}elsif ($output->{return_type} eq 'text'){
			if ($output->{suppress_nick}){
				print "$output->{output}\n";

			}else{
				print $output->{'nick'} . ": $output->{output}\n";
			}

		}elsif($output->{return_type} eq "irc_yield"){
			print "-->Doing IRC Yield command $output->{yield_command} \n";
			print "Args:\n";
			print Dumper($output->{yield_args});
			print "$output->{output}\n";


		}elsif($output->{return_type} eq "runBotCommand"){
			$args = $output->{output};
			goto BEGIN;
		}
	}
		
	if ($output->{reentry_command}){
		print "-->Reentry:  $output->{reentry_command} Opts: $output->{reentry_options} <--\n";
	}
	
	print "\nEnter a command: ";
}

