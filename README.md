<p align="center">
  <img src="docs/app-icon.png" alt="Minidisc app icon" width="128" height="128">
</p>

<h1 align="center">Minidisc</h1>

<p align="center">
  Minidisc is an opinionated music player for iOS that plays the music from your own server, and it gives you an experience that is close to Apple Music.
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MPL--2.0-brightgreen.svg" alt="License: MPL 2.0"></a>
  <a href="#requirements"><img src="https://img.shields.io/badge/platform-iOS%2026%2B-blue.svg" alt="Platform: iOS 26+"></a>
  <a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-6-orange.svg" alt="Swift 6"></a>
</p>

## Screenshots

|                        Home                        |                        Discover                        |                        Player                        |                        Album                        |                           Lidarr                           |
| :------------------------------------------------: | :----------------------------------------------------: | :--------------------------------------------------: | :-------------------------------------------------: | :--------------------------------------------------------: |
| <img src="docs/screenshots/home.jpeg" width="150"> | <img src="docs/screenshots/discover.jpeg" width="150"> | <img src="docs/screenshots/player.jpeg" width="150"> | <img src="docs/screenshots/album.jpeg" width="150"> | <img src="docs/screenshots/lidarr-album.jpeg" width="150"> |

## What is Minidisc?

Minidisc is a music player for iOS, written in Swift and SwiftUI, that plays the music from your own server. It uses the Subsonic and OpenSubsonic API, so it works with [Navidrome](https://www.navidrome.org) and with other servers that follow these standards.

Minidisc does not use accounts or subscriptions, and it does not track you, so your music stays between your device and your server. It gives you the same smooth experience as Apple Music, but it plays the music that you own.

## An opinionated fork

Minidisc is a fork of [Cassette](https://github.com/CassetteLab/cassette), which Mathieu Dubart wrote as a good client for iOS and macOS. Minidisc takes a different, narrower path, and it follows four rules:

- **iOS only.** Minidisc does not support macOS, because each screen is made for the phone.
- **Opinionated.** Minidisc has few settings and good defaults, because it makes the decisions for you and keeps the interface simple.
- **Smooth first.** Minidisc adds a function only when the function feels as good as Apple Music.
- **Familiar.** The tab bar, the mini-player, the player screen, and the Home shelves use the usual iOS patterns, so you do not have to learn them.

If you want the largest set of functions on Mac and iPhone, use Cassette. If you want the simplest iOS player for your own library, use Minidisc.

## Features

**An immersive player experience**

- Native iOS 26 design with Liquid Glass aesthetics and dynamic background color extraction.
- Full-screen player with high-resolution artwork and fluid matched-geometry transitions.
- **Motion Artwork & Animated Canvas**: Full-bleed animated covers (`.mp4`) in the full player and album view with seamless looping, local disk cache, and responsive aspect scaling.
- A mini-player docked in the tab bar that expands into the full player on tap or swipe.
- Background playback with lock screen and Control Center integration.
- AirPlay 2 support.

**Next-Gen Apple Music-Style Lyrics (TTML & Karaoke)**

- **Word-by-word synchronization**: Syllable-level progressive gradient fill with fluid sweep physics, inspired by [KaraokeText](https://github.com/WillSuo-Github/KaraokeText).
- **Duet & Multi-Artist Layout**: Left alignment for lead vocals (`v1`) and right alignment for secondary artists (`v2`), capped at 75% width for clean spatial separation.
- **Adlib Vocals**: Background vocal tags rendered dynamically with distinct typography and synchronized timing.
- **Instrumental Markers**: Three-dot animated pulsing markers for song intros and instrumental solos.
- **Calibrated Auto-Scroll**: Precise physics-based scroll tracking that keeps active verses at a constant distance from the mini cover across all verse heights (from single lines to 5+ line stanzas).
- **Auto-Hiding Controls**: Player controls automatically disappear after 5 seconds of inactivity to provide a clean, full-screen lyric canvas, reappearing instantly on user interaction.
- **Interactive Seeking**: Tap any lyric line to jump playback directly to that timestamp.
- **Smart Resume**: Temporarily frees scroll lock when browsing lyrics and automatically resumes tracking after 3 seconds of inactivity.
- **Dynamic Styling**: Passed verses reset to unlit state, inactive lines feature pure uncolored Gaussian blur, and song composer credits are softly revealed at the end of the track.
- **Multi-source fallback**: Supports local TTML files, synchronized `.lrc`, embedded ID3/MP4 tags, and automatic fallback to [LRCLIB](https://lrclib.net).

**Companion Ecosystem: NowLocal**

- Integrates seamlessly with [**NowLocal**](https://github.com/eocxa/nowlocal), a companion open-source local streaming server and web player.
- Serves `.ttml` rich lyrics, animated artwork (`.mp4` square and tall), and enrichment metadata directly to Minidisc from your local music collection.
- Configurable host URL and port in **Settings > Integrations > NowLocal**.

**Your Library & Playback**

- Browse your playlists, artists, albums, downloads, and favorites.
- Full-text search across your entire library.
- Offline mode: download entire albums, playlists, or individual songs.
- Two-deck playback engine with gapless playback, true crossfades, and ReplayGain.
- Interactive drag-and-drop queue reordering with Smart Shuffle and Auto-extend.
- **Streaming Quality & Data Saver**: Lossless by default, with configurable quality per network (Wi-Fi vs. Cellular) and dedicated Data Saver mode (192 kbps MP3).
- Instant session persistence that restores your last playback state.

**Integrations & Privacy**

- **ListenBrainz**: Scrobble your plays and receive personalized music recommendations.
- **AudioMuse-AI**: Build weekly mood playlists analyzed from the acoustic profile of your library.
- **Lidarr**: Manage your music collection directly from the app (add artists, monitor missing albums, interactive search, and manage download queues).
- **Wrapped**: Annual listening summary and statistics.
- **Zero Tracking**: All traffic stays strictly between your device and your configured server.
- **Secure Credentials**: Credentials stored exclusively in the iOS Keychain with optional custom reverse-proxy headers (Cloudflare Access, Authelia).

## Installation

### iOS: sideload the app

1. Download the `.ipa` file from the [Releases](../../releases) page.
2. Install the file with AltStore, Sideloadly, or a different sideload tool. The tool signs the app with your Apple ID during the installation.

### Build from the source

You need these items:

- macOS 15 or later, with Xcode 26 or later.
- A Subsonic, OpenSubsonic, or Navidrome server.
- An Apple Developer account. The free level is sufficient for a personal build.

Do these steps:

1. Clone the repository and open the project.
    ```bash
    git clone https://github.com/Loriage/Minidisc.git
    cd Minidisc
    open Minidisc.xcodeproj
    ```
    Swift Package Manager gets the dependencies (SwiftSonic), so you do not have to do more setup.
2. Select your team in **Signing & Capabilities**.
3. Select an iOS 26 device or simulator.
4. Build and run the app when you press Command-R.
5. At the first start, Minidisc asks for your server address, your username, and your password. Enter them and tap **Connect**. If your server is behind a reverse proxy that needs custom headers, open **Advanced** and add the headers.

## Requirements

- iOS 26.1 or later.
- A Subsonic, OpenSubsonic, or Navidrome server.

## Server compatibility

Minidisc works with each server that has the Subsonic or OpenSubsonic API. Navidrome is the recommended server, and the team tests Minidisc primarily with Navidrome. If your server has the Subsonic API but a function does not work, [open an issue](https://github.com/Loriage/Minidisc/issues).

## Architecture

This information is for developers:

- **UI.** SwiftUI views with `@Observable @MainActor` view models, and the views have no business logic.
- **Services.** Swift actors, for example `PlayerService` and `LibraryService`, that do not import SwiftUI or UIKit.
- **Playback.** A two-deck `AVPlayer` engine (`AVPlayerEngine`) for gapless playback, real crossfades, and ReplayGain, which connects to `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter`.
- **Subsonic API.** [SwiftSonic](https://github.com/CassetteLab/swiftsonic) does all server communication.
- **Integrations.** ListenBrainz, AudioMuse-AI, and Lidarr each have their own client and settings.
- **Persistence.** SwiftData for the app data, and Keychain for the credentials.
- **Concurrency.** Swift 6 strict concurrency.
- **Dependencies.** SwiftSonic, and there are no other dependencies.

## License

Minidisc uses the [MPL-2.0](LICENSE) license.

- You can use, study, change, and share the source.
- Changed files stay under MPL-2.0, but you can combine them with proprietary code in a larger work.

Dependencies: [SwiftSonic](https://github.com/CassetteLab/swiftsonic) (MIT), which is compatible with MPL-2.0.

> Code before commit 21f9227 used the GPL-3.0-or-later license.

## Disclaimer

All icons, logos, brand assets, and visual materials referenced or utilized in this project are used strictly for educational, personal, and illustrative demonstration purposes.

- **Non-Commercial**: This project is completely free, open-source, and not intended for commercialization, monetization, sale, or profit in any way.
- **No Copyright Infringement**: No copyright or trademark infringement is intended. All trademarks, service marks, product names, and company logos are the property of their respective owners.
- **Illustrative & Fair Use**: Any UI design elements and iconography are provided strictly for non-commercial personal use and illustrative design reference.

## Acknowledgments

- [Cassette](https://github.com/CassetteLab/cassette) by Mathieu Dubart, because Minidisc is a fork of Cassette.
- [KaraokeText](https://github.com/WillSuo-Github/KaraokeText) by WillSuo, for the syllable-level karaoke gradient sweep and text animation concepts.
- The [Navidrome](https://www.navidrome.org) team, because Navidrome is an excellent self-hosted music server.
- The [OpenSubsonic](https://opensubsonic.netlify.app) community, because they modernized the Subsonic API.

