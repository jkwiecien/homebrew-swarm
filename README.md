# homebrew-swarm

`SWARM.app` for macOS worker hosts: a tiny signed launcher that runs a SWARM worker
as its child, so macOS privacy prompts name **SWARM** instead of **node**, and the
permissions you grant survive `brew upgrade node`.

It does nothing else. The worker's own code is still installed and updated by
SWARM (`install.sh`, `swarm workers update`).

## Install

```bash
brew install --cask jkwiecien/swarm/swarm
```

The cask writes `~/.swarm/launchd-wrapper`, which SWARM reads whenever it writes a
worker LaunchAgent (needs a SWARM build with
[SmartTechBrewery/swarm#1376](https://github.com/SmartTechBrewery/swarm/issues/1376)).
New workers use it automatically; to switch an existing one now (restarts it):

```bash
swarm-worker agent install --profile <worker-id>
```

macOS will ask for permissions once more, this time as SWARM.

## Update / uninstall

```bash
brew upgrade --cask swarm
brew uninstall --cask swarm   # then re-run agent install for each worker
```

## How it works

`launcher/swarm.c` starts the command it is given (`node … swarm-worker.js run <id>`)
with `posix_spawn`, forwards SIGTERM/SIGINT/SIGHUP/SIGQUIT/SIGUSR1/SIGUSR2 to it and
exits with its status. It stays the parent on purpose: macOS attributes prompts to
the process launchd started, and an `exec` would hand that back to node.

## Release (maintainer)

One-time: `xcrun notarytool store-credentials swarm-notary` (Apple ID + app-specific
password, or an App Store Connect API key).

```bash
./build.sh 1.0.0 --no-notarize   # local test build in build/
./build.sh 1.0.0 --publish       # sign, notarize, release, bump the cask
```
