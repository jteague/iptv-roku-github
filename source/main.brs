sub Main(args as dynamic)
    screen = CreateObject("roSGScreen")
    m.port = CreateObject("roMessagePort")
    screen.setMessagePort(m.port)
    scene = screen.CreateScene("MainScene")
    screen.show()
    scene.observeField("exitApp", m.port)

    ' Deep link at launch, and later ones while running (roInput).
    if args <> invalid and args.contentId <> invalid
        scene.deepLink = { contentId: args.contentId, mediaType: args.mediaType }
    end if
    input = CreateObject("roInput")
    input.setMessagePort(m.port)

    while true
        msg = wait(0, m.port)
        msgType = type(msg)
        if msgType = "roSGScreenEvent"
            if msg.isScreenClosed() then return
        else if msgType = "roSGNodeEvent"
            if msg.getField() = "exitApp" then return
        else if msgType = "roInputEvent"
            if msg.isInput()
                info = msg.getInfo()
                if info.contentId <> invalid
                    scene.deepLink = { contentId: info.contentId, mediaType: info.mediaType }
                end if
            end if
        end if
    end while
end sub
