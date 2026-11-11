// Keeping the private key safe on disk (roadmap B7). The key is encrypted with the operating system's own protection
// (on Windows, tied to the signed-in user's account) and only the encrypted bytes are written, so the file is useless
// anywhere else and to anyone else. This file does not know about Electron: it is given the two functions to encrypt and
// decrypt, which the shell takes from Electron's `safeStorage`.
import { readFile } from "node:fs/promises";
import { writeFileAtomic } from "./files.ts";
import type { SecretStore } from "./identity.ts";

export type Crypt = {
  available(): boolean | Promise<boolean>; // false when the system has no protection to offer (the key is then not stored at all)
  encrypt(text: string): Uint8Array | Promise<Uint8Array>;
  decrypt(bytes: Uint8Array): string | Promise<string>;
};

export class SecretStorageUnavailable extends Error {}

export function encryptedFileStore(path: string, crypt: Crypt): SecretStore {
  return {
    async get(): Promise<string | null> {
      let bytes: Buffer;
      try {
        bytes = await readFile(path);
      } catch {
        return null;
      }
      if (!(await crypt.available())) throw new SecretStorageUnavailable("the system's key protection is not available");
      try {
        return await crypt.decrypt(bytes);
      } catch {
        // Encrypted for another user or another machine, or damaged: it cannot be used, and is not guessed at.
        throw new SecretStorageUnavailable("the stored key cannot be read by this user on this computer");
      }
    },
    async set(secret: string): Promise<void> {
      if (!(await crypt.available())) throw new SecretStorageUnavailable("the system's key protection is not available");
      await writeFileAtomic(path, await crypt.encrypt(secret));
    },
  };
}
