ANIMEVAULT - FINAL CLEAN NATIVE FLUTTER BUILD

This folder is intentionally FLAT. Upload its contents directly to the ROOT of a NEW GitHub repository.

ROOT MUST LOOK LIKE:
  codemagic.yaml
  pubspec.yaml
  lib/main.dart
  assets/icon-192.png

DO NOT put this folder inside another folder in GitHub.
DO NOT create another codemagic.yaml.

CODEMAGIC:
1. Add the new repository.
2. Select Flutter (via Workflow Editor).
3. Switch to YAML configuration.
4. Branch: main.
5. Select workflow: android-debug / AnimeVault Android APK.
6. Start build.
7. Artifact: app-debug.apk.

FEATURES:
- Native Flutter Android UI (not WebView).
- Home, Continue Watching, Popular anime.
- Discover/Search with genre, format, airing status, sort and year filters.
- AniList catalog; Jikan fallback for normal browse if AniList catalog is unavailable.
- Posters and anime details.
- Schedule with day navigation and local time.
- Watchlist, Completed, Favorites, Ongoing.
- Anime detail: Watching, Completed, Plan, Favourite.
- Watch next, Mark next, Mark through, episode jump and episode grid.
- Direct AniList episode links when available.
- Eight persistent provider slots on device.
- External provider picker with Crunchyroll, YouTube, Muse India, Ani-One, Prime Video, Netflix, JustWatch and Custom Provider slot.
- Return-to-app prompt to mark episode watched.
- Separate Mature area with Browse, Schedule, Watching and Completed.
- Mature provider gate requiring 18+ confirmation.
- Dashboard, watch-time/progress report, CSV, PDF, JSON backup/restore.
- API enrichment: Jikan, Kitsu, AnimeChan, AnimeFacts, NekosBest, Waifu.im, AniList and Trace.moe note.
- Local persistence with SharedPreferences.
