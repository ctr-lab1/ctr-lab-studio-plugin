# CTR Lab Studio Link

Studio Link is the CTR Lab plugin for Roblox Studio. It turns your game into thumbnail briefs. It looks at the **layout** of the place you have open (map size, models, tools, colours, light), shows you exactly what it found, and only sends it to [CTR Lab](https://ctr-lab.com) after you approve. It never reads or sends your scripts.

Status: **beta, included in the paid CTR Lab plans**. Anyone can read and analyse the source, but only accounts on a paid plan can link Studio Link. Each plan has a number of runs per month (a scan from Studio or a new AI brief). The server refuses every other request.

Public page with the same information: <https://ctr-lab.com/plugin>

## What it sends

Only after you press **Send to CTR Lab**, and you can see the full list first (button *Show what is sent*):

- the place name and place ID (a public number, 0 if the place is not published; it lets a new scan update the same game)
- counts of parts, models, meshes, tools, scripts and remotes
- the size of the map and a coarse 10 x 10 overview from above: how many parts, the main material and the main colour per square
- names, sizes, positions, main colours and materials of the biggest models, and of tools (plus the public mesh numbers of tools)
- spawn positions
- lighting values: time of day, brightness, colours, sky and atmosphere
- script paths and class names, remote names, names of ScreenGuis

## What it never sends

- the source code of your scripts. **Studio Link never reads it** (version 0.8.0 and newer; older versions counted lines and function names)
- comments, text typed in your game, textures, images, sounds or the models themselves
- other places, or files from your computer
- your Roblox account, password or cookies

## Photo of an item (optional)

Select a Tool or Model and press **Make photo set**. Studio Link puts a **copy** into `Workspace > CTR Lab > Session <id>`, far above the map and in front of a white wall, and points the camera at it. Your original is never moved. The folder is not archivable, so it is never saved with your place. **Clean up** removes it and restores the camera. Studio plugins cannot capture the screen, so you take the screenshot yourself and paste it into CTR Lab with Ctrl+V.

## Network

Two requests only, both to `https://ctr-lab.com`:

| Function | When |
| --- | --- |
| `pluginPair` | You enter the one-time 6-digit code from your CTR Lab account. Returns an access token for this Studio. |
| `pluginAnalyze` | You press Send. Sends the summary you reviewed. |

From 0.7.0 on, the answers of these two requests also carry the newest version number. Studio Link remembers it on your computer and shows "A new version is available" when yours is older. It sends nothing extra for this.

Search `CTRLabConnect.lua` for `RequestAsync`: it appears once, in the `request` function.

The only other thing Studio Link loads is its own logo image from Roblox (`rbxassetid://131268296952051`). If the image cannot be loaded, it shows the name "CTR Lab" in text instead.

The window uses Roblox's own UI objects (`UICorner`, `UIStroke`, `UIShadow`, `UIListLayout`, `UIPadding`) in the same lime green look as the CTR Lab Hub.

## Install

1. In Roblox Studio add a new Script and paste the whole content of `CTRLabConnect.lua` into it.
2. Right-click the Script, choose **Save as Local Plugin...**, then delete the Script from the place.
3. Open the **CTR Lab** button in the Plugins tab.
4. Create a code in your CTR Lab account, enter it, press **Scan my game**, check the list, then **Send to CTR Lab**.

If a request fails, allow `ctr-lab.com` when Studio asks, or turn on *Game Settings > Security > Allow HTTP Requests*.

## Verify your copy

The file on <https://ctr-lab.com/plugin> shows its SHA-256 checksum. Compare it with yours:

```
certutil -hashfile CTRLabConnect.lua SHA256      # Windows
shasum -a 256 CTRLabConnect.lua                  # macOS / Linux
```

Current version: **0.8.0**, SHA-256 `22aa0da4a088b8eb37768d2175584a9477e77e3434be2b4e3498e6121825ac71`.

You can also check your copy on <https://ctr-lab.com/plugin>: it fetches this file from GitHub in your browser and compares it with yours, so the reference never comes from CTR Lab's own server.

## Terms of use

Studio Link is owned by CTR Lab, all rights reserved. The source is public so you can read it, run it in your own Studio and check that it is safe. Please do not copy, modify, redistribute, resell or reuse it in other plugins or products. If you want to build on it, ask first at <https://ctr-lab.com>. Details in [LICENSE](LICENSE).

Found a problem or a security concern? Open an issue and we will look at it.
