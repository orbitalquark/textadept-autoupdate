-- Copyright 2025 Mitchell. See LICENSE.

local autoupdate = require('autoupdate')
local json = require('autoupdate.dkjson')

local nightly_name, nightly_url = 'nightly', 'https://nightly'
local beta_url = 'https://beta'
local stable_url = 'https://stable'

--- Conditional for `test.mock(os, 'spawn')` if autoupdate is requesting release information.
local function is_request(cmd) return cmd:sub(1, #autoupdate.fetch) == autoupdate.fetch end

--- Mocks a GitHub REST response that returns 3 releases: a nightly, a beta, and a stable.
-- @param beta String beta version.
-- @param stable String stable version.
-- @usage local _<close> = test.mock(os, 'spawn', mock_spawn('2.0 beta', '1.1')) -- current is 1.0
local function mock_spawn(beta, stable)
	return function()
		return {
			read = function()
				return json.encode{
					{
						name = nightly_name, prerelease = true, html_url = nightly_url,
						published_at = os.date('%Y-%m-%d'), body = 'notes'
					}, --
					{
						name = beta:gsub(' ', '_'), prerelease = true, html_url = beta_url,
						published_at = os.date('%Y-%m-%d'), body = 'notes'
					}, --
					{name = stable, html_url = stable_url, published_at = os.date('%Y-%m-%d'), body = 'notes'}
				}
			end
		}
	end
end

test('autoupdate.check show show stable -> stable update', function()
	local current, next_beta, next_stable = '1.0', '2.0 beta', '1.1'
	local _<close> = test.mock(_G, '_RELEASE', 'Textadept ' .. current)
	local _<close> = test.mock(os, 'spawn', is_request, mock_spawn(next_beta, next_stable))
	local message = test.stub()
	local _<close> = test.mock(ui.dialogs, 'message', message)
	local _<close> = test.disable_metafield(ui, 'statusbar_text')

	local update_found = autoupdate.check()

	test.assert_equal(update_found, true)
	test.assert_equal(message.called, true)
	test.assert_contains(message.args[1].text, next_stable)
	test.assert_contains(message.args[1].text, current)
	test.assert_contains(message.args[1].text, stable_url)
	test.assert_equal(buffer:get_text(), 'notes')
	test.assert_equal(buffer.modify, false)
	test.assert_equal(buffer.lexer_language, 'markdown')
	test.assert(ui.statusbar_text:find(_L['Update detected']))
end)

test('autoupdate.check should copy release URL to clipboard if selected', function()
	local current, next_beta, next_stable = '1.0', '2.0 beta', '1.1'
	local _<close> = test.mock(_G, '_RELEASE', 'Textadept ' .. current)
	local _<close> = test.mock(os, 'spawn', is_request, mock_spawn(next_beta, next_stable))
	local click_copy = test.stub(3)
	local _<close> = test.mock(ui.dialogs, 'message', click_copy)

	autoupdate.check()

	test.assert_equal(ui.get_clipboard_text(), stable_url)
end)

test('autoupdate.check should show beta -> beta update', function()
	local current, next_beta, next_stable = '1.1 beta', '1.1 beta 2', '1.0'
	local _<close> = test.mock(_G, '_RELEASE', current)
	local message = test.stub()
	local _<close> = test.mock(ui.dialogs, 'message', message)
	local _<close> = test.mock(os, 'spawn', is_request, mock_spawn(next_beta, next_stable))

	autoupdate.check()

	test.assert_equal(message.called, true)
	test.assert_contains(message.args[1].text, next_beta)
	test.assert_contains(message.args[1].text, beta_url)
end)

test('autoupdate.check should show beta -> stable update', function()
	local current, next_beta, next_stable = '1.1 beta', '1.2 beta', '1.1'
	local _<close> = test.mock(_G, '_RELEASE', current)
	local message = test.stub()
	local _<close> = test.mock(ui.dialogs, 'message', message)
	local _<close> = test.mock(os, 'spawn', is_request, mock_spawn(next_beta, next_stable))

	autoupdate.check()

	test.assert_equal(message.called, true)
	test.assert_contains(message.args[1].text, next_stable)
end)

test('autoupdate.check should not show stable -> beta update', function()
	local current, next_beta, current_stable = '1.0', '1.1 beta', '1.0'
	local _<close> = test.mock(_G, '_RELEASE', current)
	local message = test.stub()
	local _<close> = test.mock(ui.dialogs, 'message', message)
	local _<close> = test.mock(os, 'spawn', is_request, mock_spawn(next_beta, current_stable))
	local _<close> = test.disable_metafield(ui, 'statusbar_text')

	local update_found = autoupdate.check()

	test.assert(not update_found, 'update should not have been found')
	test.assert_equal(message.called, false)
	test.assert_equal(ui.statusbar_text, _L['No update detected'])
end)

test('autoupdate.check should show update for nightly -> any new release', function()
	local current, next_beta, current_stable = '1.1 nightly', '1.1 beta', '1.0'
	local _<close> = test.mock(_G, '_RELEASE', current)
	local message = test.stub()
	local _<close> = test.mock(ui.dialogs, 'message', message)
	local _<close> = test.mock(os, 'spawn', is_request, mock_spawn(next_beta, current_stable))
	local _<close> = test.mock(lfs, 'attributes', test.stub(0))

	autoupdate.check()

	test.assert_equal(message.called, true)
	test.assert_contains(message.args[1].text, next_beta)
end)

test('autoupdate.check should not show update for nightly -> prior release', function()
	local current, next_beta, current_stable = '1.1 nightly', '1.1 beta', '1.0'
	local _<close> = test.mock(_G, '_RELEASE', current)
	local message = test.stub()
	local _<close> = test.mock(ui.dialogs, 'message', message)
	local _<close> = test.mock(os, 'spawn', is_request, mock_spawn(next_beta, current_stable))
	local current_version_time = os.time() + 86400 -- this nightly is ahead of any prior release
	local _<close> = test.mock(lfs, 'attributes', test.stub(current_version_time))

	local update_found = autoupdate.check()

	test.assert(not update_found, 'update should not have been found')
	test.assert_equal(message.called, false)
end)

test('autoupdate.check should handle the lack of an internet connection', function()
	local no_internet_connection = function() return {read = function() return '' end} end
	local _<close> = test.mock(os, 'spawn', is_request, no_internet_connection)
	local _<close> = test.disable_metafield(ui, 'statusbar_text')

	autoupdate.check()

	test.assert_equal(ui.statusbar_text, _L['Could not fetch update information'])
end)
