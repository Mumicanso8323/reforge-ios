#!/bin/bash
# 束の公開の文字列表から、出さない言語(LanguageID.released に無い言語)を消す。ストアの版(REFORGE_STORE_BUILD=1)でだけ stage.sh が呼ぶ。
# macOS の /bin/bash は 3.2 なので mapfile などの bash 4 の機能を使わない。
#
#   tools/content/trim-public-languages.sh <公開の text の場所> <出す言語の CSV>
set -euo pipefail
text_dir="$1"
released_csv="$2"
[ -d "$text_dir" ] || exit 0
for language_dir in "$text_dir"/*; do
  [ -d "$language_dir" ] || continue
  language="$(basename "$language_dir")"
  case ",$released_csv," in
    *",$language,"*) ;;
    *) rm -rf "$language_dir" ;;
  esac
done
