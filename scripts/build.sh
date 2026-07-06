#!/usr/bin/env bash
#
# Assemble a signed apt + dnf repository from the latest release of each tool.
#
# Runs on an ubuntu runner. It downloads the .deb and .rpm packages that
# GoReleaser attaches to each tool's newest release, builds the Debian and RPM
# repository metadata, signs everything with the repo key, and writes the whole
# tree to ./public for GitHub Pages to serve.
#
# Inputs (environment):
#   TOOLS         space separated repo names under the owner (default below)
#   OWNER         GitHub owner (default tamnd)
#   HOST          public base URL the repo is served from, no trailing slash
#   GPG_PRIVATE_KEY   armored private signing key (from a secret)
#   GH_TOKEN      token able to read the source releases (the default one is fine)
#
set -euo pipefail

# Entries are repository names under the owner, not package names. They match
# for every tool except ccrawl, whose repo is ccrawl-cli but whose package and
# command are named ccrawl.
TOOLS="${TOOLS:-yomi kage tori aki ami ccrawl-cli kaku shirabe}"
OWNER="${OWNER:-tamnd}"
HOST="${HOST:-https://tamnd.github.io/linux-repo}"

ROOT="$PWD"
OUT="$ROOT/public"
WORK="$ROOT/work"
rm -rf "$OUT" "$WORK"
mkdir -p "$OUT" "$WORK/debs" "$WORK/rpms"

echo "==> Importing signing key"
echo "$GPG_PRIVATE_KEY" | gpg --batch --import
KEYID=$(gpg --list-keys --with-colons | awk -F: '/^fpr:/{print $10; exit}')
echo "    key $KEYID"

echo "==> Collecting packages from the latest release of: $TOOLS"
for t in $TOOLS; do
  tag=$(gh release view --repo "$OWNER/$t" --json tagName -q .tagName)
  echo "    $OWNER/$t @ $tag"
  dir="$WORK/dl/$t"
  mkdir -p "$dir"
  gh release download "$tag" --repo "$OWNER/$t" --dir "$dir" \
    --pattern '*.deb' --pattern '*.rpm'
  cp "$dir"/*.deb "$WORK/debs/" 2>/dev/null || echo "    (no .deb for $t)"
  cp "$dir"/*.rpm "$WORK/rpms/" 2>/dev/null || echo "    (no .rpm for $t)"
done
echo "    debs: $(ls "$WORK/debs" | wc -l)  rpms: $(ls "$WORK/rpms" | wc -l)"

#############################################################################
# APT repository
#############################################################################
echo "==> Building apt repository"
APT="$OUT/apt"
mkdir -p "$APT/pool/main" \
         "$APT/dists/stable/main/binary-amd64" \
         "$APT/dists/stable/main/binary-arm64"
cp "$WORK/debs"/*.deb "$APT/pool/main/"

pushd "$APT" >/dev/null
for arch in amd64 arm64; do
  dpkg-scanpackages --arch "$arch" pool/ > "dists/stable/main/binary-$arch/Packages"
  gzip -9c "dists/stable/main/binary-$arch/Packages" > "dists/stable/main/binary-$arch/Packages.gz"
done

apt-ftparchive \
  -o APT::FTPArchive::Release::Origin=tamnd \
  -o APT::FTPArchive::Release::Label=tamnd \
  -o APT::FTPArchive::Release::Suite=stable \
  -o APT::FTPArchive::Release::Codename=stable \
  -o APT::FTPArchive::Release::Components=main \
  -o APT::FTPArchive::Release::Architectures="amd64 arm64" \
  release dists/stable > dists/stable/Release

gpg --batch --yes --default-key "$KEYID" -abs -o dists/stable/Release.gpg dists/stable/Release
gpg --batch --yes --default-key "$KEYID" --clearsign -o dists/stable/InRelease dists/stable/Release
popd >/dev/null

#############################################################################
# DNF / RPM repository
#############################################################################
echo "==> Building dnf repository"
DNF="$OUT/dnf"
mkdir -p "$DNF/packages"
cp "$WORK/rpms"/*.rpm "$DNF/packages/"

# Sign every rpm so dnf's gpgcheck=1 passes on the packages themselves.
cat > "$HOME/.rpmmacros" <<EOF
%_gpg_name $KEYID
%__gpg $(command -v gpg)
%_gpg_sign_cmd_extra_args --batch --yes --pinentry-mode loopback
EOF
rpmsign --addsign "$DNF/packages"/*.rpm

createrepo_c --revision "$(git -C "$ROOT" rev-parse --short HEAD)" "$DNF"
gpg --batch --yes --default-key "$KEYID" --detach-sign --armor "$DNF/repodata/repomd.xml"

#############################################################################
# Public key, .repo file, landing page
#############################################################################
echo "==> Writing key, repo file, landing page"
gpg --armor --export "$KEYID" > "$OUT/gpg.key"

cat > "$DNF/tamnd.repo" <<EOF
[tamnd]
name=tamnd
baseurl=$HOST/dnf
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=$HOST/gpg.key
EOF

# Carry a fingerprint file so users can verify the key out of band.
gpg --fingerprint --with-colons "$KEYID" | awk -F: '/^fpr:/{print $10; exit}' > "$OUT/fingerprint.txt"

cp "$ROOT/index.html" "$OUT/index.html"

echo "==> Done. Tree under public/:"
find "$OUT" -maxdepth 3 -type f | sort | sed "s#$OUT#  public#"
