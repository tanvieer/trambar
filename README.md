<div align="center">

<img src="docs/icon.png" width="112" alt="TramBar icon">

# TramBar

**Your next tram, right in your Mac's menu bar.**

Live tram, bus and train departures for Chemnitz and the whole VMS area.

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111?logo=apple&logoColor=white)](#requirements)
[![Swift](https://img.shields.io/badge/Swift-SwiftUI-F05138?logo=swift&logoColor=white)](Sources/TramBar)
[![Homebrew](https://img.shields.io/badge/brew-tanvieer%2Ftap-FBB040?logo=homebrew&logoColor=black)](#install)
[![License: MIT](https://img.shields.io/badge/license-MIT-34C759)](LICENSE)

<br>

<a href="https://youtu.be/9cNxedOo6dk"><img src="docs/banner.jpg" width="880" alt="TramBar showing live departures from the menu bar. Click to watch the trailer."></a>

**[▶ Watch the 35-second trailer on YouTube](https://youtu.be/9cNxedOo6dk)**

</div>

<br>

## Why

Is your tram two minutes away, or did you just miss it? Normally you unlock your
phone, open an app and search for your stop. TramBar puts the answer where you
are already looking: the menu bar shows the next departure from your main stop,
for example <img src="docs/menubar.png" height="20" align="center" alt="2 · 2 min">.
Click it for the full picture.

## Features

<table>
<tr>
<td width="50%" valign="top">

### Your stops
The next departures from every stop you save, with **live delays**,
cancellations and platforms. A green signal means realtime data, a red `+3`
means the tram is running three minutes late.

</td>
<td width="50%"><img src="docs/stops.png" alt="Departures from Gutenbergstr with a +3 delay"></td>
</tr>
<tr>
<td width="50%" valign="top">

### Your routes
Save a trip from A to B, like *Chemnitz Hbf → Dresden-Neustadt*, and see your
next connections with departure and arrival times, changes and platforms.

</td>
<td width="50%"><img src="docs/route.png" alt="Route Chemnitz Hbf to Dresden-Neustadt"></td>
</tr>
<tr>
<td width="50%" valign="top">

### Near you
Somewhere new? TramBar finds the stops closest to you, how far away they are,
and what leaves from them next.

</td>
<td width="50%"><img src="docs/nearby.png" alt="Nearby stops with distance"></td>
</tr>
</table>

Departures refresh every 30 seconds, and the countdowns in the panel tick every second.

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

To update later:

```bash
brew upgrade trambar && brew services restart trambar
```

<details>
<summary><b>Without Homebrew</b></summary>

```bash
git clone https://github.com/tanvieer/trambar.git
cd trambar
./build.sh
open build/TramBar.app
```

</details>

## Use

| | |
|---|---|
| **Add stops and routes** | Click **Edit**, then type at least three letters of a stop name. |
| **Pick the menu bar stop** | The stop at the top of the list is shown in the menu bar. Use the ↑ button to change it. |
| **Near you** | Allow location access when macOS asks. Turn the section off under **Edit** if you don't want it. |
| **Settings file** | `~/Library/Application Support/TramBar/settings.json` |

## Privacy

TramBar has no account, no analytics and no server of its own. It talks only to
the public VMS timetable service. If you turn on *Near you*, your coordinates are
sent to that service to look up the closest stops, and nowhere else.

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
