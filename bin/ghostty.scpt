#!/usr/bin/osascript

-- Open a Ghostty workspace with Herdr on the left and tmux on the right.
--
-- The left pane starts in the caller's working directory; the tmux pane
-- always starts in the home directory. Finder launches fall back to home.

-- Herdr : tmux. Change these two numbers to adjust the split ratio.
property paneRatio : {3, 7}

on run
    set homeDirectory to POSIX path of (path to home folder)

    set herdrRatio to item 1 of paneRatio
    set tmuxRatio to item 2 of paneRatio
    if herdrRatio is less than or equal to 0 or tmuxRatio is less than or equal to 0 then
        error "paneRatio values must both be greater than zero"
    end if

    try
        set projectDirectory to system attribute "PWD"
        if projectDirectory is "" or projectDirectory is "/" then set projectDirectory to homeDirectory
    on error
        set projectDirectory to homeDirectory
    end try

    tell application "Ghostty"
        activate

        set herdrConfiguration to new surface configuration
        set initial working directory of herdrConfiguration to projectDirectory

        set tmuxConfiguration to new surface configuration
        set initial working directory of tmuxConfiguration to homeDirectory

        set workspaceWindow to new window with configuration herdrConfiguration
        set herdrPane to terminal 1 of selected tab of workspaceWindow
        set tmuxPane to split herdrPane direction right with configuration tmuxConfiguration
    end tell

    -- Restore the captured macOS window geometry. The window created above is
    -- frontmost, so System Events can address it without relying on its title.
    tell application "System Events"
        tell process "Ghostty"
            set frontmost to true
            set size of front window to {2294, 1440}
            delay 0.1
            set position of front window to {312, 243}
            delay 0.1
            set restoredWindowSize to size of front window
            set restoredWindowWidth to item 1 of restoredWindowSize
        end tell
    end tell

    tell application "Ghostty"
        -- Ghostty creates a 1:1 split. Convert paneRatio into the number of
        -- pixels by which the divider must move from the center.
        set contentWidth to restoredWindowWidth - 1
        set initialHerdrWidth to contentWidth div 2
        set targetHerdrWidth to round (contentWidth * herdrRatio / (herdrRatio + tmuxRatio))
        set widthDelta to targetHerdrWidth - initialHerdrWidth

        if widthDelta is less than 0 then
            set resizeAmount to -widthDelta
            perform action ("resize_split:left," & resizeAmount) on herdrPane
        else if widthDelta is greater than 0 then
            perform action ("resize_split:right," & widthDelta) on herdrPane
        end if

        -- Keep Ghostty's normal shell startup and shell integration so titles
        -- match regular windows. Wait until both shells publish their titles
        -- before sending the startup commands.
        repeat 100 times
            if (name of herdrPane is not "👻") and (name of tmuxPane is not "👻") then exit repeat
            delay 0.02
        end repeat

        input text "herdr" to herdrPane
        send key "enter" to herdrPane
        input text "tmux" to tmuxPane
        send key "enter" to tmuxPane
        focus herdrPane
    end tell
end run
