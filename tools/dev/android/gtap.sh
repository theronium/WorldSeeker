#!/bin/bash
# 前面のアプリがWorldSeekerの時だけ、実機の画面をタップする(誤って別のアプリを操作しないための安全策)。
# 使い方: gtap.sh <x> <y>   ※座標は端末の画面(横向きなら1604x720)のピクセル
set -u
. "$(cd "$(dirname "$0")" && pwd)/env.sh" || exit 1
top=$("$ADB" shell dumpsys activity activities | tr -d '\r' | grep -E 'topResumedActivity' | head -1)
case "$top" in
  *com.theronium.worldseeker*) "$ADB" shell input tap "$1" "$2"; echo "tapped $1,$2";;
  *) echo "ABORT: 前面のアプリがゲームではありません: $top"; exit 1;;
esac
