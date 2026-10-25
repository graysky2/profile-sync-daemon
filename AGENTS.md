# Repository Guidelines

## Project Structure & Module Organization

This repository packages `profile-sync-daemon`, a Bash-based user service for syncing browser profiles through tmpfs. The main script template is `common/profile-sync-daemon.in`; `make` renders it to `common/profile-sync-daemon` by substituting the version. Shared runtime files live in `common/`, browser definitions in `common/browsers/`, optional unsupported profile definitions in `contrib/`, systemd user units in `init/`, and documentation in `README.md`, `INSTALL`, and `doc/psd.1`. Debian maintainer scripts are under `common/debian/`.

## Build, Test, and Development Commands

- `make`: generates `common/profile-sync-daemon` from `common/profile-sync-daemon.in`.
- `make clean`: removes the generated script.
- `make install DESTDIR=/tmp/psd-root`: stages binaries, browser definitions, contrib files, man page, zsh completion, and systemd units without touching the live system.
- `make install`: installs to the configured prefix; run only in an appropriate packaging or root context.
- `shellcheck common/profile-sync-daemon.in common/psd-suspend-sync common/debian/*`: run shell linting when available.

There is no dedicated automated test suite in this tree. Validate changes with linting, staged installs, and targeted manual checks such as `psd p` or `systemctl --user start psd.service` in a disposable user environment.

## Coding Style & Naming Conventions

Use Bash-compatible style matching the existing scripts: two-space indentation, `[[ ... ]]` tests, lowercase local variable names, uppercase configuration variables, and quoted variable expansions for paths. Keep browser definition filenames lowercase and aligned with the values accepted in `BROWSERS`, for example `common/browsers/google-chrome` or `contrib/firefox-flatpak-cache`. Avoid unrelated formatting churn in generated or packaging files.

## Testing Guidelines

For script changes, check syntax with `bash -n common/profile-sync-daemon.in` and lint with ShellCheck. For Makefile or packaging changes, run a staged install with `DESTDIR` and inspect the resulting paths. For browser definition changes, verify the profile path logic against an installed browser profile and document any required external setup.

## Commit & Pull Request Guidelines

Recent history uses short imperative summaries, sometimes with scopes such as `contrib:` or `refactor(psd units):`. Keep commits focused and describe user-visible behavior or packaging impact. Pull requests should explain the reason for the change, list validation performed, link related issues, and note distro, browser, or systemd-version assumptions when relevant.

## Security & Data Safety

This tool moves browser profile data. Do not relax checks around running browsers, symlinked profiles, ownership, permissions, `XDG_RUNTIME_DIR`, or overlay/fuse requirements without a clear migration and validation plan. Prefer testing with disposable profiles before touching real browser data.
