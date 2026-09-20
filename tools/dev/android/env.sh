#!/bin/bash
# 実機ビルド用スクリプトの共通設定(run_on_phone.sh / gtap.sh が読み込む)。
# WS_TOOLS(ビルド道具の置き場)を決めて、ADBのパスを用意する。
#
# WS_TOOLS には次が要る(前回までのセッションの作業フォルダ、Temp配下にある):
#   adb/platform-tools/adb.exe    公式のplatform-tools
#   jdk/                          JDK 17(JAVA_HOMEになる)
#   sdk/build-tools/<版>/apksigner.bat
#   appdata/Godot/                Godotのエディタ設定(editor_settings-4.7.tres、JDK/SDKのパス入り)とexport_templates
# 環境変数WS_TOOLSで場所を指定できる。無ければ、Temp配下のセッションの作業フォルダから、上が揃ったものを探す。
# (Tempは消えることがある。消えていたら、道具を入れ直す必要がある。docs/SESSION_LOG_2026-09-19_20.md 参照)
if [ -z "${WS_TOOLS:-}" ]; then
  for d in /c/Users/thero/AppData/Local/Temp/claude/d--Repos-Games-WorldSeeker/*/scratchpad; do
    if [ -f "$d/adb/platform-tools/adb.exe" ] && [ -f "$d/appdata/Godot/editor_settings-4.7.tres" ] && [ -d "$d/jdk" ] && ls "$d"/sdk/build-tools/*/apksigner.bat >/dev/null 2>&1; then
      WS_TOOLS="$d"; break
    fi
  done
fi
if [ -z "${WS_TOOLS:-}" ]; then
  echo "ビルド道具(adb/jdk/sdk/appdata)が見つかりません。WS_TOOLS で場所を指定するか、道具を入れ直してください。" >&2
  exit 1
fi
export WS_TOOLS
ADB="$WS_TOOLS/adb/platform-tools/adb.exe"
