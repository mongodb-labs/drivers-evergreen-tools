# mongodb-runner pins

Each subdirectory is one pinned `@mongodb-js/mongodb-runner` install (renamed from
`mongodb-runner`, which stopped receiving releases at 6.11.1). `mongodb_runner.py` copies its
`package.json` and `package-lock.json` into a cache directory and runs `npm ci` there.

`default/` serves every server version that doesn't need an override, and declares only
`@mongodb-js/mongodb-runner`, so its lockfile tracks whatever driver that resolves to until the
lockfile is next regenerated. A directory named for a server version, such as `4.2/`,
overrides it and names its driver directly: the Node driver raised `minWireVersion` to 9
in `mongodb` 7.6.0, so `4.2/` holds 7.5.0.

`.github/dependabot.yml` lists `default/` only, allowing indirect dependencies and
grouping updates so the runner and its driver move together. That file only governs
version updates, so an unlisted held-back pin gets none; security updates for it are a
separate, repository-level setting, not something this file controls.

## Bumping a pin

Edit that directory's `package.json` and regenerate its lockfile:

```bash
cd <pin>
npm install --package-lock-only
```

`make lint` runs `check-pins.sh`. It rejects a manifest and lockfile that disagree, and
catches what `npm ci` cannot: a driver pinned outside the range `@mongodb-js/mongodb-runner`
declares gets a private nested copy rather than an error, so the pin never reaches the
runner. Pin a version whose range admits the driver you need. Every release published
under the new name, 6.10.0 on, requires `^7.5.0`; a driver below that has no pin to
hold.

## Adding a pin

Copy `default/` to a directory named for the server version, add the driver it needs
alongside `@mongodb-js/mongodb-runner`, and regenerate the lockfile. Leave `.github/dependabot.yml`
alone.
