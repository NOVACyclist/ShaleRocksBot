package plugins::Imgur;
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
use Digest::MD5 qw(md5_hex);

sub getOutput {
    my $self = shift;
    my $cmd = $self->{command}; 
    my $options = $self->{options};
    
    $self->suppressNick("true");

    if ($cmd eq 'imgur_stats'){
        my $runs = $self->globalCookie("total_tries") || 0;
        my $hits = $self->globalCookie("hits") || 0;
        my $misses = $self->globalCookie("misses") || 0;
        my $mg = $self->globalCookie("monopoly_guy") || 0;
        
        my $full = sprintf("%.2f", $hits/$runs * 100);
        my $popularity = sprintf("%.2f", $mg/$hits);
        my $num_monopoly_guys = sprintf("%d", 62**5 * $full / 100  * $popularity);
        my $pm = int($num_monopoly_guys * sqrt($mg) / $mg);
        $pm = $self->commify($pm);
        $num_monopoly_guys = $self->commify($num_monopoly_guys);

        my $ret = "I have requested $runs randomly generated image id's from imgur. There have been $hits hits and $misses misses. I have seen the Monopoly Guy $mg times. Based on these numbers, the imgur 5-character namespace is $full% full, and $num_monopoly_guys +/- $pm copies of Monopoly Guy live on imgur. ";
        
        if ($mg){
            my $mg_den = int ($hits / $mg);
            $ret.="Roughly 1/$mg_den images is Monopoly Guy.";
        }

        return $ret;
    }

    # The md5 of the not found image
    my $NF = 'd835884373f4d6c8f24742ceabe74946';
    
    # The md5 of the monopoly guy
    my $MG = 'd5dad890bfc37eccf1226453410a0db2';

    my $tries = 10;

    while ($tries--){
        my $id = $self->getRandID();
        $self->globalCookie("total_tries", ($self->globalCookie("total_tries") || 0) + 1);
        my $image = $self->getPage("http://i.imgur.com/" . $id . '.jpg');

        if (md5_hex($image) eq $NF){
            $self->globalCookie("misses", ($self->globalCookie("misses") || 0) + 1);
            next;
        }

        if (md5_hex($image) eq $MG){
            $self->globalCookie("monopoly_guy", ($self->globalCookie("monopoly_guy") || 0) + 1);
        }

        $self->globalCookie("hits", ($self->globalCookie("hits") || 0) + 1);
        return BOLD."A random image from imgur: ".NORMAL.GREEN.UNDERLINE."http://i.imgur.com/$id.jpg".NORMAL."  (Note: Nondeterministically NSFW)";
    }
    
}

sub commify {
   my $self = shift;
   my $num  = shift;
   $num = reverse $num;
   $num=~ s/(\d\d\d)(?=\d)(?!\d*\.)/$1,/g;
   return scalar reverse $num;
}


sub getRandID{
    no strict;
   my @chars=("A".."Z","a".."z",0..9);
   my $str = "";
   for (my $i=0;$i<5; $i++){
      $str .= $chars[int rand @chars];
   }
   return $str;
}


sub listeners{
    my $self = shift;
    
    my @commands = [qw(imgur imgur_stats)];

    my $default_permissions =[ ];

    return { commands=>@commands, permissions=>$default_permissions };

}

sub addHelp{
    my $self = shift;
    $self->addHelpItem("[plugin_description]", "Get a random image from imgur.");
    $self->addHelpItem("[imgur]", "Get a random image from imgur");
}
1;
__END__
