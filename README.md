# CTR Lab for Roblox Studio

Turn your game into a thumbnail brief. This plugin reads the **structure** of the place you have open, shows you exactly what it found, and only sends it to [CTR Lab](https://ctr-lab.com) after you approve. It never sends your code.

Status: **closed beta**. Anyone can read and use the source, but only accounts CTR Lab has invited can link the plugin. The server refuses every other request.

Public page with the same information: <https://ctr-lab.com/plugin>

## What it sends

Only after you press **Send to CTR Lab**, and you see the full list first:

- the place name and place ID (a public number, 0 if the place is not published; it lets a new scan update the same game)
- counts of instances, scripts and remotes
- script paths and class names
- line counts of each script
- function names (up to 40 per script) and `require` paths
- names of RemoteEvents and RemoteFunctions
- names of the Roblox services your scripts use

## What it never sends

- the source code of your scripts, or their comments and strings
- property values, models, meshes, images or sounds
- other places, or files from your computer
- your Roblox account, password or cookies

## Network

Two requests only, both to `https://ctr-lab.com`:

| Function | When |
| --- | --- |
| `pluginPair` | You enter the one-time 6-digit code from your CTR Lab account. Returns an access token for this Studio. |
| `pluginAnalyze` | You press Send. Sends the summary you reviewed. |

Search `CTRLabConnect.lua` for `RequestAsync`: it appears once, in the `request` function.

The only other thing the plugin loads is its own logo image from Roblox (`rbxassetid://131268296952051`). If the image cannot be loaded, the plugin shows the name "CTR Lab" in text instead.

The window uses Roblox's own UI objects (`UICorner`, `UIStroke`, `UIShadow`, `UIListLayout`, `UIPadding`) in the same lime green look as the CTR Lab Hub.

## Install

1. In Roblox Studio add a new Script and paste the whole content of `CTRLabConnect.lua` into it.
2. Right-click the Script, choose **Save as Local Plugin...**, then delete the Script from the place.
3. Open the **CTR Lab** button in the Plugins tab.
4. Create a code in your CTR Lab account, enter it, press **Review this place**, then **Send to CTR Lab**.

If a request fails, allow `ctr-lab.com` when Studio asks, or turn on *Game Settings > Security > Allow HTTP Requests*.

## Verify your copy

The file on <https://ctr-lab.com/plugin> shows its SHA-256 checksum. Compare it with yours:

```
certutil -hashfile CTRLabConnect.lua SHA256      # Windows
shasum -a 256 CTRLabConnect.lua                  # macOS / Linux
```

Current version: **0.5.0**, SHA-256 `d76d1469c59a18c19b15d2acf9dd622771f122aa5e35ec02aedb2aaabcabd035`.

You can also check your copy on <https://ctr-lab.com/plugin>: it fetches this file from GitHub in your browser and compares it with yours, so the reference never comes from CTR Lab's own server.

## Contributing

Issues and pull requests are welcome. Please keep the plugin small, read-only and transparent: anything new that leaves Studio must appear in the review list first.

## License

MIT, see [LICENSE](LICENSE).
