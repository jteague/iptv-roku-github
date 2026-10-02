' Guide programme filters ("what's on now"): the guide shows only channels whose
' current programme matches. A programme matches a filter when any rule does:
'   cat    its XMLTV categories (prog.cats, "|series|comedy|")
'   title  its title
'   chan   the channel name (sports networks; some providers' event channels end in "- NHL")
'   group  the channel's M3U group-title (e.g. "MLB Events")
' Tags are only half the story: some providers' channels carry no categories at all, so
' title and channel rules do most of the work there. Rules are case-insensitive
' PCRE; "" = no rule. Two rules veto a match: exclude (title or channel name) and
' skipCat (categories). The sports filters skip movies (The Karate Kid is not a
' fight). "Martial Arts" is not a fight tag: it also marks shows like Avatar.
' Array order is the order in the filter picker.

function programFilters() as object
    soccerTitle = "\b(soccer|f(u|ú)tbol|premier league|la ?liga|serie a|bundesliga|ligue 1|eredivisie|champions league|europa league|conference league|uefa|concacaf|conmebol|copa (am(e|é)rica|libertadores|sudamericana|del rey)|gold cup|fifa|mls|major league soccer|leagues cup|nwsl|usl|liga mx|fa cup|carabao cup|efl|a-league|superliga|liga portugal|scottish premiership|africa cup of nations|fc)\b"
    fightTitle  = "\b(ufc|mma|mixed martial arts|boxing|boxeo|bellator|pfl|one championship|bkfc|bare knuckle|jiu[- ]?jitsu|bjj|grappling|karate|kickboxing|muay thai|judo|taekwondo|wrestling|wwe|aew|nxt|smackdown|tna|njpw|top rank|golden boy|pbc|fight night|contender series)\b"
    footballTitle   = "\b(nfl|ncaaf|college football|f(u|ú)tbol americano|cfl|xfl|ufl|super bowl|(monday|thursday|sunday) night football|football)\b"
    basketballTitle = "\b(nba|wnba|ncaab|basketball|march madness|euroleague)\b"
    baseballTitle   = "\b(mlb|baseball|b(e|é)isbol)\b"
    hockeyTitle     = "\b(nhl|hockey|stanley cup)\b"
    golfTitle       = "\b(golf|pga|lpga|liv golf|ryder cup|solheim cup|presidents cup|dp world tour|korn ferry)\b"
    tennisTitle     = "\b(tennis|atp|wta|wimbledon|roland[- ]garros|davis cup|billie jean king cup|laver cup|united cup)\b"
    motorTitle      = "\b(nascar|indycar|formula (1|one|2|e)|f1|f2|motogp|supercross|motocross|imsa|le mans|drag racing|nhra)\b"
    ' Non-soccer sports that share soccer words ("Premier League", "Fútbol").
    soccerExclude = "\b(cricket|caribbean premier league|indian premier league|rugby|darts|snooker|netball|f(u|ú)tbol americano)\b"
    shopExclude   = "\b(shop|qvc|hsn)\b"
    noMovies = "\|movie\|"
    return [
        programFilter("news", "News", noMovies,
            "\|(news|newsmagazine)\|", "",
            "^(cnn|fox news|msnbc|cnbc|bloomberg|fox business|newsmax|sky news|bbc news|cbs news|abc news|nbc news|newsnation|the weather channel)",
            "", ""),
        programFilter("kids", "Kids", "",
            "\|(children|kids)\|", "",
            "pbs ?kids|disney (channel|junior|jr)|nick(elodeon| jr)|cartoon ?network|cartoonito|boomerang|pogo|kidz|cartoonz|studio ghibli|universal kids|baby ?tv",
            "", ""),
        programFilter("gameShows", "Game Shows", "",
            "\|game show\|",
            "\b(jeopardy|wheel of fortune|family feud|the price is right|let's make a deal|press your luck|the chase|who wants to be a millionaire|deal or no deal)\b",
            "game show network|\bgsn\b|buzzr", "", ""),
        ' American football. British titles and channels say "Football" for soccer.
        programFilter("football", "Football", noMovies,
            "\|football\|", footballTitle,
            "nfl network| - (nfl|ncaaf|cfl)$", "\b(nfl|ncaaf)\b",
            soccerTitle + "|sky sports? football|\b(afl|aussie rules|gaelic|rugby)\b|" + shopExclude),
        programFilter("basketball", "Basketball", noMovies,
            "\|basketball\|", basketballTitle, "nba tv| - (nba|wnba|ncaab)$", "\b(nba|wnba|ncaab)\b", ""),
        programFilter("baseball", "Baseball", noMovies,
            "\|baseball\|", baseballTitle, "mlb network| - mlb$", "\bmlb\b", ""),
        programFilter("hockey", "Hockey", noMovies,
            "\|hockey\|", hockeyTitle, "nhl network| - nhl$", "\bnhl\b", "\bair hockey\b"),
        programFilter("soccer", "Soccer", noMovies,
            "\|soccer\|", soccerTitle,
            "golazo|fox soccer|sky sports? (football|premier league)| - (soccer|mls|epl|nwsl|uefa|fifa)$",
            "\b(soccer|mls|epl|nwsl|uefa)\b", soccerExclude),
        programFilter("golf", "Golf", noMovies,
            "\|golf\|", golfTitle, "^golf channel| - (golf|pga)$", "\b(golf|pga)\b", "\b(mini(ature)?|disc|crazy) golf\b"),
        programFilter("tennis", "Tennis", noMovies,
            "\|tennis\|", tennisTitle, "^tennis channel| - tennis$", "\btennis\b", "\b(table|paddle|platform) tennis\b"),
        programFilter("fights", "Combat Sports", "\|(movie|documentary)\|",
            "\|(boxing|kickboxing|mma|mixed martial arts|[^|]*wrestling)\|", fightTitle,
            "^(ufc|wwe|fight network)| - (mma|ufc|boxing|bjj|wrestling|kickboxing|bkfc|pfl)$",
            "\b(ufc|mma|boxing|ppv)\b", ""),
        programFilter("motor", "Motorsports", noMovies,
            "\|(auto|auto racing|drag racing|motorcycle racing|motorsports?)\|", motorTitle,
            "sky sports f1| - (nascar|f1|indycar|motogp)$", "", "\b(horse|greyhound)\b"),
        programFilter("movies", "Movies", "",
            "\|(movie|feature film|tv movie)\|", "",
            "^(hbo|cinemax|showtime|starz|mgm|fxm|sky cinema|tcm)|\bmovie|moviez", "", "")
    ]
end function

' exclude is tested against the title and the channel name, and wins over every rule.
function programFilter(key as string, label as string, skipCat as string, cat as string, title as string, chan as string, group as string, exclude as string) as object
    return { key: key, label: label, skipCat: skipCat, cat: cat, title: title, chan: chan, group: group, exclude: exclude }
end function

' programFilters() with each rule compiled to an roRegex (invalid for "").
' Build once per scene; compiling on every check would dominate the cost.
function compileProgramFilters() as object
    filters = programFilters()
    for each f in filters
        for each rule in ["skipCat", "cat", "title", "chan", "group", "exclude"]
            if f[rule] = "" then f[rule] = invalid else f[rule] = CreateObject("roRegex", f[rule], "i")
        end for
    end for
    return filters
end function

' Placeholder titles on providers' event channels between games.
function placeholderRegex() as object
    return CreateObject("roRegex", "^\s*(event has (not started|ended)|no event|off air)", "i")
end function

' prog: the channel's current programme, or invalid when it has no guide data
' (then only the channel rules can match). skip: placeholderRegex().
function programMatchesFilter(f as object, ch as object, prog as dynamic, skip as object) as boolean
    if prog <> invalid
        if skip.IsMatch(prog.title) then return false
        if f.exclude <> invalid
            if f.exclude.IsMatch(prog.title) then return false
        end if
        cats = ""
        if prog.cats <> invalid then cats = prog.cats
        if f.skipCat <> invalid and cats <> ""
            if f.skipCat.IsMatch(cats) then return false
        end if
        if f.cat <> invalid and cats <> ""
            if f.cat.IsMatch(cats) then return true
        end if
        if f.title <> invalid
            if f.title.IsMatch(prog.title) then return true
        end if
    end if
    if f.exclude <> invalid
        if f.exclude.IsMatch(ch.name) then return false
    end if
    if f.chan <> invalid
        if f.chan.IsMatch(ch.name) then return true
    end if
    if f.group <> invalid and ch.group <> invalid
        if f.group.IsMatch(ch.group) then return true
    end if
    return false
end function
