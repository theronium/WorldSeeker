"""探索者肖像画像をゲーム用に加工する(godot/assets/portraits/ へ出力する)。

元画像(リポジトリの外、ユーザーが用意)は、番号付きの一覧シートを切り出したもので、
  - 縁に約2pxの白い枠が残っている
  - 左上に、シート上の番号(白い「01」「02」…)が焼き込まれている
ため、そのままゲームに入れると番号が表示されてしまう。ここでは
  1. 縁を4px切り落とす
  2. 左上の白い数字を、周囲の背景色から補間して消す(背景はほぼ単色なので自然に消える)
  3. 縦横をそろえて正方形に切り出し、256x256にリサイズする
を行う。元画像は変更しない。

使い方(依存: Pillow, numpy):
  python tools/prepare_portraits.py [元フォルダ] [出力フォルダ] [--no-number]
  既定の元フォルダ: D:\\Repos\\Games\\Sandbox\\image\\WS\\split
  既定の出力先   : godot/assets/portraits
  --no-number    : 番号消し(手順2)を行わない。イベント会話用の町人(split_npc → npc_XX.png)と
                   敵(split_enemy → enemy_XX.png)の画像は、番号が焼き込まれていないのでこれを付けて通す
                   (縁の切り落としと、正方形・256x256への加工だけを行う)
出力後にGodotでインポートし(`godot --headless --path godot --import`)、生成された`.import`ファイルも
一緒にコミットすること。ファイル名(char_XX)を増減・変更したら、
godot/scripts/portrait_library.gd の血筋ごとのプールも合わせて更新する。
"""
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

DEFAULT_SRC = r"D:\Repos\Games\Sandbox\image\WS\split"
DEFAULT_DST = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "godot", "assets", "portraits")

BORDER = 4                # 切り落とす縁(px)
NUMBER_BOX = (6, 41, 8, 53)   # 番号がある範囲(y0, y1, x0, x1。縁を切った後の座標)。番号自体は約 x10-49, y9-37
WHITE_MIN = 200           # 番号は純白なので、全チャンネルがこれ以上のピクセルを番号とみなす
CORE_HALO = 11            # 番号の周囲この範囲(MaxFilterの奇数サイズ)は、暗くても必ず塗る。番号の縁にはアンチエイリアスと、
                          # 画像の縮小で出る暗い縁取り(リンギング)があり、これが残ると色のシミになる
HALO = 17                 # その外側、番号から離れた所まで(MaxFilterの奇数サイズ)。ここは背景より暗い画素を絵の輪郭線とみなして残す
DARK_GUARD = 25           # 背景より輝度がこれ以上暗い画素を「絵の輪郭線」とみなす(番号の近くにある耳・槍などを守る)
BG_TOLERANCE = 60         # 背景色との差(RGB差の合計)がこれ未満の画素を「背景」とみなす
OUT_SIZE = 256


def erase_number(a: np.ndarray) -> np.ndarray:
    y0, y1, x0, x1 = NUMBER_BOX
    white = np.zeros(a.shape[:2], dtype=bool)
    white[y0:y1, x0:x1] = a[y0:y1, x0:x1].min(axis=2) >= WHITE_MIN
    wimg = Image.fromarray((white * 255).astype("uint8"))
    core = np.array(wimg.filter(ImageFilter.MaxFilter(CORE_HALO))) > 0
    wide = np.array(wimg.filter(ImageFilter.MaxFilter(HALO))) > 0
    lum = a.astype(float) @ np.array([0.299, 0.587, 0.114])
    not_dark = lum >= np.median(lum[0:6, 0:6]) - DARK_GUARD    # 背景より明らかに暗い画素(輪郭線)は外側では残す
    mask = core | (wide & not_dark)
    mask[:y0 - 3, :] = False   # 範囲の外は触らない(膨張が範囲を少しはみ出すのは許容)
    out = a.astype(float).copy()
    # 埋める元にするのは背景色に近い画素だけにする(近くの絵の暗い輪郭線の色を取り込んで、線が伸びてしまうのを防ぐ)
    bg = np.median(a[0:6, 0:6].reshape(-1, 3), axis=0)
    usable = np.abs(out - bg).sum(axis=2) < BG_TOLERANCE
    # 周囲の既知の色を、内側へ向けて少しずつ広げて埋める(単色背景ならそのまま背景色、グラデーションなら滑らかにつながる)
    while mask.any():
        known = ~mask & usable
        acc = np.zeros_like(out)
        cnt = np.zeros(mask.shape)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dy == 0 and dx == 0:
                    continue
                k = np.roll(known, (dy, dx), (0, 1))
                v = np.roll(out, (dy, dx), (0, 1))
                acc += v * k[..., None]
                cnt += k
        fill = mask & (cnt > 0)
        if not fill.any():
            break
        out[fill] = acc[fill] / cnt[fill][:, None]
        usable |= fill
        mask &= ~fill
    return np.clip(out + 0.5, 0, 255).astype("uint8")


def process(src_path: str, dst_path: str, erase: bool = True) -> None:
    im = Image.open(src_path).convert("RGB")
    w, h = im.size
    im = im.crop((BORDER, BORDER, w - BORDER, h - BORDER))
    if erase:
        im = Image.fromarray(erase_number(np.array(im)))
    w, h = im.size
    side = min(w, h)
    left, top = (w - side) // 2, (h - side) // 2
    im = im.crop((left, top, left + side, top + side)).resize((OUT_SIZE, OUT_SIZE), Image.LANCZOS)
    im.save(dst_path, optimize=True)


def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    erase = "--no-number" not in sys.argv[1:]
    src = args[0] if len(args) > 0 else DEFAULT_SRC
    dst = os.path.normpath(args[1] if len(args) > 1 else DEFAULT_DST)
    os.makedirs(dst, exist_ok=True)
    names = sorted(f for f in os.listdir(src) if f.lower().endswith(".png"))
    for name in names:
        process(os.path.join(src, name), os.path.join(dst, name), erase)
    print("processed %d images: %s -> %s" % (len(names), src, dst))


if __name__ == "__main__":
    main()
