# Recall

A minimalist clipboard manager for macOS. Copy as usual. Find your way back to all of it in a few seconds.

Recall sits in the menu bar and quietly keeps the text, links and images you copy. You never have to copy the same thing twice just because something else took its place on the clipboard.

- Opens with a global shortcut, ⇧⌘V by default, with the insertion point already in the search field.
- Shows what you copied, most recent first, and filters as you type.
- Return puts the selected clip back on the clipboard, ready for ⌘V.
- The history is stored encrypted on your Mac, and Recall has no access to the network.
- Skips what password managers mark as confidential, and can be paused at any time.
- English and Swedish, light and dark.

Requires macOS 26 or later.

## Using Recall

Press the shortcut anywhere to open the history. Press it again, Escape, or click somewhere else to close it. The app you came from stays in front the whole time, so after Return you can paste straight away.

| Key | In the search field | In the list |
|---|---|---|
| ⇧⌘V (configurable) | Open or close | Open or close |
| Esc | Close | Close |
| ↓ ↑ | Move through the list | Move through the list |
| Return | Copy the selected clip | Copy the selected clip |
| ⌘C | | Copy the selected clip |
| ⌘⌫ | | Delete the selected clip |
| ⌘, | Settings | Settings |

Typing always goes to the search field. ↓ moves focus into the list, and that is where ⌘⌫ deletes a clip instead of clearing the search text. ↑ from the first row returns to the search field. Clicking a row copies it, and the row under the pointer has a button for deleting.

Copying a clip, from Recall or by copying the same text again, moves it to the top. The same text never appears twice.

The menu bar icon opens a menu for pausing, clearing the history, settings and quitting. The icon changes while collecting is paused.

Settings let you change the shortcut, open Recall at login, choose how many texts and links to keep (500 by default), how many images (10) and how large an image may be (10 MB), how long to keep clips you have not used (a month by default), pause collecting, and clear the history.

## What Recall collects

Recall keeps plain text, links and images. A link is a single address, such as `https://example.com`; everything else is text.

Images are screenshots, pictures copied in a browser or an image editor, and anything else that reaches the clipboard as PNG, JPEG, TIFF or HEIC. PNG and JPEG are kept as they are, the others are stored as PNG. A row shows a small picture and the size in pixels, and Return puts the image back on the clipboard. Images have no text to search, so they are shown only while the search field is empty.

When the clipboard holds both text and an image, Recall keeps one of them. A browser puts the address next to a copied image, and then Recall keeps the image. A spreadsheet or a presentation puts a picture of the selection next to the copied text, and then Recall keeps the text. The rule is that the image wins over a lone address and loses to any other text, and to all text that comes with formatting, which is how office apps copy.

It leaves these alone, without reading them:

- anything an app has marked as confidential or temporary, the way password managers do (the [nspasteboard.org](http://nspasteboard.org) convention);
- files, including image files copied in Finder, and other content that is neither text nor an image;
- images that would take more room than the limit in Settings, and all images when the number to keep is set to None;
- text copied on another device and offered through Universal Clipboard;
- text larger than one megabyte, and text that is only whitespace;
- everything, while collecting is paused. What you copy during a pause is not picked up afterwards either.

What was on the clipboard before Recall started is not collected.

Recall cannot recognise everything that is sensitive. A password you copy from a web page or a text file looks like any other text. Pause collecting first, or delete the clip afterwards.

## Privacy

- The history is stored on your Mac, one file per clip and one more for an image, in
  ```
  ~/Library/Containers/com.freberdev.recall/Data/Library/Application Support/Recall/History/
  ```
- Each file is encrypted with AES-256-GCM, images and the small pictures in the list included. The key is created on first launch and kept in your login keychain. Without it the files cannot be read, by Recall or by anything else.
- Recall runs in the macOS app sandbox without the entitlement for network access, so it cannot open a connection. There is no telemetry, no account and no synchronisation.
- Deleting a clip, clearing the history, and the limits on count and age remove the files for good. They do not go to the Trash.
- Recall reads the clipboard only when its contents change, and never while paused.

You can check the entitlements of the app you are running:

```bash
codesign -d --entitlements - /Applications/Recall.app
```

If macOS asks whether Recall may read the clipboard, or refuses, Recall says so in its window and in Settings, with a button that opens the right part of System Settings. Until you allow it there, Recall collects nothing.

## Building

Recall is a Swift package with no dependencies. You need Xcode 26 or later.

```bash
swift test
```

```bash
scripts/build-app.sh --install
```

The script builds `build/Recall.app`, signs it and, with `--install`, copies it to `/Applications`. Without `--install` it only builds.

"Open at login" turns itself on the first time Recall runs from `/Applications`. You can turn it off in Settings.

### Signing

`scripts/build-app.sh` signs with the identity in the environment variable `RECALL_SIGN_IDENTITY`, or else the first line of a file named `.signing-identity` in the project folder. With neither, the app is signed ad hoc, which works but makes macOS treat every build as a new app, and the keychain will ask before each new build may use the key.

```bash
security find-identity -v -p codesigning
```

lists the identities on your Mac. `.signing-identity` is ignored by git.

### A disk image for others

```bash
scripts/build-dmg.sh
```

builds a universal app (Apple silicon and Intel), signs it with a Developer ID certificate, and produces `build/Recall-<version>.dmg`, notarized by Apple.

- The certificate comes from `RECALL_RELEASE_IDENTITY` or the first line of `.release-identity`.
- The notarization credentials come from a keychain profile named in `RECALL_NOTARY_PROFILE` or the first line of `.notary-profile`. Create the profile once with `xcrun notarytool store-credentials`.

Both files are ignored by git. Without a notary profile the image is signed but not notarized.

### Development options

Two command-line options help when working on Recall:

```bash
open build/Recall.app --args -historyDirectory ~/Library/Containers/com.freberdev.recall/Data/tmp/recall-dev -appearance dark
```

`-historyDirectory` keeps your real history out of the way, with an encryption key of its own. Because of the sandbox the folder has to be inside the app's container. `-appearance` (`dark` or `light`) overrides the system setting.

### Layout

- `Sources/RecallCore` holds the logic: the encrypted files, the history in memory, what is collected from the clipboard, image handling, search, the key table. It does not use AppKit and is covered by the tests in `Tests/RecallCoreTests`.
- `Sources/Recall` is the app: the floating panel, the views, the system clipboard, the keychain, the global shortcut and settings.
- `Resources` holds `Info.plist`, the entitlements, the icon and the English and Swedish strings.
- `scripts/make-icon.swift` draws the icon: `swift scripts/make-icon.swift`.

## License

MIT. See [LICENSE](LICENSE).
