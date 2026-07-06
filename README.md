# linux-repo

Signed apt and dnf package repositories for the command line tools
[yomi](https://github.com/tamnd/yomi), [kage](https://github.com/tamnd/kage),
[tori](https://github.com/tamnd/tori), [aki](https://github.com/tamnd/aki), [ami](https://github.com/tamnd/ami),
[kaku](https://github.com/tamnd/kaku), [shirabe](https://github.com/tamnd/shirabe),
and [ccrawl](https://github.com/tamnd/ccrawl-cli).

The tree is served over GitHub Pages at
**https://tamnd.github.io/linux-repo/** and is GPG signed. Install instructions
live on that page; the short version is below.

## Debian, Ubuntu

```bash
curl -fsSL https://tamnd.github.io/linux-repo/gpg.key \
  | sudo gpg --dearmor -o /usr/share/keyrings/tamnd.gpg

echo "deb [signed-by=/usr/share/keyrings/tamnd.gpg] https://tamnd.github.io/linux-repo/apt stable main" \
  | sudo tee /etc/apt/sources.list.d/tamnd.list

sudo apt update
sudo apt install yomi kage tori aki ami ccrawl kaku shirabe
```

## Fedora, RHEL, openSUSE

```bash
sudo dnf config-manager --add-repo https://tamnd.github.io/linux-repo/dnf/tamnd.repo
sudo dnf install yomi
```

## How it works

The repository carries no packages in git. The `publish` workflow downloads the
`.deb` and `.rpm` files from the newest release of each tool, builds the Debian
and RPM metadata with `dpkg-scanpackages` / `apt-ftparchive` / `createrepo_c`,
signs the `Release`, `InRelease`, each rpm, and `repomd.xml` with the repo key,
and deploys the result to GitHub Pages.

It runs on two triggers and no schedule:

- `workflow_dispatch` for a manual rebuild,
- `repository_dispatch` (type `package-released`) that each tool fires on its own
  release.

## Signing key

The public key is [`gpg.key`](./gpg.key); its fingerprint is published at
`/fingerprint.txt` on the site. The private key lives only in this repository's
`LINUX_REPO_GPG_KEY` Actions secret.
