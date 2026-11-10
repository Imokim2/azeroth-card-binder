// Hashing, hex and signatures, written with Web Crypto only so the same code runs in a Cloudflare Worker and in
// Node. Everything here follows docs/LEDGER-SPEC.md and is checked against packages/shared/vectors.

const encoder = new TextEncoder();

export function toHex(bytes: Uint8Array): string {
  let text = "";
  for (const byte of bytes) text += byte.toString(16).padStart(2, "0");
  return text;
}

// Lowercase hex of an exact length (in characters), or null.
export function fromHex(hex: string, length?: number): Uint8Array | null {
  if (!/^(?:[0-9a-f]{2})*$/.test(hex) || (length !== undefined && hex.length !== length)) return null;
  const bytes = new Uint8Array(hex.length / 2);
  for (let index = 0; index < bytes.length; index++) bytes[index] = parseInt(hex.slice(index * 2, index * 2 + 2), 16);
  return bytes;
}

export async function sha256Hex(text: string): Promise<string> {
  return toHex(new Uint8Array(await crypto.subtle.digest("SHA-256", encoder.encode(text))));
}

// Canonical JSON (spec section 6.1): keys sorted, no spaces, integers only, no null.
export function canonicalJson(value: unknown): string {
  if (value === null || value === undefined) throw new Error("canonical JSON has no null or undefined");
  if (typeof value === "number") {
    if (!Number.isSafeInteger(value)) throw new Error("canonical JSON has integers only");
    return String(value);
  }
  if (typeof value === "boolean") return value ? "true" : "false";
  if (typeof value === "string") return JSON.stringify(value);
  if (Array.isArray(value)) return "[" + value.map(canonicalJson).join(",") + "]";
  if (typeof value === "object") {
    const record = value as Record<string, unknown>;
    const keys = Object.keys(record).sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
    return "{" + keys.map((key) => JSON.stringify(key) + ":" + canonicalJson(record[key])).join(",") + "}";
  }
  throw new Error("canonical JSON cannot hold a " + typeof value);
}

// Is `signatureHex` (128 hex characters) the Ed25519 signature of `message` under `publicKeyHex` (64 hex)?
export async function verifySignature(publicKeyHex: string, signatureHex: string, message: string): Promise<boolean> {
  const key = fromHex(publicKeyHex, 64);
  const signature = fromHex(signatureHex, 128);
  if (!key || !signature) return false;
  try {
    const imported = await crypto.subtle.importKey("raw", key, { name: "Ed25519" }, false, ["verify"]);
    return await crypto.subtle.verify({ name: "Ed25519" }, imported, signature, encoder.encode(message));
  } catch {
    return false;
  }
}

// A random identifier that sorts by creation time: 10 characters of time then 16 of randomness, Crockford base32
// (a ULID). Random, never counted up, so players can be moved between databases later.
const ALPHABET = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
export function newId(nowMs: number, randomBytes: (length: number) => Uint8Array = (n) => crypto.getRandomValues(new Uint8Array(n))): string {
  let time = "";
  let remaining = nowMs;
  for (let index = 0; index < 10; index++) {
    time = ALPHABET.charAt(remaining % 32) + time;
    remaining = Math.floor(remaining / 32);
  }
  let randomPart = "";
  for (const byte of randomBytes(16)) randomPart += ALPHABET.charAt(byte % 32);
  return time + randomPart;
}
