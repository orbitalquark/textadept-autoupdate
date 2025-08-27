-- Copyright 2025 Mitchell. See LICENSE.

--- Checks for application updates and optionally applies them.
-- Install this module by copying it into your *~/.textadept/modules/* directory or Textadept's
-- *modules/* directory, and then putting the following in your *~/.textadept/init.lua*:
--
-- ```lua
-- local autoupdate = require('autoupdate')
-- ```
--
-- There will be a "Help > Check for Updates" menu item. You can also have Textadept check for
-- updates on startup by setting `autoupdate.check_on_startup`.
--
-- **macOS Note:** if you downloaded Textadept and ran it from your *~/Downloads/* folder,
-- performing an update will fail due to macOS's App Translocation security feature. Moving
-- *Textadept.app* to another location like */Applications/* or *~/Applications/* and then
-- trying again will allow updates to work.
-- @module autoupdate
local M = {}

--- Whether or not to check for updates on startup.
-- The default value is `false`.
M.check_on_startup = false

--- Command to send an HTTP request to check for updates.
-- The default value uses 'curl' on Windows, macOS, and BSD; it uses 'wget' on Linux.
M.fetch = not LINUX and 'curl -s' or 'wget -q -O-'

--- Format string for a command to download an update archive.
-- The first placeholder is the URL to download, and the second placeholder is the filename to
-- save to.
-- The default value uses 'curl' on Windows, macOS, and BSD; it uses 'wget' on Linux.
M.download = not LINUX and 'curl %s -# -o "%s" -L' or 'wget %s --progress=bar -O "%s"'

--- Command used to open a URL in a browser.
M.browser = WIN32 and 'start ""' or OSX and 'open' or LINUX and 'xdg-open'

local json = require('autoupdate.dkjson')

local ARM = LINUX and io.popen('uname -m'):read() == 'aarch64'

local updates_dir = _USERHOME .. '/updates'
if WIN32 then updates_dir = updates_dir:gsub('/', '\\') end
if not lfs.attributes(updates_dir) then assert(lfs.mkdir(updates_dir)) end

--- Logs a formatted string to the autoupdate log file.
-- @param ... Arguments to pass to `string.format()`.
local function log(...)
	io.open(_USERHOME .. '/autoupdate.log', 'a+'):write(string.format(...), '\n'):close()
end

--- Downloads a release archive to a file.
-- A dialog tracks download progress.
-- @param url String URL of the archive to download.
-- @param file String absolute filename to save the download to.
-- @return whether or not the asset was successfully downloaded
local function download(url, file)
	if lfs.attributes(file) then return true end -- for testing purposes to avoid re-downloading

	log('downloading %s', file)
	local progress, success = -1, nil
	local cmd = string.format(M.download, url, file)
	local p = assert(os.spawn(cmd, nil, function(output) -- progress is output to stderr
		progress = output:match('(%d+)%.?%d*%%') or progress
	end, function(status) progress, success = nil, status == 0 end), 'unable to download update')

	local stop = ui.dialogs.progress{
		title = _L['Downloading:'] .. ' ' .. file:match('[^/\\]+$'), work = function()
			if not progress then return nil end
			os.spawn(not WIN32 and 'sleep 0.1' or 'timeout /T 1'):wait() -- avoid busy wait for progress
			return progress
		end
	}
	if stop then
		p:kill()
		os.remove(file)
	end

	return success
end

--- Downloads, unpacks, and prepares an update.
-- @param asset GitHub API asset object, either a platform asset or modules asset.
local function prepare_update(asset)
	local filename = updates_dir .. '/' .. asset.name
	if not download(asset.browser_download_url, filename) then return false end
	ui.statusbar_text = _L['Unpacking update...']
	ui.update()

	log('unpacking %s', filename)
	local cmd = filename:find('%.zip$') and 'unzip -o' or 'tar xzf'
	cmd = string.format('%s "%s"', cmd, filename)
	if WIN32 then
		cmd = string.format(
			[[powershell -command "Expand-Archive -Path '%s' -DestinationPath '%s' -Force"]], filename,
			updates_dir)
	end
	assert(os.spawn(cmd, updates_dir, nil, nil, function(status)
		if status ~= 0 then
			os.remove(filename)
			log('failed to unpack: %d', status)
			error('failed to unpack update')
		end

		-- Apply the update before Textadept quits.
		events.connect(events.QUIT, function()
			ui.statusbar_text = _L['Applying update...']
			ui.update()

			local sep = not WIN32 and '/' or '\\' -- Windows' xcopy is picky about directory separators
			-- Most non-module downloads have a top-level 'textadept' directory.
			local source, target = updates_dir .. sep .. 'textadept', _HOME
			-- Module downloads have a top-level 'textadept-modules' directory.
			if filename:find('modules%.zip$') then
				source, target = source .. '-modules', target .. sep .. 'modules'
			elseif OSX then
				-- macOS non-module downloads have a top-level 'Textadept.app' directory.
				source = updates_dir .. '/Textadept.app'
				-- Release builds have a _HOME inside Textadept.app, so updates need to be applied to the
				-- app directory.
				if _HOME:find('Resources$') then target = target .. '/../..' end -- Textadept.app
			end
			log('copying %s to %s', source, target)

			-- Copy all files and directories from the update.
			for file in lfs.dir(source) do
				if file:find('^%.%.?$') then goto continue end
				cmd = not WIN32 and 'cp -Rf' or 'xcopy /s /y /i'
				log(string.format('%s "%s%s%s" "%s%s%s"', cmd, source, sep, file, target, sep, file))
				local status = os.spawn(string.format('%s "%s%s%s" "%s%s%s"', cmd, source, sep, file,
					target, sep, file)):wait()
				if status == 0 then goto continue end
				log('copying %s failed: %d', file, status)
				if not WIN32 or not file:find('%.exe$') then goto continue end
				-- Windows does not allow updating of executables currently in use, so put updated exes in
				-- _HOME and ask the user to finish the update.
				os.spawn(string.format('%s "%s\\%s" "%s\\%s"', cmd, source, file, target,
					file:gsub('%.exe$', '.new.exe'))):wait()
				local button = ui.dialogs.message{
					title = _L['Autoupdate'],
					text = _L['One or more executables is currently in use and cannot be auto-updated. ' ..
						'After Textadept exits, please rename all ".new.exe" files to ".exe" in this folder: '] ..
						target, button2 = _L['Cancel'], button3 = _L['Show Directory']
				}
				if button == 3 then os.spawn(string.format('%s "%s"', M.browser, target)) end
				::continue::
			end

			cmd = not WIN32 and 'rm -r' or 'rmdir /S /Q'
			os.spawn(string.format('%s "%s"', cmd, source)):wait()
			os.remove(filename)
		end)

		if not asset.name:find('modules%.zip$') then return end
		ui.statusbar_text = '' -- clear unpacking... message
		ui.dialogs.message{
			title = _L['Update Ready'], text = _L['Please restart Textadept to install updates']
		}
	end))

	return true
end

--- Checks for updates and shows a message box if there is one.
-- The message box has a button for downloading the update.
function M.check()
	ui.statusbar_text = _L['Checking for updates...']
	ui.update()

	local p = assert(os.spawn(M.fetch ..
		' https://api.github.com/repos/orbitalquark/textadept/releases'), 'unable to check for updates')
	local releases = json.decode(p:read('a'))
	if not releases then
		ui.statusbar_text = _L['Could not fetch update information']
		return
	end

	local current_version = _RELEASE:match('%d.+$')
	local check_time = current_version:find('nightly') and
		lfs.attributes(_HOME .. '/core/init.lua', 'modification')
	local stable = not current_version:find('%s') -- space means alpha, beta, or nightly

	for _, release in ipairs(releases) do
		if release.name == 'nightly' then goto continue end -- ignore nightly releases
		if release.prerelease and stable then goto continue end -- ignore unstable releases
		local version = release.name:gsub('_', ' ')
		if version == current_version then break end -- no new version
		if check_time then
			-- The current version is a nightly, so compare the modification time of core/init.lua with
			-- the release's time.
			local year, month, day = release.published_at:match('^(%d+)%-(%d+)%-(%d+)')
			local release_time = os.time{year = year, month = month, day = day}
			if release_time < check_time then return end -- no new version
		end
		ui.statusbar_text = string.format('%s (%s)', _L['Update detected'], version)

		-- Output release notes.
		buffer.new()
		buffer:append_text(release.body)
		buffer:set_save_point()
		buffer:set_lexer('markdown')

		-- Determine update asset.
		local platform_asset, modules_asset
		for _, asset in ipairs(release.assets) do
			if asset.name:find('modules%.zip$') then
				modules_asset = asset
			elseif (WIN32 and asset.name:find('win%.zip$')) or (OSX and asset.name:find('macOS%.zip$')) or
				(LINUX and ARM and asset.name:find('linux%.arm%.tgz$')) or
				(LINUX and not ARM and asset.name:find('linux%.tgz$')) then
				platform_asset = asset
			end
		end

		-- Show notification.
		local button = ui.dialogs.message{
			title = _L['Update Available'], text = table.concat({
				_L['New version'] .. ': ' .. version, --
				_L['Current version'] .. ': ' .. current_version, --
				'', -- blank line
				release.html_url --
			}, '\n'), button1 = _L['View Update'], button2 = _L['Cancel'],
			button3 = platform_asset and _L['Perform Update'] or nil
		}
		if button == 1 then
			os.spawn(M.browser .. ' ' .. release.html_url)
		elseif button == 3 then
			local ok = prepare_update(platform_asset)
			-- TODO: heuristic to determine if modules are installed?
			if ok then ok = prepare_update(modules_asset) end
			if not ok then ui.statusbar_text = _L['Update cancelled'] end
		end
		do return true end

		::continue::
	end

	ui.statusbar_text = _L['No update detected']
end
events.connect(events.INITIALIZED, function() if M.check_on_startup then M.check() end end)

-- Add a menu entry.
_L['Check for Updates'] = '_Check for Updates'
local m_about = textadept.menu.menubar['Help']
table.insert(m_about, #m_about - 1, {''}) -- separator
table.insert(m_about, #m_about - 1, {_L['Check for Updates'], M.check})

return M
