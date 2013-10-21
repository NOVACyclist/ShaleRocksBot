package plugins::WordScramble;
use strict;         
use warnings;
use base qw (modules::PluginBaseClass);
use modules::PluginBaseClass;
use Data::Dumper;

my $dbh;
my $num_wordlist_words;

sub onBotStart{
   my $self = shift;
}

sub plugin_init{
    my $self = shift;
    $self->useChannelCookies();
    $self->{dbh} = DBI->connect("dbi:SQLite:dbname=".$self->{BotDatabaseFile}, "", "", { AutoCommit => 0 });

    ## Check if table exists.
    my $sql = "SELECT count(*) FROM sqlite_master WHERE name ='wordlist' and type='table'";
    my $sth = $self->{dbh}->prepare($sql);
    $sth->execute();
    $self->{dbh}->commit;
    my $row = $sth->fetch;

    # table exists, check number of rows
    if($row->[0]){
        my $sql = "select count(*) as c from wordlist";
        my $sth = $self->{dbh}->prepare($sql);
        $sth->execute();
        $self->{dbh}->commit;
        my $row = $sth->fetch;
        $self->{num_wordlist_words} = $row->[0];
    }else{
        $self->{num_wordlist_words} = 0;
    }

    $self->suppressNick(1);

    return $self;
}


sub getOutput {
    my $self = shift;

    my $cmd = $self->{command};         # the command
    my $options = $self->{options};     # everything else on the line, except flags
    my $options_unparsed = $self->{options_unparsed};  #with the flags intact
    my $channel = $self->{channel};                 
    my $mask = $self->{mask};               # the users hostmask, not including the username
    my $BotCommandPrefix = $self->{BotCommandPrefix};   
    my $bot_name = $self->{BotName};        # the name of this bot
    my $irc_event = $self->{irc_event}; # the IRC event that triggered this call
    my $BotOwnerNick    = $self->{BotOwnerNick}; 
    my $nick = $self->{nick};   # the nick of the person calling the command
    my $accountNick = $self->accountNick(); 


    if ($cmd eq 'findwords'){
        return $self->help($cmd) if (!$options);
        $options=~s/ //gis;
        if (length ($options) > 26){
            return "That is too long.";
        }

        my @words = $self->findWords($options);

        my $list = join ", ", @words;

        if ($list){
           return "Some words found in [$options]: $list"
        }else{
           return "Sorry, no words found in [$options].  (It wasn't an exhaustive search)."
        }
    }

    if ($self->hasFlag("dropwordlist")){
        my $sql = "drop table wordlist";
        my $sth = $self->{dbh}->prepare($sql);
        $sth->execute();
        $self->{dbh}->commit;
        return "Done."; 
    }

    if (my $url = $self->hasFlagValue("loadwordlist")){
        $self->createWordlistTable();
        my $num = $self->loadWordlist($url);
        return "The wordlist now has $num words. ". '\m/_(-_-)_\m/';
    }

    if ( $self->hasFlag("wordlistinfo")){
        my $msg = "The wordlist has $self->{num_wordlist_words} words.";
        return $msg;
    }

    if (! $self->{num_wordlist_words}){
        return "Wordlist not loaded. A bot administrator can load a wordlist using -loadwordlist = <URL>. See help ws -loadwordlist for more info.";
    }


    ##
    ##  Auto show status
    ##
    if ($cmd eq '_showWSstatus'){
        return if ($self->hasFlagValue('game_id') ne $self->globalCookie('game_id'));

        my $board = $self->globalCookie('board') || 0;
        if ($board){
    
            my @letters =  split (//, $board);
            my $i = @letters;
            while ( --$i ){
                my $j = int rand( $i+1 );
                @letters[$i,$j] = @letters[$j,$i];
            }

            return "The board: ".BOLD . join (" ", @letters) .NORMAL. " - Game ends in $options minutes";   
        }
        return;
    }


    ##
    ##  manual show status
    ##
    if ($self->hasFlag("show")){
        my $board = $self->globalCookie('board') || 0;
        if ($board){
            return "The board: ".BOLD . join (" ", split (//, $board)) .NORMAL; 
        }else{
            return "No game in progress.";
        }
    }


    ##
    ##  show scores
    ##
    if ($self->hasFlag("scores")){
        my $board = $self->globalCookie('board') || 0;
        return "soon";
    }


    ##
    ##  End Game
    ##
    if ($cmd eq '_endWSgame'){
        my @ret;
        my $board = $self->globalCookie('board') || 0;
        return if (!$board);

        return if ($self->hasFlagValue('game_id') ne $self->globalCookie('game_id'));

        $self->deleteGlobalCookie('board');

        my %scores;
        my %words;
        my %badwords;
    
        my @cookies = $self->allCookies();
        my @pw = $self->findWords($board);
        my %possible_words;
        foreach my $w (@pw){
            $possible_words{$w} = 1;
        }

        foreach my $c (@cookies){
            if ($c->{name}=~/^\:gamescore\:(.+?)$/){
                my $name = $1;
                $scores{$name} = $c->{value};
            }

            if ($c->{name}=~/^\:word\:(.+?)$/){
                my $word = $1;
                $words{$c->{value}} .= "$word(".$self->scoreWord($word).") ";
                if (exists($possible_words{$word})){
                    delete($possible_words{$word});
                }
            }

            if ($c->{name}=~/^\:badwords\:(.+?)$/){
                my $name= $1;
                $badwords{$name} = $c->{value}; 
            }
        }

        ## get the winners
        my $top_score = 0;
        my $line = '';
        my $i=0;
        foreach my $name (sort {$scores{$b} <=> $scores{$a}} keys %scores){
            $i++;
            if ($i==1){
                $line = BOLD."GAME OVER. ". RED." $name".NORMAL." wins the game with $scores{$name} points!";
                $top_score = $scores{$name};
                next;

            }elsif($i==1){
                if ($scores{$name} == $top_score){
                    $line = BOLD."GAME OVER. ". RED." It's a tie!".NORMAL;
                    last;
                }
            }
        }

        if ($line ne ''){
            push @ret, $line;   
        }

        foreach my $name (sort {$scores{$b} <=> $scores{$a}} keys %scores){
            push @ret, "$name: $scores{$name} points. $words{$name}  Invalid words(-3 each): $badwords{$name}";
        }

        foreach my $name (sort keys %scores){
            my $score = $self->globalCookie(':score:'.$name) || 0;
            $self->globalCookie(':score:'.$name, $score + $scores{$name});

            my $num_games = $self->globalCookie(':num_games:'.$name) || 0;
            $self->globalCookie(':num_games:'.$name, $num_games+1);
        }

        if (!@ret){
            push @ret, "Game Over. Nobody wins. :(";
        }
        
        ## add words
        my $pwl =  join ", ", sort {length($b) <=> length($a) or $a cmp $b} keys (%possible_words);
        if ($pwl){
            push @ret, "Some words you didn't find: $pwl";
        }
        return \@ret;
    }


    ##
    ##      Start a new game
    ##
    if ($self->hasFlag('new')){
        if (($self->globalCookie('board') || 0)){
            if (! $self->hasFlag("force")){
                return "A game is already in progress. Wait until it ends.";
            }
        }
    
        my $board = "";

        ## Boggle
        #my $letters = 'EEEEEEEEEEEEEEEEEEETTTTTTTTTTTTTAAAAAAAAAAAARRRRRRRRRRRRIIIIIIIIIINNNNNNNNNNOOOOOOOOOOSSSSSSSSDDDDDDCCCCCHHHHHLLLLLFFFFMMMMPPPPUUUUGGGYYYWWBJKQVXZ';

        ## Scrabble
        my $letters = 'EEEEEEEEEEEEAAAAAAAAAIIIIIIIIIOOOOOOOONNNNNNRRRRRRTTTTTTLLLLSSSSUUUUDDDDGGGBBCCMMPPFFHHVVWWYYKJXQZ';
        my $vowels = 0;

        do {
            $board = "";
            $vowels = 0;

            for (my $i=0; $i<10; $i++){
                my $rand = int(rand(length($letters)));
                $board.=substr($letters, $rand, 1);
            }
            $vowels++ while ($board=~/A|E|I|O|U/g);

        }while ($vowels < 2);

        # add a U if Q & no U
        if ($board=~/Q/){
            if ($board!~/U/){
                $board.="U";
            }
        }

        ## bonus E on friday.  Because, fuck, it's a friday
        my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
        if ($wday == 5){
            $board.="E";
        }

        $self->globalCookie('board', $board);

        my @cookies = $self->allCookies();
        foreach my $c (@cookies){
            if ($c->{name}=~/^\:gamescore\:/){
                $self->deleteGlobalCookie($c->{name});
            }

            if ($c->{name}=~/^\:word\:/){
                $self->deleteGlobalCookie($c->{name});
            }

            if ($c->{name}=~/^\:badwords\:/){
                $self->deleteGlobalCookie($c->{name});
            }
        }

        my $game_id = int(rand(999999));
        $self->globalCookie('game_id', $game_id);
        
        my $timer_args = {
            timestamp => (int(time()) + 60 * 3),
            command => '_endWSgame',
            options => "-game_id=$game_id",
            desc => 'End word scramble game'
        };
        $self->scheduleEvent($timer_args);

        $timer_args = {
            timestamp => (int(time()) + 60 * 1),
            command => '_showWSstatus',
            options => "-game_id=$game_id 2",
            desc => 'game status 2 min left'
        };
        $self->scheduleEvent($timer_args);

        $timer_args = {
            timestamp => (int(time()) + 60 * 2),
            command => '_showWSstatus',
            options => "-game_id=$game_id 1",
            desc => 'game status 1 min left'
        };
        $self->scheduleEvent($timer_args);

        return "New Board: ".BOLD . join (" ", split (//, $board)) .NORMAL. " - 5 letter minimum. You lose points for non-words an invaild words.  Game ends in 3 minutes";
    }
    

    ##
    ## Make a guess
    ##

    my $board = $self->globalCookie('board') || 0;
    return "A game is not in progress. Start one with ws -new." if (!$board);

    if ($options){
        my $guess = uc($options);
    
        if (length($guess) < 5){
            return "$nick:  5 letter minimum.";
        }

        foreach my $letter (split //, $guess){
            if ($board!~s/$letter//i){
                #return "Invalid word: $guess";
                my $score = $self->globalCookie(":gamescore:$nick") || 0;
                $self->globalCookie(":gamescore:$nick", $score - 3 );
                my $badwords = $self->globalCookie(':badwords:' . $nick);
                $self->globalCookie(':badwords:' . $nick, $badwords.= "$guess ");
            
                return;
            }
        }

        ## check if dictionary word
        if (!$self->IsValidWord($guess)){
            my $score = $self->globalCookie(":gamescore:$nick") || 0;
            $self->globalCookie(":gamescore:$nick", $score - 3 );
            my $badwords = $self->globalCookie(':badwords:' . $nick);
            $self->globalCookie(':badwords:' . $nick, $badwords.= "$guess ");
            
            return "";
            #return "not a valid word";
        }

        ## check if already guessed
        if ($self->globalCookie(':word:' . $guess)){
            return "";
            #return "already been guessed.";
        }

        # mark word as seen
        $self->globalCookie(':word:' . $guess, $nick);
    
        ## score word
        my $wordscore = $self->scoreWord($guess);

        my $score = $self->globalCookie(":gamescore:$nick") || 0;
        $self->globalCookie(":gamescore:$nick", $score + $wordscore);

        return "Valid word: $guess. Points: $wordscore";
    }
}

sub scoreWord{
    my $self = shift;
    my $guess = shift;

    # wordfeud letter scoring
    my $letter_scores = {
        'A' => 1,
        'B' => 4,
        'C' => 4,
        'D' => 2,
        'E' => 1,
        'F' => 4,
        'G' => 3,
        'H' => 4,
        'I' => 1,
        'J' => 10,
        'K' => 5,
        'L' => 1,
        'M' => 3,
        'N' => 1,
        'O' => 1,
        'P' => 4,
        'Q' => 10,
        'R' => 1,
        'S' => 1,
        'T' => 1,
        'U' => 2,
        'V' => 4,
        'W' => 4,
        'X' => 8,
        'Y' => 4,
        'Z' => 10
    };

    my $wordscore = (length($guess) - 5) * 2;
    foreach my $letter (split //, $guess){
        $wordscore += $letter_scores->{$letter};
    }
    
    return $wordscore;
}


sub IsValidWord{
    my $self = shift;
    my $word = shift;
    my $sql = "select count(*) from wordlist where word = '$word'";
    my $sth = $self->{dbh}->prepare($sql);
    $sth->execute();
    $self->{dbh}->commit;
    my $row = $sth->fetch;
    return $row->[0];
}

sub createWordlistTable{
    my $self = shift;
    my $sql = "CREATE TABLE IF NOT EXISTS wordlist ( 
         word TEXT PRIMARY KEY,
            letters TEXT,
            num_letters INTEGER
        )";

    my $sth = $self->{dbh}->prepare($sql);
    $sth->execute();
    $self->{dbh}->commit;
    
    $sql = "create index IF NOT EXISTS wordlist_letters_idx on wordlist (letters)";
    $sth = $self->{dbh}->prepare($sql);
    $sth->execute();
    $self->{dbh}->commit;
}


sub loadWordlist{
    my $self = shift;
    my $url = shift;
    my $page = $self->getPage($url);
    my $sql = "delete from wordlist";

   my $sth = $self->{dbh}->prepare($sql);
   $sth->execute();
   $self->{dbh}->commit;
    $self->globalCookie('wordlist_size', 0);

    my $count = 0;
    foreach my $line (split /\n/, $page){
        $count++;
        $line = uc($line);
        my $num_letters = length($line);
        my $letters = join '', sort { $a cmp $b } split(//, $line);
        my $sql = "INSERT INTO wordlist (word, letters, num_letters)
                  VALUES ('$line', '$letters', $num_letters)";

    my $sth = $self->{dbh}->prepare($sql);
       $sth->execute();
        if (! ($count % 10000)){
            $self->{dbh}->commit;
        }
    }
    $self->{dbh}->commit;
    
    $sql = "select count(*) as c from wordlist";
    $sth = $self->{dbh}->prepare($sql);
    $sth->execute();
    $self->{dbh}->commit;
    my $row = $sth->fetch;
    $count = $row->[0];

    $self->{num_wordlist_words} = $count;
    return $count;
}


sub findWords{
    my $self = shift;
    my $options = shift;
    my @ret;

    my @all_letters = split //, uc($options);
        
    for (my $i=@all_letters; $i>=5; $i--){
        my @tries = $self->chooseTry($i, @all_letters);
        foreach my $try (@tries){
            $self->addToList("letters = '$try'", " OR ");
        }

        my $sql = "select * from wordlist where " . $self->getList();
        my $sth = $self->{dbh}->prepare($sql);
        $sth->execute();
        $self->{dbh}->commit;

        while (my $row = $sth->fetch){
            push @ret, $row->[0];
        }
    }

    return @ret;
}

## Choose a list of subsets to try based on vowels & consonants.  
## This isn't meant to be exhaustive, that would be too expensive.
sub chooseTry{
    my $self=shift;
    my $num = shift;
    my @letters = @_;

    my @vowels_m;
    my @consonants_m;

    my %list;

    while (my $letter = pop @letters){
        if ($letter=~/A|E|I|O|U|Y/){
            push @vowels_m, $letter;
        }else{
            push @consonants_m, $letter;
        }
    }

    # there's a bug in here where the word is sometimes 1 char too long
    for (my $loop=0; $loop<300; $loop++){
        my @vowels = @vowels_m;
        my @consonants = @consonants_m;

        my $i = @vowels;
        if ($i>2){
           while ( --$i ){
                my $j = int rand( $i+1 );
                @vowels[$i,$j] = @vowels[$j,$i];
            }
        }

        $i = @consonants;
        if ($i>2){
            while ( --$i ){
                my $j = int rand( $i+1 );
                @consonants[$i,$j] = @consonants[$j,$i];
            }
        }

        my $word = pop @vowels;

        for (my $vc = @vowels; $vc > 0; $vc--){
            if (int(rand(2)) && defined($vowels[0])){
                $word.=pop @vowels;
            }
        }

        if (!$word){
            $word = "";
        }

        while (length($word) < $num){
            if (defined($consonants[0])){
                $word .= pop @consonants;
            }else{
                $word .= pop @vowels;
            }
        }
        $word = join '', sort { $a cmp $b } split(//, $word);
        $list{$word} = 1;
    }

    
    return keys %list;
}




sub settings{
    my $self = shift;

    # Call defineSetting for as many settings as you'd like to define.
    $self->defineSetting({
        name=>'setting name',    
        default=>'default value',
        allowed_values=>[],     # enumerated list. leave blank or delete to allow any value
        desc=>'Describe what this setting does'
    });
}


sub listeners{
    my $self = shift;
    
    ##  Which commands should this plugin respond to?
    ## Command Listeners - put em here.  eg [qw (cmd1 cmd2 cmd3)]
    my @commands = [qw(ws _endWSgame _showWSstatus findwords)];

    ## Values: irc_join irc_ping irc_part irc_quit
    ## Note that irc_quit does not send channel information, and that the quit message will be 
    ## stuck in $options
    my @irc_events = [qw () ];

    ## Example:  ["/^$self->{BotName}/i",  '/hug (\w+)\W*'.$self->{BotName}.'/i' ]
    ## The only modifier you can use is /i
    my @preg_matches = [qw () ];

    ## Works in conjuntion with preg_matches.  Match patterns in preg_matches but not
    ## these patterns.  example: ["/^$self->{BotName}, tell/i"]
    my @preg_excludes = [ qw() ];

    my $default_permissions =[
        {command=>"ws", flag=>'loadwordlist', require_group => UA_ADMIN},
        {command=>"ws", flag=>'dropwordlist', require_group => UA_ADMIN},
    ];

    return { commands=>@commands,
        permissions=>$default_permissions,
        irc_events=>@irc_events,
        preg_matches=>@preg_matches,
        preg_excludes=>@preg_excludes
    };

}

sub addHelp{
    my $self = shift;
    $self->addHelpItem("[plugin_description]", "WordScramble game.  Find as many words as you can using the letters provided.  5 letter minimum.");
    $self->addHelpItem("[ws]", "WordScramble game. Unscramble words.  ws -new to start a new game.  ws <word> to make guess. ws -show to show the current board.  Scoring: (length(word) - 5 ) * 2, plus points for each letter based on standard WordFeud scoring.  -3 for each invalid word.");
    $self->addHelpItem("[ws][-loadwordlist]", "Deletes the current wordlist and loads a wordlist to use with the game, and possibly with other games.  Expects a URL as a parameter.  Each line of the file should be a single word.  You can try loading http://rocks.bot.nu/projects/RocksBot/wordlist.txt");
    $self->addHelpItem("[ws][-dropwordlist]", "Drops the wordlist table.");
    $self->addHelpItem("[ws][-wordlistinfo]", "Show info about the wordlist.");
    $self->addHelpItem("[findwords]", "Find valid words in a string of characters. Words are checked against the current wordlist. (By default, this is TWL06, but the bot administrator may have changed it.)  This list of found words is not intended to be exhaustive.  Usage: findwords <string>");
}
1;
__END__
