#!/bin/bash
# 実機(USB接続のAndroid)へ、現在のスクリプトでAPKを作って入れて起動し、ログを待つ。
# 使い方: WS_SCRATCH=<作業ディレクトリ> GODOT_ANDROID_KEYSTORE_RELEASE_PATH=... _USER=... _PASSWORD=... run_on_phone.sh "<logcatで待つ正規表現>"
#
# WS_SCRATCH(作業ディレクトリ。Temp配下でよい)に、次が要る:
#   adb/platform-tools/adb.exe   : 公式のplatform-tools(zip)を展開したもの
#   appdata/                     : APPDATAの差し替え先(Godotのエディタ設定editor_settings-4.7.tres(Java SDK/Android SDKのパス入り)、
#                                  export_templates/4.7.stable/android_*、署名用のkeystore)。ユーザーの本物のエディタ設定を汚さない
#   ci/godot/                    : プロジェクト(godot/)の複製。エクスポート用。**このスクリプトが同期するのはscripts/*.gdだけ**なので、
#                                  project.godot・シーン・アセット・licenses/・export_presets.cfgを変えた時は、複製にも自分で反映すること
#   ci/build/                    : APKの出力先
# 署名は環境変数のkeystore。実機に既にあるAPKと同じ鍵でないと、adb install -r が署名不一致で失敗する(その時にアンインストールすると
# スマホのセーブが消えるので、しない)。パスワードはコミットしない。詳細は docs/HANDOFF.md の「Androidビルド」。
set -u
: "${WS_SCRATCH:?WS_SCRATCH(作業ディレクトリ)を指定してください}"
: "${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:?keystoreのパスを指定してください}"
: "${GODOT_ANDROID_KEYSTORE_RELEASE_USER:?keystoreのユーザー(alias)を指定してください}"
: "${GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD:?keystoreのパスワードを指定してください}"
GODOT="${GODOT_EXE:-/c/Users/thero/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7-stable_win64.exe}"
ADB="$WS_SCRATCH/adb/platform-tools/adb.exe"
cd "$(dirname "$0")/../../.."   # リポジトリのルート
export APPDATA="$(cygpath -w "$WS_SCRATCH/appdata")"
timeout 90 "$GODOT" --headless --path godot --quit 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E 'SCRIPT ERROR|Parse Error' | head -3; echo "compile exit=${PIPESTATUS[0]}"
cp godot/scripts/*.gd "$WS_SCRATCH/ci/godot/scripts/" 2>/dev/null
cd "$WS_SCRATCH/ci" && rm -f build/WorldSeeker-test.apk* \
  && timeout 420 "$GODOT" --headless --path godot --export-release "Android" ../build/WorldSeeker-test.apk > export_run.log 2>&1; echo "export exit=$?"
"$ADB" install -r "$(cygpath -w "$WS_SCRATCH/ci/build/WorldSeeker-test.apk")" 2>&1 | tail -1
"$ADB" shell am force-stop com.theronium.worldseeker; "$ADB" logcat -c
"$ADB" shell monkey -p com.theronium.worldseeker -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
for i in $(seq 1 90); do "$ADB" logcat -d -s godot:V 2>&1 | grep -qE "$1" && break; sleep 0.5; done
"$ADB" logcat -d -s godot:V 2>&1 | tr -d '\r' | grep -E 'SCRIPT ERROR|ERROR' | head -5
