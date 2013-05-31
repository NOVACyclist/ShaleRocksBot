RocksBot
========

Rocksbot is a Perl IRC bot based on the Perl Object Environment (POE) framework.  Rocksbot is multi-threaded, can run as a daemon (if desired), and is extensible via plugins.  Sample plugins are provided.

Rocksbot supports user accounts and has a highly customizable permissions system, as well as a built-in help system. Built-in functions make saving and retrieving data, grabbing URLS, publishing HTML pages, and shortening URL's a snap.  All data is stored in a sqlite database.

Rocksbot makes use of "command line" flags to make argument order less important.  (Example:  login -password=blah).

Commands can be piped, similar to many *nix command shells.  (Example: To get a fortune, translate it to german, then color the output like a rainbow:  .fortune | german | rainbow )

Rocksbot is licensed according to the terms of the GNU General Public License, version 3 (GPLv3).

Installation:

1.  Download and extract the package, or issue a git pull.
2.  Create the makefile:  perl ./Makefile.PL
3.  Run the makefile to install required packages: make
4.  Copy rocksbot.cfg.sample to rocksbot.cfg. 
5.  Edit rocksbot.cfg with your desired settings.
6.  Execute the program with ./rocksbot.pl

See the "INSTALL" file for additional details.

Getting started:

On first run, an admin user will be created using the username and password specified in the config file.  You should log-in (login -username=whatever -password=whatever) and change the admin password.

To get information about the installed plugins, issue the .help command.  (Assuming that you're using a . as the bot command prefix.)  To get a list of commands contained in each plugin, issue a .help PluginName.  To get help with a particular command, issue a .help CommandName, or .help PluginName CommandName.  To get information about a command + flag combo, use .help CommandName -flag.  To get general information about a command or plugin, use .help --info.

