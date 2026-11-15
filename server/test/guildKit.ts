// Shared set-up for the guild tests: signed requests, a founder whose binder is Ranked with a declared side, and short names for the routes.
import { createRequire } from "node:module";
import { ADMIN_TOKEN, NOW, chainedHistory, newPlayer, registration, setup, signedUpload } from "./harness.ts";
import type { Player } from "./harness.ts";

export type Body = Record<string, unknown> & { error?: { code: string; detail?: Record<string, unknown> }; guild?: Record<string, unknown>; guilds?: Record<string, unknown>[] };
export const read = async (response: Response) => (await response.json()) as Body;
const reference = createRequire(import.meta.url)("../../packages/shared/src/ledger.js") as { signBatch(batch: Record<string, unknown>, key: unknown): string };
export const admin = { authorization: "Bearer " + ADMIN_TOKEN };
export const WEEK = 7 * 86_400;

export type Env = ReturnType<typeof setup>;
export const signed = (player: Player, purpose: string, fields: Record<string, unknown> = {}, extra: Record<string, unknown> = {}) => {
  const body = { key: player.publicKeyHex, sentAt: NOW, ...fields, ...extra };
  return { ...body, sig: reference.signBatch({ ...body, purpose }, player.privateKey) };
};
// A signed POST to /v1/guilds/<path>, stamped with the test clock.
export const post = (env: Env, player: Player, path: string, purpose: string, fields: Record<string, unknown> = {}) =>
  env.call("/v1/guilds/" + path, { body: signed(player, purpose, fields, { sentAt: env.clock.now }) });
export const ask = (env: Env, player: Player, character: string, name: string) => post(env, player, "request", "guild-request", { character, name });
// Recreate an old pre-automatic request for compatibility tests of moderation and pending-name protection.
export const askPending = async (env: Env, player: Player, character: string, name: string) => {
  const response = await ask(env, player, character, name);
  if (response.status !== 201) return response;
  const body = await read(response);
  const guild = body.guild!;
  env.raw.prepare("DELETE FROM guild_members WHERE guild_id = ?").run(guild["id"] as string);
  env.raw.prepare("UPDATE guilds SET status = 'pending', decided_at = NULL, decided_by = '' WHERE id = ?").run(guild["id"] as string);
  return Response.json({ ...body, guild: { ...guild, status: "pending", decidedAt: null } }, { status: 201 });
};
export const mine = async (env: Env, player: Player) => (await read(await post(env, player, "mine", "guild-mine"))).guilds!;
export const decide = (env: Env, id: string, decision: string, note?: string) => env.call(`/v1/admin/guilds/${id}`, { body: { decision, ...(note === undefined ? {} : { note }) }, headers: admin });
export const code = async (response: Response) => (await read(response)).error?.code;

// A registered player with one character who has played (so the server knows it) and whose binder is Ranked, has switched on the faction
// rules and declared a side for that character. The binder's state is set directly: the faction events themselves are tested elsewhere.
export async function founder(env: Env, name: string, options: { realm?: string; side?: string | null; mode?: string; faction?: boolean } = {}) {
  const player = newPlayer(name);
  const registered = await read(await env.call("/v1/register", { body: registration(player) }));
  const realm = options.realm ?? "Realm Name";
  await env.call("/v1/ledger", { body: signedUpload(player, chainedHistory(1, 3), { character: name, realm }) });
  const id = registered["playerId"] as string;
  const peer = `${name.toLowerCase()}-${realm.replace(/[\s'-]/g, "").toLowerCase()}`;
  const sides = options.side === null ? {} : { [`${name}-${realm.replace(/\s/g, "")}`]: options.side ?? "alliance" };
  env.raw.prepare("UPDATE ledger_state SET state_json = json_set(state_json, '$.mode', ?, '$.faction', ?, '$.sides', json(?)) WHERE player_id = ?")
    .run(options.mode ?? "ranked2", options.faction === false ? 0 : 1, JSON.stringify(sides), id);
  return { player, id, peer };
}
