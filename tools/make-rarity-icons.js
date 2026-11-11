// Native, tintable TGA silhouettes. No runtime drawing or external texture atlas.
const fs = require("node:fs");
const path = require("node:path");
const size = 64;
const polygon = (sides, inner) => Array.from({ length: inner ? sides * 2 : sides }, (_, i) => {
    const angle = -Math.PI / 2 + i * Math.PI * 2 / (inner ? sides * 2 : sides);
    const radius = inner && i % 2 ? inner : 0.43;
    return [0.5 + Math.cos(angle) * radius, 0.5 + Math.sin(angle) * radius];
});
const shapes = { Circle: null, Square: [[.15,.15],[.85,.15],[.85,.85],[.15,.85]], Diamond: polygon(4), Hexagon: polygon(6), Star: polygon(5, .19) };
function inside(x, y, points) {
    if (!points) return (x - .5) ** 2 + (y - .5) ** 2 <= .43 ** 2;
    let result = false;
    for (let i = 0, j = points.length - 1; i < points.length; j = i++) {
        const [a,b] = points[i], [c,d] = points[j];
        if ((b > y) !== (d > y) && x < (c - a) * (y - b) / (d - b) + a) result = !result;
    }
    return result;
}
const output = path.resolve(__dirname, "../AzerothCardBinder/Art/Rarity");
fs.mkdirSync(output, { recursive: true });
for (const [name, points] of Object.entries(shapes)) {
    const header = Buffer.alloc(18); header[2] = 2; header.writeUInt16LE(size, 12); header.writeUInt16LE(size, 14); header[16] = 32; header[17] = 0x28;
    const pixels = Buffer.alloc(size * size * 4);
    for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
        let coverage = 0;
        for (let sy = 0; sy < 4; sy++) for (let sx = 0; sx < 4; sx++) if (inside((x + (sx + .5) / 4) / size, (y + (sy + .5) / 4) / size, points)) coverage++;
        const offset = (y * size + x) * 4;
        pixels[offset] = pixels[offset + 1] = pixels[offset + 2] = 255; pixels[offset + 3] = Math.round(coverage / 16 * 255);
    }
    fs.writeFileSync(path.join(output, name + ".tga"), Buffer.concat([header, pixels]));
}
console.log("Wrote five native rarity silhouettes.");
