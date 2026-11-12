// The public key the app trusts for release manifests (see tools/release-manifest.js). Without a key the app still says
// when something is out of date, but it will not download or install anything. Set on 12 Nov 2026 from `keygen`'s output;
// changing it means every installed app must be replaced by hand, so keep the private key safe.
export const RELEASE_PUBLIC_KEY: string | null = "fe1ccd8a429945c045b54b9311d703919064b301d697d86882019c5e4687cc40";
