#!/bin/bash
# アプリに同梱するコンテンツの束を作る(docs/architecture/E-content.md §4.5)。CI の ios ジョブと、Mac の手元のビルドの前に回す。
#
#   tools/content/stage.sh
#
# 作るもの(どちらも gitignore):
#   AppContent/content/public/          … content/public の写し(平文)
#   AppContent/content/private.sealed   … content/private を封をした 1 ファイル(非公開の層があるときだけ)
#   AppContent/content/art.sealed       … content/private/art の絵を同じ鍵で封をした 1 ファイル(絵があるときだけ)
#   ReForge/Generated/ContentKey.swift   … 封を開く鍵(非公開の層が無ければ鍵 nil)
# content/private の平文はアプリに入れない(project.yml は AppContent/content だけを同梱する)。
set -euo pipefail
cd "$(dirname "$0")/../.."

rm -rf AppContent
mkdir -p AppContent/content
cp -R content/public AppContent/content/public
swift run --package-path ReForgeCore -c release rf-seal \
  content/private AppContent/content/private.sealed ReForge/Generated/ContentKey.swift \
  AppContent/content/art.sealed

# 平文の非公開の層が束に紛れていないこと
if [ -e AppContent/content/private ]; then
  echo "stage.sh: 束に平文の private が入っている" >&2
  exit 1
fi
echo "stage.sh: AppContent/content を作った"
