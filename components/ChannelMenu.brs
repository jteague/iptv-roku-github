sub init()
    m.border   = m.top.findNode("border")
    m.bg       = m.top.findNode("bg")
    m.title    = m.top.findNode("title")
    m.subtitle = m.top.findNode("subtitle")
    m.rowGroup = m.top.findNode("rowGroup")

    m.ROW_H  = 64
    m.WIDTH  = 640
    m.rows   = []
    m.items  = []
    m.focusIdx = 0
end sub

' Opening the menu: the cursor starts on the first item.
sub onDataChange()
    data = m.top.data
    if data = invalid then return
    m.title.text    = data.title
    m.subtitle.text = data.subtitle
    m.items = data.items
    m.focusIdx = 0

    while m.rows.count() < m.items.count()
        row = m.rowGroup.createChild("Group")
        row.translation = [0, m.rows.count() * m.ROW_H]
        bg = row.createChild("Rectangle")
        bg.translation = [16, 4]
        bg.width  = m.WIDTH - 32
        bg.height = m.ROW_H - 8
        label = row.createChild("Label")
        label.font = "font:SmallBoldSystemFont"
        label.vertAlign   = "center"
        label.translation = [40, 4]
        label.width  = m.WIDTH - 80
        label.height = m.ROW_H - 8
        m.rows.push({ node: row, bg: bg, label: label })
    end while

    height = 108 + m.items.count() * m.ROW_H + 16
    m.bg.height     = height
    m.border.height = height + 4
    render()
end sub

sub render()
    for i = 0 to m.rows.count() - 1
        row = m.rows[i]
        if i < m.items.count()
            row.label.text = m.items[i].label
            if i = m.focusIdx
                row.bg.color    = "0x96BBBBFF"
                row.label.color = "0x414535FF"
            else
                row.bg.color    = "0x414535FF"
                row.label.color = "0xF2E3BCFF"
            end if
            row.node.visible = true
        else
            row.node.visible = false
        end if
    end for
end sub

' Keys are forwarded from GuideScene (which keeps focus) via the keyEvent field.
sub onKeyEventField()
    key = m.top.keyEvent.key
    if key = "down"
        if m.focusIdx < m.items.count() - 1
            m.focusIdx = m.focusIdx + 1
            render()
        end if
    else if key = "up"
        if m.focusIdx > 0
            m.focusIdx = m.focusIdx - 1
            render()
        end if
    else if key = "OK"
        m.top.visible = false
        if m.focusIdx < m.items.count() then m.top.chosen = m.items[m.focusIdx].key
    else if key = "back" or key = "left"
        m.top.visible = false
    end if
end sub
