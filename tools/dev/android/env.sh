#!/bin/bash
# 実機ビルド用スクリプトの共通設定(run_on_phone.sh / gtap.sh が読み込む)。
# WS_TOOLS(ビルド道具の置き場)を決めて、ADBのパスを用意する。
#
# 置き場: D:\DevTools\godot-android (恒久。他のGodotプロジェクトでも使い回せる、プロジェクトに依存しない道具)。
#   adb/platform-tools/adb.exe    公式のplatform-tools
#   jdk/                          JDK 17(JAVA_HOME になる)
#   sdk/build-tools/<版>/apksigner.bat
#   appdata/Godot/                Godotのエディタ設定(editor_settings-4.7.tres。JDK/SDK/debug keystoreの絶対パスが入っている)と
#                                 export_templates。APPDATAをここに差し替えて使うので、本物のエディタ設定・セーブに触れない
#   (署名キーはここに置かない。C:\Users\thero\worldseeker-signing\ にある)
# 探す順: 環境変数WS_TOOLS → D:\DevTools\godot-android → (前のセッションの)Temp配下の作業フォルダ。
# 置き場を移したら、appdata/Godot/editor_settings-4.7.tres の中のパスも直すこと。
# このスクリプト群は**Git Bash**用(パスが`/d/...`・`/c/...`で、`cygpath`を使う)。PowerShell/cmdで`bash`と打つと、
# Windowsに入っているWSL(Linux)のbashが起動し、パスが`/mnt/d/...`になって、ここから先は動かない
# (2026-09-21、「ビルド道具が見つかりません」と出た原因)。その場合は、原因と正しい起動方法を出して止める。
if ! command -v cygpath >/dev/null 2>&1; then
  echo "このスクリプトはGit Bash用です(今のbashはWSLなどで、cygpathがありません)。" >&2
  echo "PowerShell/cmdからは、次のどちらかで実行してください:" >&2
  echo "  tools\\dev\\android\\run_on_phone.cmd" >&2
  echo "  & 'C:\\Program Files\\Git\\bin\\bash.exe' tools/dev/android/run_on_phone.sh" >&2
  exit 1
fi
_has_tools() {
  [ -f "$1/adb/platform-tools/adb.exe" ] && [ -f "$1/appdata/Godot/editor_settings-4.7.tres" ] && [ -d "$1/jdk" ] \
    && ls "$1"/sdk/build-tools/*/apksigner.bat >/dev/null 2>&1
}
if [ -z "${WS_TOOLS:-}" ]; then
  for d in /d/DevTools/godot-android /c/Users/thero/AppData/Local/Temp/claude/d--Repos-Games-WorldSeeker/*/scratchpad; do
    if _has_tools "$d"; then WS_TOOLS="$d"; break; fi
  done
fi
if [ -z "${WS_TOOLS:-}" ]; then
  echo "ビルド道具(adb/jdk/sdk/appdata)が見つかりません。D:\DevTools\godot-android を作るか、WS_TOOLS で場所を指定してください。" >&2
  exit 1
fi
export WS_TOOLS
ADB="$WS_TOOLS/adb/platform-tools/adb.exe"
