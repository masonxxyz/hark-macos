# hark-macos
macOS packaging and development tooling for the
[Hark browser](https://github.com/masonxxyz/hark), a fork of
[Helium](https://github.com/imputnet/helium).

The core repo is checked out as the `hark-chromium` submodule:

```sh
git clone --recurse-submodules https://github.com/masonxxyz/hark-macos.git
```

## Quick start (development build)
```sh
source dev.sh
hark setup    # download Chromium, apply patches, configure
hark build    # build Hark.app (component build)
hark run      # launch with a separate dev profile
```

Run `hark` on its own to list every command.
[> Full guide: docs/building.md](docs/building.md)

## Rebranding from upstream
`devutils/rebrand.py` is the transform that turned Helium into Hark. After
merging upstream changes from `imputnet/helium-macos` (or `imputnet/helium` in
the submodule), run it again over the merged tree:

```sh
python3 devutils/rebrand.py . hark-chromium ../hark-onboarding
```

## Credits

### Helium
This repo is a fork of [helium-macos](https://github.com/imputnet/helium-macos)
by [imput](https://imput.net).

### ungoogled-chromium-macos
Helium's macOS packaging is based on
[ungoogled-chromium-macos](https://github.com/ungoogled-software/ungoogled-chromium-macos).

## License
All code, patches, modified portions of imported code or patches, and
any other content that is unique to Hark or Helium and not imported from other
repositories is licensed under GPL-3.0. See [LICENSE](LICENSE).

Any content imported from other projects retains its original license (for
example, any original unmodified code imported from ungoogled-chromium remains
licensed under their [BSD 3-Clause license](LICENSE.ungoogled_chromium)).
