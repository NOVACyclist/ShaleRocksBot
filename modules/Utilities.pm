package modules::Utilities;
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
our @EXPORT = qw(FLAG_ON parseFlags);

use constant FLAG_ON => "_bTrue";

BEGIN {
  $modules::Utilities::VERSION = '1.0';
}

use strict;
use warnings;

use Data::Dumper;
use Text::ParseWords;

## 
##  jfc is it hard to parse flags when you don't know what sort
## of flags you're looking for.  Perl's parsewords is broken, btw.
## Unmatched delimiters (i.e. apostrophes) kill it. And not gracefully, either,
## it just returns nothing.  Escaping them doesn't help. 
##
sub parseFlags{
    my $options = shift;

    #print "OPTIONS : $options\n";
    if (!$options){
        return ({flags=>{}, options=>""});
    }

    #$options=~s/^ +//gis;
    my $FLAGS;
    my $new_options="";
    
    $options=~s/'/_BITEME_PARSEWORDS_/g;
    my @tokens = parse_line('\s+|=','delimiters',$options);

    # this line has a problem in that it skips -flag=0
    # so adding the temp_arr stuff instead
    # @tokens = grep { $_ && !m/^$/ } @tokens;

    my @temp_arr;
    foreach my $temp (@tokens){
        if ($temp=~/^$/){
            #skip blanks
        }else{
            push @temp_arr, $temp;
        }
    }
    @tokens = @temp_arr;

    foreach my $t (@tokens){
        $t=~s/_BITEME_PARSEWORDS_/'/gis;
    }
    #print "---------tokens-----------\n";
    #print Dumper (@tokens);
    #print "------end tokens----------\n";

    my $done_parsing = 0;
    my $flag_pos =0 ;

    for(my $i=0; ($i<@tokens) && (!$done_parsing); $i++){
        my $token = $tokens[$i];
        
        if ($token=~/^-(.+?)$/){                        # matched a flag 
            my $token_name = $1;
            $FLAGS->{$token_name} = FLAG_ON; # we know that it's at least true.  might have a val
            $FLAGS->{$token_name . '_pos'} = ++$flag_pos;
            my $j=$i+1;

            my $done_looking = 0;
        
            do {
                if ($j >= @tokens){
                    $done_looking = 1;
                }else{
                    if ($tokens[$j] eq '='){                #ok, we know it's an assignment
                        while($tokens[$j] !~/\w|\*/){
                            if ($j >= (@tokens - 1 )){
                                $done_looking = 1;
                                #$done_parsing = 1;
                                last;
                            }else{
                                $j++;
                            }
                            #last if ($j>30);                       #temp hack for options = " "  xyzzy
                        }
                        if ($tokens[$j] ne '='){
                            $FLAGS->{$token_name} = $tokens[$j];
                        }
                        $i = $j;
                        $done_looking = 1;

                    }elsif($tokens[$j] eq ""){
                        # we know nothing

                    }elsif($tokens[$j] eq " "){
                        #we know nothing

                    }elsif($tokens[$j] eq '|'){
                        #print "done on pipe\n";
                        $done_looking=1;
                        $done_parsing=1;

                    }elsif($tokens[$j]=~/^(-|\w)/){
                        #this is a flag or a word, no = encountered, must be boolean flag
                        $done_looking=1;
                    }
                }

                $j++;
            }while (!$done_looking);

            if ($done_parsing){
                while (++$i < @tokens){
                    $tokens[$i]=~s/^"(.+?)"$/$1/;
                    $new_options.=$tokens[$i];  
                    #$i++;
                }
                last;
            }
        }else{
            $tokens[$i]=~s/^"(.+?)"$/$1/;
            $new_options.=$tokens[$i];
        }
    }

    #print "new options is $new_options\n";
    $new_options=~s/^ +//;
    $new_options=~s/ +$//;
    $new_options=~s/_BITEME_PARSEWORDS_/'/g;
    if ($FLAGS){
        foreach my $flag (keys $FLAGS){
            $FLAGS->{$flag}=~s/_BITEME_PARSEWORDS_/'/gis;
            $FLAGS->{$flag}=~s/^"(.+?)"$/$1/;
            #print "Flag is now $FLAGS->{$flag}\n";
        }
    }

    #print "New option string: $new_options\n";

    return ({flags=>$FLAGS, options=>$new_options});
}


1;
__END__
