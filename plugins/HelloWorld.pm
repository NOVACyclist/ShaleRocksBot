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
# this is an example of the minimum required for a plugin that does something useful.
# you need getOutput(), listeners(), and addHelp().
# It's also an example of how "cookies" work.  Cookies are just a collection all dressed up
# for easy access.
package plugins::HelloWorld;
use strict;         
use warnings;
use base qw (modules::PluginBaseClass);
use modules::PluginBaseClass;

# getOutput is your "main" loop.
sub getOutput {
    my $self = shift;
    my $options = $self->{options};
    my $nick = $self->accountNick();

    # check for the clear flag
    if ($self->hasFlag("clear")){
        $self->deleteGlobalCookie("hello");     # this deletes the one plugin's cookie
        $self->deleteCookie("hello");               # this deletes this one user's cookie

        # but none of those touched the other users' cookies. so we should have just called this:
        $self->deletePackageCookies(); 
        return "Baleeted.";
    }

    # let's do something useful like count the number of times a user has said hello.
    # the cookie function is user-specific
    my $user_hellos = $self->cookie("hello");
    $user_hellos++;
    $self->cookie("hello", $user_hellos);


    # and lets keep track of the the total number of hellos. globalcookie() is plugin-specific
    my $total_hellos = $self->globalCookie("hello");
    $total_hellos++;
    $self->globalCookie("hello", $total_hellos);

    return "Hello, $nick. You have now said hello to me $user_hellos times. I have said hello to different people $total_hellos times.";

}


# this is where you tell the bot which commands you're interested in.
sub listeners{
    my $self = shift;
    
    my @commands = [qw(hello)];

    return {commands=>@commands };
}


# the help system will use this to help.
sub addHelp{
    my $self = shift;
    $self->addHelpItem("[plugin_description]", "This is an example of a little more than the bare minimum required for a plugin to function. It's also an example of how to use cookies.  Use hello -clear to clear the cookies database.");
   $self->addHelpItem("[hello]", "Usage: hello");
   $self->addHelpItem("[hello][-clear]", "Clear the hello database.");
}
1;
__END__
