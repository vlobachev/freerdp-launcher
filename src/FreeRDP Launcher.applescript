-- FreeRDP Launcher
-- A tiny native macOS GUI front-end / connection manager for FreeRDP (sdl-freerdp).
--
-- Why it exists: Microsoft's "Windows App" / Remote Desktop client fails NLA against
-- some RDP servers (notably gnome-remote-desktop: error 0x207 / NTLM MIC failure),
-- while FreeRDP authenticates correctly. FreeRDP ships only a command-line client on
-- macOS; this app gives it a clickable connection manager.
--
-- Connection profiles live in:  ~/.config/freerdp-launcher/connections.tsv
-- Format (TAB-separated, one per line):  name <TAB> host <TAB> user <TAB> extra_flags
-- Lines starting with "#" are ignored. No hosts or passwords are stored in the app.

property appTitle : "FreeRDP Launcher"

on run
	set cfgDir to (POSIX path of (path to home folder)) & ".config/freerdp-launcher"
	set cfgFile to cfgDir & "/connections.tsv"
	do shell script "mkdir -p " & quoted form of cfgDir & " && touch " & quoted form of cfgFile

	-- Locate a FreeRDP binary (prefer the SDL client, fall back to xfreerdp).
	-- `do shell script` runs with a minimal PATH, so include the Homebrew dirs
	-- (Apple Silicon + Intel) explicitly.
	set rdpBin to (do shell script "PATH=/opt/homebrew/bin:/usr/local/bin:/opt/homebrew/sbin:/usr/local/sbin:$PATH; command -v sdl-freerdp 2>/dev/null || command -v sdl-freerdp3 2>/dev/null || command -v xfreerdp 2>/dev/null || true")
	if rdpBin is "" then
		display dialog "FreeRDP is not installed." & return & return & "Install it with Homebrew:" & return & "    brew install freerdp" with title appTitle buttons {"OK"} default button "OK" with icon stop
		return
	end if

	set profiles to readProfiles(cfgFile)

	-- Build the menu.
	set addLabel to "+  Add connection…"
	set editLabel to "✎  Edit connections file…"
	set menuItems to {}
	repeat with p in profiles
		set end of menuItems to (item 1 of p)
	end repeat
	set end of menuItems to addLabel
	set end of menuItems to editLabel

	set chosen to (choose from list menuItems with title appTitle with prompt "Choose a connection:" without empty selection allowed)
	if chosen is false then return
	set pick to (item 1 of chosen) as text

	if pick is addLabel then
		addConnection(cfgFile)
		return
	else if pick is editLabel then
		do shell script "open -e " & quoted form of cfgFile
		return
	end if

	-- Resolve the chosen profile.
	set theProfile to missing value
	repeat with p in profiles
		if (item 1 of p) is pick then
			set theProfile to p
			exit repeat
		end if
	end repeat
	if theProfile is missing value then return

	set theHost to item 2 of theProfile
	set theUser to item 3 of theProfile
	set extraFlags to item 4 of theProfile

	-- Password (hidden, never stored).
	set pwDlg to (display dialog "Password for " & theUser & "@" & theHost & ":" default answer "" with hidden answer with title appTitle buttons {"Cancel", "Connect"} default button "Connect")
	if button returned of pwDlg is "Cancel" then return
	set thePW to text returned of pwDlg

	-- Screen mode.
	set modeBtn to button returned of (display dialog "Screen mode:" with title appTitle buttons {"Window", "Fullscreen"} default button "Window")
	if modeBtn is "Fullscreen" then
		-- FreeRDP 3 uses "+f" for fullscreen ("/f" is ignored). Ctrl+Alt+Enter toggles.
		set modeFlag to "+f /dynamic-resolution"
	else
		set modeFlag to "/dynamic-resolution"
	end if

	-- Launch detached so the FreeRDP window owns the session.
	set theCmd to quoted form of rdpBin & " /v:" & quoted form of theHost & " /u:" & quoted form of theUser & " /p:" & quoted form of thePW & " /cert:ignore " & modeFlag & " +clipboard /sound:sys:mac " & extraFlags & " >/dev/null 2>&1 &"
	do shell script theCmd
end run

on readProfiles(cfgFile)
	set out to {}
	set raw to ""
	try
		set raw to (do shell script "cat " & quoted form of cfgFile)
	end try
	if raw is "" then return out
	set oldTID to AppleScript's text item delimiters
	repeat with ln in (paragraphs of raw)
		set lnStr to (ln as text)
		if lnStr is not "" and lnStr does not start with "#" then
			set AppleScript's text item delimiters to tab
			set parts to text items of lnStr
			set AppleScript's text item delimiters to oldTID
			if (count of parts) ≥ 3 then
				set nm to item 1 of parts
				set hh to item 2 of parts
				set uu to item 3 of parts
				if (count of parts) ≥ 4 then
					set ff to item 4 of parts
				else
					set ff to ""
				end if
				set end of out to {nm, hh, uu, ff}
			end if
		end if
	end repeat
	set AppleScript's text item delimiters to oldTID
	return out
end readProfiles

on addConnection(cfgFile)
	set nm to text returned of (display dialog "Connection name:" default answer "" with title appTitle)
	set hh to text returned of (display dialog "Host (IP or hostname):" default answer "" with title appTitle)
	set uu to text returned of (display dialog "Username:" default answer "" with title appTitle)
	set ff to text returned of (display dialog "Extra FreeRDP flags (optional):" default answer "" with title appTitle)
	if nm is "" or hh is "" or uu is "" then
		display dialog "Name, host and username are required." with title appTitle buttons {"OK"} default button "OK" with icon caution
		return
	end if
	set lineStr to nm & tab & hh & tab & uu & tab & ff
	do shell script "printf '%s\\n' " & quoted form of lineStr & " >> " & quoted form of cfgFile
	display dialog "Added “" & nm & "”." & return & return & "Open the app again to connect." with title appTitle buttons {"OK"} default button "OK"
end addConnection
