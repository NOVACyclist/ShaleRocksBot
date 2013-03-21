use inc::Module::Install;
use strict;
use warnings;

name     'RocksBot';
perl_version '5.10';
author 'Egrets R. Herons <egretsareherons@gmail.com>';
license 'gpl';
version_from 'modules/RocksBot.pm';

requires 'LWP::UserAgent';
requires 'POE::Component::IRC';
requires 'POE::Component::Generic';
requires 'IRC::Utils';
requires 'Config::Simple';
requires 'Module::Reload';
requires 'DBD::SQLite';
requires 'JSON';
requires 'Net::LastFM';
requires 'Date::Manip';
requires 'Net::Twitter::Lite';
requires 'XML::Feed';
requires 'WWW::WolframAlpha';

auto_install;

WriteAll;
