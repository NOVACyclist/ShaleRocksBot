# bazaar
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
# cost basis code in its own function
{
package plugins::Dig;

use strict;
use warnings;
use base qw (modules::PluginBaseClass);
use modules::PluginBaseClass 1.0;
use Data::Dumper;
use POSIX;
use Text::ParseWords;
use DateTime;

# these are all collections
my $board;	# managed by this module
my $player;	# an object
my $store; 	# an object
my $next_digs; #a collection. loaded here & passed to player obj

#these are all settings. 
my $num_plots;
my $board_value;
my $percent_filled;
my $dig_freq_mins;
my $num_trinkets;
my $fuzz_interval;
my $use_stocks;
my $stock_update_freq;
my $stock_list;

my $never_tired;

## all of this onbotstart stuff is just to keep the user entered stock list trimmed down 
## and proper
sub onBotStart{
   my $self = shift;

	# this commented out b/c use_stocks=0 doenst disable stocks altogether, it only prevents
	# the from appearing as free items on the board.  maybe that will change.
	#if (!$self->{use_stocks}){
	#	print "Dig is not perform stock quote maintainence b/c use_stocks is not enabled\n";
	#	return;
	#}

	print "Dig is performing stock quote maintainence...\n";
	# manage the user entered stocks. we dont want to keep getting quotes for unused stocks
	# forever. i'm worried about the GET request getting too long.
	my $c_stocks = $self->getCollection(__PACKAGE__, ':stocks');
	my $c_user = $self->getCollection(__PACKAGE__, '%');
	
	## get a list of user defined stocks. symbol is val2
	my @records = $c_stocks->matchRecords({val1=>"user_stocks"});
	foreach my $rec (@records){
		my $symbol = $rec->{val2};
		my @inuse = $c_user->matchRecords({val1=>"stock", val3=>$symbol, val5=>'stock_user'});
		if (@inuse){
			print "stock $symbol is in use, not deleting.\n";
		}else{
			print "no one is using stock $symbol, deleting.\n";
			# delete the user_stocks entry. this is a master record that tells the system which stocks
			# to keep updated
			$c_stocks->delete($rec->{row_id});
			my @quotes = $c_user->matchRecords({val1=>'quote_user', val2=>$symbol});
			foreach my $quote (@quotes){
				# delete the stock quote entry. this is so we dont have old data hanging around.
				# also, the quote lookup will show the old price if this isn't updated
				$c_stocks->delete($quote->{row_id});
			}
		}
	}
	
	# make sure we have quote_user entries
	# for all the user stocks in use
	@records = $c_user->matchRecords({val1=>"stock", val5=>'stock_user'});
	my $store_opts = {
		fuzz_interval => $self->{fuzz_interval},
		use_stocks => $self->{use_stocks},
		stock_list => $self->{stock_list},
		stock_update_freq => $self->{stock_update_freq},
		BotDatabaseFile => $self->{BotDatabaseFile},
		keep_stats => $self->{keep_stats}
	};
	$store = Store->new($store_opts);
	foreach my $rec (@records){
		my $symbol = $rec->{val3};
		#print "checking $symbol for master entry... ";
		my @master = $c_stocks->matchRecords({val1=>"user_stocks", val2=>$symbol});
		if (@master){
			print "found.\n";
		}else{
			print "not found.\n";
			my $new_stock = $store->lookupNewStock($symbol);

			if (!$new_stock){
				print "Error: I couldn't find $symbol listed on any market. Maybe there was a symbol change.  This program doesn't handle that.";
			}else{
				print "adding entry for $symbol\n";
				$store->addNewStock($new_stock);
			}
		}
	}

}


sub plugin_init{
	my $self = shift;
	$self->{num_plots} = 50;
	$self->{board_value} = 30;
	$self->{percent_filled} = 35;
	$self->{dig_freq_mins} = 20;
	$self->{num_trinkets} = 3;
	$self->{use_stocks} = 1;	#this prevents stocks from being hidden on the board. that's it.
	$self->{stock_update_freq} = 60*60*1;
	$self->{fuzz_interval} = 60*60*1;
	$self->{already_dug_penalty} = 60*7;		#set to zero for no penalty
	$self->{stock_list} = [qw(MSFT F GE T BAC WFC BBRY CSCO FB NWSA ZNGA SIRI GRPN DELL NVDA CRAY AMZN CMCSA NFLX INTC SBUX WTSL FLWS STSI AMD AA ZAZA PC CZR MLNK OMX ZZ ZIP BIOF FST ACTV AHS HNSN MOBI KGN DVAX MEA REE JVA CADX GMCR BIRDF RAVN RHT OFF ROCK COW SHI SHSO FRM NWPX GRO SQD.V AF VE DF DIGI DIG SD JNY.L ASIA BSX CAKE DKS BOOM KID MEMEX FLY CHMP CATY CATM ACAT HSPG TUF.V BAD.TO BDERF WLV.V WBKC BKI BUC.BE 19544.AX BRO USA HAL OIL UA LULU LUV MNST URRE URA MOONB.BO BKW CMG XXNCB DENN JMBA FU CA GIG)]; 

	$self->{ebay_DEVID} = $self->getInitOption("ebay_DEVID");
	$self->{ebay_AppID} = $self->getInitOption("ebay_AppID");
	$self->{ebay_CertID} = $self->getInitOption("ebay_CertID");

	$self->{never_tired} = 0;
	return $self; 
}


sub getOutput {
	my $self = shift;
	my $cmd = $self->{command};
	my $options = $self->{options};
	my $output;

	if ($self->{'mask'}=~/\@/){
		$self->{'mask'}= (split(/\@/, $self->{'mask'}))[1];
	}

	$self->loadData();

	if (my $msg = $self->{player}->tell()){
		print "I have something to tell $self->{player}->{nick}\n";
		return ("Hey $self->{player}->{nick}, sorry to interrupt, but I have a message for you: $msg");
	}

	##
	##	God mode
	##
	if ($self->hasFlag('god')){
		return $self->God();
	}

	##
	##	Dig!
	##

	if ($cmd eq 'dig'){

		if ( $self->{channel} ne $self->s("dig_channel") ){
			$output = "You can only dig in the ".$self->s("dig_channel")." channel. ";
			$output .=" Type /join ".$self->s("dig_channel")." to join.";
			return $output;
		}

		if ($self->hasFlag("notify") || $self->hasFlag("n")){
			return $self->doNotify();
		}

		my $spot =  $self->hasFlagValue("plot");

		if (!$spot){
			if ($options=~/([0-9]+)\b/){
				$spot = $1;
			}
		}
		
		if (!$spot){
			$self->suppressNick(1);
			return BLUE."Pick a plot to dig using \"$self->{BotCommandPrefix}dig <number>\": ".NORMAL. $self->getBoard();
		}

		return "You can't dig via a PM window." if ($self->{channel}!~/^#/);

		my $ans = $self->{player}->canDig();

		if ($ans->{answer}){
			return $self->useBomb($spot) if ($self->hasFlag("bomb"));
			return $self->digPlot($spot);

		}else{
			my $reminder = BLUE."If you'd like a PM when you're able to dig again, ";
			$reminder.="reply with dig -notify ".NORMAL;

			if ($ans->{why} eq 'bomb'){
				my $msg= "You're still cleaning up from da last bomb you set off. ";
				$msg .="Should take about $ans->{when} more minutes. $reminder";
				return $msg;

			}elsif ($ans->{why} eq 'already_dug'){
				my $msg = "You're still trying to act all nonchalant.  Another $ans->{when} ";
				$msg .="minutes should do it. $reminder";
				return $msg;

			}elsif ($ans->{why} eq 'bathroom'){
				my $msg = "You're still looking for a bathroom. You see one off in the distance, ";
				$msg .="but it'll take you another $ans->{when} minutes to get there ";
				$msg.="and finish up your business. $reminder";
				return $msg;

			}else{
				if ($ans->{when} == 1){
					my $msg = "You're still too tired from your last dig. ";
					$msg .="You need another minute of rest. $reminder";
					return $msg;
				}else{
					my $msg = "You're still too tired from your last dig. You need $ans->{when} ";
					$msg .="minutes of rest. ";
					if ( ($ans->{when} - 1 ) > ($self->{dig_freq_mins}/1.5)){
						$msg.="To recover more quickly, buy some items from the ".BOLD;
						$msg.="dig!".NORMAL." ".$self->{BotCommandPrefix}."store. ";
					}
					$msg .= "$reminder";
					return $msg;
				}
			}
		}
	}


	##
	## crews - crew stuff
	##

	if ($cmd eq 'crews'){

		if (my $crew = $self->hasFlagValue("join")){
			$self->{player}->crew($crew);
			return "Welcome to the $crew crew!";
		}

		if ($self->hasFlag("leave")){
			my $crew = $self->{player}->crew();
			if (!$crew){
				return "You are not a member of a crew.";
			}

			$self->{player}->crew(':delete');
			return "You have parted ways with the $crew crew.";
		}
	
		if ($self->hasFlag("list")){
			$self->suppressNick(1);
			my $crew = $self->hasFlagValue("list");
			if ($crew){
				# list members
				my @members = $self->crewMembers($crew);
				foreach my $m (@members){
					$self->addToList($m);
				}
				return "Members of ".BOLD."$crew".NORMAL." crew: ".$self->getList();
			}

			#list crews
			my @crews = $self->crewList();
			foreach my $c (@crews){
				$self->addToList($c);
			}
			my $list = $self->getList();
			if (!$list){
				$list = "There are no regitered digging crews.";
			}
			return BOLD."dig!".NORMAL." crews: ".$list;
		}

		if ($self->{player}->crew()){
			my @members = $self->crewMembers($self->{player}->crew());
			my $count = @members - 1;
			$output = "You are a member of the " . $self->{player}->crew() . " crew, along with $count other diggers. To see members, crews -list=".$self->{player}->crew()." To see other crews, crews -list. To leave this crew, crews -leave.";
			return $output;
		}else{
			$output = "You are not a member of a crew. You can join or create a crew using crews -join=<crew>. To see existing crews, crews -list";
			return $output;
		}
	
	}


	##
	##	leaders - get stats
	##
	
	if ($cmd eq 'leaders'){
		$self->suppressNick(1);

		##
		##	if flags, do that. this top part uses the "fast" way of doing things.
		## which doesnt make a ton of sense since the default view uses the "slow"
		## way of instantiating each player.  oh well.
		##
		my %diggers;

		my $unit;

		if ($self->hasFlag("dirt")){
			%diggers = $self->getDiggersStats('dirt');
			$unit = 'dirt';
			$output = NORMAL.BOLD."Top dirt hoarders: ".NORMAL;

		}elsif($self->hasFlag("digs")){
			%diggers = $self->getDiggersStats('num_digs');
			$output = NORMAL.BOLD."Top diggers: ".NORMAL;

		}elsif($self->hasFlag("money")){
			%diggers = $self->getDiggersStats('money');
			$unit = 'money';
			$output = NORMAL.BOLD."Top dirty fat cats: ".NORMAL;

		}elsif($self->hasFlag("pounds")){
			$unit = 'pound';
			%diggers = $self->getDiggersStats($unit);
			$output = NORMAL.BOLD."Chaps with the most cabbage: ".NORMAL;

		}elsif($self->hasFlag("gold")){
			$unit = 'goldcoin';
			%diggers = $self->getDiggersStats($unit);
			$output = NORMAL.BOLD."Top gold collectors: ".NORMAL;

		}elsif($self->hasFlag("trilobites")){
			$unit = 'trilobite';
			%diggers = $self->getDiggersStats($unit);
			$output = NORMAL.BOLD."Top fossil hoarders: ".NORMAL;
		}


		if (keys %diggers){
			foreach my $name (sort {$diggers{$b} <=> $diggers{$a}} keys %diggers  ){
				#print $name . $diggers{$name};

				if($self->hasFlag("digs")){
					my $val = $self->commify($diggers{$name});
					$self->addToList("$name: $val digs", $self->BULLET);
				}else{
					my $c = Currency->new({id=>$unit});
					my $val = $diggers{$name};
					$self->addToList("$name: " . $c->format($val), $self->BULLET);
				}
			}
			return $output . $self->getList();
		}


		##
		##		Get a list of diggers for the following displays, then instatiate each.
		##		This isn't *that* slow.  ~200 diggers takes about half a second
		##  

	
		%diggers = $self->getDiggersStats('num_digs');


		## 
		##	Handle the -whohas flag
		##

		if (my $id = $self->hasFlagValue("whohas")){
			my $item = $self->{store}->getItem($id);
			return "I don't know what that is." if (!$item);
			my %peeps;
			foreach my $d (keys %diggers){
				my $player = $self->loadPlayer($d);
				if (my $num = $player->hasItem($id)){
					$peeps{$d} = $num;
				}
			}

			foreach my $d (sort{$peeps{$b} <=> $peeps{$a}} keys %peeps){
				$self->addToList("$d: $peeps{$d}", $self->BULLET);
			}

			my $list = $self->getList();
			if ($list){
				$output = "These people have these many $item->{name}: " . $list;
			}else{
				$output = "No one has $item->{name}";;
			}
			return $output;
		}



		##
		##	Do net worth, maybe show by crew. 
		##


		foreach my $d (keys %diggers){
			my $player = $self->loadPlayer($d);
			$diggers{$d} = {worth=>$player->getNetWorth(), crew=>$player->getCrew()};
		}

		if ($self->hasFlag("crews")){
			my %crews;
			foreach my $d (keys %diggers){
				$crews{$diggers{$d}->{crew}} += $diggers{$d}->{worth};
			}
			foreach my $c (sort {$crews{$b} <=> $crews{$a}} keys %crews){
				my $val = $self->commify($crews{$c});
				$self->addToList("$c: \$$val",$self->BULLET);
			}
			$output = NORMAL.BOLD."Top digging crews: ".NORMAL.$self->getList();
			

		}else{
			foreach my $d (sort {$diggers{$b}->{worth} <=> $diggers{$a}->{worth}} keys %diggers  ){
				my $val = $self->commify($diggers{$d}->{worth});
				$self->addToList("$d: \$$val",$self->BULLET);
			}
			$output = NORMAL.BOLD."Top diggers by Net Worth: ".NORMAL.$self->getList();
		}
		return $output;	
	}



	##
	##	Show inventory
	##

	if ($cmd eq 'inventory'){

		my ($dirt, $money, $num_digs, $bombs, $items, $trinkets, $stocks) = (0, 0, 0, 0, "", 0);
		my $pronoun;
		my $who;

		my $player; 

		if (my $pnick = $self->hasFlagValue("nick")){
			$player = $self->loadPlayer($pnick);
			if (!$player->exists()){
				return "Couldn't find that digger.";
			}
			$pronoun = "$pnick has";

		}else{
			$pronoun = "You have";
			$player = $self->{player};
		}


		if ( $self->hasFlag("status")){	

			my $output;

			## do rest time only if looking for current player.  reason: masks are 
			## used for next dig time, and we dont know a different player's mask
			if ($player->{nick} eq $self->accountNick()){
				$output .= BOLD.'Rest time: '.NORMAL;

				my $ans = $player->canDig();
				if ($ans->{answer}){
					$output.="None. ";
				}else{
					if ($ans->{when} == 1){
						$output .= "Less than a minute. ";
					}else{
						$output .= "About $ans->{when} minutes. ";
					}
				}
				$output .= $self->BULLET . ' ';
			}

			my ($rem, $total)= $player->waterRemaining();

			$output .= BOLD.'Bladder:'.NORMAL.' [';
			for (my $i=$total; $i>0; $i--){
				if ($i <= $rem){
					$output.='-';
				}else{
					$output.='=';
				}
			}
			$output .= '] ';
				
			#if ($player->{nick} eq $self->accountNick()){
				if ($player->cookie("no_shovel_penalty")){
					$output.=$self->BULLET ." ".BOLD."Shovel".NORMAL." at the repair shop for ";
					$output.=$player->cookie("no_shovel_penalty")." more turns.";
				}
			#}
			return BOLD."Player status: ".NORMAL . $output;
		}


		if (my $id = $self->hasFlagValue("detail")){
			return  $player->thingDetail($id);
		}

		if ($self->hasFlag("trinkets")){
			my ($value, $symbols);
			#$self->hasFlag("values") ? ($value=1) : ($value=0);
			$self->hasFlag("symbols") ? ($symbols=1) : ($symbols=0);
			if ($self->hasFlag("full")){
				$symbols = 1;
				$value = 1;
			}
			my $list = $player->listTrinkets({quantity=>1, noone=>1, value=>1, symbols=>$symbols});
			my $total_value= $player->{listThingsTotal};

			if ($list){
				return NORMAL."$pronoun these ".BOLD."trinkets".NORMAL.", worth \$$total_value: ". $list;
			}else{
				return NORMAL."$pronoun no ".BOLD."trinkets.".NORMAL;
			}
		}

		if ($self->hasFlag("stocks")){
			my ($value, $symbols);
			#$self->hasFlag("values") ? ($value=1) : ($value=0);
			$self->hasFlag("symbols") ? ($symbols=1) : ($symbols=0);
			if ($self->hasFlag("full")){
				$symbols = 1;
				$value = 1;
			}
			my $list = $player->listStocks({quantity=>1, noone=>1, value=>1, symbols=>$symbols});

			my $total_value= $player->{listThingsTotal};
			if ($list){
				return NORMAL."$pronoun a portfolio worth \$$total_value, consisting of these ".BOLD."stocks: ".NORMAL . $list;
			}else{
				return NORMAL."$pronoun no ".BOLD."stocks.".NORMAL;
			}
		}

		$num_digs = $player->digs() || 0;

		my $currency_list = $player->listCurrency();

		$trinkets = $player->hasTrinket();
		$stocks = $player->hasStock();

		$output = NORMAL."After $num_digs digs, $pronoun accumulated $currency_list. ";

		$items = $player->listItems({quantity=>1, noone=>1});
		if ($items){
			$output.=BOLD."Digging equipment:".NORMAL." $items. ";
		}

		if ($trinkets){
			if ($trinkets > 1){
				$trinkets = "$trinkets ".BOLD."trinkets".NORMAL;
			}else{
				$trinkets = "$trinkets ".BOLD."trinket".NORMAL;
			}
			$output.="Plus, $pronoun $trinkets. ".BLUE."($cmd -trinkets).".NORMAL;
		}

		if ($stocks){
			if ($stocks> 1){
				$stocks = "$stocks ".BOLD."stocks".NORMAL;
			}else{
				$stocks = "$stocks ".BOLD."stock".NORMAL;
			}
			$output.=" And $stocks. ".BLUE."($cmd -stocks).".NORMAL;
		}

		my $net_worth = $self->commify($player->getNetWorth());
		$output .=" Net worth: " .GREEN.BOLD.'$'.$net_worth . NORMAL . '.';
		return $output;
	}


	##
	##	Shop in the store
	##

	if ($cmd eq 'store'){

		##
		##	do item info
		##

		if (my $id= $self->hasFlagValue("info")){
			return $self->{store}->getItemInfo($id);
		}
	
		##
		##	SELL an item to the store
		##

		if ($self->hasFlag("sell")){

			my $id;

			if ( $self->hasFlagValue("sell")){
				$id = $self->hasFlagValue("sell");
			}elsif ($options){
				$id = $options;
			}

			if ($id){
				my $quantity = 1;
				if ($self->hasFlagValue("n")){
					$quantity = $self->hasFlagValue("n");
					if ($quantity < 0){
						$quantity = -$quantity;
					}
				}
	
				my $has_num = $self->{player}->hasItem($id);
				return "I couldn't find that item in your inventory."  if (!$has_num);
				
				my $thing = $self->{store}->getItem($id);
				if ( $has_num < $quantity){
					return "You only have $has_num $thing->{name} in your inventory.";	
				}
				
				if ($thing->{dont_buyback}){
					return "Sorry, but we're not looking to buy a $thing->{name} right now. ";
				}

				if ($thing->{type} eq 'stock'){
					return "Sorry, but we're not in the stock game. Sell your $thing->{name} stock in the ".BOLD."dig! ".NORMAL."stock market. ".BLUE."($self->{BotCommandPrefix}market)".NORMAL;
				}

				## remove, credit price

				my $price = $thing->{current_value};
				if ($thing->{buyback_rate}){
					$price = sprintf("%.2f", $price * $thing->{buyback_rate});
				}

				$self->{player}->takeThing($thing, $quantity, $price);
				my $balance = $self->{player}->currency({type=>$thing->{price_unit}, increment=>$price * $quantity, format=>1});

				my $p = $thing->{currency_o}->format($price * $quantity);
				my $gain = $self->{player}->getProfit();
				my $neg ="";
				if ($gain <0){
					$gain = sprintf("%.2f", -$gain);
					$neg="-";
				}
				$output = "$p has been credited to your account. ";
				if ($thing->{price_unit} eq 'money'){
					$output.="Your net profit on the transaction, based on your acquisition cost, was $neg\$$gain.";
				}
				$output.=" You now have $balance. Nice doing business with you.";
				return $output;
			}

			#
			# Show the store
			#
			$self->suppressNick(1);
			my $opts = { player=>$self->{player} };
			my $list = $self->{store}->playerBuyList($opts);
			return $list;

		}

	
		##
		##	BUY
		##

		if (my $id= $self->hasFlagValue("buy")){

			my $item = $self->{store}->getSaleItem($id);
			if (!$item){
				return "I don't know anything about that.";
			}
	
			my $price_unit = $item->{price_unit};

			my $quantity = 1;

			if ($self->hasFlagValue("n")){
				$quantity = $self->hasFlagValue("n");
				if ($quantity < 0){
					$quantity = -$quantity;
				}
			}
	
			my $price;
			my $is_insider =0;
			if ($self->{player}->hasItem("digsinsider")){
				$is_insider=1;
				$price = $item->{price} * .90;
				
				if ($item->{currency_o}->{round_down} && $price > 1){
					$price = int($price);
				}
			}else{
				$price = $item->{price};
			}
	


			if ($self->{player}->currency({type=>$price_unit}) < ($price * $quantity)){
				return "You don't have enough " . $item->{currency_o}->plural() . ".";
			}

			## Handle special items
			my $opts = { item=>$item, player=>$self->{player}, quantity=>$quantity, digsinsider=>$is_insider, parent=>$self };
			my ($is_special, $special_output) = $self->{store}->specialItem($opts);
			if ($is_special == 1){
				return $special_output;
			}

			## check if player is allowed to own this
			my ($ans, $reason) = $self->{player}->canOwn($item, $quantity);
			if (!$ans){
				return $reason;
			}

			## add item, take away money 
		
			$self->{player}->addThing($item, $quantity, $price);
			$self->{player}->currency({type=>$price_unit, increment=>(-$price * $quantity)});
			my $bal = $self->{player}->currency({type=>$price_unit, format=>1});

			my $msg = "You have $bal left.";

			if ($quantity > 1){
			#	$output = "$quantity ".$item->{name}."s have been added to your inventory. $msg";
				$output = "$quantity ".$item->{name}."s have been added to your inventory";
			}else{
			#	$output = "$item->{name} has been added to your inventory. $msg";
				$output = "$item->{name} has been added to your inventory";
			}

			if ($quantity > 1){
				$output.=", at a total cost of ". $item->{currency_o}->format($price * $quantity) .'. ';
			}else{
				$output.=", at a cost of ". $item->{currency_o}->format($price * $quantity) .'. ';
			}
	
			$output .= $msg;

			if ($self->{player}->hasItem("digsinsider")){
				my $saved = $item->{currency_o}->format($item->{current_value} - $price);
				$output.=" (You saved $saved with your Dig's Insider Card!)";
			}
			return $output;
		}
			
		$self->suppressNick(1);
		my $casino;
		$self->hasFlag('casino') ? ($casino=1) : ($casino = 0);
		my $opts = { player=>$self->{player}, casino=>$casino};
		my $list = $self->{store}->playerSellList($opts);
		return $list;

	}


	##
	##	Stock Market 
	##

	if ($cmd eq 'market'){

		if (!$self->{player}->hasItem("marketinternship") && !$self->{player}->hasItem("traderlicense")){
			$output = "You don't have access to the ".BOLD."dig!".NORMAL." stock market. ";
			$output .="Start out by buying an internship in the ".BOLD."dig!".NORMAL." store.";
			return $output;
		}
		
		if (my $symbol = $self->hasFlagValue("quote")){
			$symbol = uc($symbol);
			return "That symbol doesn't look right." if ($symbol=~/\s/);

			my $stock;
			$stock = $self->{store}->getStock($symbol);

			if (!$stock->{not_found}){
				my $lu = $stock->{last_updated};
				$lu = int((time() - $lu)/60);
				if ($lu < 60){
					$lu = $lu . " minutes ago";
				}else{
					$lu = int($lu / 60);
					$lu = $lu . " hours ago";
				}
				$output = "$stock->{desc} is currently trading at $stock->{current_value}. (Last updated: $lu.)";
				return $output;
			}

			$stock = $self->{store}->lookupNewStock($symbol);

			if (!$stock){
				return "I couldn't find $symbol listed on any market.";
			}

			$output = "$stock->{name} ($stock->{symbol}) is currently trading at $stock->{price}. (Last updated: 1 second ago.)";
			return $output;
		}
		

		#
		#		buy stocks
		#
		if (my $symbol = $self->hasFlagValue("buy")){
			my $quantity = $self->hasFlagValue("n");
			return ("You need to specify a number using -n=<#>") if (!$quantity);

			if (!$self->{player}->hasItem("traderlicense")){
				my $last_trade_time = $self->{player}->cookie("last_stock_trade");
				if ($last_trade_time && ($last_trade_time > (time() - 60 * 60 * 16))){
					return "You can only trade once every 16 hours, intern. Now go get me some coffee.";
				}
			}

			$symbol = uc($symbol);
			return "That symbol doesn't look right." if ($symbol=~/\s/);

			my $stock;
			$stock = $self->{store}->getStock($symbol);
			if ($stock->{not_found}){
				#this is a new stock to us.  see if it exists.
				my $new_stock = $self->{store}->lookupNewStock($symbol);

				if (!$new_stock){
					return "I couldn't find $symbol listed on any market.";
				}

				# found the stock.  add it to the store update list
				$self->{store}->addNewStock($new_stock);
			}

			$stock = $self->{store}->getStock($symbol);
			if ($stock->{not_found}){
				return "Oh no! Something went wrong when buying that stock. Sorry bud.";
			}
	
			my $lu = $stock->{last_updated};
			$lu = int((time() - $lu));
			if ($lu > 60*60*96){
				print "lu s $lu\n";
				$lu = int ($lu /60 / 60 / 24) . " days";
				return ("Hmm, my stock quote for $symbol looks out of date. It was last updated $lu ago. Trading has been suspended.");
			}
			
			if ($self->{player}->currency({type=>$stock->{price_unit}}) < ($stock->{price} * $quantity)){
				return "You don't have enough " . $stock->{currency_o}->plural() . ".";
			}

			my $price = $stock->{price};
			$self->{player}->addThing($stock, $quantity);
			$self->{player}->currency({type=>$stock->{price_unit}, increment=>(-$price * $quantity)});
			my $bal = $self->{player}->currency({type=>$stock->{price_unit}, format=>1});

			$output = "$quantity shares of $stock->{desc} have been added to your portfolio ";
			$output .= "at a price of $price per share. ";
			$output .= "You have $bal remaining in your account.";

			$self->{player}->cookie('last_stock_trade', time());
			print "Set cookie\n";
			return $output;

		}


		#
		#		sell stocks
		#
		if (my $symbol = $self->hasFlagValue("sell")){
			my $quantity = $self->hasFlagValue("n");
			return ("You need to specify a number using -n=<#>") if (!$quantity);

			if (!$self->{player}->hasItem("traderlicense")){
				my $last_trade_time = $self->{player}->cookie("last_stock_trade");
				if ($last_trade_time && ($last_trade_time > (time() - 60 * 60 * 16))){
					return "You can only trade once every 16 hours, intern. Now go get me some coffee.";
				}
			}

			$symbol = uc($symbol);
			my $has_num = $self->{player}->hasStock($symbol);
			return "I couldn't find that stock in your portfolio."  if (!$has_num);
				
			my $stock = $self->{store}->getStock($symbol);
			if ( $has_num < $quantity){
				return "You only have $has_num $stock->{name} in your portfolio.";	
			}

			my $price;
			my $fee_rate;
			if ($self->{player}->hasItem("digsinsider")){
				$price = $stock->{current_value} * .99;
				$fee_rate = 1;
			}else{
				$price = $stock->{current_value} * .91;
				$fee_rate = 9;
			}

			$self->{player}->takeThing($stock, $quantity, $price);
			my $balance = $self->{player}->currency({type=>$stock->{price_unit}, increment=>$price * $quantity, format=>1});

			my $p = $stock->{currency_o}->format($stock->{current_value} * $quantity);
			my $gain = $self->{player}->getProfit();
			my $neg ="";
			if ($gain <0){
					$gain = sprintf("%.2f", -$gain);
					$neg="-";
			}

			my $fee = sprintf("%.2f", ($stock->{current_value} * $quantity ) - ($price * $quantity));
			$output = "$p has been credited to your account. ";
			$output.="After paying a $fee_rate% transaction fee of \$$fee, ";
			$output.="your net profit on the trade was $neg\$$gain. ";
			if ($self->{player}->hasItem("digsinsider")){
				my $saved = sprintf("%.2f", $fee * 8);
				$output.="(You saved \$$saved on the transaction fee with your Dig's Insider Card!) ";
			}
			$output.="You now have $balance in your account. ";
			$self->{player}->cookie('last_stock_trade', time());
			return $output;

		}
	
		$self->suppressNick(1);
		$output = "Welcome to the ".BOLD."dig!".NORMAL." stock market.  Use -quote=<x> to get a quote. ";
		$output .= "Use -buy=<symbol> -n=<quantity> to buy. ";
		$output .= "Use -sell=<symbol> -n=<quantity> to sell.";
		return $output;
	}


	##
	##	Bazaar
	##
	if ($cmd eq 'bazaar'){

	#	if (!$self->{player}->hasItem("") && !$self->{player}->hasItem("traderlicense")){
	#		$output = "You don't have access to the ".BOLD."dig!".NORMAL." stock market. ";
	#		$output .="Start out by buying an internship in the ".BOLD."dig!".NORMAL." store.";
	#		return $output;
	#	}
		
		if ($self->hasFlag("browse")){
			return $self->{store}->bazaarListings();
		}

		if (my $id = $self->hasFlagValue("list")){
			my $price = $self->hasFlagValue("price");
			my $quantity = $self->hasFlagValue("quantity");
			return "You need to use -quantity=<#>" if (!$quantity);
			return "You need to use -price=<#>" if (!$price);
			my $pricecheck = $price;	
			$pricecheck=~s/[0-9]//gis;
			$pricecheck=~s/\.//gis;
			return "The price should be only a number" if ($pricecheck);
			$pricecheck = $quantity;	
			$pricecheck=~s/[0-9]//gis;
			$pricecheck=~s/\.//gis;
			return "The quantity should be only a number" if ($pricecheck);

			my $thing = $self->{store}->getItem($id);
			if (!$thing){
				return "I don't know what a $id is.";
			}

			my $num = $self->{player}->hasItem($id);
			if ($num < $quantity){
				return "You only have $num of those.";
			}

			$self->{store}->bazaarListItem($thing, $player, $price, $quantity);

		}

		$output  = "Welcome to the bazaar, where you can trade items with other players. ";
		$output .= "To browse the available items, use -browse. ";
		$output .= "To list an item for sale, -list=<id> -quantity=<#>. ";
		$output .= "When an item is listed for sale, it is removed from your inventory. ";
		$output .= "You can re-claim an item at any time by canceling the listing. (-cancel)";
		return $output;
	}
}

##
## Multi-player stats.  Much faster to handle this here than to instantiate
## All of those player objects
## money num_digs dirt
##
sub getDiggersStats{
	my $self = shift;
	my $what = shift;

	my $c = $self->getCollection(__PACKAGE__, '%');

	my @records;
	my $val1;
	if ($what eq 'num_digs'){
		$val1 = 'account';
	}else{
		$val1 = 'currency';
	}

	@records = $c->matchRecords({val1=>$val1, val2=>$what});

	my %ret;
	foreach my $rec (@records){
		$ret{$rec->{collection_name}} = $rec->{val3};
	}
	return %ret;
}


sub crewMembers{
	my $self = shift;
	my $crew = shift;

	my $c = $self->getCollection(__PACKAGE__, '%');

	my @ret;
	my @records = $c->matchRecords({val1=>'account', val2=>'crew', val3=>$crew});
	foreach my $rec (@records){
		push @ret, $rec->{collection_name};
	}

	return @ret;
}


sub crewList{
	my $self = shift;

	my $c = $self->getCollection(__PACKAGE__, '%');

	my %nums;
	my @ret;
	my @records = $c->matchRecords({val1=>'account', val2=>'crew'});
	foreach my $rec (@records){
		if ($rec->{val3}){
			$nums{$rec->{val3}}++;
		}
	}

	foreach my $crew (sort {$nums{$b} <=> $nums{$a}}  keys %nums){
		my $word;
		if ($nums{$crew} == 1){
			$word = "member";
		}else{
			$word = "members";
		}
		push @ret, "$crew ($nums{$crew} $word)";
	}

	return @ret;
}

sub commify {
	my $self = shift;
	my $num  = shift;
	$num = reverse $num;
	$num=~ s/(\d\d\d)(?=\d)(?!\d*\.)/$1,/g;
	return scalar reverse $num;
}

sub doNotify{
	my $self = shift;
	my @records = $self->{next_digs}->matchRecords({val1=>$self->{mask}});

	my $r = $self->{player}->canDig();
	if ($r->{answer} == 1){
		return "You're able to dig right now, ".$self->{nick}.".";
	}
	
	my $sched_command = '_internal_echo';
	my $sched_options = "It's time to dig! again.";

	my $timer_args = {
		timestamp => $r->{when_time},
		command => $sched_command,
		options => $sched_options,
		channel => $self->{nick}, 
		desc => 'next dig reminder from Dig game.'
	};

	print "=================================\n";
	print "----------> SCHEDULED  next dig reminder for $self->{nick} at $r->{when_time}\n";
	print "=================================\n";
	my $timer_id = $self->scheduleEvent($timer_args);
	$self->{player}->cookie('notify_timer_id', $timer_id);
	$self->{player}->cookie('notify_timer_time', $r->{when_time});

	$self->suppressNick(1);
	return "OK, " . $self->{nick}.".  I'll send you a PM when you can dig! again.";

}

sub useBomb{
	my $self = shift;
	my $plot = shift;

	if (!$self->{player}->hasItem("bomb")){
		return "You don't have da bomb!";
	}
	
	my %total_currency;
	my $total_dirt = 0;
	my $map = 0;
	my $trinkets = "";

	#$self->{board}->startBatch();
	#$self->{player}->startBatch();

	# xyzzy this should be rewritten to loop on records instead of reloading & use batch
	for (my $i=($plot-2); ($i <= ($plot + 2)) && $i < $self->{num_plots}; $i++){
		my @records = $self->{board}->matchRecords({val1=>$i});

		next if ($records[0]->{val3} ne ':0');

		$self->{board}->updateRecord($records[0]->{row_id}, {val3=>$self->accountNick()});

		if ($records[0]->{val5} && $records[0]->{val5} eq 'currency'){
			my $amt = $records[0]->{val2};
			my $type = $records[0]->{val4};
	
			my $currency = Currency->new({id=>$type});
			if ($currency->{multiply}){
				my $bomb_tool = $self->{player}->getItemByGroup("bomb_tool");

				if ($bomb_tool){
					$amt = $amt * $bomb_tool->{item_info}->{attributes}->{money_multiplier};
				}
			}

			$self->{player}->currency({type=>$type, increment=>$amt, format=>0});
			$total_currency{$type} += $amt;

		}elsif ($records[0]->{val4} eq 'dirt'){
			my $num=1;
			my $sack = $self->{player}->getItemByGroup("sack");
			if ($sack){
				$num = $num * $sack->{item_info}->{attributes}->{dirt_multiplier};
			}
			$self->{player}->dirt($num);

			$total_dirt+=$num;

		}elsif ($records[0]->{val4} eq 'map'){
			$map = 1;
			my $num_spots = $records[0]->{val2};
			$self->sendMap($num_spots);

		}elsif ($records[0]->{val4} eq 'trinket'){
			my $trinket = $self->{store}->getTrinket($records[0]->{val2});
			$self->addToList($trinket->{name});
			$self->{player}->addThing($trinket, 1);

		}elsif ($records[0]->{val4} eq 'stock'){
			my $stock= $self->{store}->getStock($records[0]->{val2});
			$self->addToList('a share of ' . $stock->{name});
			$self->{player}->addThing($stock, 1);
		}
	}

	$self->{player}->digs(5);
	my $cur_out;
	foreach my $type (keys %total_currency){
		my $currency = Currency->new({id=>$type});
		$self->addToList($currency->format($total_currency{$type}));
	}

	$cur_out = $self->getList();
	#$total_money = sprintf('%.2f', $total_money);

	my $bomb =$self->{store}->getItem("bomb");
	$self->{player}->takeThing($bomb);
	$self->{player}->determineNextDigTime('bomb');

	#$self->{board}->endBatch();
	#$self->{player}->endBatch();

	my $msg;
	if ($cur_out){
		$msg = "After bombing plot #$plot and its neighbors, you found $cur_out, and $total_dirt piles of dirt. ";	
	}else{
		$msg = "After bombing plot #$plot and its neighbors, you found $total_dirt piles of dirt. ";	
	}

	if ($map){
		$msg.="You also found a treasure map! I'm PM'ing you with the details. ";
	}

	$trinkets = $self->getList();
	if ($trinkets){
		$msg.="You found some stuff, too: $trinkets.";
	}

	return $msg;
}


##
##	Dig!
##

sub digPlot{
	my $self = shift;
	my $plot = shift;

	my @records = $self->{board}->matchRecords({val1=>$plot});
	my $output;

	return "I couldn't find that spot."  if (!@records);

	my $rec = $records[0];

	## Spot already dug - assess penalty. or not
	if ($records[0]->{val3} ne ':0'){

		if ($self->{already_dug_penalty}){
			my $mins = int ($self->{already_dug_penalty} / 60);
			if ($rec->{val3} eq $self->accountNick()){
				$output .="Whoa nelly! You just set up on a spot that you've already dug! ";
			}else{
				$output .="Whoa nelly! You just set up on a spot already dug by $rec->{val3}! ";
			}
			$output .="You're so embarrassed by your faux pas that you spend the next $mins ";
			$output .="minutes trying to play it off like you meant to do it. ";

			if ( $self->{player}->money() >= 1){
				my $to;

				if ($rec->{val3} ne $self->accountNick()){
					$to = $rec->{val3};
				}else{
					$self->{next_digs}->sort({field=>'val2', type=>'numeric', order=>'desc'});
					my @records = $self->{next_digs}->getAllRecords();
					foreach my $rec (@records){
						if ($self->accountNick() ne $rec->{val4}){
							$to = $rec->{val4};
							last;
						}
					}
				}

				if ($to){
					my $penalty_amount = 1;

					$penalty_amount = sprintf("%.2f", $penalty_amount);
					$output .= "Also, you paid $to \$$penalty_amount to keep the news of your blunder on the down low. ";
					$self->{player}->money(-$penalty_amount);
					my $player = $self->loadPlayer($to);
					$player->money($penalty_amount);
				}
			}	

			$self->{player}->determineNextDigTime('already_dug');

		}else{
			$output .= "That spot was already dug by $rec->{val3} on $rec->{'sys_update_date'}. ";
			$output .="Pick a different plot to dig.";
		}

		return $output;
	}

	# mark plot as dug
	$self->{board}->updateRecord($rec->{row_id}, {val3=>$self->accountNick()});

	my $no_shovel_penalty = 0;
	if (my $p = $self->{player}->cookie("no_shovel_penalty")){
		if ($p == 1){
			$self->{player}->cookie("no_shovel_penalty", ':delete');
		}else{
			$self->{player}->cookie("no_shovel_penalty", $p-1);
			$no_shovel_penalty = 1;
		}
	}

	$self->{player}->startBatch();

	if ($rec->{val2} eq 'pitfall'){
		my $type = $rec->{val4};
		if ($type eq 'rock'){
			$output = "Oh no! You hit a rock! ";
			$output .= "Unfortunately this means that you'll have to send your shovel off ";
			$output .="to the shovel repair shop, and you'll be digging your next 10 plots ";
			$output .="sans-shovel. Keep on bein' awesome";
			$self->{player}->cookie("no_shovel_penalty", 10);
		}

	}elsif ($rec->{val5} && $rec->{val5} eq 'currency'){
		my $amt = $rec->{val2};
		my $type = $rec->{val4};
		my $currency = Currency->new({id=>$type});
	
		if ($currency->{multiply} && !$no_shovel_penalty){
			my $shovel = $self->{player}->getItemByGroup("shovel");

			if ($shovel){
				$amt = $amt * $shovel->{item_info}->{attributes}->{money_multiplier};
			}
		}

		#
		## Streak Longevity Multiplier
		#
		my $streak_start = 5;
		my $streak_step = .3;
		my $streak = $self->{player}->cookie("dig_streak") || 0;
		if ($streak > $streak_start){
			## longevity multiplier.
			my $mult = 1 + (($streak - $streak_start) * $streak_step);

			if ($currency->{round_down}){
				$mult = int($mult);
			}

			if ($mult > 1){
				$output = RED. $self->{player}->cookie("dig_streak") ." in a row!".NORMAL;
				$output .=" Earnings multiplied by ".BOLD."$mult".NORMAL."! ";
				$amt = $amt * $mult;
			}
		}

		##
		my $val = $self->{player}->currency({type=>$type, increment=>$amt, format=>1});
		$amt = $currency->format($amt);
		$output .= "You found $amt. You now have a total of $val";


	}elsif ($rec->{val4} eq 'dirt'){
		my $num = 1;
		my $sack = $self->{player}->getItemByGroup("sack");

		if ($sack){
			$num = $num * $sack->{item_info}->{attributes}->{dirt_multiplier};
		}
		my $val = $self->{player}->dirt($num);
		$output = "You found dirt";


	}elsif ($rec->{val4} eq 'map'){
		$output = "You found a treasure map! I'm sending you a PM with the details";
		my $num_spots = $rec->{val2};
		$self->sendMap($num_spots);


	}elsif ($rec->{val4} eq 'trinket' || $rec->{val4} eq 'stock'){
		my $thing = $self->{store}->getItem($rec->{val2});

		if ($thing->{type} eq 'trinket'){
			$output = "You found something! $thing->{name} has been added to your trinket bag";

		}elsif($thing->{type} eq 'stock'){
			$output = "You found something! A share of $thing->{name} has been added to ";
			$output.="your stock portfolio";
		}

		if ($self->{player}->hasItem("bifocals")){
			$output.=". And since you're seeing double, you get two of 'em";
			$self->{player}->addThing($thing, 2);
		}else{
			$self->{player}->addThing($thing, 1);
		}
	}


	# update number of digs.
	$self->{player}->digs(1);

	$self->{player}->endBatch();

	# set next dig time
	if ($self->{player}->determineNextDigTime('dig')){
		return $output . '.';		# ;)
	}else{
		return $output;
	}
}



##
##	Send Map
##

sub sendMap{
	my $self = shift;
	my $num_spots = shift;
	my $has_money = 0;

	$self->{board}->sort({field=>'val2', type=>'numeric', order=>'desc'});

	my @records = $self->{board}->matchRecords({val4=>'money', val3=>':0'});

	my $map;
	if (!@records){
		$map = "Hmm, I guess this isn't a map after all. Sorry, my mistake. ";
	}else{
		$map = "Treasure Map!  The best spots left to dig for cash are: ";
		$has_money = 1;
	}

	for (my $i=0; ($i<$num_spots) && ($i<@records); $i++){
		$self->addToList('#'.$records[$i]->{val1});
	}

	$map.=$self->getList();

	# check for trinkets
	@records = $self->{board}->matchRecords({val4=>'trinket', val3=>':0'});
	if (@records){
		my $tsquare = $records[int(rand(@records))]->{val1};
		my @blanks = $self->{board}->matchRecords({val4=>'dirt', val3=>':0'});
		if (@blanks){
			my $bsquare = $blanks[int(rand(@blanks))]->{val1};
			my $mix;
			if (int(rand(2))){
				$mix = "#$bsquare, #$tsquare";
			}else{
				$mix = "#$tsquare, #$bsquare";
			}

			if (int(rand(3))==1){
				if ($has_money){
					$map.=". And this part is hard to read, but I *think* one of these two ";
					$map.="squares contains a trinket of some sort: $mix. ";
				}
			}
		}
	}
	$self->sendPM($self->{nick}, $map);
}


sub loadData{
	my $self = shift;

	#load the next digs records
	$self->{next_digs} = $self->getCollection(__PACKAGE__, ':next_digs');

	##
	## load the store
	##
	my $store_opts = {
		fuzz_interval => $self->{fuzz_interval},
		use_stocks => $self->{use_stocks},
		stock_list => $self->{stock_list},
		stock_update_freq => $self->{stock_update_freq},
		BotDatabaseFile => $self->{BotDatabaseFile},
		next_digs_c => $self->{next_digs},
		keep_stats => $self->{keep_stats}
	};
	$self->{store} = Store->new($store_opts);
	# this is for keepStats
	push @{$self->{keep_stats_collections}}, $self->{store}->{stock_c};
	push @{$self->{keep_stats_collections}}, $self->{store}->{fuzz_c};

	# this is kinda messed up.  makeBoard needs the store, and the store needs
	# data from make board to determine some prices. hence the split.
	$self->makeBoard();

	my $opts = { 
			board_plotsRemaining=>$self->board_plotsRemaining(),
			board_moneyRemaining=>$self->board_moneyRemaining(),
			num_plots => $self->{num_plots}
	};
	$self->{store}->storeInit($opts);


	##
	##	Load the current player
	##
	$self->{player} = $self->loadPlayer($self->accountNick());
	$self->{player}->{never_tired} = $self->{never_tired};
	
}	

sub loadPlayer{
	my $self = shift;
	my $nick = shift;

	my $mask;
	if ($nick eq $self->accountNick()){
		$mask = $self->{mask};
	}else{
		$mask = "fake_mask";
	}

	my $player_opts = {
		nick=> $nick,
		BotDatabaseFile => $self->{BotDatabaseFile},
		keep_stats => $self->{keep_stats},
		store=>$self->{store},
		mask=>$mask,
		dig_freq_mins=>$self->{dig_freq_mins},
		next_digs => $self->{next_digs},
		already_dug_penalty => $self->{already_dug_penalty}
	};

	my $player = Player->new($player_opts);
	# this is for keepStats
	push @{$self->{keep_stats_collections}}, $player->{c};
	#push @{$self->{keep_stats_collections}}, $player->{next_digs_c};

	return $player;
}



##
##	Board Functions
##

sub getBoard{
	my $self = shift;
	my $output;

	$self->{board}->sort({field=>'val1', type=>'numeric', order=>'asc'});
	my @records = $self->{board}->getAllRecords();

	foreach my $rec (@records){
		if ($rec->{val3} ne ':0'){
			if ($rec->{val1} < 10 ){
				$output.="[X] ";
			}else{
				$output.="[XX] ";
			}
		}else{
			$output.="[$rec->{val1}] ";
		}
	}
	
	return $output;
}

sub board_plotsRemaining{
	my $self = shift;
	my @records = $self->{board}->matchRecords({val3=>':0'});
	my $plots_remaining = @records;
	return $plots_remaining
}

sub board_moneyRemaining{
	my $self = shift;
	my @records = $self->{board}->matchRecords({val3=>':0'});
	my $money_remaining;
	foreach my $rec (@records){
		if ($rec->{val4} eq 'money'){
			$money_remaining += $rec->{val2};
		}
	}
	return $money_remaining;
}

sub makeBoard{
	my $self = shift;

	#g|dig:board|1:num|2:contents|3:dug_by_nick or :0|4:content type (dirt, money, map)
	$self->{board} = $self->getCollection(__PACKAGE__, ':board');
	my @records = $self->{board}->matchRecords({val3=>':0'});

	return if (@records);
	
	# make a new board
	$self->{board}->deleteAllRecords();

	my $pennies = $self->{board_value} * 100;
	my $num_squares = int(($self->{percent_filled} / 100) * $self->{num_plots});
	my %splits;

	for (my $i=0; $i<$num_squares; $i++){
		my $split = int(rand($pennies));
		$splits{$split} = 1;
	}

	my $last = 0;
	my %contents;
	my @amounts;
	foreach my $x (sort {$a<=>$b} keys %splits){
		my $amount = sprintf("%.2f", ($x - $last)/100);
		$last = $x;
		push @amounts, $amount;
	}
	
	my @squares = (1 .. $self->{num_plots});
	my $i = @squares;
	while ( --$i ){
		my $j = int rand( $i+1 );
		@squares[$i,$j] = @squares[$j,$i];
	}
	@squares = @squares[0 .. (@amounts-1)];


	##
	##	Fill the board
	##

	$self->{board}->startBatch();
	my $count = 0;

	my $currency_type;
	if ($self->{store}->yi()){
		$currency_type = 'pound';
	}else{
		$currency_type = 'money';
	}

	for (my $i=1; $i<=$self->{num_plots}; $i++){
		if ($i ~~ @squares){
			$self->{board}->add($i, $amounts[$count++], ':0', $currency_type, 'currency');
		}else{

			if (int(rand(100)) == 4){
				$self->{board}->add($i, '5', ':0','map');
			}else{
				$self->{board}->add($i, "dirt", ':0','dirt');
			}
		}
	}
	$self->{board}->endBatch();


	##
	## Add Trinkets and Stocks to Board
	##
	
	while ($self->{num_trinkets}-- > 0){
		my @records = $self->{board}->matchRecords({val2=>'dirt'});
		my $rand = int ( rand (@records));

		my $item;
		if ($self->{use_stocks}){
			if (int(rand(3))){
				$item = $self->{store}->getTrinket(':random');
			}else{
				$item = $self->{store}->getStock(':random');
			}

		}else{
			$item = $self->{store}->getTrinket(':random');
		}
		$self->{board}->updateRecord($records[$rand]->{row_id}, {val2=>$item->{id}, val4=>$item->{type}, val5=>'' } );
	}


	##
	##	add danger.
	##

	# rock
	if (int(rand(3)) == 1){
		my @records = $self->{board}->matchRecords({val2=>'dirt'});
		my $rand = int ( rand (@records));
		$self->{board}->updateRecord($records[$rand]->{row_id}, {val2=>'pitfall', val4=>'rock', val5=>'' } );
	}

	# salt vein
	#if (int(rand(2)) == 1){
	#	my @records = $self->{board}->matchRecords({val2=>'dirt'});
	#	my $rand = int ( rand (@records));
	#	$self->{board}->updateRecord($records[$rand]->{row_id}, {val2=>'pitfall', val4=>'rock', val5=>'' } );
	#}

	##
	##	add weird currencies.
	##

	## add trilobite to 1 in x boards
	if (int(rand(4)) == 1){
		my @records = $self->{board}->matchRecords({val2=>'dirt'});
		my $rand = int ( rand (@records));
		$self->{board}->updateRecord($records[$rand]->{row_id}, {val2=>1, val4=>'trilobite', val5=>'currency' } );
	}

	## add a gold coin
	if (int(rand(3)) == 1){
		my @records = $self->{board}->matchRecords({val2=>'dirt'});
		my $rand = int ( rand (@records));
		$self->{board}->updateRecord($records[$rand]->{row_id}, {val2=>1, val4=>'goldcoin', val5=>'currency' } );
	}

	## save the board id so store can not sell water if player bought too many
	$self->{store}->globalCookie("board_id", time());
}


##
##	God
##
sub God{
	my $self = shift;
	my $output;

	if ($self->hasFlag("killboard")){
		# why are we getting the board again? xyzzy
		$self->{board} = $self->getCollection(__PACKAGE__, ':board');
		$self->{board}->deleteAllRecords();
		return "ok";
	}

	if ($self->hasFlag("give") || $self->hasFlag("take")){
		
		my $what = $self->hasFlagValue("what") || return "You need to use -what=<currency|thing>";
		my $who = $self->hasFlagValue("nick") || return "You need to use -nick=<nick>";
		my $quantity = $self->hasFlagValue("quantity") || return "You need to use -quantity=<#>";

		
		my $player = $self->loadPlayer($who);
		return "That player doesn't exist." if (!$player->exists());
		
		if ($what eq 'currency'){
			my $id = $self->hasFlagValue("id");
			my $c = Currency->new();
			my @types = $c->getAllTypes();

			if (!$id){
				$output = "You need to use -id=<currency_id>, where id is one of ";
				$output .= join ", ", @types;
				return $output ;
			}
			
			if (not $id ~~ @types){
				$output = "$id is not valid currency type. Valid types are ";
				$output .= join ", ", @types;
				return $output;
			}

			if ($self->hasFlag("take")){
				$quantity = -$quantity;
			}

			my $balance = $player->currency({type=>$id, increment=>$quantity, format=>1});
			return "$who now has $balance.";
		}
		
		if ($what eq 'thing' ){
			my $id = $self->hasFlagValue("id") || return "You need to use -id=<item_id>";
	
			my $type = $self->{store}->getThingType($id);
			if (!$type){
				return "I couldn't find that ID.";
			}

			my $thing;

			if ($type eq 'trinket'){
				$thing = $self->{store}->getTrinket($id);
			}elsif ($type eq 'stock'){
				$thing = $self->{store}->getStock($id);
			}elsif ($type eq 'item'){
				$thing = $self->{store}->getItem($id);
				my $cq = $quantity;
				if ($cq< 0){
					$cq = -$cq;
				}
				my ($ans, $reason) = $self->{player}->canOwn($thing, $cq);
				if (!$ans){
					#xyzzy this needs work
					#return $reason;
				}
			}

			my $new_num;

			if ($self->hasFlag("give")){
				$new_num = $player->addThing($thing, $quantity);
			}else{
				$new_num = $player->takeThing($thing, $quantity);
			}
			return "$who now has $new_num $thing->{name}.";
		}

	}

	if ($self->hasFlag("letdig")){
		my $who = $self->hasFlagValue("nick") || return "You need to use -nick=<nick>";
		my @records = $self->{next_digs}->matchRecords({val4=>$who});
		return "Who?" if (!@records);
		$self->{next_digs}->updateRecord($records[0]->{row_id}, {val2=>time()-1, val3=>'dig'});
		return "ok.";
	}
}


sub listeners{
   my $self = shift;

   my @commands = ['dig', 'inventory', 'store', 'leaders', 'crews', 'market' ];

   my $default_permissions =[  
		{command=>"dig",  flag=>'god', require_users => [ "$self->{BotOwnerNick}"] },
	];

   return {commands=>@commands, permissions=>$default_permissions};
}

sub settings{
	my $self = shift;

	$self->defineSetting({
		name=>'dig_channel',
		default=>'#dig!',
		allowed_values=>[],
		desc=>'It\'s a good (and fair) idea to restrict digging to a single channel. Define that channel here. This only restricts the "dig" command. Other commands will still work in other channels and via PM. '
	});
}

sub addHelp{
   my $self = shift;
   $self->addHelpItem("[plugin_description]", "You're a digger digging for treasure in the game of dig!.  Use  $self->{BotCommandPrefix}dig to see the open plots. Use $self->{BotCommandPrefix}dig <number> to dig a particular plot. As you dig, you'll acquire money, dirt, and trinkets. The trinkets can be sold for cash in the store using $self->{BotCommandPrefix}store -sell. The trinket market tends to fluctuate, so be sure to sell when the time is right. You may uncover various stock certificates along the way. Look these stocks up on your favorite financial site to determine the best time to sell. When you first start out, you won't be very good at digging. Purchase items from the dig! store to help you with your dig: $self->{BotCommandPrefix}store. The more equipment you purchase, the better you'll get at digging. Use $self->{BotCommandPrefix}inventory to see your inventory. Use $self->{BotCommandPrefix}leaders to see the current leaderboards. Join $self->{BotCommandPrefix}crews if you'd like. Good luck!");
   $self->addHelpItem("[dig]", "Dig for treasure.  Usage: dig <number>.  Use -bomb to use a bomb.");
   $self->addHelpItem("[dig][-god]", "Giveth and taketh. -killboard -nick=<nick> -give -take -what=<currency|thing> -quantity=<#num> -id=<id> -letdig");
   $self->addHelpItem("[inventory]", "See your dig inventory. Use -nick=<nick> to see someone else's inventory. Use -detail=<id> to get detail for one item. With -trinkets and -stocks, use -symbols to include symbols.  Use -status to see your current status.");
   $self->addHelpItem("[store]", "Buy items to help you dig. Use -sell=<item id> to sell an item. Use the -n=<number> flag to specify a quantity (optional).");
   $self->addHelpItem("[leaders]", "See the leaderboard. Flags: -money -dirt -digs -crews -gold -pounds -trilobites -whohas=<item_id>.");
   $self->addHelpItem("[crews]", "Join a diggin' crew.  -list to see current crews.  -list=<crew> to list members of a crew.  -join=<crew name> to join or start your own crew.");
   $self->addHelpItem("[market]", "The Dig Stock Market. -quote=<symbol> -buy=<symbol> -sell=<symbol> -n=<number>");
}

} #herein ends the plugins::Dig package

{
package Player;
use strict;
use warnings;
use Data::Dumper;
use POSIX;
use Text::ParseWords;
use DateTime;
use modules::Collection;
use constant Collection => 'modules::Collection';
use base qw (modules::PluginBaseClass);
use modules::PluginBaseClass;

my $BotDatabaseFile;
my $keep_stats;
my $dig_freq_mins;
my $already_dug_penalty;

my $c;
my $next_digs_c; # passed from Dig

my $store;	#obj

my $nick;
my $num_digs;
my $crew;

my $items;	#array
my $trinkets;	#array
my $stocks;		#array
my $currency_h;  #array

my $never_tired; 	#for testing
my $loaded;

sub new {
	my $class = shift;
	my $self = bless {}, $class;
	my $opts = shift;

	$self->{nick} = $opts->{nick};
	$self->{store} = $opts->{store};
	$self->{BotDatabaseFile} = $opts->{BotDatabaseFile};
	$self->{keep_stats} = $opts->{keep_stats};
	$self->{dig_freq_mins} = $opts->{dig_freq_mins};
	$self->{next_digs_c} = $opts->{next_digs};
	$self->{already_dug_penalty} = $opts->{already_dug_penalty};
	$self->{mask} = $opts->{mask};
	if ($self->{'mask'}=~/\@/){
		$self->{'mask'}= (split(/\@/, $self->{'mask'}))[1];
	}

	$self->{PackageShortName} = "Dig::Player";	#to make PBC:keepStats not bitch. xyzzy

	$self->load();
	return $self;
}

sub load {
	my $self = shift;
	$self->{loaded} = 0;
	$self->{num_digs} = 0;
	$self->{crew} = "";
	delete($self->{items});
	delete($self->{trinkets});
	delete($self->{stocks});
	delete($self->{c});
	delete($self->{currency_h});

	$self->{c} = $self->Collection->new({db_file=>$self->{BotDatabaseFile}, module_name=>'Dig',
         collection_name=>$self->{nick}, keep_stats=>$self->{keep_stats}});
	$self->{c}->load();

	my @records = $self->{c}->getAllRecords();
	foreach my $rec (@records){

		$self->{loaded} = 1;

		if ($rec->{val1} eq 'account'){
			$self->{'num_digs'} = $rec->{val3} if ($rec->{val2} eq 'num_digs');
			$self->{'crew'} = $rec->{val3} if ($rec->{val2} eq 'crew');

		}elsif($rec->{val1} eq 'currency'){
			my $o = Currency->new({id=>$rec->{val2}});
			$self->{currency_h}->{$rec->{val2}} =  {balance=>$rec->{val3}, o=>$o};

		}elsif($rec->{val1} eq 'item'){
			my $item = $self->{store}->getItem($rec->{val3});	
			my $thing = {
				id=>$rec->{val3},
				row_id=>$rec->{row_id},
				quantity=>$rec->{val2},
				basis=> $rec->{val4},
				item_info=>$item
			};
			push @{$self->{items}}, $thing;
		
		}elsif($rec->{val1} eq 'trinket'){
			my $item = $self->{store}->getTrinket($rec->{val3});	
			my $thing = {
				id=>$rec->{val3},
				row_id=>$rec->{row_id},
				quantity=>$rec->{val2},
				basis=> $rec->{val4},
				item_info=>$item
			};

			push @{$self->{trinkets}}, $thing;

		}elsif($rec->{val1} eq 'stock'){
			my $item = $self->{store}->getStock($rec->{val3});	
			my $thing = {
				id=>$rec->{val3},
				row_id=>$rec->{row_id},
				quantity=>$rec->{val2},
				basis=> $rec->{val4},
				item_info=>$item
			};
			push @{$self->{stocks}}, $thing;
		}
	}
}


sub tell{
	my $self = shift;
	my $what = shift;
	
	if (!defined($what)){
		my $tell = $self->cookie("tell");
		if ($tell){
			$self->cookie("tell", ':delete');
			return $tell;
		}

	}else{
	print "setting tell";
		my $tell = $self->cookie("tell");
		if ($tell){
			$what = $tell ." ".$self->BULLET." ".$what;
		}
		$self->cookie("tell", $what);
	}

	return 0;
}


##
##	"Cookies"
##

sub cookie{
	my $self = shift;
	my $key = shift;
	my $value = shift;

	my @records = $self->{c}->matchRecords({val1=>':cookies', val2=>$key});

	if (defined($value) && $value eq ':delete'){
		$self->{c}->delete($records[0]->{row_id});
		return;

	}elsif (defined($value)){
		if (@records){
			$self->{c}->updateRecord($records[0]->{row_id}, {val3=>$value});
		}else{
			$self->{c}->add(':cookies', $key, $value);
		}
		return $value;
	}

	if (defined ($records[0]->{val3})){
		return $records[0]->{val3};
	}else{
		return "";
	}
}


sub globalCookie{
	my $self = shift;
	my $key = shift;
	my $value = shift;

	my @records = $self->{next_digs_c}->matchRecords({val1=>':cookies', val2=>$key});

	if (defined($value) && $value eq ':delete'){
		$self->{c}->delete($records[0]->{row_id});
		return;

	}elsif (defined($value)){
		if (@records){
			$self->{next_digs_c}->updateRecord($records[0]->{row_id}, {val3=>$value});
		}else{
			$self->{next_digs_c}->add(':cookies', $key, $value);
		}
		return $value;
	}

	return $records[0]->{val3};
}


##
##	Batch mode for speed
##

sub startBatch{
	my $self = shift;
	$self->{c}->startBatch();
	$self->{next_digs_c}->startBatch();
}

sub endBatch{
	my $self = shift;
	$self->{c}->endBatch();
	$self->{next_digs_c}->endBatch();
}


##
##	Things
##

sub exists{
	my $self = shift;
	return ($self->{loaded});
}

## this changed.  now hasItem can handle items of any type.
sub hasItem{
	my $self = shift;
	my $id = shift;

	my $type = $self->{store}->getThingType($id);
	if ($type){
		return $self->hasThing($type . 's', $id);
	}else{
		return 0;
	}
}

#going bye bye
sub hasTrinket{
	my $self = shift;
	my $id = shift;
	return $self->hasThing('trinkets', $id);
}

#going bye bye
sub hasStock{
	my $self = shift;
	my $id = shift;
	return $self->hasThing('stocks', $id);
}

sub hasThing{
	my $self = shift;
	my $type = shift;
	my $id = shift;
	
	my $quantity = 0 ;
	foreach my $thing (@{$self->{$type}}){
		if (!$id){
			$quantity+=$thing->{quantity};

		}elsif ($thing->{id} eq $id){
			$quantity+=$thing->{quantity};
		}
	}

	return $quantity;
}

sub getItemByGroup{
	my $self = shift;
	my $group  = shift; 
	foreach my $item (@{$self->{items}}){
		if ($item->{item_info}->{group} eq $group){
			return $item;
		}
	}
	return 0;
}

sub listItems{
	my $self = shift;
	my $opts = shift;
	return $self->listThings('items', $opts);
}

sub listTrinkets{
	my $self = shift;
	my $opts = shift;
	return $self->listThings('trinkets', $opts);
}

sub listStocks{
	my $self = shift;
	my $opts = shift;
	return $self->listThings('stocks', $opts);
}


# opts:  exclude=[], quantity=>1, noone=>1 array=>1, price=>1, total=>1
sub listThings{
	my $self = shift;
	my $type = shift;
	my $opts = shift;

	my @ret_arr; #if requested
	my %list;
	
	## sum the things
	foreach my $thing (@{$self->{$type}}){
		if (!defined($list{$thing->{id}})){

			$list{$thing->{id}} =	
				{	name=>$thing->{item_info}->{name},
					current_value=>$thing->{item_info}->{current_value},
					quantity_arr=>[$thing->{quantity}],
					basis_arr => [$thing->{basis}],
					quantity =>$thing->{quantity},
					currency_o =>$thing->{item_info}->{currency_o},
					price_unit =>$thing->{item_info}->{price_unit},
				};
		}else{
			$list{$thing->{id}}->{quantity} += $thing->{quantity};
			push @{$list{$thing->{id}}->{quantity_arr}}, $thing->{quantity};
			push @{$list{$thing->{id}}->{basis_arr}}, $thing->{basis};
		}
	}


	## determine weighted average for basis
	foreach my $item(keys %list){
		my $num = 0;
		for (my $i=0; $i<@{$list{$item}->{quantity_arr}}; $i++){
			my $q = $list{$item}->{quantity_arr}[$i];
			my $b = $list{$item}->{basis_arr}[$i];
			$num+= ($q * $b);
		}
		$list{$item}->{basis} = sprintf("%.2f", $num / $list{$item}->{quantity});
		$self->{listThingsTotal} +=  $list{$item}->{current_value} * $list{$item}->{quantity};
	}

	# create output string
	foreach my $id (sort keys %list){
		if (defined($opts->{exclude})){
			next if ($id ~~ @{$opts->{exclude}});
		}

		my $gain=0;
		#print "Basis is $list{$id}->{basis}\n";
		if ($list{$id}->{basis} != 0){
			#print "$id gain is  $list{$id}->{current_value} - $list{$id}->{basis} ppoo\n";
			$gain = ($list{$id}->{current_value} - $list{$id}->{basis}) / $list{$id}->{basis} * 100;
		}

		$gain = sprintf("%.2f", $gain);
		if ($gain < 0){
			$gain = $gain.'%';
		}else{
			$gain = '+'.$gain.'%';
		}
	
		my $msg = "";
		if ($opts->{symbols}){
			$msg = "[$id] ";
		}

		if ($opts->{quantity}){
			if ($opts->{noone} && $list{$id}->{quantity} == 1){
				#dont add quantity
			}else{
 				$msg.= " $list{$id}->{quantity} ";
			}
			$msg .= $list{$id}->{name};
			if ($opts->{value}){
				my $item_tv = $list{$id}->{current_value} * $list{$id}->{quantity};
				$item_tv = $list{$id}->{currency_o}->format($item_tv);
				$msg.=" worth $item_tv";
				if ($list{$id}->{quantity} > 1){
					$msg.= ' ('.$list{$id}->{currency_o}->format($list{$id}->{current_value}).'/ea)';
				}
				$msg.=" ($gain)";
				#$list{$id}->{currency_o}->format($list{$id}->{current_value}) ." ($gain)";
			}

		
			$self->addToList($msg, $self->BULLET);
			push @ret_arr, $id;


		}else{
			$msg .= $list{$id}->{name};

		#	if ($opts->{value}){
		#		$msg.=" worth ". $list{$id}->{currency_o}->format($list{$id}->{current_value}) ." ($gain)";
		#	}

			if ($opts->{value}){
				my $item_tv = $list{$id}->{current_value} * $list{$id}->{quantity};
				$item_tv = $list{$id}->{currency_o}->format($item_tv);
				$msg.=" worth $item_tv";
				if ($list{$id}->{quantity} > 1){
					$msg.= ' ('.$list{$id}->{currency_o}->format($list{$id}->{current_value}).'/ea)';
				}
				$msg.=" ($gain)";
				#$list{$id}->{currency_o}->format($list{$id}->{current_value}) ." ($gain)";
			}
		
			$self->addToList($msg);
			push @ret_arr, $id;
		}
	}

	if ($opts->{array}){
		return @ret_arr;
	}else{
		my $listing = $self->getList();
		return $listing;
	}
}



sub thingDetail{
	my $self = shift;
	my $id= shift;
	my $output;
	return "You don't have anything called $id" if (!$self->hasItem($id));
	my $type = $self->{store}->getThingType($id) . 's';
	return "I don't know what $id is." if (!$type);

	# this is icky
	my $quantity=0;
	my $total = 0;
	my $numerator;
	my $current_value;
	my $current_value_f;
	my $name;
	my $currency_o;
	my $thing_o;

	foreach my $thing (@{$self->{$type}}){
		next if ($thing->{id} ne $id);
		$currency_o = $thing->{item_info}->{currency_o};
		$quantity+=$thing->{quantity};
		$numerator+= $thing->{quantity} * $thing->{basis};
		$total = $thing->{item_info}->{currency_o}->format(
			$quantity * $thing->{item_info}->{current_value}
		);
		$name=$thing->{item_info}->{name};
		$current_value_f=$thing->{item_info}->{currency_o}->format($thing->{item_info}->{current_value});
		$current_value=$thing->{item_info}->{current_value};
		$self->addToList($thing->{quantity} .' @ '.$thing->{basis} .'/ea', $self->BULLET);
		$thing_o = $thing;
	}
	
	if (defined($thing_o->{item_info}->{buyback_rate})){
		$current_value *= $thing_o->{item_info}->{buyback_rate};
		$current_value_f=$currency_o->format($current_value);
		$total = $currency_o->format($quantity * $current_value);
	}

	$output = "$self->{nick} has $quantity $name, worth a total of $total. Lots: ";
	$output.=$self->getList();
	my $avg = $numerator/$quantity;
	$output.=". The average acquisition cost was ";
	$output.= $currency_o->format($avg);
	$output.="/ea. Based on the current value of ";
	my $gain =  sprintf("%.2f", ($current_value - $avg)/$avg * 100);
	$output.="$current_value_f, the gain is $gain%";
}



sub addThing{
	my $self = shift;
	my $new_thing = shift;
	my $quantity = shift;
	my $price = shift || -1;


	if ($quantity < 1){
		return $self->takeThing($new_thing, -$quantity);
	}

	my $type = $new_thing->{type};

	if ($price == -1){
		$price = $new_thing->{price};
		if ($new_thing->{current_value}){
			$price = $new_thing->{current_value};
		}
	}

	$price = sprintf("%.2f", $price);

	my $found = 0;
	foreach my $thing (@{$self->{$type . 's'}}){
		if ($thing->{id} eq $new_thing->{id} && $price == $thing->{basis}){
			## We found the thing at the price, increment the counter
			$found = 1;
			$thing->{quantity} += $quantity;
			$self->{c}->updateRecord($thing->{row_id}, {val2=>$thing->{quantity}});
		}
	}

	if (!$found){

		$self->{c}->add($type, $quantity, $new_thing->{id}, $price, $new_thing->{group});
		my $entry = {
			id=>$new_thing->{id},
			quantity=>$quantity,
			basis=> $price,
			item_info=>$new_thing
		};

		push @{$self->{$type . 's'}}, $entry;

		# now that it's added, we need to remove any eclipsed items
		if ($new_thing->{type} eq 'item'){
			foreach my $i (@{$self->{items}}){
				#print "checking $i->{item_info}->{name}\n";
				if ($self->itemEclipsed($i->{item_info})){
					#print "taking $i->{item_info}->{name}\n";
					# hmm, can i do this while in the foreach?
					$self->takeThing($i->{item_info});
				}
			}
		}
		
	}

	return $self->hasThing($type .'s', $new_thing->{id});
}


sub takeThing{
	my $self = shift;
	my $new_thing = shift;
	my $quantity = shift || 1;
	my $sell_price = shift || 0;

	if ($quantity < 1){
		return $self->addThing($new_thing, -$quantity);
	}

	my $type = $new_thing->{type};
	return $self->hasThing($type .'s', $new_thing->{id}) if ($quantity == 0);

	my $profit = 0;
	my $found = 0;
	do{
		$found =0;
		foreach my $thing (@{$self->{$type . 's'}}){
			if ($thing->{id} eq $new_thing->{id}){
				$found = 1 if ($thing->{quantity});

				if ($thing->{quantity} > $quantity){
					$profit += ( $sell_price - $thing->{basis}) * $quantity;
					$thing->{quantity} -= $quantity;
					$quantity=0;
					$self->{c}->updateRecord($thing->{row_id}, {val2=>$thing->{quantity}});

				}elsif($thing->{quantity} == $quantity){
					$profit += ($sell_price - $thing->{basis}) * $quantity;
					$thing->{quantity} -= $quantity;
					$quantity=0;
					$self->{c}->delete($thing->{row_id});

				}else{
					$quantity = $quantity - $thing->{quantity};
					$thing->{quantity} = 0;
					$self->{c}->delete($thing->{row_id});
					$profit += ($sell_price - $thing->{basis}) * $thing->{quantity};
				}
			}
		}

	}while ($quantity>0 && $found);

	$self->{last_txn_profit} = $profit;
	return $self->hasThing($type .'s', $new_thing->{id});
}

sub getProfit{
	my $self = shift;
	return sprintf("%.2f", $self->{last_txn_profit} || 0);
}

##
##	account values getters & setters
##

sub currency{
	my $self = shift;
	my $opts = shift;
	my $type = $opts->{type};
	my $increment = $opts->{increment};
	
	if (!defined($self->{currency_h}->{$type})){
		my $o = Currency->new({id=>$type});
		$self->{currency_h}->{$type} =  {balance=>0, o=>$o};
	}

	my $o = $self->{currency_h}->{$type};

	if ($increment){
		$o->{balance} += $increment;

		my @records = $self->{c}->matchRecords({val1=>'currency', val2=>$type});

		if (!@records){
			$self->{c}->add('currency', $type, $increment);
		}else{
			my $val = $o->{balance};
			$self->{c}->updateRecord($records[0]->{row_id}, {val3=>$val });
		}

		if ( ($o->{balance} == 0) && (($type ne 'money') && ($type ne 'dirt')) ){
			$self->{c}->delete($records[0]->{row_id});
		}
	}

	if ($opts->{format}){
		return $o->{o}->format($o->{balance});
	}else{
		return $o->{balance};
	}
}

sub listCurrency{
	my $self = shift;
	my $list;

	my $num = keys %{$self->{currency_h}};

	# money first
	$list = $self->currency({format=>1, type=>'money'});

	my $count = 0;
	foreach my $type (keys %{$self->{currency_h}}){	
		next if ($type eq  'money');

		if (($num-2) == $count){
			$list.=", and ";
		}else{
			$list .= ", " if ($num != 2);
		}
		$list .= $self->currency({format=>1, type=>$type});
		$count++;
	}
	return $list;
}

sub money_f{
	my $self = shift;
	my $increment = shift;
	return $self->currency({type=>'money', increment=>$increment, format=>1});
}

sub money{
	my $self = shift;
	my $increment = shift;
	return $self->currency({type=>'money', increment=>$increment});
}

sub dirt_f{
	my $self = shift;
	my $increment = shift;
	return $self->currency({type=>'dirt', increment=>$increment, format=>1});
}

sub dirt{
	my $self = shift;
	my $increment = shift;
	return $self->currency({type=>'dirt', increment=>$increment});
}


sub digs{
	my $self = shift;
	my $increment = shift;

	if ($increment){
		$self->{num_digs} += $increment;
	
		my @records = $self->{c}->matchRecords({val1=>'account', val2=>'num_digs'});

		if (!@records){
			$self->{c}->add('account', 'num_digs', $increment);
		}else{
			#my $val = $records[0]->{val3} + $increment;
			my $val = $self->{num_digs};
			$self->{c}->updateRecord($records[0]->{row_id}, {val3=>$val });
		}
	}

	return $self->{num_digs};
}


sub getCrew{
	my $self = shift;
	if ($self->{crew}){
		return $self->{crew};
	}else{
		return "unaffiliated";
	}
}

sub crew{
	my $self = shift;
	my $crew = shift;

	if ($crew && $crew eq ':delete'){
		$self->{crew} = "";
		my @records = $self->{c}->matchRecords({val1=>'account', val2=>'crew'});
		if (@records){
			$self->{c}->delete($records[0]->{row_id});
		}
		return "";
	}


	if ($crew){
		$self->{crew} = $crew;
	
		my @records = $self->{c}->matchRecords({val1=>'account', val2=>'crew'});

		if (!@records){
			$self->{c}->add('account', 'crew', $crew);
		}else{
			$self->{c}->updateRecord($records[0]->{row_id}, {val3=>$crew});
		}
	}

	return $self->{crew};
}


sub getNetWorth{
	my $self = shift;
	my $worth = $self->digs() *.10;

	foreach my $c (keys $self->{currency_h}){
		$worth += $self->{currency_h}->{$c}->{balance} * $self->{currency_h}->{$c}->{o}->{conversion_rate};
	}

	my @arrs = ('items', 'trinkets', 'stocks');
	foreach my $a (@arrs){
		foreach my $thing (@{$self->{$a}}){
			my $price = $thing->{item_info}->{current_value} * $thing->{quantity} * $thing->{item_info}->{currency_o}->{conversion_rate};
			if ($thing->{item_info}->{buyback_rate}){
				$price = $price * $thing->{item_info}->{buyback_rate};
			}
			$worth += $price;
			#print "$worth ($price)\n";
			#if ($thing->{id} eq 'bomb'){
			#	print Dumper ($thing);
			#}
		}
	}
	return sprintf("%.2f", $worth);
}

sub canDig{
	my $self = shift;

	my @records = $self->{next_digs_c}->matchRecords({val1=>$self->{mask}});

	return {answer=>1, when=>''} if (!@records);
	
	return {answer=>1, when=>''}  if ($records[0]->{val2} < time());

	my $when = ceil(($records[0]->{val2} - time()) / 60);
	my $when_time = $records[0]->{val2};
	return {answer=>0, when=>$when, why=>$records[0]->{val3}, when_time=>$when_time};
}


sub determineNextDigTime{
	my $self = shift;
	my $reason = shift;
	my $done = 0;

	my @records = $self->{next_digs_c}->matchRecords({val1=>$self->{mask}});
	my $next_dig_time = time();

	if ($reason eq 'dig'){
		my $range = 2;

		$range++ if ($self->hasItem("gloves"));
		$range++ if ($self->hasItem("visor"));

		print "Dig Range is $range\n";

		if (int(rand($range)) == 1){
			if ($self->hasItem("kneepads")){
				$next_dig_time = time() + ($self->{dig_freq_mins} * 60 / 1.5 );

			}elsif ($self->hasItem("beesknees")){
				$next_dig_time = time() + ($self->{dig_freq_mins} * 60 / 2 );

			}else{
				$next_dig_time = time() + ($self->{dig_freq_mins} * 60);
			}

			$done = 1;
		}

		# new people dig free
		if ($self->{num_digs} < 5){
			$next_dig_time = time();
			$done = 0;
		}

	}elsif ($reason eq 'bomb'){

		if ($self->hasItem("swiffer")){
			$next_dig_time = time() + ($self->{dig_freq_mins} * 60 / 3 );
		}else{
			$next_dig_time = time() + ($self->{dig_freq_mins} * 60 / 1.5 );
		}
		$done = 1;

	}elsif ($reason eq 'already_dug'){
		$next_dig_time = time() + $self->{already_dug_penalty};
		$done = 1;

	}elsif ($reason eq 'bathroom'){
		$next_dig_time = time() + (60 * 20);
		$done = 1;
	}

	if ($self->{never_tired}){
		$next_dig_time = time();
		$done = 0;
	}

	if ($done){
		$self->cookie("dig_streak", 0);
	}else{
		my $s = $self->cookie("dig_streak") || 0;
		$self->cookie("dig_streak", $s + 1);
	}

	print "streak is " . $self->cookie("dig_streak") . "\n";
	if (!@records){
		$self->{next_digs_c}->add($self->{mask}, $next_dig_time, $reason,  $self->{nick});
	}else{
		$self->{next_digs_c}->updateRecord($records[0]->{row_id}, {val2=>$next_dig_time, val3=>$reason,  val4=>$self->{nick}});
	}

	return $done;
}

sub canOwn{
	my $self = shift;
	my $item = shift;
	my $quantity = shift;

	# check if already owns a greater item
	my ($ans, $reason) = $self->itemEclipsed($item);
	if ($ans){
		return (0, "You can't own $item->{name} because you already own $reason.");
	}

	#check if trying to own too many
	if (defined($item->{can_own_max})){
		if ($quantity > $item->{can_own_max}){
			return (0, "You can't own more than $item->{can_own_max} $item->{name}.");
		}
		
		if ( $item->{can_own_max} <  ($self->hasItem($item->{id}) + $quantity)){
			return (0, "You can't own more than $item->{can_own_max} $item->{name}.");
		}
	}

	#check if has the pre-requisite item
	my $ok = 0;
	if ($item->{group_level} > 1){
		foreach my $i (@{$self->{items}}){
			if ($i->{item_info}->{group} eq $item->{group}){
				if($i->{item_info}->{group_level} == ($item->{group_level} - 1)){
					$ok = 1;
				}
			}
		}
	}else{
		$ok = 1;
	}

	if (!$ok){
		my $preq = $self->{store}->getItemByGroupLevel($item->{group}, $item->{group_level}-1);
		return (0, "You have to own $preq->{name} before you can own $item->{name}.");
	}

	return (1, "sure");

}

sub waterRemaining{
	my $self = shift;
	my $board_id = $self->{store}->globalCookie("board_id") || 0;

	if ($self->cookie("water_board_id") ne $board_id){
		$self->cookie("water_board_id", $board_id);
		$self->cookie("water_purchased", 0);
	}

	my $water_purchased = $self->cookie("water_purchased") || 0;
	my $max_waters = 4;
	my $item = ($self->getItemByGroup("potty"));
	if ($item){
		$max_waters = $item->{item_info}->{attributes}->{num_waters};
	}
	my $water_remaining = $max_waters - $water_purchased;

	return ($water_remaining, $max_waters);
}


sub itemEclipsed{
	my $self = shift;
	my $item = shift;

	my $group = $item->{group};
	my $group_level = $item->{group_level};

	foreach my $i (@{$self->{items}}){
		# note this dies when item is not defined xyzzy
		if ( ($i->{item_info}->{group} eq $group)  && ($i->{item_info}->{group_level} > $group_level)){
			return (1, $i->{item_info}->{name});
		}
	}

	return (0, "");
}


}	#herein ends the User package

#############################################################################
#############################################################################
#############################################################################


{
package Store;
use strict;
use warnings;
use Data::Dumper;
use POSIX;
use Text::ParseWords;
use DateTime;
use modules::Collection;
use constant Collection => 'modules::Collection';
use base qw (modules::PluginBaseClass);
use modules::PluginBaseClass;

my $BotDatabaseFile;
my $keep_stats;

my $fuzz_interval;
my $use_stocks;
my $stock_list;
my $stock_update_freq;

my $stock_c;	#collection
my $fuzz_c;	#collection
my $bazaar_c;	#collection
my $next_digs_c;

my $items; 		#array
my $trinkets;	#array
my $stocks;		#array

use constant{
	DICE_1 => "\x{2680}",
	DICE_2 => "\x{2681}",
	DICE_3 => "\x{2682}",
	DICE_4 => "\x{2683}",
	DICE_5 => "\x{2684}",
	DICE_6 => "\x{2685}",
	TRADEMARK=> "\x{00AE}",
};

sub new {
	my $class = shift;
	my $self = bless {}, $class;
	my $opts = shift;

	$self->{stock_list} = $opts->{stock_list};
	$self->{use_stocks} = $opts->{use_stocks};
	$self->{stock_update_freq} = $opts->{stock_update_freq};
	$self->{BotDatabaseFile} = $opts->{BotDatabaseFile};
	$self->{keep_stats} = $opts->{keep_stats};
	$self->{fuzz_interval} = $opts->{fuzz_interval};
	$self->{next_digs_c} = $opts->{next_digs_c};

	$self->{PackageShortName} = "Dig::Store";	#to make PBC:keepStats not bitch.
	$self->load();
	return $self;
}


sub globalCookie{
	my $self = shift;
	my $key = shift;
	my $value = shift;

	my @records = $self->{next_digs_c}->matchRecords({val1=>':cookies', val2=>$key});

	if (defined($value) && $value eq ':delete'){
		$self->{c}->delete($records[0]->{row_id});
		return;

	}elsif (defined($value)){
		if (@records){
			$self->{next_digs_c}->updateRecord($records[0]->{row_id}, {val3=>$value});
		}else{
			$self->{next_digs_c}->add(':cookies', $key, $value);
		}
		return $value;
	}

	return $records[0]->{val3};
}


##
##	Getting things
##

sub getThingType{
	my $self = shift;
	my $id = shift;

	foreach my $thing (@{$self->{items}}){
		return 'item' if ($thing->{id} eq $id);
	}

	foreach my $thing (@{$self->{trinkets}}){
		return 'trinket' if ($thing->{id} eq $id);
	}

	foreach my $thing (@{$self->{stocks}}){
		return 'stock' if ($thing->{id} eq $id);
	}

	return 0;
}

sub getItemByGroupLevel{
	my $self = shift;
	my $group = shift;
	my $group_level = shift;

	foreach my $i (@{$self->{items}}){
		if (($i->{group} eq $group) && ($i->{group_level} eq $group_level)){
			return $i;
		}
	}

	return undef;
}


sub getItem{
	my $self = shift;
	my $id = shift;

	my $type = $self->getThingType($id);
	if ($type){
		my $item = $self->getThing($type .'s', $id);
		return $item;
	}else{
		return 0;
	}
}

sub getTrinket{
	my $self = shift;
	my $id = shift;
	my $item = $self->getThing('trinkets', $id);
	return $item;
}

sub getStock{
	my $self = shift;
	my $id = shift;
	my $item = $self->getThing('stocks', $id);
	return $item;
}

sub getThing{
	my $self = shift;
	my $type = shift;
	my $id = shift;

	my $thing;

	if ($id eq ':random'){
		my $level = 0;
		my $rand;
		my $counter = 0;

		# get a level
		do{
			$counter++;
			$rand = int(rand(2));

			$level = $counter if ($rand < 1);
			$level = 10 if ($counter == 10);

		}while (!$level);
	

		# get an item from that level, but if no items exist, $level--
		my @set;
		my $done = 0;
		do{
			foreach my $thing (@{$self->{$type}}){
				if ($thing->{rarity_level} == $level){
					if ($thing->{group} ne 'user_stock'){
						push @set, $thing;
					}
				}
			}

			if (@set){
				$done = 1;
			}else{
				$level--;
			}

			if ($level == 1){
				$done = 1;
			}

		}while (!$done);

		if (@set){
			$thing =  $set[int(rand(@set))];
		}else{
			print "Dig: Warning: No items found in rarity level, trying to return random item.";
			print " This shouldnt happen.\n";
			@set = @{$self->{$type}};
			$thing =  $set[int(rand(@set))];
		}

	}else{
		foreach my $t(@{$self->{$type}}){
			if ($t->{id} eq $id){
				$thing = $t;
				last;
			}
		}
	}

	if ($thing){
		$thing->{currency_o} = Currency->new({id=>$thing->{price_unit}});
		if ($thing->{type} eq 'trinket' && $thing->{currency_o}->{fuzz}){
			$thing->{current_value} = 
				sprintf("%.2f", $thing->{price} * $self->fuzz($thing->{rarity_level}));
		}else{
			$thing->{current_value} = sprintf("%.2f", $thing->{price});
		}
		return $thing;
	}else{

		my $ret=	{  type => $type,
				id => $id,
				not_found => 1,
				name => '??Unknown Item '.$id.' ??',
				desc=> '??Unknown Item '.$id.' ??',
				price => '0',
				price_unit => 'money',
				rarity_level => '10',
				group => 'none',
				group_level => '1',
				current_value=>0
		};
		$ret->{currency_o} = Currency->new({id=>'money'});

		return $ret;
	}
}

sub load {
	my $self = shift;

	my @items = (
	{	type => 'item',
		id	=> 'water',
		name => 'water',
		desc => 'Cut your current dig recovery time in half. (One time immediate use).',
		price => .20,
		price_unit => 'money',
		rarity_level => '1',
		group	=> 'necessity',
		always_sell => 1,
		always_buy => 0,
		group_level => '1',
		can_own_max => 99,
		buyback_rate => '1',
		dont_buyback => '1',
		for_sale => 1
	},
	
	{	type => 'item',
		id	=> 'bomb',
		name => 'da bomb',
		desc => 'Blow up 5 spots in a single turn. (One time use.) To use da bomb, use "dig <#number> -bomb".',
		price => 1,
		price_unit => 'money',
		rarity_level => '1',
		group	=> 'necessity',
		group_level => '1',
		always_sell => 1,
		always_buy => 1,
		buyback_rate => '.75',
		can_own_max => 50,
		for_sale => 1

	},
	
	{	type => 'item',
		id	=> 'lottery',
		name => 'lottery ticket',
		desc => 'Win up to $10 with a scratch-off lottery ticket.',
		price => '30',
		price_unit => 'dirt',
		rarity_level => '1',
		group	=> 'necessity',
		always_sell => 1,
		group_level => '1',
		for_sale => 1
	},
	
	{	type => 'item',
		id	=> 'kneepads',
		name => 'kneepads',
		desc => 'Allows you to recover from digging more quickly',
		price => '10',
		price_unit => 'money',
		rarity_level => '1',
		group	=> 'recovery',
		group_level => '1',
		buyback_rate => '.75',
		dont_buyback => '1',
		can_own_max => 1,
		for_sale => 1
	},
	
	{	type => 'item',
		id	=> 'beesknees',
		name => 'fancy kneepads',
		desc => 'Allows you to recover from digging more quickly.  This is an upgrade from regular kneepads, so you have to own those before you can buy these.',
		price => '24',
		price_unit => 'money',
		rarity_level => '1',
		group	=> 'recovery',
		group_level => '2',
		buyback_rate => '.75',
		dont_buyback => '1',
		can_own_max => 1,
		for_sale => 1
	},
	
	{	type => 'item',
		id	=> 'gloves',
		name => 'diggin\' gloves',
		desc => 'Allows you to dig longer before getting tired',
		price => '25',
		price_unit => 'money',
		rarity_level => '1',
		group	=> 'longer',
		group_level => '1',
		buyback_rate => '.75',
		dont_buyback => '1',
		can_own_max => 1,
		for_sale => 1
	},
	
	{	type => 'item',
		id	=> 'swiffer',
		name => 'swiffer',
		desc => 'Clean up bomb debris in half the time',
		price => '30',
		price_unit => 'money',
		rarity_level => '1',
		group	=> 'none',
		group_level => '1',
		buyback_rate => '.75',
		dont_buyback => '1',
		can_own_max => 1,
		for_sale => 1
	},

	{	type => 'item',
		id	=> 'bifocals',
		name => 'bifocals',
		desc => 'You\'re seeing double!  Recover twice as many trinkets per plot.',
		price => '10',
		price_unit => 'trilobite',
		rarity_level => '1',
		group	=> 'none',
		group_level => '1',
		buyback_rate => '.75',
		dont_buyback => '1',
		can_own_max => 1,
		for_sale => 1
	},

	{	type => 'item',
		id	=> 'visor',
		name => 'sweet visor',
		desc => 'Allows you to dig longer before getting tired',
		price => '40',
		price_unit => 'money',
		rarity_level => '1',
		group	=> 'longer',
		group_level => '1',
		buyback_rate => '.75',
		dont_buyback => '1',
		can_own_max => 1,
		for_sale => 1
	},

	{	type => 'item',
		id	=> 'portapotty',
		name => 'small porta-potty',
		desc => 'Allows you to do your business on the dig site, so you can purchase up to 8 waters per board. ',
		price => '200',
		price_unit => 'money',
		rarity_level => '1',
		group	=> 'potty',
		group_level => '1',
		buyback_rate => '.75',
		dont_buyback => '1',
		can_own_max => 1,
		for_sale => 1,
		attributes => { num_waters => 8}
		
	},
	
	{	type => 'item',
		id	=> 'shovel',
		name => 'shovel',
		desc => 'Dig deeper, earning you more money per 2urn.',
		price => '60',
		price_unit => 'money',
		rarity_level => '1',
		group	=> 'shovel',
		group_level => '1',
		buyback_rate => '.75',
		dont_buyback => '1',
		can_own_max => 1,
		for_sale => 1,
		attributes => { money_multiplier=> 2}
	},

	{	type => 'item',
		id	=> 'knapsack',
		name => 'knapsack',
		desc => 'Carry more dirt away from the dig site 2 your stash with this stylin\' knapsack.',
		price => '3',
		price_unit => 'trilobite',
		rarity_level => '1',
		group	=> 'sack',
		group_level => '1',
		buyback_rate => '.75',
		dont_buyback => '1',
		can_own_max => 1,
		for_sale => 1,
		attributes => { dirt_multiplier=> 2}
	},
	
	{	type => 'item',
		id	=> 'ducttape',
		name => 'Neverending Duct Tape',
		desc => 'Wrap your bomb in duct tape 2 make it more powerful, uncovering more money per plot. You never run out of Neverending Duct Tape, it\'s never-ending.',
		price => '150',
		price_unit => 'money',
		rarity_level => '1',
		group	=> 'bomb_tool',
		group_level => '1',
		buyback_rate => '.75',
		dont_buyback => '1',
		can_own_max => 1,
		for_sale => 1,
		attributes => { money_multiplier=> 2}
	},

	{	type => 'item',
		id	=> 'agggs',
		name => 'silver shovel',
		desc => 'Dig ev3n deeper, earning you even more money per turn.',
		price => '167',
		price_unit => 'money',
		rarity_level => '1',
		group	=> 'shovel',
		group_level => '2',
		buyback_rate => '.75',
		dont_buyback => '1',
		can_own_max => 1,
		for_sale => 1,
		attributes => { money_multiplier=> 3}
	},
	
	{	type => 'item',
		id	=> 'blings',
		name => 'blinged out shovel',
		desc => 'Dig yet 4eeper, earning you yet more money per turn.',
		price => '433',
		price_unit => 'money',
		rarity_level => '1',
		group	=> 'shovel',
		group_level => '3',
		buyback_rate => '.75',
		dont_buyback => '1',
		can_own_max => 1,
		for_sale => 1,
		attributes => { money_multiplier=> 4}
	},

	{	type => 'item',
		id	=> 'wd40',
		name => 'Bottomless WD-40',
		desc => 'Apply WD-40 to your bombs and make them more powerful, earning you more money per plot.  Having no bottom, this can of WD-40 will n3ver run dry.',
		price => '450',
		price_unit => 'money',
		rarity_level => '1',
		group	=> 'bomb_tool',
		group_level => '2',
		buyback_rate => '.75',
		dont_buyback => '1',
		can_own_max => 1,
		for_sale => 1,
		attributes => { money_multiplier=> 3}
	},
	{	type => 'item',
		id	=> 'auyeahs',
		name => 'gold plated shovel',
		desc => 'Dig still deeper, earning you 5till more money per turn.',
		price => '881',
		price_unit => 'money',
		rarity_level => '1',
		group	=> 'shovel',
		group_level => '4',
		buyback_rate => '.75',
		dont_buyback => '1',
		can_own_max => 1,
		for_sale => 1,
		attributes => { money_multiplier=> 5}
	} ,

	{	type => 'item',
		id	=> 'platys',
		name => 'platinum shovel',
		desc => 'Dig way deeper, earning you way more money pe7 turn.',
		price => '1781',
		price_unit => 'money',
		rarity_level => '1',
		group	=> 'shovel',
		group_level => '5',
		buyback_rate => '.75',
		dont_buyback => '1',
		can_own_max => 1,
		for_sale => 1,
		attributes => { money_multiplier=> 7}
	},

	{	type => 'item',
		id	=> 'gassys',
		name => 'gasoline powered shovel',
		desc => 'Dig hella deeper, earnin9 you hella more money per turn.',
		price => '20',
		price_unit => 'goldcoin',
		rarity_level => '1',
		group	=> 'shovel',
		group_level => '6',
		buyback_rate => '.75',
		dont_buyback => '1',
		can_own_max => 1,
		for_sale => 1,
		attributes => { money_multiplier=> 9}
	},

	{	type => 'item',
		id	=> 'chank',
		name => 'diesel powered shovel',
		desc => 'Dig hella deeper, earning you he11a more money per turn.',
		price => '30',
		price_unit => 'goldcoin',
		rarity_level => '1',
		group	=> 'shovel',
		group_level => '7',
		buyback_rate => '.75',
		dont_buyback => '1',
		can_own_max => 1,
		for_sale => 1,
		attributes => { money_multiplier=> 11}
	},

	{	type => 'latys',
		id	=> 'latys',
		name => 'latinum shovel',
		desc => 'Dig entirely deeper, earning you ent1r3ly more money per turn.',
		price => '1',
		price_unit => 'latinum',
		rarity_level => '1',
		group	=> 'shovel',
		group_level => '8',
		buyback_rate => '.75',
		dont_buyback => '1',
		can_own_max => 1,
		for_sale => 1,
		attributes => { money_multiplier=> 13}
	},

	{	type => 'item',
		id	=> 'gaiwiio',
		name => 'gaiwiio shovel',
		desc => 'For mag1cal digging5.',
		price => '1',
		price_unit => 'wampum',
		rarity_level => '1',
		group	=> 'shovel',
		group_level => '9',
		buyback_rate => '.75',
		dont_buyback => '1',
		can_own_max => 1,
		for_sale => 1,
		attributes => { money_multiplier=> 15}
	},

	{	type => 'item',
		id	=> 'marketinternship',
		name => 'Stock Market Internship',
		desc => 'Gain access to the dig stock market. This is a one-time internship fee. As an intern, you can perform one trade per day. You need a stock trader license to perform unlimited trades.',
		price => '500',
		price_unit => 'money',
		rarity_level => '1',
		group	=> 'stocktrader',
		group_level => '1',
		buyback_rate => '1',
		dont_buyback => '1',
		can_own_max => 1,
		for_sale => 1
	},

	{	type => 'item',
		id	=> 'traderlicense',
		name => 'Stock Trader License',
		desc => 'Perform unlimited trades in the dig! stock market. The transaction fee for selling in the dig! stock market is 9%, unless you\'re a Dig\'s Insdider.',
		price => '5',
		price_unit => 'goldcoin',
		rarity_level => '1',
		group	=> 'stocktrader',
		group_level => '2',
		buyback_rate => '1',
		dont_buyback => '1',
		can_own_max => 1,
		for_sale => 1
	},
	{	type => 'item',
		id	=> 'luckyrabbit',
		name => 'Lucky Rabbit\'s Foot',
		desc => 'Lucky you, you get to double your lottery winnings each time you play.',
		price => '8',
		price_unit => 'trilobite',
		rarity_level => '1',
		group	=> 'lucky',
		group_level => '1',
		buyback_rate => '.50',
		dont_buyback => '1',
		can_own_max => 1,
		for_sale => 1,
		attributes => { money_multiplier=> 2}
	},


	{	type => 'item',
		id	=> 'digsinsider',
		name => 'Dig\'s Insider Card',
		desc => 'Save 10% on purchases in the dig! store, and pay only a 1% transaction fee on dig! stock market trades.',
		price => '1000',
		price_unit => 'dirt',
		rarity_level => '1',
		group	=> 'none',
		group_level => '1',
		buyback_rate => '1',
		dont_buyback => '1',
		can_own_max => 1,
		for_sale => 1
	},

	{	type => 'item',
		id	=> 'dirtdice',
		name => 'Dirt Dice',
		desc => 'Roll a pair of dice.  Whatever the total, you win that many piles of dirt. ',
		price => '7',
		price_unit => 'dirt',
		rarity_level => '1',
		group	=> 'casino',
		group_level => '1',
		for_sale => 1
	},

	{	type => 'item',
		id	=> 'sevens',
		name => 'Sevens',
		desc => 'Roll a pair of dice. If you roll a 7, win 42 piles of dirt. ',
		price => '7',
		price_unit => 'dirt',
		rarity_level => '1',
		group	=> 'casino',
		group_level => '1',
		for_sale => 1
	},

	{	type => 'item',
		id	=> 'dirtraffle',
		name => 'Dig Dirt Raffle',
		desc => 'Buy a ticket in the dig! Dirt Raffle and win 100 piles of dirt. Winner will be determined when all tickets are sold.',
		price => '10',
		price_unit => 'dirt',
		rarity_level => '1',
		group	=> 'casino',
		group_level => '1',
		for_sale => 1
	},

	{	type => 'item',
		id	=> 'hrdirtraffle',
		name => 'High Roller Dirt Raffle',
		desc => 'Buy a ticket in the dig! High Roller Dirt Raffle and win 1000 piles of dirt. Winner will be determined when all tickets are sold.',
		price => '100',
		price_unit => 'dirt',
		rarity_level => '1',
		group	=> 'casino',
		group_level => '1',
		for_sale => 1
	},

	{	type => 'item',
		id	=> 'biggamble',
		name => 'The Big Gamble',
		desc => 'Risk all your $cash in a game of chance. Roll a single die. 4, 5, or 6 - double your money. 3 - no change.  1, 2 = you lose it all.',
		price => '200',
		price_unit => 'dirt',
		rarity_level => '1',
		group	=> 'casino',
		group_level => '1',
		for_sale => 1
	}
	);

	my @trinkets = (
	
	{	type => 'trinket',
		id	=> 'sundrop',
		name => 'a Sundrop bottle cap',
		desc => 'a Sundrop bottle cap',
		price => '.43',
		price_unit => 'money',
		rarity_level => '1',
		group	=> 'bottle cap',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'dry',
		name => 'a Diet Canada Dry bottle cap',
		desc => 'a Diet Canada Dry bottle cap',
		price => '.29',
		price_unit => 'money',
		rarity_level => '1',
		group	=> 'bottle cap',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'nehi',
		name => 'a Nehi bottle cap',
		desc => 'a Nehi bottle cap',
		price => '.14',
		price_unit => 'money',
		rarity_level => '1',
		group	=> 'bottle cap',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'ketchup',
		name => 'a packet of McDonald\'s Ketchup',
		desc => 'a packet of McDonald\'s Ketchup',
		price => '.03',
		price_unit => 'money',
		rarity_level => '1',
		group	=> '',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'ike',
		name => 'an "I Like Ike" campaign pin',
		desc => 'an "I Like Ike" campaign pin',
		price => '.75',
		price_unit => 'money',
		rarity_level => '1',
		group	=> '',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'car',
		name => 'an Old Matchbox car',
		desc => 'an Old Matchbox car',
		price => '1.89',
		price_unit => 'money',
		rarity_level => '1',
		group	=> '',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'acorn',
		name => 'an acorn',
		desc => 'an acorn',
		price => '.03',
		price_unit => 'money',
		rarity_level => '1',
		group	=> '',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'rock',
		name => 'a cool looking rock',
		desc => 'a cool looking rock',
		price => '.42',
		price_unit => 'money',
		rarity_level => '1',
		group	=> '',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'aol',
		name => 'an AOL CD containing 750 Free hours of internet',
		desc => 'an AOL CD containing 750 Free hours of internet',
		price => '.15',
		price_unit => 'money',
		rarity_level => '1',
		group	=> '',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'tract',
		name => 'a faded Chick tract',
		desc => 'a faded Chick tract',
		price => '.39',
		price_unit => 'money',
		rarity_level => '1',
		group	=> '',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'worm',
		name => 'a worm',
		desc => 'a worm',
		price => '.06',
		price_unit => 'money',
		rarity_level => '1',
		group	=> '',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'peep',
		name => 'a stale Peep',
		desc => 'a stale Peep',
		price => '.05',
		price_unit => 'money',
		rarity_level => '1',
		group	=> '',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'friends',
		name => 'a friendship bracelet',
		desc => 'a friendship bracelet',
		price => '.99',
		price_unit => 'money',
		rarity_level => '1',
		group	=> '',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'garbage',
		name => 'a Garbage Pail Kids card',
		desc => 'a Garbage Pail Kids card',
		price => '.69',
		price_unit => 'money',
		rarity_level => '1',
		group	=> '',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'outrageous',
		name => 'a Jem and the Holograms hologram',
		desc => 'a Jem and the Holograms hologram',
		price => '1.89',
		price_unit => 'money',
		rarity_level => '1',
		group	=> '',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'slap',
		name => 'a slap bracelet',
		desc => 'a slap bracelet',
		price => '1.20',
		price_unit => 'money',
		rarity_level => '1',
		group	=> '',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'jack',
		name => 'a box of Crackerjack',
		desc => 'a box of Crackerjack',
		price => '.79',
		price_unit => 'money',
		rarity_level => '1',
		group	=> 'food',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'ship',
		name => 'a Monopoly token',
		desc => 'a Monopoly token',
		price => '.55',
		price_unit => 'money',
		rarity_level => '1',
		group	=> 'none',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'snoop',
		name => 'an autographed photo of Snoop Dogg',
		desc => 'an autographed photo of Snoop Dogg',
		price => '1.05',
		price_unit => 'money',
		rarity_level => '1',
		group	=> 'none',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'ugly',
		name => 'a macrame wall hanging',
		desc => 'a macrame wall hanging',
		price => '.60',
		price_unit => 'money',
		rarity_level => '1',
		group	=> 'none',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'mm',
		name => 'a Mickey Mouse figurine',
		desc => 'a Mickey Mouse figurine',
		price => '.30',
		price_unit => 'money',
		rarity_level => '1',
		group	=> 'none',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'forevergob',
		name => 'a box of Everlasting Gobstoppers',
		desc => 'a box of Everlasting Gobstoppers',
		price => '2.30',
		price_unit => 'money',
		rarity_level => '1',
		group	=> 'none',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'aaah',
		name => 'a can of Crystal Pepsi',
		desc => 'a can of Crystal Pepsi',
		price => '2',
		price_unit => 'money',
		rarity_level => '1',
		group	=> 'none',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'cockadoodledoo',
		name => 'a Dirt album by Alice in Chains',
		desc => 'a Dirt album by Alice in Chains',
		price => '30',
		price_unit => 'dirt',
		rarity_level => '2',
		group	=> 'album',
		group_level => '1'
	},

	{	type => 'trinket',
		id	=> 'piper',
		name => 'a Piper at the Gates of Dawn album',
		desc => 'a Piper at the Gates of Dawn album',
		price => '6',
		price_unit => 'money',
		rarity_level => '2',
		group	=> 'album',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'saucer',
		name => 'a Saucerful of Secrets cassette tape',
		desc => 'a Saucerful of Secrets cassette tape',
		price => '3.89',
		price_unit => 'money',
		rarity_level => '2',
		group	=> 'album',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'more',
		name => 'Pink Floyd\'s More album, on tape',
		desc => 'Pink Floyd\'s More album, on tape',
		price => '2',
		price_unit => 'money',
		rarity_level => '2',
		group	=> 'album',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'umma',
		name => 'Ummagumma',
		desc => 'Ummagumma',
		price => '6',
		price_unit => 'money',
		rarity_level => '2',
		group	=> 'album',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'atom',
		name => 'an Atom Heart Mother album',
		desc => 'an Atom Heart Mother album',
		price => '7',
		price_unit => 'money',
		rarity_level => '2',
		group	=> 'album',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'meddle',
		name => 'a Pink Floyd Meddle CD',
		desc => 'a Pink Floyd Meddle CD',
		price => '6.99',
		price_unit => 'money',
		rarity_level => '2',
		group	=> 'album',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'obscured',
		name => 'an Obscured by Clouds album',
		desc => 'an Obscured by Clouds album',
		price => '8.43',
		price_unit => 'money',
		rarity_level => '2',
		group	=> 'album',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'dsotm',
		name => 'a Dark Side of the Moon LP',
		desc => 'a Dark Side of the Moon LP',
		price => '11.00',
		price_unit => 'money',
		rarity_level => '2',
		group	=> 'album',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'wywh',
		name => 'a Wish You Were Here 8-track',
		desc => 'a Wish You Were Here 8-track',
		price => '7.32',
		price_unit => 'money',
		rarity_level => '2',
		group	=> 'album',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'oink',
		name => 'a Pink Floyd Animals 8-track',
		desc => 'a Pink Floyd Animals 8-track',
		price => '5.65',
		price_unit => 'money',
		rarity_level => '2',
		group	=> 'album',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'wall',
		name => 'The Wall: 2 disc set.',
		desc => 'The Wall: 2 disc set.',
		price => '12.99',
		price_unit => 'money',
		rarity_level => '2',
		group	=> 'album',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'crap',
		name => 'a never listened to "The Final Cut" tape ',
		desc => 'a never listened to "The Final Cut" tape ',
		price => '.99',
		price_unit => 'money',
		rarity_level => '2',
		group	=> 'album',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'lapse',
		name => 'a Momentary Lapse of Reason LP',
		desc => 'a Momentary Lapse of Reason LP',
		price => '2.99',
		price_unit => 'money',
		rarity_level => '2',
		group	=> 'album',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'bell',
		name => 'The Division Bell CD',
		desc => 'The Division Bell CD',
		price => '4.50',
		price_unit => 'money',
		rarity_level => '2',
		group	=> 'album',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'ccgh',
		name => 'a Christopher Cross Greatest Hits CD',
		desc => 'a Christopher Cross Greatest Hits CD',
		price => '2',
		price_unit => 'money',
		rarity_level => '2',
		group	=> 'album',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'lovin',
		name => 'an autographed photo of Luther Vandross',
		desc => 'an autographed photo of Luther Vandross',
		price => '6',
		price_unit => 'money',
		rarity_level => '2',
		group	=> '',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'goodolboy',
		name => 'a Don Williams concert ticket stub',
		desc => 'a Don Williams concert ticket stub',
		price => '3.43',
		price_unit => 'money',
		rarity_level => '2',
		group	=> '',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'lostinlove',
		name => 'an official Air Supply Concert T-shirt',
		desc => 'an official Air Supply Concert T-shirt',
		price => '7',
		price_unit => 'money',
		rarity_level => '2',
		group	=> '',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> '\m/',
		name => 'a Bon Jovi Slippery When Wet album',
		desc => 'a Bon Jovi Slippery When Wet album',
		price => '6.43',
		price_unit => 'money',
		rarity_level => '2',
		group	=> 'album',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'ow',
		name => 'a tube of Preparation-H',
		desc => 'a tube of Preparation-H',
		price => '3.99',
		price_unit => 'money',
		rarity_level => '2',
		group	=> '',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'archie',
		name => 'an old Archie comic book',
		desc => 'an old Archie comic book',
		price => '6',
		price_unit => 'money',
		rarity_level => '2',
		group	=> '',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'pillow',
		name => 'a body pillow',
		desc => 'a body pillow',
		price => '4.99',
		price_unit => 'money',
		rarity_level => '2',
		group	=> '',
		group_level => '1'
	},

	{	type => 'trinket',
		id	=> 'sharp',
		name => 'a brick of 10 year aged Sharp Cheddar Cheese',
		desc => 'a brick of 10 year aged Sharp Cheddar Cheese',
		price => '15',
		price_unit => 'money',
		rarity_level => '3',
		group	=> 'food',
		group_level => '1'
	},

	{	type => 'trinket',
		id	=> 'eh',
		name => 'A bottle of fine Canadian Maple Syrup',
		desc => 'A bottle of fine Canadian Maple Syrup',
		price => '15',
		price_unit => 'money',
		rarity_level => '3',
		group	=> 'food',
		group_level => '1'
	},


	{	type => 'trinket',
		id	=> 'strongest',
		name => 'a Grimlock',
		desc => 'a Grimlock',
		price => '1',
		price_unit => 'trilobite',
		rarity_level => '3',
		group	=> '',
		group_level => '1'
	},

	{	type => 'trinket',
		id	=> 'train',
		name => 'a Mrs. Pteranodon figurine',
		desc => 'a Mrs. Pteranodon figurine',
		price => '1',
		price_unit => 'trilobite',
		rarity_level => '3',
		group	=> '',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'makeitso',
		name => 'a tin of Earl Grey Tea',
		desc => 'a tin of Earl Grey Tea',
		price => '5.50',
		price_unit => 'pound',
		rarity_level => '3',
		group	=> 'food',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'perl',
		name => 'an autographed copy of the "Camel Book"',
		desc => 'an autographed copy of the "Camel Book"',
		price => '21.00',
		price_unit => 'money',
		rarity_level => '3',
		group	=> 'food',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'abs',
		name => 'an old Ab-Rocker',
		desc => 'an old Ab-Rocker',
		price => '7',
		price_unit => 'money',
		rarity_level => '3',
		group	=> 'food',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'shortycakes',
		name => 'a Strawberry Shortcake Doll',
		desc => 'a Strawberry Shortcake Doll',
		price => '4.50',
		price_unit => 'money',
		rarity_level => '3',
		group	=> '',
		group_level => '1'
	},

	{	type => 'trinket',
		id	=> 'carebear',
		name => 'a Care Bear',
		desc => 'a Care Bear',
		price => '7.20',
		price_unit => 'money',
		rarity_level => '3',
		group	=> '',
		group_level => '1'
	},

	{	type => 'trinket',
		id	=> 'haaay',
		name => 'a Rainbow Brite Doll',
		desc => 'a Rainbow Brite Doll',
		price => '6.99',
		price_unit => 'money',
		rarity_level => '3',
		group	=> '',
		group_level => '1'
	},

	{	type => 'trinket',
		id	=> 'brony',
		name => 'a My Little Pony doll',
		desc => 'a My Little Pony doll',
		price => '8.99',
		price_unit => 'money',
		rarity_level => '3',
		group	=> '',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'clif',
		name => 'a box of Clif Bars',
		desc => 'a box of Clif Bars',
		price => '11.99',
		price_unit => 'money',
		rarity_level => '3',
		group	=> 'food',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'ibt4u',
		name => 'the one where you find a DVD box set of Friends',
		desc => 'the one where you find a DVD box set of Friends',
		price => '22.99',
		price_unit => 'money',
		rarity_level => '3',
		group	=> 'none',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'idol',
		name => 'an American Idol golden ticket',
		desc => 'an American Idol golden ticket',
		price => '13',
		price_unit => 'money',
		rarity_level => '4',
		group	=> 'none',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'morethanmeetstheeye',
		name => 'an Optimus Prime',
		desc => 'an Optimus Prime',
		price => '19',
		price_unit => 'money',
		rarity_level => '4',
		group	=> '',
		group_level => '1'
	},

	{	type => 'trinket',
		id	=> 'brownies',
		name => 'an Easy Bake Oven',
		desc => 'an Easy Bake Oven',
		price => '14',
		price_unit => 'money',
		rarity_level => '4',
		group	=> '',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'lotus',
		name => 'a Black Lotus MTG card',
		desc => 'a Black Lotus MTG card',
		price => '27.00',
		price_unit => 'money',
		rarity_level => '4',
		group	=> 'none',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'furby',
		name => 'a Furby',
		desc => 'a Furby',
		price => '26.44',
		price_unit => 'money',
		rarity_level => '4',
		group	=> 'none',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'eltron',
		name => 'a really messed up looking salad',
		desc => 'a really messed up looking salad',
		price => '11.49',
		price_unit => 'money',
		rarity_level => '4',
		group	=> 'food',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'nox',
		name => 'a loud cat',
		desc => 'a loud cat',
		price => '33.49',
		price_unit => 'money',
		rarity_level => '4',
		group	=> '',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'happyhappy',
		name => 'a Monchichi',
		desc => 'a Monchichi',
		price => '21.29',
		price_unit => 'money',
		rarity_level => '4',
		group	=> '',
		group_level => '1'
	},

	{	type => 'trinket',
		id	=> 'snoopy',
		name => 'a Snoopy Sno-Cone machine',
		desc => 'a Snoopy Sno-Cone machine',
		price => '28',
		price_unit => 'money',
		rarity_level => '5',
		group	=> 'none',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'cuecat',
		name => 'a vintage CueCat device',
		desc => 'a vintage CueCat device',
		price => '27',
		price_unit => 'money',
		rarity_level => '5',
		group	=> 'none',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'newton',
		name => 'an antique Apple Newton',
		desc => 'an antique Apple Newton',
		price => '36',
		price_unit => 'money',
		rarity_level => '5',
		group	=> 'none',
		group_level => '1'
	},

	{	type => 'trinket',
		id	=> 'box',
		name => 'a strange glowing box?',
		desc => 'a strange glowing box?',
		price => '1',
		price_unit => 'goldcoin',
		rarity_level => '5',
		group	=> 'none',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'c64',
		name => 'a Commodore 64, new in box',
		desc => 'a Commodore 64, new in box',
		price => '54',
		price_unit => 'money',
		rarity_level => '5',
		group	=> 'none',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'shine',
		name => 'a conflict-free Diamond',
		desc => 'a conflict-free Diamond',
		price => '89',
		price_unit => 'money',
		rarity_level => '6',
		group	=> 'none',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'mox',
		name => 'a Mox Diamond',
		desc => 'a Mox Diamond',
		price => '78',
		price_unit => 'money',
		rarity_level => '6',
		group	=> 'none',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'daisy',
		name => 'a Dukes of Hazzard lunchbox',
		desc => 'a Dukes of Hazzard lunchbox',
		price => '75',
		price_unit => 'money',
		rarity_level => '6',
		group	=> 'none',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'meteorite',
		name => 'a small meteorite',
		desc => 'a small meteorite',
		price => '99.95',
		price_unit => 'money',
		rarity_level => '6',
		group	=> 'none',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'burt',
		name => 'an invitation to ride on on SpaceShipOne',
		desc => 'an invitation to ride on on SpaceShipOne',
		price => '120',
		price_unit => 'money',
		rarity_level => '7',
		group	=> 'none',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'adams',
		name => 'an collection of Ansel Adams photos',
		desc => 'an collection of Ansel Adams photos',
		price => '99',
		price_unit => 'money',
		rarity_level => '7',
		group	=> 'none',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'itsmale',
		name => 'a RealDoll',
		desc => 'a RealDoll',
		price => '140',
		price_unit => 'money',
		rarity_level => '7',
		group	=> 'none',
		group_level => '1'
	},

	{	type => 'trinket',
		id	=> 'scotty',
		name => 'a recipe for transparent aluminum',
		desc => 'a recipe for transparent aluminum',
		price => '159',
		price_unit => 'money',
		rarity_level => '8',
		group	=> 'none',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'she-pac',
		name => 'a Ms. Pacman arcade game',
		desc => 'a Ms. Pacman arcade game',
		price => '130',
		price_unit => 'money',
		rarity_level => '8',
		group	=> 'none',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'higgs',
		name => 'definitive proof of the Higgs Boson\'s existence',
		desc => 'definitive proof of the Higgs Boson\'s existence',
		price => '210',
		price_unit => 'money',
		rarity_level => '9',
		group	=> 'none',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'sallgood',
		name => 'a previously unknown draft of the U.S. Constitution',
		desc => 'a previously unknown draft of the U.S. Constitution',
		price => '250',
		price_unit => 'money',
		rarity_level => '9',
		group	=> 'none',
		group_level => '1'
	},

	{	type => 'trinket',
		id	=> 'feather',
		name => 'an red hawk\'s tail feather',
		desc => 'a red hawk\'s tail feather',
		price => '1',
		price_unit => 'wampum',
		rarity_level => '9',
		group	=> 'none',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'sg1',
		name => 'a Goa\'uld sarcophagus',
		desc => 'a Goa\'uld sarcophagus',
		price => '350',
		price_unit => 'money',
		rarity_level => '10',
		group	=> 'none',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'hoffa',
		name => 'Jimmy Hoffa',
		desc => 'Jimmy Hoffa',
		price => '420',
		price_unit => 'money',
		rarity_level => '10',
		group	=> 'none',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'jk',
		name => 'an isolated quark',
		desc => 'an isolated quark',
		price => '1',
		price_unit => 'latinum',
		rarity_level => '10',
		group	=> 'none',
		group_level => '1'
	},
	
	{	type => 'trinket',
		id	=> 'tard',
		name => 'a Tardis',
		desc => 'a Tardis',
		price => '320',
		price_unit => 'money',
		rarity_level => '10',
		group	=> 'none',
		group_level => '1'
	}
	);
	
	$self->{items} = \@items;
	$self->{trinkets} = \@trinkets;

	# load the fuzz and move the local markets if necessary
	$self->{fuzz_c} = $self->Collection->new({db_file=>$self->{BotDatabaseFile}, module_name=>'Dig',
			collection_name=>':fuzz', keep_stats=>$self->{keep_stats}});
	$self->{fuzz_c}->load();
	#my $icky = $self->fuzz(1);


	if ($self->{use_stocks}){
		$self->{stock_c} = $self->Collection->new({db_file=>$self->{BotDatabaseFile}, module_name=>'Dig',
         collection_name=>':stocks', keep_stats=>$self->{keep_stats}});
		$self->{stock_c}->load();

		my @groups = ('system', 'user');
		foreach my $group (@groups){
			$self->updateStockData($group);

			my @stocks = $self->{stock_c}->matchRecords({val1=>'quote_'.$group});
			foreach my $stock (@stocks){
				## xyzzy make this average the level values?
				my $level;
				$level = 1 if ($stock->{val4} > 0);
				$level = 2 if ($stock->{val4} > 6);
				$level = 3 if ($stock->{val4} > 15);
				$level = 4 if ($stock->{val4} > 25);
				$level = 5 if ($stock->{val4} > 40);
				$level = 6 if ($stock->{val4} > 60);
				$level = 7 if ($stock->{val4} > 90);
				$level = 8 if ($stock->{val4} > 150);
				$level = 9 if ($stock->{val4} > 220);
				$level = 10 if ($stock->{val4} > 300);

				push @{$self->{stocks}}, 
					{	type => 'stock',
						id	=> uc($stock->{val2}),
						name => "$stock->{val3} ($stock->{val2})",
						desc => "$stock->{val3} ($stock->{val2})",
						price => $stock->{val4},
						price_unit => 'money',
						rarity_level => $level,
						group	=> 'stock_' . $group,
						last_updated => $stock->{val5},
						group_level => 1,
					}
				;
			}
		}
	}
}


##
##	Stock & Fuzz  - Pricing stuff
##

sub updateStockData{
	my $self = shift;
	my $mode = shift;

	my @lurecords = $self->{stock_c}->matchRecords({val1=>'last_updated_'.$mode});
	if (!@lurecords){
		$self->{stock_c}->add('last_updated_'.$mode , time() - 60*60*24);
		@lurecords = $self->{stock_c}->matchRecords({val1=>'last_updated_'.$mode});
	}

	# xyzzy make this work only when market is open. be careful of user added stocks
	#my $last_update = $lurecords[0]->{val2};

	if ($lurecords[0]->{val2} < (time() - $self->{stock_update_freq} ) ){
		print "Dig::Store is Updating stocks...\ $mode\n";

		## if someone changed the list of stocks in plugin_init, we should delete the list 
		## start fresh so we dont give out bad stocks. this should happen elsewhere. oh well.
		my @count = $self->{stock_c}->matchRecords({val1=>'quote'});
		if (@{$self->{stock_list}} != @count){
			my @count = sort { $b->{display_id} <=> $a->{display_id} } @count;
			$self->{stock_c}->startBatch();
			foreach my $rec (@count){
				$self->{stock_c}->delete($rec->{row_id});
			}
			$self->{stock_c}->endBatch();
		}

		my $sym_list;
		if ($mode eq 'system'){
			foreach my $sym (@{$self->{stock_list}}){
				$sym_list.=$sym . '+';
			}

		}else{
			my @records = $self->{stock_c}->matchRecords({val1=>'user_stocks'});
			foreach my $rec (@records){
				$sym_list.=$rec->{val2} . '+';
			}
		}

		if ($sym_list){
			my $page = $self->getPage("http://download.finance.yahoo.com/d/quotes.csv?s=$sym_list&f=snl1");
			my @lines = split /\r\n/, $page;

			$self->{stock_c}->startBatch();
			foreach my $line (@lines){
				#print "|$line|\n";
				my @col = quotewords(',', 0 , $line);
				my @records=$self->{stock_c}->matchRecords({val1=>'quote_'.$mode, val2=>$col[0]});
				if (@records){
					$self->{stock_c}->updateRecord($records[0]->{row_id}, {val4=>$col[2], val5=>time()});
				}else{
					$self->{stock_c}->add('quote_'.$mode, $col[0], $col[1], $col[2], time());
				}
			}
			$self->{stock_c}->endBatch();
		}
		$self->{stock_c}->updateRecord($lurecords[0]->{row_id}, {val2=>time()});
	}
}

sub lookupNewStock{
	my $self = shift;
	my $symbol = shift;

	return 0 if ($symbol=~/\s/);

	# col1 = comany name col2 = symbol col3 = price
	my $page = $self->getPage("http://download.finance.yahoo.com/d/quotes.csv?s=$symbol&f=snl1");
	my @lines = split /\r\n/, $page;

	my $ret;

	foreach my $line (@lines){
		my @col = quotewords(',', 0 , $line);
		if ($col[2] ne '0.00'){
			$ret = {name=>$col[1], symbol=>$col[0], price=>$col[2]};
			return $ret;
		}
	}

	return 0;
}

sub addNewStock{
	my $self=shift;
	my $stock = shift;
	
	my @records = $self->{stock_c}->matchRecords({val1=>'quote_user', val2=>$stock->{symbol}});
	if (!@records){
		$self->{stock_c}->add('quote_user', $stock->{symbol}, $stock->{name}, $stock->{price}, time());
	}

	@records = $self->{stock_c}->matchRecords({val1=>'user_stocks', val2=>$stock->{symbol}});
	if (!@records){
		$self->{stock_c}->add('user_stocks', $stock->{symbol}, $stock->{name});
	}

	push @{$self->{stocks}}, 
		{	type => 'stock',
			id	=> $stock->{symbol},
			name => "$stock->{name} ($stock->{symbol})",
		 	desc => "$stock->{name} ($stock->{symbol})",
			price => $stock->{price},
			price_unit => 'money',
			rarity_level => 1,
			group	=> 'stock_user',
			last_updated => time(),
			group_level => 1,
		}
	;
	
}

sub fuzz{
	my $self = shift;
	my $level = shift;
	my @lurecords = $self->{fuzz_c}->matchRecords({val1=>'last_updated'});

	if (!@lurecords){
		$self->{fuzz_c}->add('last_updated', time() - 60*60*24);

		for (my $i=1; $i<=10; $i++){
			my @r = $self->{fuzz_c}->matchRecords({val1=>'level', val2=>$i});
			if (!@r){
				$self->{fuzz_c}->add('level', $i, '1');
			}
		}

		@lurecords = $self->{fuzz_c}->matchRecords({val1=>'last_updated'});
	}

	if ($lurecords[0]->{val2} < (time() - $self->{fuzz_interval} ) ){
		my @records = $self->{fuzz_c}->matchRecords({val1=>'level'});

		$self->{fuzz_c}->startBatch();
		foreach my $rec(@records){
			print "fuzzing\n";

			my $cur = $rec->{val3};

			if (int(rand(2))){
				if ($rec->{val2} == 1){
					$cur += .3;
					$cur = 5 if ($cur > 5);
				}else{
					$cur += .1;
					$cur = 2.5 if ($cur > 2.5);
				}

			}else{
				if ($rec->{val2} ==1){
					$cur -= .3;
					$cur = .1 if ($cur < .1 );

				}else{
					$cur -= .1;
					$cur = .1 if ($cur < .1);
				}
			}

			#print "go $rec->{val2}\n";
			$self->{fuzz_c}->updateRecord($rec->{row_id}, {val3=>$cur});
		}

		$self->{fuzz_c}->updateRecord($lurecords[0]->{row_id}, {val2=>time()});
		$self->{fuzz_c}->endBatch();

	}

	my @records = $self->{fuzz_c}->matchRecords({val1=>'level', val2=>$level});
	return $records[0]->{val3};
}


sub waterPrice{
	my $self = shift;
	my $plots_remaining =$self->{board_plotsRemaining};
	my $price = .2 + (($self->{num_plots} - $plots_remaining) / 50);
	$price = .1 if ($self->yi());
	$price = sprintf('%.2f', $price);
	return $price;
}

sub bombPrice{
	my $self = shift;
	
	my $plots_remaining = $self->{board_plotsRemaining} || 50;
	my $money_remaining = $self->{board_moneyRemaining} || 0;
	my $price = ($money_remaining / $plots_remaining) * 4;
	$price = 1 if ($price < 1);
	$price = 3.14 * 1.333 if ($price > (3.14 * 1.333));

	if ($self->yi()){
		if (int(rand(10))){
			$price=.1;
		}else{
			$price=(3.14 * 1.333);
		}
	}
	$price = sprintf('%.2f', $price);
	return $price;
}

sub yi{
	my $self = shift;
	my $quads = int(time() / 1753200);
	my $remainder = time() % 1753200;
	my $raels = $quads * 4;
	my $extraraels = int($remainder / 432000);
	if ($extraraels != 4){
		return 0;
	}

	return 1;
}

sub updateNecessityPrices{
	my $self = shift;

	foreach my $item (@{$self->{items}}){
		if ($item->{id} eq 'water'){
			$item->{current_value} = $self->waterPrice();
			$item->{price} = $self->waterPrice();
		}

		if ($item->{id} eq 'bomb'){
			$item->{current_value} = $self->bombPrice();
			$item->{price} = $self->bombPrice();
		}

		if ($item->{id} eq 'dirtraffle'){
			my ($total, $rem);
			if ($total = $self->globalCookie("specialItem_raffle_dirtraffle_total")){
				$rem = $self->globalCookie('specialItem_raffle_dirtraffle_remaining');
				if ($rem == 0){
					$rem = $total;
				}
				$item->{desc} .= BOLD.RED." $rem/$total tickets remain.".NORMAL;
			}
		}

		if ($item->{id} eq 'hrdirtraffle'){
			my ($total, $rem);
			if ($total = $self->globalCookie("specialItem_raffle_hrdirtraffle_total")){
				$rem = $self->globalCookie('specialItem_raffle_hrdirtraffle_remaining');
				if ($rem == 0){
					$rem = $total;
				}
				$item->{desc} .= BOLD.RED." $rem/$total tickets remain.".NORMAL;
			}
		}
	}
}

sub storeInit{
	my $self = shift;
	my $opts = shift;
	my $player = $opts->{player};
	$self->{board_plotsRemaining} = $opts->{board_plotsRemaining};
	$self->{board_moneyRemaining} = $opts->{board_moneyRemaining};
	$self->{num_plots}= $opts->{num_plots};
	$self->updateNecessityPrices();
}


##
##	Bazaar
##

sub bazaarLoad{
	my $self = shift;

	return if ($self->{bazaar_c});

	$self->{bazaar_c} = $self->Collection->new({db_file=>$self->{BotDatabaseFile}, module_name=>'Dig',
			collection_name=>':bazaar', keep_stats=>$self->{keep_stats}});
	$self->{bazaar_c}->load();

}


sub bazaarListings{
	my $self = shift;
	my $output;
	$self->bazaarLoad();

	my @records = $self->{bazaar_c}->getAllRecords();
	if (!@records){
		$output="The bazaar has no listings right now.";
		return $output;
	}
}

sub bazaarListItem{
	my $self = shift;
	my $thing = shift;
	my $player = shift;
	my $price = shift;
	my $quantity = shift;

	#$player->takeThing($thing, $quantity);
	#1:item_id, 2:item_quantity, 3:item_price, 4:item_price_unit, 5:seller nick, 6: seller acq price 7: date listed
	#$self->{bazaar_c}->add($thing->{id}, $quantity, $price, $price_unit, $player->accountNick(), 0, time());
}


sub playerBuyList{
	my $self = shift;
	my $opts = shift;
	my $player = $opts->{player};

	my @stuff;
	
	# get the always buy items
	foreach my $item (@{$self->{items}}){
		if ($item->{always_buy}){
			my $thing = $self->getItem($item->{id});
			push @stuff, $thing;
		}
	}

	# get the trinkets
	my @ids = $player->listTrinkets({array=>1});	
	foreach my $id (@ids){
		my $thing = $self->getTrinket($id);
		push @stuff, $thing;
	}

	# get the stocks
	#@ids = $player->listStocks({array=>1});	
	#foreach my $id (@ids){
	#	my $thing = $self->getStock($id);
	#	push @stuff, $thing;
	#}

	foreach my $item (@stuff){
		my $price = $item->{current_value};
		if ($item->{buyback_rate}){
			$price = sprintf("%.2f", $price * $item->{buyback_rate});
		}
		
		my $price_f = $item->{currency_o}->format($price);
		my $msg = '['.$item->{id}.'] '. $item->{name} . ' ('.$price_f.')';
		$self->addToList($msg, $self->BULLET);
	}

	my $list = $self->getList();
	my $yi="";
	if ($self->yi()){
		$yi=RED."yi sale!";
	}
	return BOLD."The Dig Store$yi".NORMAL." is looking to buy the following items the listed rates.".BLUE." To sell an item, \"store -sell=<#>\". ".NORMAL.$list;
}


sub playerSellList{
	my $self = shift;
	my $opts = shift;
	my $player = $opts->{player};

	my @stuff;
	my $title = "The dig! Store";

	# get the always sell items
	foreach my $item (@{$self->{items}}){
		if ($opts->{casino}){
			$title = "The dig! Dirt Casino";
			if ($item->{group} eq 'casino'){
				my $i = $self->getItem($item->{id});
				push @stuff, $i;
			}

		}else{
			next if ($item->{group} eq 'casino');

			if ($item->{always_sell}){
				my $i = $self->getItem($item->{id});
				push @stuff, $i;
				next;
			}

			next if ($player->hasItem($item->{id}));
			next if (($player->itemEclipsed($item))[0]);
			my $i = $self->getItem($item->{id});
			push @stuff, $i;
		}
	}


	foreach my $item (@stuff){
		my $msg;
		my $price = $item->{price} || 99999;
		my $price_f = $item->{currency_o}->format($price);
		$msg = '['.$item->{id}.'] '. $item->{name} . ' ('.$price_f.')';
		$self->addToList($msg, $self->BULLET);
	}

	my $list = $self->getList();

	my $yi = "";
	if ($self->yi()){
		$yi=RED." yi sale!";
	}
	return BOLD.$title.$yi.":".NORMAL.BLUE." To buy, \"store -buy=<#>\". For info, \"store -info=<#>\". ".NORMAL.$list;

}

sub getSaleItem{
	my $self= shift;
	my $id = shift;
	
	foreach my $item (@{$self->{items}}){
		if ($item->{id} eq $id && $item->{'for_sale'}){
			return $self->getItem($item->{id});
		}
	}
	return 0;
}

sub getItemInfo{
	my $self= shift;
	my $id = shift;
	my $output;
	my $item = $self->getItem($id);

	if ($item){
		$output = NORMAL.BOLD."Item Name: ".NORMAL.$item->{name}. " ";
		$output .= BOLD."Description: ".NORMAL.$item->{desc}. " ";
		my $label="Price";
		if (!$item->{for_sale}){
			$label="Current value";
		}

		my $price_f = $item->{currency_o}->format($item->{current_value});
	
		$output .= BOLD."$label: ".NORMAL . $price_f. ". ";
		
		if ($item->{for_sale}){
			$output .=BLUE."To purchase this item, use \"store -buy=$item->{id}\".".NORMAL;
		}
	}else{
		$output = "I know nothing about that item.";
	}

	return $output;
}

sub specialItem{
	my $self = shift;
	my $opts = shift;
	my $item = $opts->{item};


	#prInt "DI is $opts->{digsinsider}\n";
	if ($item->{id} eq 'water'){
		my $msg = $self->specialItem_water($opts);
		return (1, $msg);
	}
		
	if ($item->{id} eq 'lottery'){
		my $msg = $self->specialItem_lottery($opts);
		return (1, $msg);
	}

	if ($item->{id} eq 'biggamble'){
		my $msg = $self->specialItem_biggamble($opts);
		return (1, $msg);
	}

	if ($item->{id} eq 'dirtdice'){
		my $msg = $self->specialItem_dirtdice($opts);
		return (1, $msg);
	}

	if ($item->{id} eq 'dirtraffle'){
		my $msg = $self->specialItem_raffle($opts);
		return (1, $msg);
	}

	if ($item->{id} eq 'hrdirtraffle'){
		my $msg = $self->specialItem_raffle($opts);
		return (1, $msg);
	}

	if ($item->{id} eq 'sevens'){
		my $msg = $self->specialItem_sevens($opts);
		return (1, $msg);
	}


		
	return (0, "you're not special, snowflake");
}

sub specialItem_raffle{
	my $self = shift;
	my $opts = shift;
	my $item = $opts->{item};
	my $player = $opts->{player};
	my $parent = $opts->{parent};
	my $quantity = $opts->{quantity};
	my $flags = $opts->{flags};
	my $output;

	my $total_spots = 10;
	my $cookie_stub = "specialItem_raffle_" . $item->{id}. "_";

	my $spots = $player->globalCookie($cookie_stub . 'remaining');

	$player->startBatch();
	#start a game if necesary
	if ( (!$spots) || ($spots <=0) ){
		for (my $i=1; $i<=$total_spots; $i++){
			 $player->globalCookie($cookie_stub . $i, ':nobody');
		}
		$player->globalCookie($cookie_stub . "remaining", 10);
		$player->globalCookie($cookie_stub . "total",  10);
	}

	my $spots_remaining = $player->globalCookie($cookie_stub . "remaining");
	$player->endBatch();
	my @available;

	for (my $i=1; $i<=$total_spots; $i++){
		if ( $player->globalCookie($cookie_stub . $i) eq ':nobody'){
			push @available, $i;
		}
	}

	my $spot = (@available[int(rand(@available))]);
	my $balance = $player->currency({type=>$item->{price_unit}, increment=>-$item->{price}, format=>1});

	$player->globalCookie($cookie_stub . $spot, $player->{nick});
	$player->globalCookie($cookie_stub . 'remaining', @available - 1);

	$output = "You just bought raffle ticket #$spot in the ".$item->{name}.' for ';
	$output .= $item->{currency_o}->format($item->{price}) . ', ';
	$output .="where you can win " . $item->{currency_o}->format($item->{price} * $total_spots) . '. ';

	if (@available - 1 == 0){
		$output .= RED."Doing raffle drawing now... ".NORMAL;

		my @raffle;
		for (my $i=1; $i<=$total_spots; $i++){
			push @raffle, $player->globalCookie($cookie_stub . $i);
		}

		my $winner_name = (@raffle[int(rand(@raffle))]);
		my $winner = $parent->loadPlayer($winner_name);
		$winner->tell("You won the " . $item->{name} . "! ".$item->{currency_o}->format($item->{price} * $total_spots)." have been credited to your account. Congrats!");

		$winner->currency({type=>$item->{price_unit}, increment=>$item->{price} * $total_spots, format=>1});
		$output .= BOLD."$winner_name has won the raffle! ".NORMAL;
		$output .= $item->{currency_o}->format($item->{price} * $total_spots) . ' ';
		$output .= "have been credited to $winner_name. ";

	}else{
		$output .= "You have $balance left. " ;
		$output .= "The winner will be determined once the remaining ".(@available - 1)." tickets are sold. ";
		$output .= "Thanks for playing! ";
	}

	return $output;
	
}

sub specialItem_water{
	my $self = shift;
	my $opts = shift;
	my $item = $opts->{item};
	my $player = $opts->{player};
	my $quantity = $opts->{quantity};
	my $output;

	my @records = $player->{next_digs_c}->matchRecords({val1=>$player->{mask}});

	if ($records[0]->{val3} eq 'bomb'){
		return "Water isn't going to help you clean up after da bomb!";
	}

	if ($records[0]->{val3} eq 'already_dug'){
		return "Water can't begin to wash away your shame.";
	}

	if ($records[0]->{val3} eq 'bathroom'){
		return "How is water going to help you find a bathroom?  Isn't water what got you into this mess in the first place?";
	}

	my $board_id = $self->globalCookie("board_id") || 0;

	if ($player->cookie("water_board_id") ne $board_id){
		$player->cookie("water_board_id", $board_id);
		$player->cookie("water_purchased", 0);
	}

	my $water_purchased = $player->cookie("water_purchased") || 0;
	my $max_waters = 4;
	
	my $ppitem = ($player->getItemByGroup("potty"));
	if ($ppitem){
		$max_waters = $ppitem->{item_info}->{attributes}->{num_waters};
	}

	# the logic is not perfect here.
	if ( ($water_purchased + $quantity) >  $max_waters){
		my $msg = "Having already purchased $max_waters waters this board, you find yourself unable ";
		$msg .= "to contain yourself any longer. You spend the next 20 minutes looking for ";
		$msg .= "a bathroom.";

		$player->determineNextDigTime("bathroom");
		return $msg;
	}

	my $when_s = $records[0]->{val2} - time();

	if ($when_s > 0){
		my $newwhen_s = $when_s;
		for (my $i=0; $i<$quantity; $i++){
			$newwhen_s = $newwhen_s/2;
		}

		if ($newwhen_s < 60){
			$newwhen_s = 60;
		}

		my $newtime = time() + $newwhen_s;
		$player->{next_digs_c}->updateRecord($records[0]->{row_id}, {val2=>$newtime});
		my $min = ceil($newwhen_s/60);
			
		if ($min == 1){
			$output = "Aaaaah, how refreshing. You will be ready to dig again in $min minute.";
		}else{
			$output = "Aaaaah, how refreshing. You will be ready to dig again in $min minutes.";
		}
	
	}else{
		$output = "Ahh, how refreshing!";
	}

	$player->cookie("water_purchased", $water_purchased + $quantity);


	my $ntt = $player->cookie('notify_timer_time') || 0;

	if ($ntt > time()){
		my $ntid = $player->cookie('notify_timer_id');
		print "I should tell someone to cancel that timer! $ntid\n";
	}

	if ($opts->{digsinsider}){
		$player->money(-$item->{price} * $quantity );
	}else{
		$player->money(-$item->{price} * .9 * $quantity );
	}
	return ($output);
}


sub specialItem_lottery{
	my $self = shift;
	my $opts = shift;
	my $item = $opts->{item};
	my $player = $opts->{player};
	my $quantity = $opts->{quantity};
	my $output;

	my $total = 0;
	$player->startBatch();
	while ($quantity--){
		my $val = sprintf("%.2f", int(rand(1001))/ 100);

		my $luckyitem = ($player->getItemByGroup("lucky"));
		if ($luckyitem){
			$val = $val * $luckyitem->{item_info}->{attributes}->{money_multiplier};
		}

		$player->money($val);
		if ($opts->{digsinsider}){
			$player->dirt(-$item->{price} * .9);
		}else{
			$player->dirt(-$item->{price});
		}
		$total+=$val;
	}
	$player->endBatch();
	$total = sprintf("%.2f", $total);
	return "You won \$$total!  ".BLUE."Do you know about the dig! dirt casino?  Type \"store -casino\" to visit.".NORMAL;
}

sub specialItem_biggamble{
	my $self = shift;
	my $opts = shift;
	my $item = $opts->{item};
	my $player = $opts->{player};
	my $quantity = $opts->{quantity};
	my $output;

	my $result = int(rand(6)) + 1;
	my $die = "DICE_" . $result;

	$player->dirt(-$item->{price});

	if ($result>=4){
		$player->money($player->money());
		my $cash = $player->money_f();
		$output.=BOLD."CONGRATULATIONS! You rolled a $result".$self->$die;
		$output.=", doubling your money in the game of dig! ".NORMAL;
		$output.="You now have ".BOLD."$cash dollars".NORMAL.". Put that in your pipe & smoke it, h8trz!";

	}elsif($result == 3){
		my $cash = $player->money_f();
		$output.=BOLD."You rolled a three. " . $self->$die.NORMAL." Which isn't what you ";
		$output.="wanted, I know, but things could be worse. You're may be 200 piles of dirt ";
		$output.="poorer, but at least you have your health. And you cash - all $cash of it. ";
		$output .="Congrats on not losing it all!";

	}else{
		$player->money(-$player->money());
		my $cash = $player->money_f();
		$output.=BOLD."OH NO! You rolled a $result!".NORMAL." (Here's proof, if you don't believe ";
		$output.="me: ".$self->$die.") Unfortunately that means you've lost all of your cash. ";
		$output.="Win some, lose some. Nothing ventured nothing gained. ";
		$output.="All we are is dirt in the wind. Whatever. ";
		$output.= "The good news is that I'll never run out of plots for you ";
		$output.="to dig. Better get to work. ".BOLD."Your new balance: $cash.".NORMAL;
	}

	return "$output";
}


sub specialItem_sevens{
	my $self = shift;
	my $opts = shift;
	my $item = $opts->{item};
	my $player = $opts->{player};
	my $quantity = $opts->{quantity};
	my $next_play_seconds = 10;

	my $output;

	if ($player->cookie('sevens') > time()){
		return "You can only play ".BOLD."Sevens".NORMAL." once every $next_play_seconds seconds.";
	}
	
   my $n = int(rand(6)) + 1;
   my $m = int(rand(6)) + 1;
   my $total = $n+$m;

	my $die1 = "DICE_" . $n;
	my $die2 = "DICE_" . $m;
	my $dice = $self->$die1 . " " . $self->$die2;

	my $net = -$item->{price};
	if ($total == 7){
		$net+= ($item->{price} * 6);
	}

	$player->dirt($net);
	
	$net += $item->{price};
	if ($total == 7){
		$output = "You rolled a $total $dice!  You just won $net piles of dirt. ";
	}else{
		$output = "You rolled a $total $dice. Better luck next time! ";
	}

	my $dirt = $player->dirt();
	$output.="You now have $dirt piles of dirt.";

	$player->cookie('sevens', time() + $next_play_seconds);
	return $output;
}


sub specialItem_dirtdice{
	my $self = shift;
	my $opts = shift;
	my $item = $opts->{item};
	my $player = $opts->{player};
	my $quantity = $opts->{quantity};
	my $next_play_seconds = 10;

	my $output;

	if ($player->cookie('dirtdice') > time()){
		return "You can only play ".BOLD."Dirt Dice".NORMAL." once every $next_play_seconds seconds.";
	}
	

   my $n = int(rand(6)) + 1;
   my $m = int(rand(6)) + 1;
   my $total = $n+$m;

	my $die1 = "DICE_" . $n;
	my $die2 = "DICE_" . $m;
	my $dice = $self->$die1 . " " . $self->$die2;

	my $net = $total - $item->{price};
	$player->dirt($net);
	
	$output = "You rolled a $total $dice, winning you $total piles of dirt. ";

	if ($net > 0){
		if ($net == 1){
			$output.= "Thats a net gain of $net pile!  Congrats! ";
		}else{	
			$output.= "Thats a net gain of $net piles!  Congrats! ";
		}
	}elsif($net == 0){
		$output.= "You broke even! ";
	}else{
		$net = -$net;
		if ($net == 1){
			$output.= "After paying the entry fee, you're down $net pile. Better luck next time! ";
		}else{
			$output.= "After paying the entry fee, you're down $net piles. Better luck next time! ";
		}
	}

	my $dirt = $player->dirt();
	$output.="You now have $dirt piles of dirt.";

	$player->cookie('dirtdice', time() + $next_play_seconds);
	return $output;
}

}	#end store


#####################################################
#####################################################
#####################################################
#####################################################

{
package Currency;
use strict;
use warnings;
use Data::Dumper;
use POSIX;

my $id;
my $desc_s;
my $desc_pl;
my $format;
my $fuzz;				#fuzzable item or no?
my $conversion_rate;  #only used in net worth calculation
my $multiply;  # multiply when digging up with shovel?
my $round_down;
my $loaded;

sub new {
	my $class = shift;
	my $self = bless {}, $class;
	my $opts = shift;
	$self->{loaded} = 0;

	if ($opts->{id}){
		$self->load($opts->{id});
	}
	return $self;
}


sub types{
	my @types = (
		{ id => 'money',
			desc_s => 'money',
			desc_pl =>'money',
			format =>'$%.2f',
			fuzz =>1,
			conversion_rate =>1,
			multiply =>1,
			use_desc => 0
 
		},
		{ id => 'dirt',
			desc_s => 'pile of dirt',
			desc_pl =>'piles of dirt',
			format =>'%d',
			fuzz =>0,
			conversion_rate =>.04,
			multiply =>0,
			use_desc => 1,
			round_down => 1
		},
		{ id => 'wampum',
			desc_s => 'wampum',
			desc_pl =>'wampums',
			format =>'%d',
			fuzz =>0,
			conversion_rate =>1000,
			multiply =>0,
			use_desc => 1
			
		},
		{ id => 'goldcoin',
			desc_s => 'gold coin',
			desc_pl =>'gold coins',
			format =>'%d',
			fuzz =>0,
			multiply => 0,
			conversion_rate =>50,
			use_desc => 1,
			round_down => 1
		},
		{ id => 'trilobite',
			desc_s => 'trilobite',
			desc_pl =>'trilobites',
			format =>'%d',
			fuzz =>0,
			conversion_rate =>50,
			multiply =>0,
			use_desc => 1,
			round_down => 1
		},
		{ id => 'pound',
			desc_s => 'sterling',
			desc_pl =>'sterling',
			format =>"\x{00A3}%.2f",
			fuzz =>1,
			conversion_rate =>2,
			multiply =>1,
			use_desc => 1
		},
		{ id => 'latinum',
			desc_s => 'bar of gold-pressed latinum',
			desc_pl =>'bars of gold-pressed latinum',
			format =>"%d",
			fuzz =>0,
			conversion_rate =>1000,
			multiply =>0,
			use_desc => 1
		},
	);

	return \@types;
}


sub load{
	my $self = shift;
	my $id = shift;

	$self->{id} = $id;

	my $types = $self->types();

	foreach my $t (@{$types}){
		if ($t->{id} eq $self->{id}){
			$self->{desc_s} = $t->{desc_s};
			$self->{desc_pl} = $t->{desc_pl};
			$self->{format} = $t->{format};
			$self->{use_desc} = $t->{use_desc};
			$self->{fuzz} = $t->{fuzz};
			$self->{conversion_rate} = $t->{conversion_rate};
			$self->{loaded} =1;
			$self->{multiply} =$t->{multiply};
			$self->{round_down} =$t->{round_down} || 0;
			return;
		}
	}
	$self->{loaded} =0;
}


sub getAllTypes{
	my $self = shift;
	my $types = $self->types();

	my @ret;
	foreach my $type (@{$types}){
		push @ret, $type->{id};
	}

	return @ret;
}


sub plural{
	my $self = shift;
	my $num = shift;
	return 0 if (!$self->{loaded});
	return $self->{desc_pl};
}

sub format{
	my $self = shift;
	my $num = shift;

	return 0 if (!$self->{loaded});

	my $ret = sprintf($self->{format}, $num);
	$ret = $self->commify($ret);

	if ($self->{use_desc}){
		if ($num == 1){
			$ret.=" $self->{desc_s}";
		}else{
			$ret.=" $self->{desc_pl}";
		}
	}
	return $ret;
}

sub commify {
	my $self = shift;
	my $num  = shift;
	return 0 if (!$self->{loaded});
	$num = reverse $num;
	$num=~ s/(\d\d\d)(?=\d)(?!\d*\.)/$1,/g;
	return scalar reverse $num;
}

}	#end Currency 

1;
__END__
