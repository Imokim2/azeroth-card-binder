// Signing in with Discord, the app's half (roadmap B7). The player's own browser shows Discord's sign-in page; Discord
// sends the browser back to a tiny web server that listens on this computer only, with a one-time code. The app hands the
// code to our server, which is the only place that holds the Discord application's secret and the only one that talks to
// Discord about it. The app never sees a Discord password, token or secret.
import { createServer } from "node:http";
import type { IncomingMessage, Server, ServerResponse } from "node:http";
import { registerKey } from "./client.ts";
import type { ClientOptions, Outcome } from "./client.ts";

// The Discord application (public), and the address registered for it in the Discord developer portal.
export const DISCORD_CLIENT_ID = "1569844563957260298";
export const REDIRECT_PORT = 53682;

export type SignInOptions = {
  open: (url: string) => void | Promise<void>; // opens the page in the player's browser (Electron: shell.openExternal)
  clientId?: string;
  port?: number; // 0 picks a free one (tests); the real app uses the registered port
  timeoutMs?: number; // how long to wait for the player (default five minutes)
  state?: () => string; // for tests
};

export type SignInResult = { status: "code"; code: string } | { status: "failed"; reason: "denied" | "timeout" | "port-busy" | "closed" | "browser" };

export function authorizeUrl(clientId: string, redirectUri: string, state: string): string {
  const query = new URLSearchParams({ client_id: clientId, response_type: "code", scope: "identify", redirect_uri: redirectUri, state });
  return `https://discord.com/oauth2/authorize?${query.toString()}`;
}

const randomState = (): string => [...crypto.getRandomValues(new Uint8Array(16))].map((byte) => byte.toString(16).padStart(2, "0")).join("");

const page = (title: string, message: string): string =>
  `<!doctype html><html lang="en"><meta charset="utf-8"><title>${title}</title>` +
  `<body style="font-family:sans-serif;background:#1b1410;color:#ecdcb4;text-align:center;padding-top:20vh">` +
  `<h1 style="color:#e0b066">${title}</h1><p>${message}</p></body></html>`;

function reply(response: ServerResponse, status: number, title: string, message: string): void {
  response.writeHead(status, { "content-type": "text/html; charset=utf-8", "cache-control": "no-store", "x-content-type-options": "nosniff", "referrer-policy": "no-referrer" });
  response.end(page(title, message));
}

export function signIn(options: SignInOptions): Promise<SignInResult> {
  const clientId = options.clientId ?? DISCORD_CLIENT_ID;
  const state = (options.state ?? randomState)();
  return new Promise<SignInResult>((resolve) => {
    let finished = false;
    let server: Server | undefined;
    let timer: ReturnType<typeof setTimeout> | undefined;
    const finish = (result: SignInResult): void => {
      if (finished) return;
      finished = true;
      if (timer) clearTimeout(timer);
      server?.close();
      server?.closeAllConnections();
      resolve(result);
    };
    server = createServer((request: IncomingMessage, response: ServerResponse) => {
      const address = server?.address();
      const port = typeof address === "object" && address ? address.port : 0;
      // Only this computer's own address is accepted as the host, so a web page cannot talk to this server by tricking the
      // browser into resolving another name to 127.0.0.1.
      if (request.headers.host !== `127.0.0.1:${port}`) return reply(response, 400, "Not allowed", "This address cannot be used here.");
      const url = new URL(request.url ?? "/", `http://127.0.0.1:${port}`);
      if (request.method !== "GET" || url.pathname !== "/callback") return reply(response, 404, "Not found", "There is nothing here.");
      if (url.searchParams.get("state") !== state) return reply(response, 400, "Sign-in not recognised", "This sign-in was not started by World of Warcards. Close this window and try again from the app.");
      if (url.searchParams.get("error")) {
        reply(response, 200, "Sign-in cancelled", "You can close this window and return to World of Warcards.");
        return finish({ status: "failed", reason: "denied" });
      }
      const code = url.searchParams.get("code");
      if (!code || !/^[A-Za-z0-9._-]{8,200}$/.test(code)) return reply(response, 400, "Sign-in failed", "Discord did not send a usable code. Close this window and try again.");
      reply(response, 200, "Signed in", "You can close this window and return to World of Warcards.");
      finish({ status: "code", code });
    });
    server.on("error", (error: NodeJS.ErrnoException) => finish({ status: "failed", reason: error.code === "EADDRINUSE" ? "port-busy" : "closed" }));
    server.listen(options.port ?? REDIRECT_PORT, "127.0.0.1", () => {
      const address = server?.address();
      const port = typeof address === "object" && address ? address.port : 0;
      timer = setTimeout(() => finish({ status: "failed", reason: "timeout" }), options.timeoutMs ?? 300_000);
      Promise.resolve().then(() => options.open(authorizeUrl(clientId, `http://127.0.0.1:${port}/callback`, state))).catch(() => finish({ status: "failed", reason: "browser" }));
    });
  });
}

// Sign in, then register this computer's key against the Discord account the sign-in proved.
export async function signInAndRegister(
  client: ClientOptions, visibility: "public" | "private", options: SignInOptions,
): Promise<{ status: "registered"; playerId: string } | Outcome | Extract<SignInResult, { status: "failed" }>> {
  const result = await signIn(options);
  if (result.status !== "code") return result;
  return registerKey(client, result.code, visibility);
}
