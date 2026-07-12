# Paint-n-Seek launcher

This directory contains the dependency-free Go launcher published alongside
each game release. On every launch it:

1. Calls GitHub's public `releases/latest` API for this repository.
2. Selects the Windows x86_64, Linux x86_64, or universal macOS game package.
3. Downloads and SHA-256 verifies a new package when necessary.
4. Safely extracts it into the user's application-data directory.
5. Starts the game, or starts the previous installed version when GitHub is
   temporarily unavailable or an update fails.

Installed versions and `launcher.log` are stored under:

- Windows: `%AppData%\\PaintNSeek`
- macOS: `~/Library/Application Support/PaintNSeek`
- Linux: `${XDG_CONFIG_HOME:-~/.config}/PaintNSeek`

The release workflow injects its own `owner/repository` value at build time, so
forks automatically update from their own releases. A local build defaults to
`maccam912/mega-chamomile`.

## Local development

```sh
go test ./...
go build .
```

Only the Go standard library is used. Release builds are created by
`.github/workflows/release-builds.yml`.
