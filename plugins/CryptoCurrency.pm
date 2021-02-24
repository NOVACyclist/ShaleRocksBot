package plugins::CryptoCurrency;
#---------------------------------------------------------------------------
#    Copyright (C) 2014  egretsareherons@gmail.com
#    https://github.com/NOVACyclist/ShaleRocksBot
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
use base qw (modules::PluginBaseClass);
use modules::PluginBaseClass;
use strict;
use warnings;

use Data::Dumper;

my $types;

sub plugin_init{
    my $self = shift;

    $self->{types} = ['dogecoin', 'bitcoin', 'litecoin', 'ppcoin', 'namecoin', 
                'quarkcoin', 'feathercoin', 'novacoin', 'terracoin', 'freicoin'];
    return $self;
}


sub getOutput {
    my $self = shift;
    my $command = $self->{'command'};
    my $options = $self->{options};
    my $output = "";

    ## Dogecoin specific
    if ($command eq 'dc'){

        my $current_price = 0;
        if ($self->hasFlag('24') || $self->hasFlag('usd')){
            my $URL = "http://doge4.us/";
            my $page = $self->getPage($URL);
            $page=~m#(Dogecoin is .+?in the last 24 hours)#gs;
            my $gain = $1;
            $gain=~s/<.+?>//gis;
            $gain=~s/\-//gis;

            $page=~m#(1 Dogecoin =.+?US Dollars)#gs;
            my $usd= $1;
            $usd=~s/<.+?>//gis;

            if ($self->hasFlag("24")){
               return $gain . '. ' . $usd . '.';
            }else{
                $current_price = (split /=/, $usd)[1];
                $current_price=~s/[A-Za-z ]//gis;
            }
        }

        my $URL = 'http://dogechain.info/chain/Dogecoin/q/';

        if (my $address = $self->hasFlagValue('balance')){
            my $page = $self->getPage($URL . 'addressbalance/' . $address);
            if ($self->hasFlag('usd')){
                my $bal = sprintf("%.3f", $current_price * $page);
                return "$page dogecoins (\$".$self->commify($bal).") at $address";
                
            }else{
                return "$page dogecoins at $address";
            }
        }

        if (my $address = $self->hasFlagValue('sent')){
            my $page = $self->getPage($URL . 'getsentbyaddress/' . $address);
            if ($self->hasFlag('usd')){
                my $bal = sprintf("%.3f", $current_price * $page);
                return "$page dogecoins (\$".$self->commify($bal).") sent from $address";
                
            }else{
                return "$page dogecoins sent from $address";
            }
        }

        if (my $address = $self->hasFlagValue('received')){
            my $page = $self->getPage($URL . 'getreceivedbyaddress/' . $address);
            if ($self->hasFlag('usd')){
                my $bal = sprintf("%.3f", $current_price * $page);
                return "$page dogecoins (\$".$self->commify($bal).") received at $address";
            }else{
                return "$page dogecoins received at $address";
            }
        }
        
        if ($self->hasFlag('total')){
            my $page = $self->getPage($URL . 'totalbc');
            if ($self->hasFlag('usd')){
                my $bal = sprintf("%.3f", $current_price * $page);
               return $self->commify(sprintf("%d", $page)) . " total dogecoins (\$".$self->commify($bal).") have been mined";
            }else{
               return $self->commify(sprintf("%d", $page)) . " total dogecoins have been mined";
            }
        }
        
        return $self->help($command);
    }


    if ($command ~~ @{$self->{types}}){
        my $URL = "http://bitinfocharts.com/$command";
        my $page = $self->getPage($URL);
    
        $page=~m#<h1>(.+?) statistics</h1>#gis;
        my $currency_name = $1;

        $page =~ m#<span\s+itemprop="price">(.+?)</span> \(<small>(.+?)</small>\)</span>#;
        my $price_usd= $1;
        my $price_update_utc = $2;
 
        my $num = $price_usd;
        $num = (split / /, $price_usd)[0];
        my $dollar = sprintf("%.8f", 1 / $num);
        $dollar = sprintf("%.2f", $dollar) if ($dollar > 1);

        return "Latest $currency_name price: $price_usd ($price_update_utc). 1 USD = $dollar $currency_name ".GREEN.UNDERLINE.$self->getShortURL($URL).NORMAL;
    
    }
}

sub commify {
    my $self = shift;
    my $num  = shift;
    $num = reverse $num;
    $num=~ s/(\d\d\d)(?=\d)(?!\d*\.)/$1,/g;
    return scalar reverse $num;
}

sub listeners{
    my $self = shift;
    my @commands = ('dc');

    # push each currency from plugin_init as a command
    foreach my $type (@{$self->{types}}){
        push @commands, $type;
    }

    my $default_permissions =[ ];
    return {commands=>\@commands, permissions=>$default_permissions};
}

sub addHelp{
    my $self = shift;
    $self->addHelpItem("[plugin_description]", "Get cryptocurrency price quotes from bitinfocharts.com. Get some other dogecoin specific stuff too.");
    foreach my $type (@{$self->{types}}){
        $self->addHelpItem("[$type]", "Get a $type price quote from bitinfocharts.com");
    }
    $self->addHelpItem("[dc]", "Dogecoin info.  Flags: -balance=<address> -sent=<address> -received=<address> -total -24 [-usd includes \$USD values]");
}

1;
__END__
