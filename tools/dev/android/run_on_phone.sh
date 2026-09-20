#!/bin/bash
# 実機(USB接続のAndroid)へ、リポジトリの現在の内容で、本物のリリース鍵で署名したAPKを作って上書きインストールし、起動する。
# 使い方: run_on_phone.sh ["logcatで待つ正規表現"]
#
# - 署名キーは C:\Users\thero\worldseeker-signing\ (worldseeker-release.keystore と PASSWORD.txt)。パスワードはこのファイルを実行時に読むだけで、
#   どこにも書き出さない。環境変数(WS_SIGNING_DIR / GODOT_ANDROID_KEYSTORE_RELEASE_PATH/_USER/_PASSWORD)で上書きできる。
# - リポジトリから直接エクスポートする(作業ツリーの内容が、そのまま実機に載る。別セッションの未コミットの変更も含む)。
# - 署名者が、本物のキーの指紋と一致しない限り、インストールしない。
# - adb install -r なので、署名が同じなら、スマホ内のセーブは残る。署名不一致で失敗しても、**アンインストールしない**
#   (セーブが消える。古い使い捨てキー時代のAPKが入っている場合だけ、ユーザーの了承のうえで1回だけ行う)。
# - インストールのたびにゲームは再起動する(新規開始の状態になる)。
# ビルド道具の場所は env.sh を参照。
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/env.sh" || exit 1
REPO="$(cd "$HERE/../../.." && pwd)"

SIGN_DIR="${WS_SIGNING_DIR:-/c/Users/thero/worldseeker-signing}"
export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:-$SIGN_DIR/worldseeker-release.keystore}"
export GODOT_ANDROID_KEYSTORE_RELEASE_USER="${GODOT_ANDROID_KEYSTORE_RELEASE_USER:-worldseeker}"
if [ -z "${GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD:-}" ]; then
  [ -f "$SIGN_DIR/PASSWORD.txt" ] || { echo "PASSWORD.txt が見つかりません: $SIGN_DIR" >&2; exit 1; }
  export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD="$(cat "$SIGN_DIR/PASSWORD.txt")"
fi
EXPECTED_SHA256="54d1bfc73d490fccbde7c5985edc0b0e2755c3bdfb17a76ddeb7de3fb76a361b" # 本物のリリース鍵(公開してよい指紋。SIGN_DIR/README.txt)

GODOT="${GODOT_EXE:-/c/Users/thero/AppData/Local/Microsoft/WinGet/Packages/GodotEngine.GodotEngine_Microsoft.Winget.Source_8wekyb3d8bbwe/Godot_v4.7-stable_win64.exe}"
export APPDATA="$(cygpath -w "$WS_TOOLS/appdata")" # 実際のエディタ設定・セーブに触れないよう、隔離した場所を使う
OUT_DIR="$WS_TOOLS/build-release"; mkdir -p "$OUT_DIR"; APK="$OUT_DIR/WorldSeeker-release.apk"; rm -f "$APK" "$APK.idsig"

cd "$REPO"
timeout 90 "$GODOT" --headless --path godot --quit 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -E 'SCRIPT ERROR|Parse Error' | head -3; echo "compile exit=${PIPESTATUS[0]}"
timeout 480 "$GODOT" --headless --path godot --export-release "Android" "$(cygpath -w "$APK")" > "$OUT_DIR/export.log" 2>&1; echo "export exit=$?"
[ -f "$APK" ] || { echo "APKができませんでした。$OUT_DIR/export.log を確認してください" >&2; exit 1; }

export JAVA_HOME="$(cygpath -w "$WS_TOOLS/jdk")"
APKSIGNER="$(ls "$WS_TOOLS"/sdk/build-tools/*/apksigner.bat | tail -1)"
SIGNER="$("$APKSIGNER" verify --print-certs "$(cygpath -w "$APK")" 2>&1 | grep -i 'Signer #1 certificate SHA-256' | sed 's/.*: *//' | tr -d ' \r')"
if [ "$SIGNER" != "$EXPECTED_SHA256" ]; then echo "署名者が本物のキーと一致しません($SIGNER)。インストールしません" >&2; exit 1; fi
echo "署名OK(本物のリリース鍵)"

"$ADB" devices | grep -q "device$" || { echo "実機が接続されていません(adb devices)" >&2; exit 1; }
"$ADB" install -r "$(cygpath -w "$APK")" 2>&1 | tail -1
"$ADB" logcat -c
"$ADB" shell monkey -p com.theronium.worldseeker -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
if [ -n "${1:-}" ]; then
  for i in $(seq 1 90); do "$ADB" logcat -d -s godot:V 2>&1 | grep -qE "$1" && break; sleep 0.5; done
else
  sleep 6
fi
"$ADB" logcat -d -s godot:V 2>&1 | tr -d '\r' | grep -E 'SCRIPT ERROR|ERROR' | head -5; echo "log-check done"
