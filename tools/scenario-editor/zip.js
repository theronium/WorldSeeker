'use strict';
// シナリオの書き出し/取り込み用の、最小のzip読み書き(依存パッケージなし。Node.jsのzlibだけを使う)。
// 書くもの: 通常のzip(deflate/store、UTF-8のファイル名)。ゲーム(GodotのZIPReader)とWindows/macOSの標準の展開で読める。
// 読むもの: 上と同じ形式のzip。暗号化・zip64・分割は非対応(エラー)。取り込みは信用できないファイルを読むので、
// 展開後の大きさ・ファイル数の上限、CRCの検証を行う(展開爆弾・破損の対策)。ファイル名の検査は、呼び出し側が行う。
const zlib = require('zlib');

const SIG_LOCAL = 0x04034b50;
const SIG_CENTRAL = 0x02014b50;
const SIG_EOCD = 0x06054b50;

const CRC_TABLE = (() => {
  const table = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = (c & 1) ? (0xedb88320 ^ (c >>> 1)) : (c >>> 1);
    table[n] = c >>> 0;
  }
  return table;
})();

function crc32(buffer) {
  let c = 0xffffffff;
  for (let i = 0; i < buffer.length; i++) c = CRC_TABLE[(c ^ buffer[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

function dosDateTime(date) {
  const time = (date.getHours() << 11) | (date.getMinutes() << 5) | (date.getSeconds() >> 1);
  const day = (Math.max(date.getFullYear(), 1980) - 1980) << 9 | ((date.getMonth() + 1) << 5) | date.getDate();
  return { time: time & 0xffff, date: day & 0xffff };
}

// entries: [{name, data: Buffer, store?: boolean}] → zipのBuffer。storeがtrueなら圧縮しない(PNGなど、既に圧縮済みのもの)
function createZip(entries, now) {
  const stamp = dosDateTime(now || new Date());
  const locals = [];
  const centrals = [];
  let offset = 0;
  for (const entry of entries) {
    const name = Buffer.from(entry.name, 'utf8');
    const data = Buffer.isBuffer(entry.data) ? entry.data : Buffer.from(entry.data);
    const deflated = entry.store ? null : zlib.deflateRawSync(data);
    const useDeflate = deflated && deflated.length < data.length;
    const body = useDeflate ? deflated : data;
    const method = useDeflate ? 8 : 0;
    const crc = crc32(data);

    const local = Buffer.alloc(30);
    local.writeUInt32LE(SIG_LOCAL, 0);
    local.writeUInt16LE(20, 4); // 展開に必要な版
    local.writeUInt16LE(0x0800, 6); // ファイル名はUTF-8
    local.writeUInt16LE(method, 8);
    local.writeUInt16LE(stamp.time, 10);
    local.writeUInt16LE(stamp.date, 12);
    local.writeUInt32LE(crc, 14);
    local.writeUInt32LE(body.length, 18);
    local.writeUInt32LE(data.length, 22);
    local.writeUInt16LE(name.length, 26);
    local.writeUInt16LE(0, 28);
    locals.push(local, name, body);

    const central = Buffer.alloc(46);
    central.writeUInt32LE(SIG_CENTRAL, 0);
    central.writeUInt16LE(20, 4); // 作成した版
    central.writeUInt16LE(20, 6);
    central.writeUInt16LE(0x0800, 8);
    central.writeUInt16LE(method, 10);
    central.writeUInt16LE(stamp.time, 12);
    central.writeUInt16LE(stamp.date, 14);
    central.writeUInt32LE(crc, 16);
    central.writeUInt32LE(body.length, 20);
    central.writeUInt32LE(data.length, 24);
    central.writeUInt16LE(name.length, 28);
    central.writeUInt32LE(offset, 42);
    centrals.push(central, name);
    offset += local.length + name.length + body.length;
  }
  const centralBuffer = Buffer.concat(centrals);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(SIG_EOCD, 0);
  end.writeUInt16LE(entries.length, 8);
  end.writeUInt16LE(entries.length, 10);
  end.writeUInt32LE(centralBuffer.length, 12);
  end.writeUInt32LE(offset, 16);
  return Buffer.concat([...locals, centralBuffer, end]);
}

class ZipError extends Error {}

// zipのBuffer → [{name, data}](ディレクトリのエントリは除く)。limits: {maxEntries, maxEntryBytes, maxTotalBytes}
function readZip(buffer, limits) {
  const { maxEntries = 2000, maxEntryBytes = 8 * 1024 * 1024, maxTotalBytes = 64 * 1024 * 1024 } = limits || {};
  if (buffer.length < 22) throw new ZipError('zipファイルではありません');
  let eocd = -1;
  for (let i = buffer.length - 22; i >= Math.max(0, buffer.length - 22 - 65535); i--) {
    if (buffer.readUInt32LE(i) === SIG_EOCD) { eocd = i; break; }
  }
  if (eocd < 0) throw new ZipError('zipファイルではありません');
  const total = buffer.readUInt16LE(eocd + 10);
  const centralSize = buffer.readUInt32LE(eocd + 12);
  const centralOffset = buffer.readUInt32LE(eocd + 16);
  if (total === 0xffff || centralOffset === 0xffffffff || centralSize === 0xffffffff) throw new ZipError('zip64には対応していません');
  if (total > maxEntries) throw new ZipError(`zipの中のファイルが多すぎます(${total}個)`);
  if (centralOffset + centralSize > buffer.length) throw new ZipError('zipファイルが壊れています');

  const out = [];
  let pos = centralOffset;
  let totalBytes = 0;
  for (let n = 0; n < total; n++) {
    if (pos + 46 > buffer.length || buffer.readUInt32LE(pos) !== SIG_CENTRAL) throw new ZipError('zipファイルが壊れています');
    const flags = buffer.readUInt16LE(pos + 8);
    const method = buffer.readUInt16LE(pos + 10);
    const crc = buffer.readUInt32LE(pos + 16);
    const compressedSize = buffer.readUInt32LE(pos + 20);
    const size = buffer.readUInt32LE(pos + 24);
    const nameLength = buffer.readUInt16LE(pos + 28);
    const extraLength = buffer.readUInt16LE(pos + 30);
    const commentLength = buffer.readUInt16LE(pos + 32);
    const localOffset = buffer.readUInt32LE(pos + 42);
    const name = buffer.toString('utf8', pos + 46, pos + 46 + nameLength);
    pos += 46 + nameLength + extraLength + commentLength;
    if (name.endsWith('/')) continue; // ディレクトリ
    if (flags & 1) throw new ZipError('暗号化されたzipには対応していません');
    if (compressedSize === 0xffffffff || size === 0xffffffff) throw new ZipError('zip64には対応していません');
    if (size > maxEntryBytes) throw new ZipError(`zipの中のファイルが大きすぎます: ${name}`);
    totalBytes += size;
    if (totalBytes > maxTotalBytes) throw new ZipError('zipを展開した大きさが大きすぎます');
    if (localOffset + 30 > buffer.length || buffer.readUInt32LE(localOffset) !== SIG_LOCAL) throw new ZipError('zipファイルが壊れています');
    const dataStart = localOffset + 30 + buffer.readUInt16LE(localOffset + 26) + buffer.readUInt16LE(localOffset + 28);
    if (dataStart + compressedSize > buffer.length) throw new ZipError('zipファイルが壊れています');
    const raw = buffer.subarray(dataStart, dataStart + compressedSize);
    let data;
    if (method === 0) data = Buffer.from(raw);
    else if (method === 8) {
      try { data = zlib.inflateRawSync(raw, { maxOutputLength: Math.max(size, 1) }); }
      catch { throw new ZipError(`zipの中のファイルを展開できません: ${name}`); }
    } else throw new ZipError(`対応していない圧縮方式です: ${name}`);
    if (data.length !== size || crc32(data) !== crc) throw new ZipError(`zipの中のファイルが壊れています: ${name}`);
    out.push({ name, data });
  }
  return out;
}

module.exports = { createZip, readZip, crc32, ZipError };
