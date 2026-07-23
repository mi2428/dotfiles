#!/usr/bin/osascript

-- Open a Ghostty workspace with Herdr on the left and tmux on the right.
--
-- The left pane starts in the caller's working directory; the tmux pane
-- always starts in the home directory. Finder launches fall back to home.

-- Fixed Herdr pane width in pixels.
property herdrWidth : 700

on run
    set homeDirectory to POSIX path of (path to home folder)

    if herdrWidth is less than or equal to 0 then error "herdrWidth must be greater than zero"

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
        activate window workspaceWindow
        focus herdrPane

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
        activate window workspaceWindow
        focus herdrPane
    end tell

    -- Quick Terminal hides asynchronously. Wait until the new two-pane window
    -- is frontmost, then reapply its geometry until macOS reports the captured
    -- values. This prevents the final window-placement pass from restoring the
    -- default height after this script has already resized the window.
    tell application "System Events"
        tell process "Ghostty"
            set frontmost to true
            set workspaceWindowReady to false

            repeat 100 times
                try
                    set candidateWindow to front window
                    set splitGroup to group 1 of group 1 of candidateWindow
                    if (count of groups of splitGroup) is 2 then
                        set workspaceWindowReady to true
                        exit repeat
                    end if
                end try
                delay 0.02
            end repeat

            if not workspaceWindowReady then error "The new Ghostty workspace window did not become frontmost"

            set desiredWindowSize to {2294, 1440}
            set desiredWindowPosition to {312, 243}
            set geometryRestored to false

            repeat 6 times
                set position of front window to desiredWindowPosition
                delay 0.1
                set size of front window to desiredWindowSize
                delay 0.1
                set position of front window to desiredWindowPosition
                delay 0.1

                if (size of front window is desiredWindowSize) and (position of front window is desiredWindowPosition) then
                    set geometryRestored to true
                    exit repeat
                end if
            end repeat

            if not geometryRestored then error "macOS did not restore the requested Ghostty window geometry"

            set restoredWindowSize to size of front window
            set restoredWindowWidth to item 1 of restoredWindowSize
        end tell
    end tell

    tell application "Ghostty"
        -- Ghostty creates a 1:1 split. Move the divider from the center so
        -- Herdr reaches its fixed target width.
        set contentWidth to restoredWindowWidth - 1
        set initialHerdrWidth to contentWidth div 2
        set widthDelta to herdrWidth - initialHerdrWidth

        if widthDelta is less than 0 then
            set resizeAmount to -widthDelta
            perform action ("resize_split:left," & resizeAmount) on herdrPane
        else if widthDelta is greater than 0 then
            perform action ("resize_split:right," & widthDelta) on herdrPane
        end if

        focus herdrPane
    end tell
end run
