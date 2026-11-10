// The player's identity: an Ed25519 key pair made on first run (docs/LEDGER-SPEC.md, section 7). The private key is
// kept as a secret by a `SecretStore`; the Electron shell backs that with the operating system's keychain, so the key
// is never written to a plain file. This file does the cryptography and does not know where the secret lives.
import { fromHex, toHex } from "../../packages/shared/src/crypto.ts";

export interface SecretStore {
  get(): Promise<string | null>;
  set(secret: string): Promise<void>;
}

export type Identity = {
  publicKeyHex: string;
  // Ed25519 signature of the text (as UTF-8), as 128 lowercase hex characters.
  sign(message: string): Promise<string>;
};

const encoder = new TextEncoder();

async function fromPrivateKey(privateHex: string, publicKeyHex: string): Promise<Identity> {
  const bytes = fromHex(privateHex);
  if (!bytes) throw new Error("the stored key is damaged");
  const key = await crypto.subtle.importKey("pkcs8", bytes, { name: "Ed25519" }, false, ["sign"]);
  return {
    publicKeyHex,
    async sign(message: string): Promise<string> {
      return toHex(new Uint8Array(await crypto.subtle.sign({ name: "Ed25519" }, key, encoder.encode(message))));
    },
  };
}

// The stored secret is "<public key hex>:<private key hex>" so the public key never has to be re-derived.
export async function loadOrCreateIdentity(store: SecretStore): Promise<Identity> {
  const saved = await store.get();
  if (saved) {
    const [publicKeyHex, privateHex] = saved.split(":");
    if (publicKeyHex && privateHex && /^[0-9a-f]{64}$/.test(publicKeyHex)) return fromPrivateKey(privateHex, publicKeyHex);
    throw new Error("the stored key is damaged; restore it or register a new one");
  }
  const pair = (await crypto.subtle.generateKey({ name: "Ed25519" }, true, ["sign", "verify"])) as unknown as { publicKey: Parameters<typeof crypto.subtle.exportKey>[1]; privateKey: Parameters<typeof crypto.subtle.exportKey>[1] };
  const publicKeyHex = toHex(new Uint8Array(await crypto.subtle.exportKey("raw", pair.publicKey)));
  const privateHex = toHex(new Uint8Array(await crypto.subtle.exportKey("pkcs8", pair.privateKey)));
  await store.set(`${publicKeyHex}:${privateHex}`);
  return fromPrivateKey(privateHex, publicKeyHex);
}
