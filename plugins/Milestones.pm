package plugins::Milestones;
#---------------------------------------------------------------------------
#    ShaleRocksBot - Milestones
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
#
#  Tells people what their next badge milestone is and how far away it is.
#
#  The Badges plugin already answers "what day am I on". Nobody was ever told
#  what is COMING -- someone sitting on day 88 had no way to know 90 was two
#  days out. This reads the existing Badges data and answers that. It stores
#  nothing of its own.
#
#  ON-DEMAND ONLY, DELIBERATELY. These are recovery channels. The bot never
#  announces a milestone on its own: a day count is the user's to share, and
#  someone whose count has just reset should not have that noticed for them.
#  Every output here is the direct result of somebody typing the command.
#
use strict;
use warnings;
use base qw (modules::PluginBaseClass);
use modules::PluginBaseClass;
use Date::Manip;
use Time::Local qw(timegm);

##  Badges lives in its own collection namespace; read it by name.
use constant BADGE_PACKAGE => 'plugins::Badges';

##  Milestones worth marking, in days. Deliberately generous at the start --
##  in early recovery the short ones are the ones that matter -- then round
##  numbers and year anniversaries after that.
sub milestoneList {
    my @m = (1, 7, 14, 21, 30, 60, 90, 100, 120, 150, 180, 270);

    ##  Every 100 days out to 1000.
    for (my $d = 200; $d <= 1000; $d += 100) { push @m, $d; }

    ##  Year anniversaries. 365.25 keeps them from drifting off the real date
    ##  over long spans -- this database has people past 16,000 days.
    for my $y (1 .. 60) { push @m, int(365.25 * $y + 0.5); }

    ##  Round thousands, which people notice as much as anniversaries.
    for (my $d = 1000; $d <= 25000; $d += 1000) { push @m, $d; }

    my %seen;
    return sort { $a <=> $b } grep { !$seen{$_}++ } @m;
}

##  Human label for a milestone, so "1826" reads as "5 years".
sub milestoneLabel {
    my ($self, $days) = @_;

    for my $y (1 .. 60) {
        return ($y == 1 ? "1 year" : "$y years") if ($days == int(365.25 * $y + 0.5));
    }
    return "$days days";
}

##  Next milestone strictly after $days, or undef if they are past the lot.
sub nextMilestone {
    my ($self, $days) = @_;
    foreach my $m ($self->milestoneList()) {
        return $m if ($m > $days);
    }
    return undef;
}

##  Most recent milestone at or before $days, or undef if they are short of
##  the first one.
sub lastMilestone {
    my ($self, $days) = @_;
    my $last;
    foreach my $m ($self->milestoneList()) {
        last if ($m > $days);
        $last = $m;
    }
    return $last;
}

##  Days since a badge start date, matching Badges' own count exactly
##  (including its +1, so "day 1" is the start date itself).
##
##  Fast path first. Badges stores YYYYMMDDHH:MM:SS, and Date::Manip needs
##  roughly 7ms to parse one -- fine for a single badge, but the -channel
##  scan covers every badge in the database and took 30 SECONDS that way.
##  A CommandHandler worker is blocked for the whole call, and there are only
##  three of them, so that was enough for three users to stall the bot.
##  Plain arithmetic on the known format is ~1000x faster; Date::Manip stays
##  as the fallback for anything not in that shape.
##
##  Both paths anchor at midday UTC so daylight-saving shifts can never round
##  a day count up or down.
sub daysSince {
    my ($self, $date_str) = @_;

    return undef if (!defined $date_str || $date_str eq '');

    if ($date_str =~ /^(\d{4})(\d{2})(\d{2})/) {
        my ($y, $m, $d) = ($1, $2, $3);

        if ($m >= 1 && $m <= 12 && $d >= 1 && $d <= 31) {
            my $then = eval { timegm(0, 0, 12, $d, $m - 1, $y) };

            if (defined $then) {
                my @n   = gmtime(time);
                my $now = timegm(0, 0, 12, $n[3], $n[4], $n[5] + 1900);
                my $days = int(($now - $then) / 86400);
                return ($days >= 0) ? $days + 1 : $days;
            }
        }
    }

    my $date = new Date::Manip::Date;
    my $err  = $date->parse($date_str);
    return undef if ($err);

    my $now = new Date::Manip::Date;
    $now->parse("today");

    my @dv   = $date->calc($now)->value();
    my $days = int($dv[4] / 24);

    return ($days >= 0) ? $days + 1 : $days;
}

##  How near a milestone has to be to be worth mentioning, in days either side.
##
##  Scales with how long someone has been going, because the two audiences
##  need opposite things. Somebody counting their first month checks in daily
##  and wants the exact day -- telling them "around 30 days" is useless and
##  slightly insulting. Somebody at ten years may look in once a month, so a
##  one-day window means they simply never see their own anniversary. The
##  further out you are, the wider the net.
sub milestoneWindow {
    my ($self, $days) = @_;

    return 0  if ($days < 90);      # first 90 days: exact, no fuzz
    return 1  if ($days < 365);     # first year
    return 3  if ($days < 1826);    # under 5 years
    return 7  if ($days < 3653);    # under 10 years
    return 14;                      # 10 years and beyond
}

##  All badges for one nick, as {name, days}, newest-progress first.
sub badgesFor {
    my ($self, $nick) = @_;
    my @out;

    return @out if (!defined $nick || $nick eq '');

    my $c = $self->getCollection(BADGE_PACKAGE, $nick);
    foreach my $rec ($c->getAllRecords()) {
        next if (!defined $rec->{val1} || $rec->{val1} eq '');
        next if (!defined $rec->{val2} || $rec->{val2} eq '');

        my $days = $self->daysSince($rec->{val2});
        next if (!defined $days || $days < 0);

        push @out, { name => $rec->{val1}, days => $days };
    }
    return @out;
}

sub getOutput {
    my $self    = shift;
    my $options = $self->{options};
    my $channel = $self->{channel};

    return $self->help('milestones') if ($self->hasFlag('h') || $self->hasFlag('help'));

    ##  -channel : who in here reaches a milestone today.
    return $self->channelToday($channel) if ($self->hasFlag('channel'));

    ##  Whose milestones? A bare argument or -nick=, else your own account.
    my $who = $self->hasFlagValue('nick') || $options || $self->accountNick();
    $who =~ s/^\s+//;
    $who =~ s/\s+$//;

    my @badges = $self->badgesFor($who);

    if (!@badges) {
        return "$who doesn't have any badges set. Use the badge command to add one."
            if ($who ne $self->accountNick());
        return "You don't have any badges yet. Use the badge command to set one, "
             . "then I can tell you what's coming up.";
    }

    ##  Report the soonest milestone first -- that is the useful one.
    my @lines;
    foreach my $b (@badges) {
        my $window = $self->milestoneWindow($b->{days});

        ##  Did they just go past one? Someone at ten years may only look in
        ##  once a month, and "you passed it nine days ago" is the whole point
        ##  of the command for them. Newbies get window 0 and never see this.
        my $passed = $self->lastMilestone($b->{days});
        if (defined $passed && $window > 0 && ($b->{days} - $passed) <= $window
            && $b->{days} != $passed) {
            my $ago = $b->{days} - $passed;
            push @lines, {
                to  => -1,   # sorts ahead of anything upcoming
                txt => "$b->{name}: day $b->{days} -- you passed "
                     . $self->milestoneLabel($passed)
                     . ($ago == 1 ? " yesterday" : " $ago days ago"),
            };
            next;
        }

        my $next = $self->nextMilestone($b->{days});
        if (!defined $next) {
            push @lines, { to => 999999,
                           txt => "$b->{name}: day $b->{days}, and past every milestone I know about" };
            next;
        }

        my $to    = $next - $b->{days};
        my $label = $self->milestoneLabel($next);
        my $when  = $to == 1 ? "tomorrow" : "in $to days";

        push @lines, { to  => $to,
                       txt => "$b->{name}: day $b->{days} -- $label $when" };
    }

    @lines = sort { $a->{to} <=> $b->{to} } @lines;

    my $out = ($who eq $self->accountNick()) ? "Your next milestones: " : "$who: ";
    $out .= join(" " . $self->BULLET . " ", map { $_->{txt} } @lines);

    return $out;
}

##  Anyone in this channel hitting a milestone today.
##
##  Scans every badge in the database via the '%' wildcard collection, the
##  same way Badges' own listing does. That is ~4k rows, which is fine for a
##  command someone typed, but it is why this is not on a timer.
sub channelToday {
    my ($self, $channel) = @_;

    my $c = $self->getCollection(BADGE_PACKAGE, '%');
    my @hits;

    foreach my $rec ($c->getAllRecords()) {
        next if (!defined $rec->{val1} || !defined $rec->{val2});
        next if ($rec->{val1} eq '' || $rec->{val2} eq '');

        my $days = $self->daysSince($rec->{val2});
        next if (!defined $days || $days <= 0);

        ##  Within this person's window of a milestone? The window widens the
        ##  longer they have been going -- see milestoneWindow. Without it a
        ##  ten-year anniversary is visible for exactly one day, to someone
        ##  who may not look in that day.
        my $window = $self->milestoneWindow($days);

        my $hit;
        foreach my $m ($self->milestoneList()) {
            if (abs($m - $days) <= $window) { $hit = $m; last; }
            last if ($m > $days + $window);
        }
        next if (!defined $hit);

        my $off  = $days - $hit;
        my $when = $off == 0  ? "today"
                 : $off == 1  ? "yesterday"
                 : $off == -1 ? "tomorrow"
                 : $off > 0   ? "$off days ago"
                 :              abs($off) . " days away";

        push @hits, { nick  => $rec->{collection_name},
                      name  => $rec->{val1},
                      days  => $days,
                      when  => $when,
                      exact => ($off == 0 ? 1 : 0),
                      label => $self->milestoneLabel($hit) };
    }

    return "No milestones around right now that I can see."
        if (!@hits);

    ##  Exact-today first, then longest-running -- so the biggest anniversaries
    ##  lead rather than being buried behind a dozen 30-day marks.
    @hits = sort { $b->{exact} <=> $a->{exact} || $b->{days} <=> $a->{days} } @hits;

    ##  The pager offers the rest via the more command.
    my $out = "Milestones: ";
    $out .= join(" " . $self->BULLET . " ",
                 map { "$_->{nick} -- $_->{label} of $_->{name}"
                       . ($_->{exact} ? "" : " ($_->{when})") } @hits);

    return $out;
}

sub listeners {
    my $self = shift;
    my @commands = [qw(milestones)];

    ##  Read-only over data the badge command already exposes, so it carries
    ##  the same access level rather than a stricter one.
    my $default_permissions = [ { command => "milestones", require_group => UA_UNREGISTERED } ];

    return { commands => @commands, permissions => $default_permissions };
}

sub addHelp {
    my $self = shift;

    $self->addHelpItem("[plugin_description]",
        "Tells you what your next badge milestone is and how many days away it is. "
      . "Reads the badges you already set with the badge command; it stores nothing itself "
      . "and never announces anything on its own.");

    $self->addHelpItem("[milestones]",
        "Usage: milestones [<nick>] [-nick=<nick>] [-channel].  With no arguments, shows your "
      . "own next milestone for each badge, soonest first.  Give a nick to see theirs.");

    $self->addHelpItem("[milestones][-channel]",
        "Show everyone who reaches a milestone today.");

    $self->addHelpItem("[milestones][-nick]",
        "milestones -nick=<nick>.  Show that person's upcoming milestones.");
}

1;
__END__
