package modules::Collection;
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
#use warnings;

BEGIN {
  $modules::Collection::VERSION = '1.0';
}

use Data::Dumper;
use DBI;
use Time::HiRes;

my $BotDatabaseFile;
my $module_name;
my $collection_name;

my $commit;

my $dbh;
my @records;
my $max_record_id;

my $table_name;
my $sql_pragma_synchronous;

my $keep_stats; # see command handler for info
my $keep_stats_start;
my @keep_stats_records;
my @keep_stats_collections;

######################################
######################################

sub new {
    my ($class, $args) = @_;
   my $self = bless {}, $class;

    my $db_file = $args->{db_file};
    my $module_name= $args->{module_name};
    my $collection_name= $args->{collection_name};
    $self->{keep_stats} = $args->{keep_stats};
    $self->{table_name} = $args->{table_name} || 'collections';
    $self->{sql_pragma_synchronous} = $args->{sql_pragma_synchronous};

    if (!defined($self->{sql_pragma_synchronous})){
        $self->{sql_pragma_synchronous} = 1;
    }

    ##strip the namespace:: part
    $module_name=~s/^.+\:(\w+)$/$1/gis;

    $self->{module_name} = $module_name;
    $self->{collection_name} = $collection_name;
    $self->{BotDatabaseFile} = $db_file;

    $self->{commit} = 1;

    $self->{dbh} = DBI->connect("dbi:SQLite:dbname=".$self->{BotDatabaseFile}, "", "", { AutoCommit => 0 });

    my $sql = "PRAGMA synchronous = $self->{sql_pragma_synchronous}";
    my $sth = $self->{dbh}->prepare($sql);
    $sth->execute();

    $self->{dbh}->{'RaiseError'} = 1;
    $self->createTable();

    return $self;
}

sub startBatch{
    my $self = shift;
    $self->{commit} = 0;
}

sub endBatch{
    my $self = shift;
    $self->keepStats({a=>'start'});
    $self->{commit} = 1;
    $self->{dbh}->commit;
    $self->keepStats({a=>'end', data=>'endBatch ' . $self->{module_name}."->".$self->{collection_name}});
    $self->load();
}

sub createTable{
   my $self = shift;

    ##
    ## Create the table if necessary
    ##
    my $sql = "CREATE TABLE IF NOT EXISTS $self->{table_name} ( 
         module_name TEXT, collection_name TEXT NOT NULL, display_id INTEGER, 
         sys_creation_date TEXT, sys_update_date TEXT, 
            val1 TEXT, val2 TEXT, val3 TEXT, val4 TEXT, val5 TEXT, val6 TEXT, 
            val7 TEXT, val8 TEXT, val9 TEXT, val10 TEXT)";

    my $sth = $self->{dbh}->prepare($sql);
    $sth->execute();
    $self->{dbh}->commit if ($self->{commit});
    
    $sql = "create index IF NOT EXISTS ".$self->{table_name}."_idx1 on $self->{table_name} 
                (module_name, collection_name)";
    $sth = $self->{dbh}->prepare($sql);
    $sth->execute();
    $self->{dbh}->commit if ($self->{commit});
}

##  When does the database think it is?
## I dont think this is used anywhere
sub now{
    my $self = shift;
    my $sql = "select strftime('%s', 'now')";
    my $sth = $self->{dbh}->prepare($sql);
    $sth->execute();
    my $row = $sth->fetch;
    $self->{dbh}->commit if ($self->{commit});
    return $row->[0];
}


# load or reload
sub load{
   my $self = shift;

    $self->keepStats({a=>'start'});
    
    $self->{'records'} = [];
    $self->{'max_record_id'} = 0;

    #print "Collection loading. $self->{module_name} $self->{collection_name} " . time() . "\n";;

    ##
    ## load the data
    ##

    my $sth;

    if ($self->{'collection_name'} eq '%'){
        my $sql = "SELECT ROWID, display_id, collection_name, val1, val2, val3, val4, val5, val6, 
            val7, val8, val9, val10, 
            sys_creation_date, sys_update_date, strftime('%s',sys_creation_date) as scd_ts,
            strftime('%s',sys_update_date) as sud_ts
            from $self->{table_name} where module_name = ? ";
        $sql.="       ORDER BY display_id";

        $sth = $self->{dbh}->prepare($sql);
        $sth->execute($self->{'module_name'});

    }else{
        my $sql = "SELECT ROWID, display_id, collection_name, val1, val2, val3, val4, val5, val6, 
            val7, val8, val9, val10,
            sys_creation_date, sys_update_date, strftime('%s',sys_creation_date) as scd_ts,
            strftime('%s',sys_update_date) as sud_ts
            from $self->{table_name} where module_name = ? ";
        $sql.=" and collection_name = ? ";
        $sql.="       ORDER BY display_id";

        $sth = $self->{dbh}->prepare($sql);
        $sth->execute($self->{'module_name'}, $self->{'collection_name'});

    }

    $self->{'records'} = [];

    while (my $row = $sth->fetch){
        my %data;
        $data{'row_id'} = $row->[0];
        $data{'display_id'} = $row->[1];
        $data{'collection_name'} = $row->[2];
        $data{'val1'} = $row->[3];
        $data{'val2'} = $row->[4];
        $data{'val3'} = $row->[5];
        $data{'val4'} = $row->[6];
        $data{'val5'} = $row->[7];
        $data{'val6'} = $row->[8];
        $data{'val7'} = $row->[9];
        $data{'val8'} = $row->[10];
        $data{'val9'} = $row->[11];
        $data{'val10'} = $row->[12];
        $data{'sys_creation_date'} = $row->[13];
        $data{'sys_update_date'} = $row->[14];
        $data{'sys_creation_timestamp'} = $row->[15];
        $data{'sys_update_timestamp'} = $row->[16];
        #print Dumper(%data);

        push @{$self->{'records'}}, {%data};

        if ( $self->{'max_record_id'} < $data{'display_id'}){
            $self->{'max_record_id'} = $data{'display_id'};
        }
    }

    $self->{dbh}->commit if ($self->{commit});

    $self->keepStats({a=>'end', data=>$self->{module_name}."->".$self->{collection_name}});

    #print "Collection loaded. $self->{module_name} $self->{collection_name} " . time() . "\n";;
}

sub numRecords{
    my $self = shift;
    my $count = @{$self->{'records'}};
    return $count;
}

##
##  This doesn't take a hashref, it takes 6 arguments. The idea is that 
## if you're adding a record, you're probably starting at val1. 
## xyzzy - dont return display_id here, dummy.

sub add {
   my $self = shift;
    my ($val1, $val2, $val3, $val4, $val5, $val6, $val7, $val8, $val9, $val10) = @_;

    $self->keepStats({a=>'start'});

    my $sql = "insert into $self->{table_name} (module_name, collection_name, display_id, 
        val1, val2, val3, val4, val5, val6, val7, val8, val9, val10, sys_creation_date)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now', 'localtime'))";

    my $sth = $self->{dbh}->prepare($sql);
    
    my $display_id = $self->{max_record_id} + 1;

    ## xyzzy add error checking
    my $status = $sth->execute($self->{module_name}, $self->{collection_name}, $display_id, 
        $val1, $val2, $val3, $val4, $val5, $val6, $val7, $val8, $val9, $val10 );

    $self->{'display_id'} = $display_id;

    if ($self->{commit}){
        $self->{dbh}->commit;
        $self->keepStats({a=>'end', data=>"$val1, $val2, $val3, $val4 ... "});
        $self->load();
    }else{
        $self->keepStats({a=>'end', data=>"$val1, $val2, $val3, $val4 ... "});
    }
        

    return $display_id;
}


sub delete {
   my $self = shift;
    my $row_id = shift;
    
    $self->keepStats({a=>'start'});
    my $collection = $self->{collection_name};

    if ($collection eq '%'){
        my $sql = "select collection_name from $self->{table_name} where module_name = ? 
                        and ROWID = ?";
        my $sth = $self->{dbh}->prepare($sql);
        $sth->execute($self->{'module_name'}, $row_id);
        my $row = $sth->fetch;
        $collection = $row->[0];
    }

    # first get the display_id so we can renumber
    my $sql = "select display_id from $self->{table_name} WHERE module_name = ? AND collection_name =  ?
                AND ROWID  = ?";
    my $sth = $self->{dbh}->prepare($sql);
    $sth->execute($self->{'module_name'}, $collection, $row_id);
    my $row = $sth->fetch;
    my $display_id = $row->[0];

    # now do the deletion
    $sql = "delete from $self->{table_name} WHERE module_name = ? AND collection_name =  ?
                AND ROWID  = ?";
    $sth = $self->{dbh}->prepare($sql);
    $sth->execute($self->{'module_name'}, $collection, $row_id);
    
    ## rowid was deleted.  renumber all of the remaining records
    #if ($sth->rows){
    #   $sql = "update $self->{table_name} set display_id = display_id-1 
    #           WHERE module_name = ? AND collection_name =  ?
    #           AND display_id > ?";
    #   $sth = $self->{dbh}->prepare($sql);
    #   $sth->execute($self->{'module_name'}, $collection, $display_id);
    #}

    if ($self->{commit}){
        $self->{dbh}->commit;
        $self->keepStats({a=>'end', data=>"row_id: $row_id"});
        $self->load();
    }else{
        $self->keepStats({a=>'end', data=>"row_id: $row_id"});
    }
}

sub renumber{
    my $self = shift;
    $self->sort({field=>'display_id', type=>'numeric', order=>'asc'});
    
    $self->startBatch();
    for (my $i=1; $i<=@{$self->{records}}; $i++){
        my $rec = @{$self->{records}}[$i-1];
        #print "Update row $rec->{row_id}\n";
        $self->updateRecord($rec->{row_id}, {display_id=>$i});
    }
    $self->endBatch();
}

sub deleteByVal {
   my $self = shift;
    my $fields = shift;
    
    $self->sort({field=>'display_id', type=>'numeric', order=>'desc'});
    my @records = $self->matchRecords($fields);
    foreach my $rec (@records){
        print "deleting record id $rec->{row_id}\n";
        $self->delete($rec->{row_id});
    }
}

sub deleteAllRecords{
   my $self = shift;

    return 0 if (!$self->{module_name});
    return 0 if (!$self->{collection_name});

    my $sql = "delete from $self->{table_name} where module_name = ? AND collection_name =  ?";

    my $sth = $self->{dbh}->prepare($sql);
    $sth->execute($self->{'module_name'}, $self->{collection_name});
    $self->{dbh}->commit if ($self->{commit});
    
    return 1;
}


sub getAllRecords{
   my $self = shift;

    return @{$self->{records}};
}


##
##  Two types of search - regular and advanced. 
## Advanced search is AND, use +term1 -term2
## $c->searchRecords($string, $field_number)
## Example:  $c->searchRecords("foo", 1) #Matches val1=~/foo/ field
## Example:  $c->searchRecords("foo bar", 1) #Matches (val1=~/foo/ || val1=~/bar/)
## Example:  $c->searchRecords("+foo -bar", 2)  #Matches (val2=~/foo/ && val2!~/bar/)
##
##
sub searchRecords{
   my $self = shift;
    my $str = shift;
    my $field = shift;

    if (!$field){
        $field=1;
    }

    my @ret = ();

    my @terms = split / /, $str;

    #print Dumper (@terms);

    if ($str=~/\+|\-/){
        #print "Advanced Search\n";

        my $add_this = 0;
        my $dont_add_this = 0;

        foreach my $rec (@{$self->{'records'}}){
            foreach my $term_m (@terms){    
                my $term = $term_m;
                #print " - test $term\n";
                if ($term=~/^\-/){
                    $term=~s/^\-//gis;

                    if ($rec->{'val' . $field}=~/$term/i){
                        #print " - Set Dont add flag\n";
                        $dont_add_this = 1;
                    }
                    
                }else{
                    $term=~s/^\+//gis;
                    if ($rec->{'val' . $field}=~/$term/i){
                        $add_this = 1;
                    }else{
                        $dont_add_this = 1;
                    }
                }
            }
            
            if ($add_this){
                if (!$dont_add_this){
                    my %data;
                    $data{'row_id'} = $rec->{'row_id'};
                    $data{'display_id'} = $rec->{'display_id'};
                    $data{'collection_name'} = $rec->{'collection_name'};
                    $data{'val1'} = $rec->{'val1'};
                    $data{'val2'} = $rec->{'val2'};
                    $data{'val3'} = $rec->{'val3'};
                    $data{'val4'} = $rec->{'val4'};
                    $data{'val5'} = $rec->{'val5'};
                    $data{'val6'} = $rec->{'val6'};
                    $data{'val7'} = $rec->{'val7'};
                    $data{'val8'} = $rec->{'val8'};
                    $data{'val9'} = $rec->{'val9'};
                    $data{'val10'} = $rec->{'val10'};
                    $data{'sys_creation_date'} = $rec->{'sys_creation_date'};
                    $data{'sys_update_date'} = $rec->{'sys_update_date'};
                    $data{'sys_creation_timestamp'} = $rec->{'sys_creation_timestamp'};
                    $data{'sys_update_timestamp'} = $rec->{'sys_update_timestamp'};
                    push @ret, {%data};
                }
            }

            $add_this = 0;
            $dont_add_this = 0;
        }
    
    }else{      ## Simple or search
        #print "Simple Search\n";

        #print Dumper(@terms);

        my $add_this = 0;

        foreach my $rec (@{$self->{'records'}}){
            foreach my $term (@terms){
                #print " - test $term\n";
                if ($rec->{'val' . $field}=~/$term/i){
                    $add_this = 1;
                    last;
                }
            }
            
            if ($add_this){
                my %data;
                $data{'row_id'} = $rec->{'row_id'};
                $data{'display_id'} = $rec->{'display_id'};
                $data{'collection_name'} = $rec->{'collection_name'};
                $data{'val1'} = $rec->{'val1'};
                $data{'val2'} = $rec->{'val2'};
                $data{'val3'} = $rec->{'val3'};
                $data{'val4'} = $rec->{'val4'};
                $data{'val5'} = $rec->{'val5'};
                $data{'val6'} = $rec->{'val6'};
                $data{'val7'} = $rec->{'val7'};
                $data{'val8'} = $rec->{'val8'};
                $data{'val9'} = $rec->{'val9'};
                $data{'val10'} = $rec->{'val10'};
                $data{'sys_creation_date'} = $rec->{'sys_creation_date'};
                $data{'sys_update_date'} = $rec->{'sys_update_date'};
                $data{'sys_creation_timestamp'} = $rec->{'sys_creation_timestamp'};
                $data{'sys_update_timestamp'} = $rec->{'sys_update_timestamp'};
                push @ret, {%data};
                $add_this = 0;
            }
        }
    }



    #print "--------------------\n";
    #print Dumper (@ret);
    #print "--------------------\n";
    return @ret;
}



##
##  updates by record id.  accepts id & a hashref of values.
## Example:  $c->updateRecord(1, {val1=>'blah', val4=>'blah');
##
sub updateRecord{
   my $self = shift;
    my $row_id = shift;
    my $fields = shift;
    
    $self->keepStats({a=>'start'});

    my @record = $self->getRecords($row_id);

    if (@record != 1){
        print "Error updating record.  C-uR-1\n";   
        print "row_id: $row_id\nFields:\n";
        print Dumper ($fields);
        return 0;
    }

    my $sql;

    if ($self->{collection_name} eq '%'){
        $sql = "UPDATE $self->{table_name} set display_id = ?,
                 val1 = ?, val2 = ?, val3 = ?, val4 = ?, val5 = ?, val6 = ?, 
                val7 = ?, val8 = ?, val9 = ?, val10 = ?, 
                sys_update_date = datetime('now', 'localtime')
                 WHERE module_name = ? 
                AND ROWID  = ?";
    }else{
        $sql = "UPDATE $self->{table_name} set display_id = ?,
                 val1 = ?, val2 = ?, val3 = ?, val4 = ?, val5 = ?, val6 = ?, 
                val7 = ?, val8 = ?, val9 = ?, val10 = ?, 
                sys_update_date = datetime('now', 'localtime')
                 WHERE module_name = ? AND collection_name =  ?
                AND ROWID  = ?";
    }

    my ($db_val1, $db_val2, $db_val3, $db_val4, $db_val5, $db_val6, $db_val7, 
        $db_val8, $db_val9, $db_val10, $db_display_id);

    if (defined($fields->{'display_id'})){ $db_display_id = $fields->{'display_id'};
    }else{ $db_display_id = $record[0]->{'display_id'}; }

    if (defined($fields->{'val1'})){ $db_val1 = $fields->{'val1'};
    }else{ $db_val1 = $record[0]->{'val1'}; }

    if (defined($fields->{'val2'})){ $db_val2 = $fields->{'val2'};
    }else{ $db_val2 = $record[0]->{'val2'}; }

    if (defined($fields->{'val3'})){ $db_val3 = $fields->{'val3'};
    }else{ $db_val3 = $record[0]->{'val3'}; }

    if (defined($fields->{'val4'})){ $db_val4 = $fields->{'val4'}; 
    }else{ $db_val4 = $record[0]->{'val4'}; }

    if (defined($fields->{'val5'})){ $db_val5 = $fields->{'val5'}; 
    }else{ $db_val5 = $record[0]->{'val5'}; }

    if (defined($fields->{'val6'})){ $db_val6 = $fields->{'val6'}; 
    }else{ $db_val6 = $record[0]->{'val6'}; }

    if (defined($fields->{'val7'})){ $db_val7 = $fields->{'val7'}; 
    }else{ $db_val6 = $record[0]->{'val7'}; }
    
    if (defined($fields->{'val8'})){ $db_val8 = $fields->{'val8'}; 
    }else{ $db_val6 = $record[0]->{'val8'}; }

    if (defined($fields->{'val9'})){ $db_val9 = $fields->{'val9'}; 
    }else{ $db_val6 = $record[0]->{'val9'}; }

    if (defined($fields->{'val10'})){ $db_val10 = $fields->{'val10'}; 
    }else{ $db_val6 = $record[0]->{'val10'}; }

    my $sth = $self->{dbh}->prepare($sql);


    ## xyzzy add error checking
    my $status;
    if ($self->{collection_name} eq '%'){
        $status = $sth->execute($db_display_id, $db_val1, $db_val2, $db_val3, $db_val4, $db_val5, $db_val6,
            $db_val7, $db_val8, $db_val9, $db_val10,
            $self->{'module_name'}, $row_id);

    }else{
        $status = $sth->execute($db_display_id, $db_val1, $db_val2, $db_val3, $db_val4, $db_val5, $db_val6,
            $db_val7, $db_val8, $db_val9, $db_val10,
            $self->{'module_name'}, $self->{'collection_name'}, $row_id);
    }

    my $detail;
    foreach my $f (sort keys %{$fields}){
        $detail.="$f>$fields->{$f} * ";
    }

    if ($self->{commit}){
        $self->{dbh}->commit;
        $self->keepStats({a=>'end', data=>"row_id: $row_id $detail"});
        $self->load();
    }else{
        $self->keepStats({a=>'end', data=>"row_id: $row_id $detail"});
    }

    return (1);
}

##
##  getMax - return the max value of a row
##

sub getMax{
   my $self = shift;
    my $match = shift;
    my $field = shift;
    
    my @records = $self->matchRecords($match);

    my $max;
    foreach my $rec (@records){
        if (!$max){
            $max = $rec->{$field};
        }

        if ( $rec->{$field} > $max){
            $max = $rec->{$field};
        }
    }
    return $max;
}


sub getUnique{
   my $self = shift;
    my $match = shift;
    my $field = shift;
    
    my %ret;

    my @records = $self->matchRecords($match);

    foreach my $rec (@records){
        if (!defined($ret{$rec->{$field}}) ){
            $ret{$rec->{$field}} = 1;
        }else{
            $ret{$rec->{$field}}++;
        }

    }

    return \%ret;
}


##
##  matchRecords
## Match records for exact match on supplied fields
## Accepts a hashref of arguments
##  Example: $c->matchRecords({val1=>'foo', val2=>'bar'}) 
##

sub matchRecords{
   my $self = shift;
    my $fields = shift;
    
    if (ref($fields) ne 'HASH'){
        print "Error: You need to supply a hashref to the matchRecords function. C-mR-1\n";
        return;
    }

    #print "Fields:\n";
    #print Dumper($fields);

    my @ret = ();
    foreach my $rec (@{$self->{'records'}}){
        my $match = 0;
        my $notmatch = 0;

        foreach my $f (keys %{$fields}){
            #print "F is $f, rec is ".$rec->{$f}." fields is ".$fields->{$f}."\n";
            
            if ($rec->{$f} eq $fields->{$f}){
                $match = 1;
            }else{
                $notmatch= 1;
            }
        }
        
        if ($match && !$notmatch){
            my %data;
            $data{'row_id'} = $rec->{'row_id'};
            $data{'display_id'} = $rec->{'display_id'};
            $data{'collection_name'} = $rec->{'collection_name'};
            $data{'val1'} = $rec->{'val1'};
            $data{'val2'} = $rec->{'val2'};
            $data{'val3'} = $rec->{'val3'};
            $data{'val4'} = $rec->{'val4'};
            $data{'val5'} = $rec->{'val5'};
            $data{'val6'} = $rec->{'val6'};
            $data{'val7'} = $rec->{'val7'};
            $data{'val8'} = $rec->{'val8'};
            $data{'val9'} = $rec->{'val9'};
            $data{'val10'} = $rec->{'val10'};
            $data{'sys_creation_date'} = $rec->{'sys_creation_date'};
            $data{'sys_update_date'} = $rec->{'sys_update_date'};
            $data{'sys_creation_timestamp'} = $rec->{'sys_creation_timestamp'};
            $data{'sys_update_timestamp'} = $rec->{'sys_update_timestamp'};
            push @ret, {%data};
        }

    }

    #print "--------------------\n";
    #print Dumper (@ret);
    #print "--------------------\n";
        
    return @ret;
}


##
##  getRecords by row_id.  getRecords(1,3,4,5);
##
sub getRecords{
   my $self = shift;
    my $num_list = shift;

    my @num_arr = split /,/, $num_list;
    
    my @ret = ();

    foreach my $rec (@{$self->{'records'}}){
        #print "recid = " . $rec->{'row_id'} . "\n";
        if (grep { $_ == $rec->{'row_id'} } @num_arr){
            my %data;
            $data{'row_id'} = $rec->{'row_id'};
            $data{'display_id'} = $rec->{'display_id'};
            $data{'collection_name'} = $rec->{'collection_name'};
            $data{'val1'} = $rec->{'val1'};
            $data{'val2'} = $rec->{'val2'};
            $data{'val3'} = $rec->{'val3'};
            $data{'val4'} = $rec->{'val4'};
            $data{'val5'} = $rec->{'val5'};
            $data{'val6'} = $rec->{'val6'};
            $data{'val7'} = $rec->{'val7'};
            $data{'val8'} = $rec->{'val8'};
            $data{'val9'} = $rec->{'val9'};
            $data{'val10'} = $rec->{'val10'};
            $data{'sys_creation_date'} = $rec->{'sys_creation_date'};
            $data{'sys_update_date'} = $rec->{'sys_update_date'};
            $data{'sys_creation_timestamp'} = $rec->{'sys_creation_timestamp'};
            $data{'sys_update_timestamp'} = $rec->{'sys_update_timestamp'};

            push @ret, {%data};
        }
    }

    return @ret;
}


##
##  because sometimes running sql is easier than dealing with date conversions
##
sub runSQL{
    my $self = shift;
    my $sql = shift;

    if (!$sql){
        return;
    }

    my $sth = $self->{dbh}->prepare($sql);
    $sth->execute();
    $self->{dbh}->commit if ($self->{commit});
}

## Sort the records in the collection
## Takes a hashref of values
## field = the field to sort on
## type = numeric of alpha
## order = desc or asc
sub sort{
    my $self=shift;
    my $opts = shift;
    
    my $field = $opts->{field};
    my $type = $opts->{type} || 'alpha';
    my $order = $opts->{order};
    
    #print "Sorting on field $field, $type, $order\n";

    if ($type eq 'numeric'){
        if ($order eq 'desc'){
            @{$self->{records}} = sort {lc($b->{$field}) <=> lc($a->{$field})} @{$self->{records}};
        }else{
            @{$self->{records}} = sort {lc($a->{$field}) <=> lc($b->{$field})} @{$self->{records}};
        }
    }

    if ($type eq 'alpha'){
        if ($order eq 'desc'){
            @{$self->{records}} = sort {lc($b->{$field}) cmp lc($a->{$field})} @{$self->{records}};
        }else{
            @{$self->{records}} = sort {lc($a->{$field}) cmp lc($b->{$field})} @{$self->{records}};
        }
    }
}

sub setValue{
   my $self = shift;

   my ($key, $value) = @_;

   $self->{$key} = $value;

   #print "I set $key to $value\n";
   return $self->{'options'};
}

sub getValue {
   my $self = shift;
    my $key = shift;
    #print "getting $key\n";
    #print "value is " . $self->$key . "\n";

    if (defined($self->$key)){
        return ($self->$key);
    }else{
        #print "ERROR - not defined\n";
        return "";
    }
}

sub getStats{
   my $self = shift;

   if (defined($self->{keep_stats_records})){
      return @{$self->{keep_stats_records}};
   }else{
      return ();
   }
}

sub keepStats{
   my $self = shift;
   my $opts = shift;

   return if ($self->{keep_stats} < 4);

   if ($opts->{a} eq 'start'){
      $self->{keep_stats_start} = Time::HiRes::time();
   }

   if ($opts->{a} eq 'end'){
      my $time = sprintf( "%.3f", Time::HiRes::time() - $self->{keep_stats_start});
      my $parent = ( caller(1) )[3];
      $parent=~/Collection::(.+?)$/;
      $parent = $1;
      my $line = "$time\tCollection"."->$parent\t" . $opts->{data};
      push @{$self->{keep_stats_records}}, $line;
   }
}


sub DESTROY {
   my $self = shift;
    $self->{dbh}->commit if ($self->{commit});
   $self->{'dbh'}->disconnect();
}

1;
__END__

