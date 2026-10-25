#!/usr/bin/env bash
# Builds RR Pocket signed with your upload key, asking for the keystore (drag
# it onto the terminal) and its password, then running tool/build_aab.sh or
# tool/build_apk.sh with them. The password is checked before the build.
#
# Usage: tool/build_signed.sh [aab|apk] [arguments for that script]
#   e.g. tool/build_signed.sh aab --build-name 1.0.0 --build-number 7
#        tool/build_signed.sh apk arm64
set -euo pipefail

kind="${1:-aab}"
case "$kind" in
  aab | apk) shift $(($# > 0 ? 1 : 0)) ;;
  *) echo "usage: $0 [aab|apk] [arguments for tool/build_<kind>.sh]" >&2; exit 64 ;;
esac

root="$(cd "$(dirname "$0")/.." && pwd)"
source "$root/tool/env.sh"

read -r -p "Keystore (drag it here): " ks
# A dragged file arrives quoted, or with its spaces escaped, and a trailing
# space.
ks="${ks%"${ks##*[![:space:]]}"}"
ks="${ks#\'}"; ks="${ks%\'}"; ks="${ks#\"}"; ks="${ks%\"}"
ks="$(printf '%s' "$ks" | sed 's/\\\(.\)/\1/g')"
ks="${ks/#\~/$HOME}"
[[ -f "$ks" ]] || { echo "no keystore at $ks" >&2; exit 1; }

read -r -p "Key alias [upload]: " alias
alias="${alias:-upload}"
read -r -s -p "Keystore password: " store_pass
echo

export RR_KEYSTORE_PASS="$store_pass"
if ! keytool -list -keystore "$ks" -storepass:env RR_KEYSTORE_PASS \
    -alias "$alias" >/dev/null; then
  echo "wrong password, or no key named $alias in $ks" >&2
  exit 1
fi
# A PKCS12 keystore's key shares its password; an older JKS one may not.
export RR_KEY_PASS="$store_pass"
if ! keytool -certreq -keystore "$ks" -storepass:env RR_KEYSTORE_PASS \
    -alias "$alias" -keypass:env RR_KEY_PASS -file /dev/null 2>/dev/null; then
  read -r -s -p "Key password: " RR_KEY_PASS
  echo
  keytool -certreq -keystore "$ks" -storepass:env RR_KEYSTORE_PASS \
    -alias "$alias" -keypass:env RR_KEY_PASS -file /dev/null >/dev/null ||
    { echo "wrong key password" >&2; exit 1; }
fi

export RR_KEYSTORE="$ks" RR_KEY_ALIAS="$alias"
exec "$root/tool/build_$kind.sh" "$@"
