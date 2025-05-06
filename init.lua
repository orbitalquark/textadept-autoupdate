-- Copyright 2025 Mitchell. See LICENSE.

--- Checks for application updates.
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
-- At this time, this module does not perform any auto-updates. The user is expected to act on
-- any update notifications.
-- @module autoupdate
local M = {}

--- Whether or not to check for updates on startup.
-- The default value is `false`.
M.check_on_startup = false

--- Command to send an HTTP request to check for updates.
-- The default value uses 'curl' on Windows, macOS, and BSD; it uses 'wget' on Linux.
M.fetch = not LINUX and 'curl -s' or 'wget -q -O-'

local json = require('autoupdate.dkjson')

-- Localizations.
local _L = _L
if not rawget(_L, 'Check for Updates') then
	_L['Check for Updates'] = '_Check for Updates'
	_L['Checking for updates...'] = 'Checking for updates...'
	_L['Update detected'] = 'Update detected'
	_L['Update Available'] = 'Update Available'
	_L['New version'] = 'New version'
	_L['Current version'] = 'Current version'
	_L['This link has been copied to your clipboard'] = 'This link has been copied to your clipboard'
	_L['No update detected'] = 'No update detected'
end

--- Checks for updates, shows a message box if there is one, and copies the update URL to the
-- clipboard so the user can download it.
function M.check()
	ui.statusbar_text = _L['Checking for updates...']
	ui.update()

	local p = assert(os.spawn(M.fetch ..
		' https://api.github.com/repos/orbitalquark/textadept/releases'), 'unable to check for updates')
	local releases = json.decode(p:read('a'))

	local current_version = _RELEASE:match('%d.+$')
	local stable = not current_version:find('%s') -- space means alpha, beta, or nightly

	for _, release in ipairs(releases) do
		if release.name == 'nightly' then goto continue end -- ignore nightly releases
		if release.prerelease and stable then goto continue end -- ignore unstable releases
		local version = release.name:gsub('_', ' ')
		if version == current_version then break end -- no new version
		ui.statusbar_text = string.format('%s (%s)', _L['Update detected'], version)
		buffer:copy_text(release.html_url)

		ui.dialogs.message{
			title = _L['Update Available'], text = table.concat({
				_L['New version'] .. ': ' .. version, --
				_L['Current version'] .. ': ' .. current_version, --
				'', -- blank line
				release.html_url, --
				'', -- blank line
				_L['This link has been copied to your clipboard']
			}, '\n')
		}
		do return true end

		::continue::
	end

	ui.statusbar_text = _L['No update detected']
end
events.connect(events.INITIALIZED, function() if M.check_on_startup then M.check() end end)

local m_about = textadept.menu.menubar['Help']
table.insert(m_about, #m_about - 1, {''}) -- separator
table.insert(m_about, #m_about - 1, {_L['Check for Updates'], M.check})

return M
