#!/bin/bash
# 前面のアプリがWorldSeekerの時だけ、実機の画面をタップする(誤って別のアプリを操作しないための安全策)。
# 使い方: WS_SCRATCH=<作業ディレクトリ> gtap.sh <x> <y>   ※座標は端末の画面(横向きなら1604x720)のピクセル
set -u
: "${WS_SCRATCH:?WS_SCRATCH(作業ディレクトリ)を指定してください}"
ADB="$WS_SCRATCH/adb/platform-tools/adb.exe"
top=$("$ADB" shell dumpsys activity activities | tr -d '\r' | grep -E 'topResumedActivity' | head -1)
case "$top" in
  *com.theronium.worldseeker*) "$ADB" shell input tap "$1" "$2"; echo "tapped $1,$2";;
  *) echo "ABORT: 前面のアプリがゲームではありません: $top"; exit 1;;
esac
