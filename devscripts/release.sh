#!/bin/bash

# IMPORTANT: the following assumptions are made
# * the GH repo is on the origin remote
# * the gh-pages branch is named so locally
# * the git config user.signingkey is properly set

# You will need
# pip install coverage nose rsa wheel

# TODO
# release notes
# make hash on local files

set -e

skip_tests=true
gpg_sign_commits=""
buildserver='localhost:8142'

while true
do
case "$1" in
    --run-tests)
        skip_tests=false
        shift
    ;;
    --gpg-sign-commits|-S)
        gpg_sign_commits="-S"
        shift
    ;;
    --buildserver)
        buildserver="$2"
        shift 2
    ;;
    --*)
        echo "ERROR: unknown option $1"
        exit 1
    ;;
    *)
        break
    ;;
esac
done

if [ -z "$1" ]; then echo "ERROR: specify version number like this: $0 1994.09.06"; exit 1; fi
version="$1"
major_version=$(echo "$version" | sed -n 's#^\([0-9]*\.[0-9]*\.[0-9]*\).*#\1#p')
if test "$major_version" '!=' "$(date '+%Y.%m.%d')"; then
    echo "$version does not start with today's date!"
    exit 1
fi

if [ ! -z "`git tag | grep "$version"`" ]; then echo 'ERROR: version already present'; exit 1; fi
if ! type pandoc >/dev/null 2>/dev/null; then echo 'ERROR: pandoc is missing'; exit 1; fi
if ! python3 -c 'import rsa' 2>/dev/null; then echo 'ERROR: python3-rsa is missing'; exit 1; fi
if ! python3 -c 'import wheel' 2>/dev/null; then echo 'ERROR: wheel is missing'; exit 1; fi

read -p "Is ChangeLog up to date? (y/n) " -n 1
if [[ ! $REPLY =~ ^[Yy]$ ]]; then exit 1; fi

/bin/echo -e "\n### First of all, testing..."
make clean
if $skip_tests ; then
    echo 'SKIPPING TESTS'
else
    nosetests --verbose --with-coverage --cover-package=youtube_dl --cover-html test --stop || exit 1
fi

/bin/echo -e "\n### Changing version in version.py..."
sed -i "s/__version__ = '.*'/__version__ = '$version'/" youtube_dl/version.py

/bin/echo -e "\n### Changing version in ChangeLog..."
sed -i "s/<unreleased>/$version/" ChangeLog

/bin/echo -e "\n### OK, now it is time to build the binaries..."
REV=$(git rev-parse HEAD)
make youtube-dl youtube-dl.tar.gz
read -p "VM running? (y/n) " -n 1
wget "http://$buildserver/build/ytdl-org/youtube-dl/youtube-dl.exe?rev=$REV" -O youtube-dl.exe
mkdir -p "build/$version"
mv youtube-dl youtube-dl.exe "build/$version"
mv youtube-dl.tar.gz "build/$version/youtube-dl-$version.tar.gz"
RELEASE_FILES="youtube-dl youtube-dl.exe youtube-dl-$version.tar.gz"
(cd build/$version/ && md5sum $RELEASE_FILES > MD5SUMS)
(cd build/$version/ && sha1sum $RELEASE_FILES > SHA1SUMS)
(cd build/$version/ && sha256sum $RELEASE_FILES > SHA2-256SUMS)
(cd build/$version/ && sha512sum $RELEASE_FILES > SHA2-512SUMS)

/bin/echo -e "\n### Signing and uploading the new binaries to GitHub..."
for f in $RELEASE_FILES; do gpg --passphrase-repeat 5 --detach-sig "build/$version/$f"; done

ROOT=$(pwd)
python devscripts/create-github-release.py ChangeLog $version "$ROOT/build/$version"

ssh ytdl@yt-dl.org "sh html/update_latest.sh $version"

/bin/echo -e "\n### Now switching to gh-pages..."
git clone --branch gh-pages --single-branch . build/gh-pages
(
    set -e
    ORIGIN_URL=$(git config --get remote.origin.url)
    cd build/gh-pages
    "$ROOT/devscripts/gh-pages/add-version.py" $version
    "$ROOT/devscripts/gh-pages/update-feed.py"
    "$ROOT/devscripts/gh-pages/sign-versions.py" < "$ROOT/updates_key.pem"
    "$ROOT/devscripts/gh-pages/generate-download.py"
    "$ROOT/devscripts/gh-pages/update-copyright.py"
    "$ROOT/devscripts/gh-pages/update-sites.py"
    git add *.html *.html.in update
    git commit $gpg_sign_commits -m "release $version"
    git push "$ROOT" gh-pages
    git push "$ORIGIN_URL" gh-pages
)
rm -rf build

make pypi-files
echo "Uploading to PyPi ..."
python setup.py sdist bdist_wheel upload
make clean

/bin/echo -e "\n### DONE!"
