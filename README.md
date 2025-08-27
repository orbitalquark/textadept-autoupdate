# Autoupdate

**Note:** this module is deprecated in favor of the [update notifier][] module.

[update notifier]: https://github.com/orbitalquark/textadept-update-notifier

Checks for application updates.

Install this module by copying it into your *~/.textadept/modules/* directory or Textadept's
*modules/* directory, and then putting the following in your *~/.textadept/init.lua*:

```lua
local autoupdate = require('autoupdate')
```

There will be a "Help > Check for Updates" menu item. You can also have Textadept check for
updates on startup by setting [`autoupdate.check_on_startup`](#autoupdate.check_on_startup).

At this time, this module does not perform any auto-updates. The user is expected to act on
any update notifications.

<a id="autoupdate.check"></a>
## `autoupdate.check`()

Checks for updates, shows a message box if there is one, and copies the update URL to the
clipboard so the user can download it.

<a id="autoupdate.check_on_startup"></a>
## `autoupdate.check_on_startup`

Whether or not to check for updates on startup.

The default value is `false`.

<a id="autoupdate.fetch"></a>
## `autoupdate.fetch`

Command to send an HTTP request to check for updates.

The default value uses 'curl' on Windows, macOS, and BSD; it uses 'wget' on Linux.



