#!/usr/bin/env node
/**
 * Generate solid-colour PNG icons for the PWA manifest. No image-processing
 * dependencies — we emit raw PNG bytes using Node's built-in zlib + crc32.
 *
 * Output:
 *   public/icons/icon-192.png
 *   public/icons/icon-512.png
 *   public/icons/icon-maskable-512.png
 *
 * These are intentionally simple (teal shield on dark) so the PWA install
 * flow has a real icon. Replace with a designer asset for production.
 */
import { writeFileSync, mkdirSync } from 'node:fs';
import { deflateSync } from 'node:zlib';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const outDir = resolve(__dirname, '..', 'public', 'icons');
mkdirSync(outDir, { recursive: true });

const BG = [0x08, 0x0c, 0x14];
const FG = [0x00, 0xc9, 0xa7];

function crc32(buf) {
  let c;
  const table = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    table[n] = c >>> 0;
  }
  let crc = 0xffffffff;
  for (let i = 0; i < buf.length; i++) crc = table[(crc ^ buf[i]) & 0xff] ^ (crc >>> 8);
  return (crc ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length, 0);
  const typeBuf = Buffer.from(type, 'ascii');
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(Buffer.concat([typeBuf, data])), 0);
  return Buffer.concat([len, typeBuf, data, crc]);
}

// Draw a simple shield + dot in FG on BG, returning a size×size RGB pixel grid.
function render(size, maskableSafeZone = false) {
  const pixels = new Uint8Array(size * size * 3);
  for (let i = 0; i < size * size; i++) {
    pixels[i * 3] = BG[0];
    pixels[i * 3 + 1] = BG[1];
    pixels[i * 3 + 2] = BG[2];
  }
  const inset = maskableSafeZone ? Math.floor(size * 0.2) : Math.floor(size * 0.08);
  const cx = size / 2;
  const cy = size / 2;
  const shieldW = size - 2 * inset;
  const shieldH = size - 2 * inset;
  const strokeW = Math.max(2, Math.floor(size / 40));

  function setPx(x, y, rgb) {
    if (x < 0 || y < 0 || x >= size || y >= size) return;
    const idx = (y * size + x) * 3;
    pixels[idx] = rgb[0];
    pixels[idx + 1] = rgb[1];
    pixels[idx + 2] = rgb[2];
  }

  // Shield outline
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const nx = (x - cx) / (shieldW / 2);
      const ny = (y - cy) / (shieldH / 2);
      // Rounded top, pointed bottom
      const onTop = ny < -0.1 && nx * nx + (ny + 0.2) * (ny + 0.2) * 1.2 < 0.92;
      const onBody =
        ny >= -0.1 && ny < 0.45 && Math.abs(nx) < 0.9 - ny * 0.1;
      const onPoint = ny >= 0.45 && Math.abs(nx) < 0.9 - (ny - 0.45) * 1.6;
      const inside = onTop || onBody || onPoint;
      if (!inside) continue;

      // Border band
      const edgeDist = Math.min(
        Math.abs(0.9 - Math.abs(nx)),
        Math.abs(ny + 0.95),
        Math.abs(0.85 - ny),
      );
      if (edgeDist < strokeW / size) {
        setPx(x, y, FG);
      }
    }
  }

  // Centre dot
  const dotR = Math.max(6, Math.floor(size / 12));
  for (let y = -dotR; y <= dotR; y++) {
    for (let x = -dotR; x <= dotR; x++) {
      if (x * x + y * y <= dotR * dotR) {
        setPx(Math.round(cx + x), Math.round(cy + y - size * 0.05), FG);
      }
    }
  }

  return pixels;
}

function writePng(filePath, size, maskableSafeZone = false) {
  const pixels = render(size, maskableSafeZone);
  // Build raw scanlines prefixed with filter byte 0.
  const raw = Buffer.alloc(size * (size * 3 + 1));
  for (let y = 0; y < size; y++) {
    raw[y * (size * 3 + 1)] = 0;
    for (let x = 0; x < size; x++) {
      const src = (y * size + x) * 3;
      const dst = y * (size * 3 + 1) + 1 + x * 3;
      raw[dst] = pixels[src];
      raw[dst + 1] = pixels[src + 1];
      raw[dst + 2] = pixels[src + 2];
    }
  }
  const idatData = deflateSync(raw);

  const signature = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(size, 0);
  ihdr.writeUInt32BE(size, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 2; // RGB
  ihdr[10] = 0;
  ihdr[11] = 0;
  ihdr[12] = 0;

  const png = Buffer.concat([
    signature,
    chunk('IHDR', ihdr),
    chunk('IDAT', idatData),
    chunk('IEND', Buffer.alloc(0)),
  ]);
  writeFileSync(filePath, png);
  console.log(`wrote ${filePath} (${png.length} bytes)`);
}

writePng(resolve(outDir, 'icon-192.png'), 192);
writePng(resolve(outDir, 'icon-512.png'), 512);
writePng(resolve(outDir, 'icon-maskable-512.png'), 512, true);
