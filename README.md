# Brain Train

Premium Mahjong Solitaire for Android and iOS, built with Flutter by Sun Game Studio.

- 3D-look tiles with arbitrary multi-layer layouts, glass UI, day and night modes.
- Levels, symbols and artwork are data: published to Cloudflare R2, cached for offline play, with
  the current levels bundled in the app.

```bash
flutter pub get
flutter run            # Android emulator or device
flutter test
```

- Developer notes: [CLAUDE.md](CLAUDE.md)
- Publishing levels: [docs/CONTENT_PUBLISHING.md](docs/CONTENT_PUBLISHING.md)
- Symbol artwork (IconScout) pipeline: [docs/ASSET_PIPELINE.md](docs/ASSET_PIPELINE.md)
