package modules::EventTimer;
#---------------------------------------------------------------------------
#    Copyright (C) 2013  egretsareherons@gmail.com
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
use strict;
use warnings;
use modules::Collection;
use constant Collection => 'modules::Collection';
use Data::Dumper;
use DBI;

BEGIN {
  $modules::EventTimer::VERSION = '1.0';
}

my $BotDatabaseFile;
my $dbh;
my $caller;
my %events;
my %cron_jobs;
my $last_update_time;
my $update_interval;
my $discard_at;

my @output_queue;

sub new {
    my ($class, @args) = @_;
   my $self = bless {}, $class;

    my ($db_file, $caller)  = @args;

    $self->{caller} = $caller;
    $self->{BotDatabaseFile} = $db_file;
    $self->{dbh} = DBI->connect("dbi:SQLite:dbname=".$self->{BotDatabaseFile}, "", "");
    $self->{last_update_time} = 0;
    $self->{update_interval} = 60 * 10;
    $self->{discard_at} = 10;

    $self->createTable();
    return $self;
}


sub tick{
   my $self = shift;
    my $now = time();
    my $hasJobs= 0;
    my $reloadEvents = 0;

    if ($self->{last_update_time} < ($now - $self->{update_interval})){
        $self->updateEvents();
        $self->updateCron();
    }

    ## Handle Cron
    if ($self->{cron_jobs}){
        my ($secs, $mins, $hours, $day, $month, $year, $dow, $dst)= localtime(time);
        my $key = sprintf("%02d%02d%02d", $hours, $mins, $secs);
        if (defined($self->{cron_jobs}->{$key})){
            foreach my $job (@{$self->{cron_jobs}->{$key}}){
                print "Processing cron job $job->{command} ";
                if (defined($job->{options})){
                    print "options: ($job->{options}) ";
                }
                print "\n";

                $self->processCronJob($job);
                $hasJobs=1;
            }
        }
    }

    ## Handle Events

    if ($self->{events}){
        foreach my $k (sort keys %{$self->{events}}){
            #print " " . ($k - $now) . " ";
        }

        foreach my $k (keys %{$self->{events}}){
            if ($k <= $now){
                $self->processEvent($k);
                $hasJobs = 1;
                $reloadEvents=1;
            }
        }   
    }

    if ($reloadEvents){
        $self->updateEvents();
    }

    if ($hasJobs){
        return 1;
    }else{
        return 0;
    }
}


sub processCronJob{
    my $self = shift;
    my $job = shift;
    
    my $e = {
        command => $job->{command},
        options => $job->{options},
        channel => $job->{channel},
        nick      => $job->{nick},
        mask      => $job->{mask},
        origin  => 'internal'
    };

    push @{$self->{output_queue}}, $e;

}

sub processEvent{
    my $self = shift;
    my $key = shift;

    my $now = time();
    
    # Ditch event if it's too old.
    # I should probably log this in a table somewhere.
    my $old = $now - $key;
    if ( $old > $self->{discard_at}){
        print "Discarding event: Too old ($old secs)\n";
        #print Dumper ($self->{events}->{$key});
        while (my $event = shift @{$self->{events}->{$key}}){
            $self->deleteEvent($event);
        }
        delete ($self->{events}->{$key});
    }

    ## process the event
    while (my $event = shift @{$self->{events}->{$key}}){
        my $e = {
            command => $event->{command},
            options => $event->{options},
            channel => $event->{channel},
            nick      => $event->{nick},
            mask      => $event->{mask}
        };

        print "Running event: \n";
        print Dumper($event);
        push @{$self->{output_queue}}, $e;
        $self->deleteEvent($event);
    }

    delete ($self->{events}->{$key});
}


sub getEvents{
    my $self = shift;
    my $e = $self->{output_queue};
    delete ($self->{output_queue});
    return $e;
}


sub deleteEvent{
    my $self = shift;
    my $event = shift;

    #print "===========================\n";
    #print "DELETE!\n";
    #print "===========================\n";

    my $sql = "delete from event_timer where event_id = ?";
    my $sth = $self->{dbh}->prepare($sql);
    $sth->execute($event->{event_id});
}

sub createTable{
   my $self = shift;

    ##
    ## Create the table if necessary
    ##
    my $sql = "CREATE TABLE IF NOT EXISTS event_timer( 
            event_id INTEGER PRIMARY KEY ASC, sys_creation_time INTEGER,
            event_time INTEGER, event_type TEXT, module_name TEXT, 
            command TEXT, options TEXT,  nick TEXT, mask TEXT, channel TEXT,
            event_description TEXT)";

    my $sth = $self->{dbh}->prepare($sql);
    $sth->execute();
        
    $sql = "create index IF NOT EXISTS event_timer_idx1 on event_timer (event_time)";
    $sth = $self->{dbh}->prepare($sql);
    $sth->execute();


    $sql = "CREATE TABLE IF NOT EXISTS event_timer_cron( 
            job_id INTEGER PRIMARY KEY ASC, sys_creation_time INTEGER,
            job_sec TEXT, job_min TEXT, job_hour TEXT,
            command TEXT, options TEXT, nick TEXT, mask TEXT, channel TEXT
            )";

    $sth = $self->{dbh}->prepare($sql);
    $sth->execute();
        
}


sub update{
   my $self = shift;
    $self->updateEvents();
    $self->updateCron();
}


sub updateCron{
   my $self = shift;

    delete ($self->{cron_jobs});

    my $sql = "SELECT job_id, sys_creation_time, job_sec, job_min, job_hour, 
                command, options, nick, mask, channel FROM event_timer_cron";

    my $sth = $self->{dbh}->prepare($sql);
    $sth->execute();

    while (my $row = $sth->fetch){
        my %data;
        $data{'job_id'} = $row->[0];
        $data{'sys_creation_time'} = $row->[1];
        $data{'job_sec'} = $row->[2];
        $data{'job_min'} = $row->[3];
        $data{'job_hour'} = $row->[4];
        $data{'command'} = $row->[5];
        $data{'options'} = $row->[6];
        $data{'nick'} = $row->[7];
        $data{'mask'} = $row->[8];
        $data{'channel'} = $row->[9];

        if ($data{job_sec} eq '*'){
            $data{job_sec} = '0';
            for (my $i=1; $i<60; $i++){
                $data{job_sec}.=",$i";
            }
        }

        if ($data{job_min} eq '*'){
            $data{job_min} = '0';
            for (my $i=1; $i<60; $i++){
                $data{job_min}.=",$i";
            }
        }

        if ($data{job_hour} eq '*'){
            $data{job_hour} = '0';
            for (my $i=1; $i<24; $i++){
                $data{job_hour}.=",$i";
            }
        }

        my @secs = split /,/, $data{job_sec};
        my @mins = split /,/, $data{job_min};
        my @hours = split /,/, $data{job_hour};
        
        foreach my $h (@hours){
            foreach my $m (@mins){
                foreach my $s (@secs){
                    my $str = sprintf("%02d%02d%02d", $h, $m, $s);
                    if (!defined($self->{cron_jobs}->{$str})){
                        $self->{cron_jobs}->{$str} = [];
                    }
                    delete $data{'job_sec'};
                    delete $data{'job_min'};
                    delete $data{'job_hour'};
                    delete $data{'sys_creation_time'};
                    push @{$self->{cron_jobs}->{$str}}, {%data};
                }
            }
        }
    }

}   


sub updateEvents{
   my $self = shift;
    #print "Updating events\n";

    ##
    ## load the data
    ##

    my $sql = "SELECT event_id, sys_creation_time, event_time, event_type, 
            module_name,  command, options, 
            nick, mask, channel, event_description from event_timer";

    my $sth = $self->{dbh}->prepare($sql);
    #$sth->execute($self->{'module_name'});
    $sth->execute();

    delete ($self->{events});

    while (my $row = $sth->fetch){
        my %data;
        $data{'event_id'} = $row->[0];
        $data{'sys_creation_time'} = $row->[1];
        $data{'event_time'} = $row->[2];
        $data{'event_type'} = $row->[3];
        $data{'module_name'} = $row->[4];
        $data{'command'} = $row->[5];
        $data{'options'} = $row->[6];
        $data{'nick'} = $row->[7];
        $data{'mask'} = $row->[8];
        $data{'channel'} = $row->[9];
        $data{'event_description'} = $row->[10];

        #print Dumper(%data);

        if (!defined($self->{events}->{$data{event_time}})){
            $self->{events}->{$data{event_time}} = [];
        }
        push @{$self->{events}->{$data{event_time}}}, {%data};

    }
    #print Dumper ($self);

    $self->{last_update_time} = time();
}


sub getCronJobs{
   my $self = shift;
    my $sql = "SELECT job_id, sys_creation_time, job_sec, job_min, job_hour, 
                command, options, nick, mask, channel FROM event_timer_cron";

    my $sth = $self->{dbh}->prepare($sql);
    $sth->execute();

    my @ret;

    while (my $row = $sth->fetch){
        my %data;
        $data{'job_id'} = $row->[0];
        $data{'sys_creation_time'} = $row->[1];
        $data{'job_sec'} = $row->[2];
        $data{'job_min'} = $row->[3];
        $data{'job_hour'} = $row->[4];
        $data{'command'} = $row->[5];
        $data{'options'} = $row->[6];
        $data{'nick'} = $row->[7];
        $data{'mask'} = $row->[8];
        $data{'channel'} = $row->[9];
        push @ret, {%data};
    }

    return @ret;
}


sub scheduleCronJob{
   my $self = shift;
    my $args = shift;

   my $sec = $args->{job_sec};
   my $min = $args->{job_min};
   my $hour= $args->{job_hour};
   my $command  = $args->{command};
   my $options  = $args->{options};
   my $nick= $args->{nick};
   my $mask = $args->{mask};
   my $channel = $args->{channel};

    my $sql = "insert into event_timer_cron (job_id, sys_creation_time, job_sec, job_min, job_hour, command, options, nick, mask, channel) VALUES (null, datetime('now', 'localtime'), ?, ?, ?, ?, ?, ?, ?, ?)";

    my $sth = $self->{dbh}->prepare($sql);
    
    my $status = $sth->execute( $sec, $min, $hour, $command, $options, $nick, $mask, $channel );
    return $status;
}

sub deleteCronJob{
   my $self = shift;
    my $num = shift;

    my $sql = "delete from event_timer_cron where job_id = ?";
    my $sth = $self->{dbh}->prepare($sql);
    my $status = $sth->execute($num);

    print "delete status is $status\n";
    return $status;
}

sub scheduleEvent{
   my $self = shift;
    my $args = shift;

   my $event_time = $args->{event_time};
   my $event_type = $args->{event_type};
   my $module_name = $args->{module_name}; 
   my $command  = $args->{command};
   my $options  = $args->{options};
   my $nick= $args->{nick};
   my $mask = $args->{mask};
   my $channel = $args->{channel};
   my $event_description  = $args->{event_description};

    ## In case someone's using time hires
    $event_time =~s/\.[0-9]+$//;

    my $sql = "insert into event_timer ( event_id, sys_creation_time, 
        event_time, event_type, module_name,  command, 
        options, nick, mask, channel, event_description )
        VALUES (null, datetime('now', 'localtime'), ?, ?, ?, ?, ?, 
            ?, ?, ?, ?)";

    my $sth = $self->{dbh}->prepare($sql);
    
    my $status = $sth->execute( $event_time, $event_type, $module_name, 
         $command, $options, $nick,
        $mask, $channel, $event_description);

    my $rv = $self->{dbh}->last_insert_id(undef, undef, 'event_timer', 'event_id');
    return $rv;
}



1;
__END__

