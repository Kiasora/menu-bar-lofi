# Menu Bar Lofi

Made by Kian. Procedural lo-fi radio and a focus timer in your Mac's menu bar.

- Six stations: Chill, Study, Rainy, Café, Night, and Game Boy.
- 120 generated tracks per station, about 30 hours of music in total.
- Distinct arrangements, instruments, tempos, and station ambience. No audio files or streaming account needed.
- Play, pause, skip, volume, media keys, and a sleep timer.
- Focus sessions pause with the music and finish with a volume-matched chime.
- Optional start at login.

## Build

Requires macOS 26 or later and Xcode.

1. Open `MenuBarLofi.xcodeproj`.
2. Select the **MenuBarLofi** scheme and **My Mac**.
3. Press **Run**.

## Announce a new version

Existing copies check `update.json` when opened and once every 24 hours. This is a notification with a download link, not an automatic installer.

1. In Xcode, select the **MenuBarLofi** target and increase its version under **General**. Keep the app and test target versions aligned.
2. Publish the new download on this repository's **Releases** page.
3. Update `update.json`:
   - `version`: the new app version, such as `1.1`.
   - `message`: a short description of what changed.
   - `url`: the release or Ko-fi download link.
4. Commit and push `main`.

A version higher than the installed version shows a banner in the app. Users can dismiss it; the next new version will show again. An unavailable network simply leaves the app working normally until the next check.

## Tests

Select the **MenuBarLofi** scheme and press **Product → Test** in Xcode, or run:

```sh
xcodebuild test -project MenuBarLofi.xcodeproj -scheme MenuBarLofi -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

The tests generate and render audio locally; they do not need music files or personal documents.
