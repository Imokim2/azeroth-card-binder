// The versions the server announces (GET /v1/releases). The newest versions come from a signed manifest that the release
// tool writes (server/src/releases.json) when there is one, and from Worker variables when there is not; the oldest accepted
// versions are always Worker variables, so raising a minimum never needs a new signature. The server does not check the
// signature: it only passes the manifest on, and the companion app, which holds the public key, decides whether to trust it.

export type Releases = {
  latestApp: string;
  latestAddon: string;
  minAddon: string;
  signed?: { manifest: string; signature: string }; // the manifest exactly as signed, and its Ed25519 signature (hex)
};

export type BundledRelease = { manifest: string | null; signature: string | null };

const VERSION = /^\d+\.\d+\.\d+$/;

type Variables = { MIN_CLIENT: string; LATEST_APP?: string; LATEST_ADDON?: string; MIN_ADDON?: string };

export function releasesFrom(env: Variables, bundled: BundledRelease): Releases {
  const releases: Releases = {
    latestApp: env.LATEST_APP ?? env.MIN_CLIENT,
    latestAddon: env.LATEST_ADDON ?? "0.0.0",
    minAddon: env.MIN_ADDON ?? "0.0.0",
  };
  if (typeof bundled.manifest === "string" && typeof bundled.signature === "string" && /^[0-9a-f]{128}$/.test(bundled.signature)) {
    try {
      const manifest = JSON.parse(bundled.manifest) as { app?: { version?: unknown }; addon?: { version?: unknown } };
      const app = manifest.app?.version;
      const addon = manifest.addon?.version;
      if (typeof app === "string" && VERSION.test(app) && typeof addon === "string" && VERSION.test(addon)) {
        releases.latestApp = app;
        releases.latestAddon = addon;
        releases.signed = { manifest: bundled.manifest, signature: bundled.signature };
      }
    } catch {
      // A manifest that cannot be read is ignored: the variables stand.
    }
  }
  return releases;
}

export type DownloadFile = { version: string; url: string; size: number; sha256: string };

// The two files the signed manifest names, for the download page. The server does not trust the manifest for anything the
// app does (the app checks the signature itself); here it only decides which buttons the page shows, so a file is shown only when
// its address is https and its checksum and size look right. A manifest that cannot be read shows nothing.
export function downloadsFrom(releases: Releases | undefined): { app?: DownloadFile; addon?: DownloadFile } {
  if (!releases?.signed) return {};
  try {
    const manifest = JSON.parse(releases.signed.manifest) as Record<string, unknown>;
    const read = (value: unknown): DownloadFile | undefined => {
      const item = value as Record<string, unknown> | null;
      if (!item || typeof item !== "object") return undefined;
      const { version, url, size, sha256 } = item;
      if (typeof version !== "string" || !VERSION.test(version)) return undefined;
      if (typeof url !== "string" || !/^https:\/\/[^\s"'<>]+$/.test(url)) return undefined;
      if (typeof size !== "number" || !Number.isSafeInteger(size) || size < 1) return undefined;
      if (typeof sha256 !== "string" || !/^[0-9a-f]{64}$/.test(sha256)) return undefined;
      return { version, url, size, sha256 };
    };
    const app = read(manifest["app"]);
    const addon = read(manifest["addon"]);
    return { ...(app ? { app } : {}), ...(addon ? { addon } : {}) };
  } catch {
    return {};
  }
}

// The public page of the project's releases (GitHub). Absent until the repository is public, so the site never links to a page
// that does not exist yet.
export function releasesPageFrom(value: string | undefined): string | undefined {
  return value !== undefined && /^https:\/\/github\.com\/[\w.-]+\/[\w.-]+\/releases(\/latest)?$/.test(value) ? value : undefined;
}
