# Development

Everything you need to work on `unified.nvim`. These are plain commands — there
is no build step.

## Tests

Requires Neovim (`nvim`) on your `PATH`.

```bash
# Run the whole suite
./test/run_tests.sh

# Run a single test, addressed as <group>.<function>
./test/run_tests.sh --test=test_features.test_diff_against_commit
```

## Formatting

Code is formatted with [stylua](https://github.com/JohnnyMorganz/StyLua), pinned
via the Nix flake so everyone uses the same version. With
[Nix](https://nixos.org) (flakes enabled), no separate stylua install is needed:

```bash
nix run .#stylua -- lua/ test/ example/           # format in place
nix run .#stylua -- --check lua/ test/ example/    # verify formatting only
```

Flake equivalents: `nix fmt` formats the tree, `nix flake check` fails if it
isn't stylua-clean, and `nix develop` drops you into a shell with `stylua` and
`git` on `PATH`.

### Without Nix (Docker)

Run the same stylua inside a container (see `Dockerfile`):

```bash
docker build -t stylua-nvim .
docker run --rm -v "$PWD":/app stylua-nvim lua/ test/ example/           # format
docker run --rm -v "$PWD":/app stylua-nvim --check lua/ test/ example/   # check
```

## Pre-commit hook (optional)

`.git/hooks/` is not version-controlled, so install this per clone if you want
formatting and tests to run automatically before each commit:

```sh
cat > .git/hooks/pre-commit <<'EOF'
#!/bin/sh
nix run .#stylua -- lua/ test/ example/ || { echo "Formatting failed"; exit 1; }
git add -u
./test/run_tests.sh || { echo "Tests failed. Commit aborted."; exit 1; }
EOF
chmod +x .git/hooks/pre-commit
```
