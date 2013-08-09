package plugins::TextUtils;
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
use IRC::Utils ':ALL';

my $colors = {
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

sub plugin_init{
	my $self = shift;
	$self->suppressNick("true");
	return $self;
}

sub getOutput {
	my $self = shift;
	my $output = "";
	my $options = $self->{'options'};
	my $cmd = $self->{'command'};

	##
	## Rainbow
	##
	if ($cmd eq 'rainbow'){
		print "RAINBOW GETTING $options\n";
		return $self->help($cmd) if ($self->{'options'} eq '' );
	
		# remove the old color codes from the string. otherwise this gets ugly
		$options = strip_color($options);
	
		my @str;
		if ($self->hasFlag("w")){
			#split on words
			@str = split / /, $options;
			
		}elsif(my $num = $self->hasFlagValue("c")){
			@str = unpack("(A$num)*", $options);
			print Dumper (@str);

		}else{
			#split each char
			@str = split //, $options;
		}

		foreach my $c (@str){
			my $rn = int(rand(16));
			if ($rn < 10){
				$rn = "0" . $rn;
			}
			$output.="\x03".$rn . $c;

			if($self->hasFlag("w")){
				$output.=" ";
			}
		}

		print "RAINBOW RETURNING $output\n";
		return $output;
	}

	##
	##	List colors
	##

	if ($cmd eq 'listcolors'){
		my $bullet = "";
		foreach (sort { ($colors->{$a} cmp $colors->{$b}) } keys $colors){
			$output.= $bullet . $colors->{$_} . "$_"."\x0f" ;
			$bullet = " " . $self->BULLET ." ";
		}

		return $output;
	}

	##	
	##	Colors
	##
	if ($cmd eq 'color'){
		print "OPTIONS IS $options\n";
		return $self->help($cmd) if($options!~/^(.+?) (.+?)$/);
		
		my $color = uc($1);
		my $text = $2;

		# remove the old color codes from the string. otherwise ick
		$text = strip_color($text);
	
		if (!defined($colors->{$color})){
			return "Invalid Color.  Try listcolors to get a list of colors";
		}

		return ($colors->{$color} . $text . "\x0f");
	}


	##
	##	Echo
	##	

	if ($cmd eq 'echo'){
		return $self->help($cmd) if ($options!~/^(.+?)$/);
		
		if (my $c = $self->hasFlagValue("channel")){
			$self->{channel} = $c;
		}

		if ($self->hasFlag('action')){
			$self->returnType('action');
		}

		return $options;
	}


	##
	##	 Case
	##	

	if ($cmd eq 'lc'){
		return $self->help($cmd) if ($options!~/\w/);
		return lc ($options);
	}

	if ($cmd eq 'uc'){
		return $self->help($cmd) if ($options!~/\w/);
		return uc ($options);
	}

	if ($cmd eq 'ucwords'){
		return $self->help($cmd) if ($options!~/\w/);
		$options = join " ", map {ucfirst} split / /, $options;
		return ($options);
	}

	if ($cmd eq 'ucsent'){
		return $self->help($cmd) if ($options!~/\w/);
		#my @sent = split / \./, $options;
		$options = join ". ", map {ucfirst} split /\.\s+/, $options;
		$options = join "? ", map {ucfirst} split /\?\s+/, $options;
		$options = join "! ", map {ucfirst} split /\!\s+/, $options;
		return ($options);
	}


	
	##
	##	Trims
	##	

	if ($cmd eq 'ltrim'){
		return $self->help($cmd) if ($options!~/\w/);
		$options=~s/^\s+//;
		return ($options);
	}

	if ($cmd eq 'rtrim'){
		return $self->help($cmd) if ($options!~/\w/);
		$options=~s/\s+$//;
		return ($options);
	}

	if ($cmd eq 'trim'){
		return $self->help($cmd) if ($options!~/\w/);
		$options=~s/\s+$//;
		$options=~s/^\s+//;
		return ($options);
	}


	##
	##	bolding & whatnot
	##	

	if ($cmd eq 'bold'){
		return $self->help($cmd) if ($options!~/\w/);
		return (BOLD.$options.NORMAL);
	}

	if ($cmd eq 'underline'){
		return $self->help($cmd) if ($options!~/\w/);
		return (UNDERLINE.$options.NORMAL);
	}

	if ($cmd eq 'inverse'){
		return $self->help($cmd) if ($options!~/\w/);
		return (REVERSE.$options.NORMAL);
	}





	##
	## strpos
	##

	if ($cmd eq 'strpos'){
		return $self->help($cmd) if ($options!~/(.+?) (.+?)$/);
		my $key = $1;
		my $str = $2;
		my $output ="";

		my @tokens = split(/ /, $str);
		for(my $i=0; $i<@tokens; $i++){
			if ($tokens[$i] eq $key){
				if ($output){
					$output .= ", " . ($i+1);
				}else{
					$output = ($i+1);
				}
			}
		}

		if ($output=~/,/){
			return ("$key found at positions: $output");
		}else{
			return ("$key found at position: $output");
		}

	}

	##
	##	Translate
	##

	if ($cmd eq 'tr'){
		return $self->help($cmd) if ($options!~/(.+?)\s+(.+?)\s+(.+?)$/);
		my $start = $1;
		my $end = $2;
		my $str = $3;
	
		if ($self->hasFlag("i")){
			$str=~s/$start/$end/gi;
		}else{
			$str=~s/$start/$end/g;
		}
		return ($str);
	}

	##
	##	grep
	##

	if ($cmd eq 'grep'){
		my $pattern;

		if ($self->hasFlag("p")){
			$pattern = $self->hasFlagValue("p");
		}else{
			$options=~s/^(.+?) //;
			$pattern = $1;
		}

		my $pos = index($options, $pattern);

		if ($pos >= 0){
			my $start = $pos - 40;
			my $run = length($pattern) + 80;

			if ($start < 0){
				$start = 0;
			}
			
			return substr($options, $start, $run);
		}else{
			return "not found";
		}
	}

	##
	## Scramble
	##

	if ($cmd eq 'scramble'){
		return $self->help($cmd) if ($options!~/(.+?)$/);
	
		my $input = $options;

		if ($self->hasFlag("w")){
			my @words = split / /, $input;

			foreach my $word (@words){
				my @letters = split //, $word;
				my $i= @letters;
				while ( --$i ){
					my $j = int rand( $i+1 );
					@letters[$i,$j] = @letters[$j,$i];
				}

				foreach my $letter (@letters){
					$output.=$letter;
				}

				$output.= " ";
			}
			$output =~s/ $//;
		}
	
		if ($output){
			$input = $output;
		}

		if ($self->hasFlag("m")){
			$output = "";
			my @words = split / /, $input;
			my $i= @words;
			while ( --$i ){
				my $j = int rand( $i+1 );
				@words [$i,$j] = @words[$j,$i];
			}
			
			foreach my $word (@words){
				$output.="$word ";
			}
			$output =~s/ $//;
		}

		if (!$output){		# No flags
			my @letters= split //, $options;
			my $i= @letters;
			while ( --$i ){
				my $j = int rand( $i+1 );
				@letters[$i,$j] = @letters[$j,$i];
			}
			
			foreach my $l (@letters){
				$output.=$l;
			}
			
		}

		return $output;
	}


	##
	##	Cut
	##

	if ($cmd eq 'cut'){
		return $self->help($cmd) if ($options!~/\w/);

		if (my $range= $self->hasFlagValue("c")){
			return $self->help($cmd) if ($range!~/-/);

			my $stop;
			my($start, $end) = split /-/, $range;

			$start-=1;

			if (!$end){
				$stop=9999;
			}else{
				$stop = (($end-1) - $start);
			}
			return substr($options, $start, $stop);
		}
	
		if (my $fieldlist = $self->hasFlagValue("f")){
			my $temp = $fieldlist;
			$temp=~s/[0-9]//gis;
			$temp=~s/,//gis;

			if ($temp){
				return $self->help( ($cmd, "-f"));
			}
			
			my $delimiter = $self->hasFlagValue("d");
			if (!$delimiter){
				$delimiter = " ";
			}
	
			my $output_delimiter = $self->hasFlagValue("od");
			if (!$output_delimiter){
				$output_delimiter=" ";
			}

			my @fields = split /,/, $fieldlist;
			my @tokens = split /$delimiter/, $options;

			foreach my $field (@fields){
				next if ($field > @tokens);

				if ($output){
					$output .= $output_delimiter . $tokens[$field-1];
				}else{
					$output .= $tokens[$field-1];
				}
			}

			return $output;
		}
	}


	##
	##	Banner.  I'm really sorry about this.
	##	
	if ($cmd eq "banner"){
		return $self->help($cmd) if ($options eq "");

		my $lshade = "\x{2591}";
		my $dshade = "\x{2593}";
		my $font = {
		0=>".xxxxxx../xxx..xxx./xx..xxxx./xx.xx.xx./xxx..xxx./.xxxxxx../",
		1=>".xx./xxx./.xx./.xx./.xx./.xx./",
		2=>"xxxxxxx./xx..xxx./...xxxx./.xxxx.../xxxx..../xxxxxxx./",
		3=>"xxxxxxx./xx..xxx./..xxxxx./..xxxxx./xx...xx./xxxxxxx./",
		4=>"..xxxx../.xxxxx../xxx.xx../xxxxxxx./....xx../....xx../",
		5=>"..xxxxx./.xxxxxx./xx....../xxxxxxx./....xxx./xxxxxxx./",
		6=>"...xx.../..xxx.../.xxx..../xxxxxxx./xxx.xxx./xxxxxx../",
		7=>"xxxxxxx./xx..xxx./...xxx../..xxx.../.xxx..../xxx...../",
		8=>"xxxxxxx./xx...xx./xxxxxxx./xxxxxxx./xx...xx./xxxxxxx./",
		9=>"xxxxxxx./xxx.xxx./xxxxxxx./...xxx../..xxx.../.xxx..../",
		a=>".xxxxx../xxx.xxx./xxxxxxx./xxxxxxx./xx...xx./xx...xx./",
		b=>"xxxxxxx./xx..xxx./xxxxxxx./xxxxxxx./xx...xx./xxxxxxx./",
		c=>".xxxxxx./xxx..xx./xx....../xx....../xxx..xx./.xxxxxx./",
		d=>"xxxxxxx./xx..xxx./xx...xx./xx...xx./xx..xxx./xxxxxxx./",
		e=>"xxxxxxx./xxx...../xxxxxxx./xxxxxxx./xxx...../xxxxxxx./",
		f=>"xxxxxxx./xxx...../xxxxx.../xxxxx.../xx....../xx....../",
		g=>".xxxxx../xxx.xxx./xx....../xx..xxx./xxx.xxx./.xxxxx../",
		h=>"xx...xx./xx...xx./xxxxxxx./xxxxxxx./xx...xx./xx...xx./",
		i=>"xxxxxxxx./..xxxx.../...xx..../...xx..../..xxxx.../xxxxxxxx./",
		j=>"...xxxx./...xxxx./....xx../....xx../xxx.xx../xxxxxx../",
		k=>"xx...xx./xx.xxxx./xxxxx.../xxxxx.../xx.xxxx./xx...xx./",
		l=>"xx....../xx....../xx....../xx....../xxxxxxx./xxxxxxx./",
		m=>"xxxx..xxxx./xxxxxxxxxx./xx..xx..xx./xx..xx..xx./xx..xx..xx./xx..xx..xx./",
		n=>"xxx...xx./xxxx..xx./xxxxx.xx./xx.xxxxx./xx..xxxx./xx...xxx./",
		o=>".xxxxxx../xxx..xxx./xx....xx./xx....xx./xxx..xxx./.xxxxxx../",
		p=>"xxxxxxx./xx..xxx./xxxxxxx./xxxxx.../xx....../xx....../",
		q=>".xxxxxx../xxx..xxx./xx....xx./xx....xx./xxx..xxx./.xxxxxx../",
		r=>"xxxxxxx./xx..xxx./xxxxxxx./xxxxx.../xx.xxxx./xx...xx./",
		s=>"xxxxxxx./xxx..xx./xxxxx.../..xxxxx./xx...xx./xxxxxxx./",
		t=>"xxxxxxxx./xxxxxxxx./...xx..../...xx..../...xx..../...xx..../",
		u=>"xx....xx./xx....xx./xx....xx./xx....xx./xxx..xxx./xxxxxxxx./",
		v=>"xx....xx./xx....xx./xx....xx./xxx..xxx./.xxxxxx../...xx..../",
		w=>"xx...xxx...xx./xx...xxx...xx./xx...xxx...xx./xx...xxx...xx./xxx.xxxxx.xxx./.xxxxx.xxxxx../",
		x=>"xx....xx./xxx..xxx./.xxxxxx../.xxxxxx../xxx..xxx./xx....xx./",
		y=>"xx....xx./xxx..xxx./.xxxxxx../...xx..../...xx..../...xx..../",
		z=>"xxxxxxx./xx..xxx./...xxx../..xxx.../.xxx.xx./xxxxxxx./",
		','=>".../.../.../xx./xx./.x./",
		'!'=>"xx./xx./xx./xx./.../xx./",
		'>'=>"xx...../.xxx.../...xxx./...xxx./.xxx.../xx...../",
		'<'=>"...xxx./.xxx.../xx...../xx...../.xxx.../...xxx./",
		')'=>"xx...../.xxx.../...xxx./...xxx./.xxx.../xx...../",
		'('=>"...xxx./.xxx.../xx...../xx...../.xxx.../...xxx./",
		'.'=>".../.../.../.../xx./xx./",
		'?'=>"xxxxxxx./xx..xxx./...xxxx./..xxx.../......../..xx..../",
		';'=>"xx./xx./.../xx./xx./.x./",
		' '=>".../.../.../.../.../.../"
		};

		my $test_str = $options;
		$test_str=~s/\w|\?|\!|\>|\<| |,|\.|;|\)|\(//g;
		return "invalid characters" if ($test_str);
	
		my @letters = split //, lc($options);
		my @word;

		foreach  my $letter (@letters){
			if (@word){
				my @lines = split /\//, $font->{$letter};
				for (my $i=0; $i<@lines; $i++){
					$word[$i] .= "." . $lines[$i];
				}

			}else{
				@word = split /\//, $font->{$letter};
			}
		}

		if (length($word[0]) > 48){
			return "$options is too long";
		}

		for (my $i=0; $i<@word; $i++){
			$word[$i]=~s/\./$lshade/gis;
			$word[$i]=~s/x/$dshade/gis;
		}
		push @word, $lshade x length($word[0]);
		unshift @word, $lshade x length($word[0]);

		return \@word;
	}
	
}

sub listeners{
   my $self = shift;

   ##Command Listeners - put em here.  eg ['one', 'two']
   my @commands = ['rainbow', 'listcolors', 'color', 'echo','lc','uc','ucwords','cut',
						'rtrim', 'ltrim', 'trim', 'tr','strpos','scramble', 'banner', 'ucsent',
						'bold', 'underline' ,'inverse', 'grep'];

	my @irc_events = [];

   my $default_permissions =[
			{command=>"banner", require_users => ["$self->{BotOwnerNick}"] },
			{command=>"echo", flag=>'channel', require_group => UA_TRUSTED }
			];
   return {commands=>@commands, permissions=>$default_permissions, irc_events=>@irc_events};
}

sub addHelp{
   my $self = shift;
   $self->addHelpItem("[plugin_description]", "A collection of text utilities.");
   $self->addHelpItem("[banner]", "Print out an old sk00l banner. This may well get the bot kicked for flooding.  Usage:  banner <text>");
   $self->addHelpItem("[color]", "Color up some text.  Usage: color <color> <text>");
   $self->addHelpItem("[echo]", "Repeat something. Usage: echo <text> [-channel=<#channel>] [-action]");
   $self->addHelpItem("[lc]", "Translate to lower case.  Usage: lc <text>");
   $self->addHelpItem("[listcolors]", "Prints all of the IRC colors");
   $self->addHelpItem("[rainbow]", "Usage: rainbow <text>.  Options [-w], [-c=<number>]");
   $self->addHelpItem("[rainbow][-w]", "Make a rainbow splitting on words.  Usage: rainbow -w <text>");
   $self->addHelpItem("[rainbow][-c]", "Make a rainbow splitting on X characters.  Usage: rainbow -c=<number> <text>");
   $self->addHelpItem("[bold]", "Usage: bold <text>");
   $self->addHelpItem("[underline]", "Usage: underline <text>");
   $self->addHelpItem("[inverse]", "Usage: inverse <text>");
   $self->addHelpItem("[uc]", "Translate to upper case. Usage: uc <text>");
   $self->addHelpItem("[ucwords]", "Upper case the first letter of each word. Usage: uc <text>");
   $self->addHelpItem("[ucsent]", "Upper case the first letter of each sentence. Poorly. Usage: ucsent <text>");
   $self->addHelpItem("[cut]", "Cut a string.  Usage: cut [-c=<range>] [-f=<list,of,fields> [-d=<delimiter>]] <string>");
   $self->addHelpItem("[cut][-c]", "Cut a string using x-y character range.  Example: cut -c=7-20 antidisestablishmentarianism");
   $self->addHelpItem("[cut][-f]", "Cut a string and return fields specified by comma delimited list.  Example: cut -f=2,3,4 These pretzels are making me thirsty. Use [-d=<val>] to specify a delimiter, default is space. Use [-od] to specify an output delimiter.");
   $self->addHelpItem("[cut][-d]", "Specify a delimiter to cut on. Use with -f");
   $self->addHelpItem("[cut][-od]", "Specify an output delimiter.  Use with -f");
   $self->addHelpItem("[rtrim]", "trim whitespace from the right side of a string.");
   $self->addHelpItem("[ltrim]", "trim whitespace from the left side of a string.");
   $self->addHelpItem("[trim]", "trim whitespace from both sides of a string.");
   $self->addHelpItem("[tr]", "Change (translate) this to that in a string.  Usage: tr <this> <that> <string>. Flags: -i (case insensitive)");
   $self->addHelpItem("[strpos]", "Get the position of <word> in a string.  Usage: pos <word> <string>.");
   $self->addHelpItem("[grep]", "Grep for a pattern in very long string. This happens before a line is paginated.  Usage: grep <pattern> <string>, or use the -p=\"<pattern>\" flag.  Most useful with pipes.  Example: ~inventory | grep Pacman");
   $self->addHelpItem("[scramble]", "Scramble the letters in a string.  Usage: scramble [<-w><-m>] <string>.");
   $self->addHelpItem("[scramble][-w]", "Scramble each word within a string.  Usage: scramble -w <string>.");
   $self->addHelpItem("[scramble][-m]", "Scramble the order of the words in a string.  Usage: scramble -wm <string>.");


}

1;
__END__
