// Draws the app's icons (a brass diamond on a dark leather square, like the card gem) as plain PNG files, with no
// image library: node tools/make-icons.js. The output is committed (app/assets/), so this only needs running to change them.
const fs = require("fs");
const path = require("path");
const zlib = require("zlib");

function crc32(buffer) {
  let crc = ~0;
  for (const byte of buffer) {
    crc ^= byte;
    for (let bit = 0; bit < 8; bit++) crc = (crc >>> 1) ^ (0xedb88320 & -(crc & 1));
  }
  return ~crc >>> 0;
}
function chunk(type, data) {
  const body = Buffer.concat([Buffer.from(type), data]);
  const out = Buffer.alloc(12 + data.length);
  out.writeUInt32BE(data.length, 0);
  body.copy(out, 4);
  out.writeUInt32BE(crc32(body), 8 + data.length);
  return out;
}
function png(size, pixel) {
  const raw = Buffer.alloc((size * 4 + 1) * size);
  for (let y = 0; y < size; y++) {
    raw[y * (size * 4 + 1)] = 0;
    for (let x = 0; x < size; x++) {
      const [r, g, b, a] = pixel(x + 0.5, y + 0.5, size);
      raw.set([r, g, b, a], y * (size * 4 + 1) + 1 + x * 4);
    }
  }
  const header = Buffer.alloc(13);
  header.writeUInt32BE(size, 0);
  header.writeUInt32BE(size, 4);
  header.set([8, 6, 0, 0, 0], 8);
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk("IHDR", header), chunk("IDAT", zlib.deflateSync(raw)), chunk("IEND", Buffer.alloc(0))]);
}

// A diamond (|x| + |y| <= r) with a lighter inner diamond, on a rounded dark square.
function icon(x, y, size) {
  const c = size / 2;
  const dx = Math.abs(x - c) / size;
  const dy = Math.abs(y - c) / size;
  const corner = size * 0.18;
  const inSquare = Math.min(x, size - x) > 0 && Math.min(y, size - y) > 0 &&
    !(Math.min(x, size - x) < corner && Math.min(y, size - y) < corner && Math.hypot(corner - Math.min(x, size - x), corner - Math.min(y, size - y)) > corner);
  if (!inSquare) return [0, 0, 0, 0];
  const d = dx + dy;
  if (d <= 0.2) return [255, 214, 120, 255];
  if (d <= 0.32) return [196, 140, 60, 255];
  if (d <= 0.36) return [96, 66, 28, 255];
  return [30, 22, 16, 255];
}

const out = path.join(__dirname, "..", "app", "assets");
fs.mkdirSync(out, { recursive: true });
fs.writeFileSync(path.join(out, "icon.png"), png(256, icon));
fs.writeFileSync(path.join(out, "tray.png"), png(32, icon));
console.log("wrote app/assets/icon.png and tray.png");
