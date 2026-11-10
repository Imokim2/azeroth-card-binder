// The Cloudflare Worker entry point. It only wires configuration to the pieces in the other files; there is no
// logic here. Settings come from wrangler.toml (variables) and the dashboard or `wrangler secret` (secrets).
import { createApi } from "./api.ts";
import type { Deps } from "./api.ts";
import { fromD1 } from "./db.ts";
import type { D1Like } from "./db.ts";
import { SqlStore } from "./sqlStore.ts";
import type { Catalog } from "./shared.ts";
import catalog from "../../packages/shared/catalog.json";

export interface Env {
  DB: D1Like;
  MIN_CLIENT: string;
  VERSION: string;
  TAPE_SECRET?: string; // a secret (wrangler secret put TAPE_SECRET); without it Ranked is closed
}

const log: Deps["log"] = (entry) => console.log(JSON.stringify({ at: new Date().toISOString(), ...entry }));

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const db = fromD1(env.DB);
    const store = new SqlStore(db);
    const handle = createApi({
      players: store, ingest: store, board: store, tapes: store, catalog: catalog as Catalog, tapeSecret: env.TAPE_SECRET,
      now: () => Math.floor(Date.now() / 1000), log,
      health: async () => { await db.all("SELECT 1"); },
      minClient: env.MIN_CLIENT, version: env.VERSION,
      // identity: added with the Discord sign-in (roadmap B7); until then registration answers "registration_closed".
    });
    return handle(request);
  },
};
