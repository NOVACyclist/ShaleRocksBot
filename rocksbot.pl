#!/usr/bin/perl
#   RocksBot
#   Usage: rocksbot.pl  (will read rocksbot.cfg in local directory)
#   or: rocksbot.pl <config filename>   (will read specified config file)
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
use modules::RocksBot;
use constant RocksBot => 'modules::RocksBot';
use Cwd qw(abs_path getcwd);

my $config_file;

## Look for config file on command line
if (@ARGV){
    my $full_name = abs_path($ARGV[0]);
    if (! -f $full_name){
        die "Couldn't find that file: $ARGV[0]";
    }

    $config_file = $full_name;
}else{
    my $cwd = getcwd();
    $config_file = "$cwd/rocksbot.cfg";
}

my $RocksBot = RocksBot->new($config_file);
exit;
