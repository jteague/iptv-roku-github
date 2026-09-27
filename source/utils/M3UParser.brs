' Parse M3U text into array of channel objects.
' Each channel: { id, number, name, logoUrl, group, streamUrl }; group is "" when
' the #EXTINF line has no group-title.
function parseM3U(text as string) as object
    channels = []
    lines = text.split(Chr(10))
    i = 0
    while i < lines.count()
        line = lines[i].trim()
        if Left(line, 7) = "#EXTINF"
            chName = extractExtinfTitle(line)
            ' HDHomeRun writes channel-id / channel-number instead of the tvg- attributes.
            chId = extractAttr(line, "tvg-id")
            if chId = "" then chId = extractAttr(line, "channel-id")
            if chId = "" then chId = chName
            chNumber = extractAttr(line, "tvg-chno")
            if chNumber = "" then chNumber = extractAttr(line, "channel-number")
            ch = {
                id:        chId,
                number:    chNumber,
                name:      chName,
                logoUrl:   extractAttr(line, "tvg-logo"),
                group:     extractAttr(line, "group-title"),
                streamUrl: ""
            }
            ' Next non-blank line is the stream URL.
            j = i + 1
            while j < lines.count()
                candidate = lines[j].trim()
                if candidate <> "" and Left(candidate, 1) <> "#"
                    ch.streamUrl = candidate
                    i = j
                    exit while
                end if
                j = j + 1
            end while
            if ch.streamUrl <> "" then channels.push(ch)
        end if
        i = i + 1
    end while
    return channels
end function

function extractAttr(line as string, attrName as string) as string
    search = attrName + "="""
    attrPos = Instr(1, line, search)
    if attrPos = 0 then return ""
    valStart = attrPos + Len(search)
    valEnd = Instr(valStart, line, """")
    if valEnd = 0 then return ""
    return Mid(line, valStart, valEnd - valStart)
end function

function extractExtinfTitle(line as string) as string
    commaPos = Instr(1, line, ",")
    if commaPos = 0 then return ""
    return Mid(line, commaPos + 1).trim()
end function
