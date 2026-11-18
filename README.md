# Hundred Face

Hundred Face tracks detected games in the current Windows account and posts game starts, stops, and summaries to the Discord channel connected to a webhook.

## Install on Windows

1. Clone the [Hundred Face repository](https://github.com/m3m0rydmp/Hundred-face) or choose **Code → Download ZIP** on GitHub and extract the source files.
2. Double-click **Install Hundred Face.cmd** and read the activity-sharing prompt.
3. Type `YES` to install, then paste the Discord channel webhook and press Enter. The paste is masked.
4. Check the destination channel for the setup message.

The installer uses built-in Windows PowerShell, installs for the current user, and runs immediately and at sign-in. The webhook is encrypted for the installing Windows account and stored under `%LOCALAPPDATA%\Hundred Face`. Anyone with access to the Discord channel can see the posted activity. Run setup again to change the webhook.

## What gets tracked

- The monitor checks every 20 seconds for game windows. It looks for installed Steam games, Epic launch executables, and games in the standard `XboxGames` folder. Some launchers, tools installed through Steam, or games using nonstandard paths can be misclassified or missed. Standalone games outside these locations are generally missed.
- Session duration measures how long the game is detected, including time left open. Starts and stops are approximate and short launches can fall between checks.
- Daily and weekly summaries are sent when the monitor runs after local midnight and the Monday week boundary. If the laptop is off across multiple boundaries, it summarizes the most recent completed day or week.
- Session history stays on the laptop. Notifications wait in a local queue if Discord is temporarily unreachable.

## Stop tracking

Open `%LOCALAPPDATA%\Hundred Face` in File Explorer and double-click **Uninstall Hundred Face.cmd**. It disables tracking, removes the startup entry and deletes the saved webhook. Local session history remains in that folder.
