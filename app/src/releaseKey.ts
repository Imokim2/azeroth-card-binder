// The public key the app trusts for release manifests (see tools/release-manifest.js). Until it is set, the app still says
// when something is out of date, but it will not download or install anything. Set it once, from `keygen`'s output; changing
// it later means every installed app must be replaced by hand, so keep the private key safe.
export const RELEASE_PUBLIC_KEY: string | null = null;
