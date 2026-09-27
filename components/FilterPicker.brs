sub init()
    m.bg       = m.top.findNode("bg")
    m.edge     = m.top.findNode("edge")
    m.title    = m.top.findNode("title")
    m.rowGroup = m.top.findNode("rowGroup")

    m.pageRows = 0
    m.rows   = []
    m.items  = []
    m.active = ""
    m.topIdx   = 0
    m.focusIdx = 0
end sub

' Build the row pool once; there can be more filters than rows, so the
' list scrolls over these rows rather than creating one node set per filter.
sub onLayoutChange()
    lay = m.top.layout
    if lay = invalid or m.rows.count() > 0 then return
    m.pageRows = lay.rows
    height = lay.headerH + lay.rows * lay.rowHeight
    m.bg.width   = lay.width
    m.bg.height  = height
    m.edge.height = height
    m.edge.translation = [lay.width - 2, 0]
    m.title.width  = lay.width - 32
    m.title.height = lay.headerH
    m.rowGroup.translation = [0, lay.headerH]

    for i = 0 to lay.rows - 1
        row = m.rowGroup.createChild("Group")
        row.translation = [0, i * lay.rowHeight]
        bg = row.createChild("Rectangle")
        bg.width  = lay.width - 2
        bg.height = lay.rowHeight
        ' Marks the filter the guide is showing now.
        mark = row.createChild("Rectangle")
        mark.color  = "0xC19875FF"
        mark.width  = 6
        mark.height = lay.rowHeight
        name = row.createChild("Label")
        name.color  = "0xF2E3BCFF"
        name.font   = "font:SmallSystemFont"
        name.vertAlign   = "center"
        name.translation = [22, 0]
        name.width  = lay.width - 140
        name.height = lay.rowHeight
        count = row.createChild("Label")
        count.color  = "0x96BBBBFF"
        count.font   = "font:SmallSystemFont"
        count.horizAlign  = "right"
        count.vertAlign   = "center"
        count.translation = [lay.width - 112, 0]
        count.width  = 92
        count.height = lay.rowHeight
        m.rows.push({ node: row, bg: bg, mark: mark, name: name, count: count })
    end for
end sub

' Opening the picker: the cursor starts on the active filter.
sub onDataChange()
    data = m.top.data
    if data = invalid then return
    m.items  = data.items
    m.active = data.active
    m.focusIdx = 0
    for i = 0 to m.items.count() - 1
        if m.items[i].key = m.active
            m.focusIdx = i
            exit for
        end if
    end for
    m.topIdx = 0
    if m.focusIdx >= m.pageRows then m.topIdx = m.focusIdx - m.pageRows + 1
    render()
end sub

sub render()
    for i = 0 to m.rows.count() - 1
        row = m.rows[i]
        idx = m.topIdx + i
        if idx < m.items.count()
            item = m.items[idx]
            row.name.text  = item.label
            row.count.text = item.count.toStr()
            if idx = m.focusIdx
                row.bg.color = "0x618985FF"
            else
                row.bg.color = "0x2F3227FF"
            end if
            row.mark.visible = (item.key = m.active)
            row.node.visible = true
        else
            row.node.visible = false
        end if
    end for
end sub

sub moveFocus(delta as integer)
    last = m.items.count() - 1
    if last < 0 then return
    idx = m.focusIdx + delta
    if idx < 0 then idx = 0
    if idx > last then idx = last
    if idx = m.focusIdx then return
    m.focusIdx = idx
    if m.focusIdx < m.topIdx then m.topIdx = m.focusIdx
    if m.focusIdx >= m.topIdx + m.pageRows then m.topIdx = m.focusIdx - m.pageRows + 1
    render()
end sub

' Keys are forwarded from GuideScene (which keeps focus) via the keyEvent field.
sub onKeyEventField()
    key = m.top.keyEvent.key
    if key = "down"
        moveFocus(1)
    else if key = "up"
        moveFocus(-1)
    else if key = "fastforward"
        moveFocus(m.pageRows)
    else if key = "rewind"
        moveFocus(-m.pageRows)
    else if key = "OK"
        m.top.visible = false
        if m.focusIdx < m.items.count() then m.top.chosen = m.items[m.focusIdx].key
    else if key = "back" or key = "left" or key = "replay"
        m.top.visible = false
    end if
end sub
