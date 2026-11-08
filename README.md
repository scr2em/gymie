# Gymie

A native macOS menu bar app that reminds you to move. When a break is due, it opens a 2-minute, camera-coached routine for the areas that bother you (neck, shoulders, upper and lower back, wrists, knees, eyes). Your webcam counts reps and scores form, and the score turns into XP, levels, streaks, daily challenges and badges. Stats sync to a private GitHub repo, which also serves as the team leaderboard.

Built in SwiftUI on top of [Squat Overflow](https://github.com/malik-hesham/Squat-Overflow) (MIT). Its scheduling and game logic is ported to Swift, and its pose server runs locally from `PoseServer/`.

## Requirements

- macOS 14 or later, Xcode 16 or later (Swift 6 toolchain)
- Python 3.10–3.12 for the pose engine (`brew install python@3.12`)
- Optional: GitHub CLI (`brew install gh`, then `gh auth login`) for stats sync

## Build and run

```bash
make pose-server # one time: Python env with MediaPipe in ~/Library/Application Support/Gymie/pose-venv
make run         # builds build/Gymie.app and opens it
make install     # copies it to ~/Applications (use this for "Open at login")
make test        # Swift tests for the ported logic
```

On first launch, Settings opens. Pick your areas, then click **Get started**. You can also install the pose engine from **Settings → Break → Install pose engine**.

Builds are signed ad-hoc by default, so macOS may ask for camera access again after each rebuild. To keep permissions across rebuilds, sign with your development certificate:

```bash
SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" make run
```

## Features

**Menu bar.** A countdown to the next break (`23m`, then seconds in the last minute) and a dashboard with your level and XP, next break (including times shifted by a snooze), today's stats, daily challenges, this week's featured area, a 16-week heatmap, badges and the leaderboard. Buttons: Break now (also **⌃⌥⌘B** from anywhere), Pause 1 hr / Resume, Practice, Settings.

**Breaks.** Three moves, 6 reps each, picked from your areas. The camera preview is mirrored and blurred by default, with a skeleton overlay. You get a live rep counter, a form score per rep, cues ("Go a little further"), optional spoken coaching, a "different exercise" swap and a demo link. A summary screen shows the XP breakdown, level progress, and a level-up with confetti.

**Schedule rules (same as the extension).** Reminders follow a fixed grid within your active hours and workdays.
- **Done** keeps the grid.
- **Snooze 20 min** shifts the grid. After 2 snoozes in a row, Snooze is disabled.
- **Skip**, or closing the window without acting, counts as a skip. After 3 skips in a row, the next reminder shows a "~N hours without moving" warning first.
- **Late alarms** (the Mac was asleep) are dropped rather than opening a stale break.
- **Away**: if you've been idle for 5 minutes or the screen is locked when a break is due, it passes without counting as a skip.

**Mac-only additions**
- Holds a reminder while any app uses the camera or microphone (Zoom, Teams, Meet, FaceTime…), while an app is fullscreen, or (optionally) during busy events in the macOS Calendar app. It rechecks every 5 minutes and fires once you're free.
- System-wide idle and screen-lock detection.
- A notification 1 minute before a break, with **Start now** and **Snooze**.
- Open at login, and a global shortcut.
- **Practice** window: any exercise, live rep counting, no XP.

## Pose engine (local only)

Rep counting and form scoring come from `PoseServer/`, the Squat Overflow FastAPI + MediaPipe server. Gymie bundles it, starts it on `127.0.0.1:8765` when a break or practice needs it, and stops it when Gymie quits. Only loopback addresses are accepted, so camera frames never leave the Mac. Server output goes to `~/Library/Application Support/Gymie/pose-server.log`.

To run it yourself instead, turn off **Settings → Break → Gymie starts and stops the pose engine** and run:

```bash
cd PoseServer && "$HOME/Library/Application Support/Gymie/pose-venv/bin/python" app.py
```

## Stats and leaderboard: a private GitHub repo

The app's only network traffic is to GitHub.

1. **Settings → Stats & leaderboard**: pick one of your `gh` accounts (Gymie runs `gh auth status` to list them). Enter a repo such as `<you>/gymie-data`, then click **Connect**. If the repo doesn't exist, click **Create private repo**.
2. Gymie gets the account's token with `gh auth token --user <login>` and keeps it in memory only. Without `gh`, you can paste a fine-grained token (Contents: Read and write). That token is stored in the Keychain.
3. Your stats go to `players/<github-login>.json`. Gymie pushes on a schedule (every 30 minutes by default, and only when something changed) and about 10 seconds after a break that earned XP. Each push is a commit, so the repo history doubles as your stats log.
4. Keep the stats repo **private**. Only the app code is public. The leaderboard (This week / All time) reads every file in `players/`. To compete with colleagues, add them as collaborators. Each person connects with their own account and writes only their own file.
5. On a new Mac, connecting finds your existing file and offers **Restore from GitHub**.

Example `players/<login>.json` (trimmed):

```json
{
  "schema": 1, "login": "octocat", "name": "Octo Cat",
  "xp": 412, "level": 3, "levelName": "Stretch Rookie", "streak": 4,
  "week": "2026-W45", "weekXp": 96, "breaksToday": 3, "totalBreaks": 57,
  "badges": ["daily:variety", "weekly:Neck tension"],
  "activity": { "2026-11-06": { "breaks": 4, "xp": 31 } },
  "profile": { "...": "full XP/challenge state, used for restore" },
  "updatedAt": "2026-11-08T14:20:00Z", "app": "gymie-macos/0.1.0"
}
```

## Where things live

| Path | What |
|---|---|
| `Sources/GymieCore/` | Ported logic: schedule, XP and levels, challenges, routine, activity heatmap, catalog, pose protocol, the GitHub stats file and leaderboard ranking, `gh auth status` parsing |
| `Sources/Gymie/App/` | App entry, `AppModel` (state, 1-second wall-clock scheduler, actions), windows, persistence |
| `Sources/Gymie/Camera/` | Camera capture, pose WebSocket client, the break session |
| `Sources/Gymie/Presence/` | Idle, screen lock, camera/microphone in use, fullscreen apps, Calendar busy time |
| `Sources/Gymie/Services/` | GitHub sync, GitHub CLI, local pose engine manager, notifications, login item, hotkey, Keychain |
| `Sources/Gymie/Views/` | Dashboard, break window, settings, practice |
| `PoseServer/` | Local pose engine (from Squat Overflow, MIT) |
| `~/Library/Application Support/Gymie/` | `state.json` (settings, profile, schedule, activity, break log), `pose-venv/`, `pose-server.log` |

## License

MIT. See [LICENSE](LICENSE). `PoseServer/` and the ported game logic come from [Squat Overflow](https://github.com/malik-hesham/Squat-Overflow) by Malik Hesham (MIT, see [PoseServer/LICENSE](PoseServer/LICENSE)).
