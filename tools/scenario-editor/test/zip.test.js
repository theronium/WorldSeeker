'use strict';
const test = require('node:test');
const assert = require('node:assert');
const zlib = require('zlib');
const { createZip, readZip, crc32, ZipError } = require('../zip.js');

const text = (s) => Buffer.from(s, 'utf8');

test('crc32: 既知の値(zlibと同じ)', () => {
  assert.strictEqual(crc32(text('123456789')), 0xcbf43926);
  assert.strictEqual(crc32(Buffer.alloc(0)), 0);
  if (zlib.crc32) assert.strictEqual(crc32(text('日本語のテキスト')), zlib.crc32(text('日本語のテキスト')));
});

test('往復: 圧縮(deflate)と無圧縮(store)、日本語のファイル名、空のファイルを読み戻せる', () => {
  const big = text('あいうえお'.repeat(2000)); // よく圧縮できる
  const random = Buffer.from(Array.from({ length: 500 }, (_, i) => (i * 131 + 7) % 251)); // 圧縮しても縮まない
  const zipBuffer = createZip([
    { name: 'a.json', data: big },
    { name: 'events/日本語.json', data: text('{}') },
    { name: 'images/x.png', data: random, store: true },
    { name: 'empty.txt', data: Buffer.alloc(0) },
  ]);
  assert.ok(zipBuffer.length < big.length, '圧縮されている');
  const out = readZip(zipBuffer);
  assert.deepStrictEqual(out.map((e) => e.name), ['a.json', 'events/日本語.json', 'images/x.png', 'empty.txt']);
  assert.ok(out[0].data.equals(big) && out[2].data.equals(random) && out[3].data.length === 0);
});

test('読み込みの防御: zipでない・壊れている・上限超え・CRC不一致・暗号化・未対応の圧縮方式を拒否する', () => {
  const good = createZip([{ name: 'a.txt', data: text('hello world hello world hello world') }]);
  assert.throws(() => readZip(text('これはzipではありません、ただの文字列です。')), ZipError);
  assert.throws(() => readZip(good.subarray(0, good.length - 10)), ZipError); // 終端が欠けている

  const many = createZip(Array.from({ length: 5 }, (_, i) => ({ name: `f${i}.txt`, data: text('x') })));
  assert.throws(() => readZip(many, { maxEntries: 4 }), /多すぎ/);
  assert.throws(() => readZip(good, { maxEntryBytes: 10 }), /大きすぎ/);
  assert.throws(() => readZip(good, { maxTotalBytes: 10 }), /大きすぎ/);

  // 中央ディレクトリの先頭(PK\x01\x02)を探して、フィールドを書き換える
  const central = good.indexOf(Buffer.from([0x50, 0x4b, 0x01, 0x02]));
  const corrupt = (mutate) => { const b = Buffer.from(good); mutate(b); return b; };
  assert.throws(() => readZip(corrupt((b) => b.writeUInt32LE(b.readUInt32LE(central + 16) ^ 1, central + 16))), /壊れて/); // CRC
  assert.throws(() => readZip(corrupt((b) => b.writeUInt16LE(1, central + 8))), /暗号化/);
  assert.throws(() => readZip(corrupt((b) => b.writeUInt16LE(99, central + 10))), /圧縮方式/);
  // 申告された展開後の大きさが嘘(展開爆弾): 上限を超える申告は、展開する前に拒否する
  assert.throws(() => readZip(corrupt((b) => b.writeUInt32LE(50 * 1024 * 1024, central + 24))), /大きすぎ/);
  // 申告は小さいが、実際にはもっと大きく展開される: 展開を打ち切って拒否する
  const bomb = createZip([{ name: 'bomb.txt', data: Buffer.alloc(200000, 0x41) }]);
  const bombCentral = bomb.indexOf(Buffer.from([0x50, 0x4b, 0x01, 0x02]));
  bomb.writeUInt32LE(100, bombCentral + 24);
  assert.throws(() => readZip(bomb), ZipError);
});

test('ゲームのZIPReaderが読める形(ローカルヘッダのUTF-8旗・sizeが入っている)', () => {
  const b = createZip([{ name: 'manifest.json', data: text('{"a":1}') }]);
  assert.strictEqual(b.readUInt32LE(0), 0x04034b50);
  assert.strictEqual(b.readUInt16LE(6) & 0x0800, 0x0800);
  assert.strictEqual(b.readUInt32LE(22), 7); // 展開後の大きさ
});
