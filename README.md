# TramBar

Live tram, bus and train departures in your Mac's menu bar, for Chemnitz and the
rest of the VMS area (Verkehrsverbund Mittelsachsen).

The menu bar shows the next departure from your main stop, for example `🚊 2 · 4 min`.
Click it to see:

- **Your stops**: the next departures, with live delays, cancellations and platforms.
- **Your routes**: the next connections from A to B, for example *Chemnitz Hbf → Dresden-Neustadt*.
- **Near you**: the closest stops to where you are right now, and what leaves from them.

Times refresh every 30 seconds, and countdowns tick every second.

## Install

With [Homebrew](https://brew.sh):

```bash
brew install tanvieer/tap/trambar
```

Then start it, and have it start again at every login:

```bash
brew services start trambar
```

Homebrew builds TramBar on your Mac from this source code. That takes a minute
or two, and it needs Apple's Command Line Tools (`xcode-select --install`), which
Homebrew asks for if they are missing. Because the app is built on your own
machine, macOS opens it without any "unidentified developer" warning.

### Without Homebrew

```bash
git clone https://github.com/tanvieer/trambar.git
cd trambar
./build.sh
open build/TramBar.app
```

## Use

- **Edit** adds and removes stops and routes. Type at least three letters of a stop name.
- The stop at the top of the list is the one shown in the menu bar. Use the ↑ button to change it.
- Allow location access when macOS asks, and the *Near you* section fills in.
  Turn it off under **Edit** if you don't want it.

Settings are kept in `~/Library/Application Support/TramBar/settings.json`.

## Data

Departures come from the public EFA timetable service of the
[Verkehrsverbund Mittelsachsen](https://www.vms.de), which covers CVAG trams and
buses, the Chemnitz Bahn, and DB regional trains, with realtime data where the
operator provides it. No account or API key is needed. TramBar is not affiliated
with VMS, CVAG or Deutsche Bahn.

## Requirements

macOS 14 Sonoma or later.

## License

[MIT](LICENSE)
