// The review page: it exists only when an admin token is set, it may run only its own script, nothing loads without the token,
// and what it shows from the server is text, never markup. The script is run here against a small stand-in for the browser's
// page and the real API, so the buttons are exercised as a person would press them.
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { runInNewContext } from "node:vm";
import test from "node:test";
import { ADMIN_SCRIPT } from "../src/adminPage.ts";
import { ADMIN_TOKEN, NOW, chainedHistory, newPlayer, registration, setup, signedUpload } from "./harness.ts";

type Body = Record<string, unknown>;
const BASE = "https://admin.test";

// ---- a very small browser page: just enough for the script ----
class Node_ {
  children: Node_[] = [];
  listeners: Record<string, ((event: { preventDefault(): void }) => void)[]> = {};
  className = "";
  value = "";
  disabled = false;
  placeholder = "";
  maxLength = 0;
  removed = false;
  private text = "";
  tag: string;
  constructor(tag: string) { this.tag = tag; }
  set textContent(value: string) { this.text = value; this.children = []; }
  get textContent(): string { return this.text + this.children.map((child) => child.textContent).join(""); }
  set innerHTML(_value: string) { throw new Error("the script must never set innerHTML"); }
  appendChild(child: Node_) { this.children.push(child); return child; }
  replaceChildren(...nodes: Node_[]) { this.children = nodes; this.text = ""; }
  remove() { this.removed = true; }
  addEventListener(type: string, handler: (event: { preventDefault(): void }) => void) { (this.listeners[type] ??= []).push(handler); }
  fire(type: string) { for (const handler of this.listeners[type] ?? []) handler({ preventDefault() {} }); }
  find(predicate: (node: Node_) => boolean): Node_[] { return [...(predicate(this) ? [this] : []), ...this.children.flatMap((child) => child.find(predicate))]; }
}

function page(fetchImpl: typeof fetch, answer = true) {
  const ids: Record<string, Node_> = {};
  for (const [id, tag] of [["signin", "form"], ["token", "input"], ["state", "select"], ["refresh", "button"], ["message", "p"], ["flags", "div"]] as const) ids[id] = new Node_(tag);
  ids["state"]!.value = "open";
  const confirms: string[] = [];
  runInNewContext(ADMIN_SCRIPT, {
    document: { getElementById: (id: string) => ids[id], createElement: (tag: string) => new Node_(tag) },
    window: { confirm: (question: string) => { confirms.push(question); return answer; } },
    fetch: fetchImpl, encodeURIComponent, Date, JSON, Object, Error, Promise,
  });
  return { ids, confirms, signIn: async (token: string) => { ids["token"]!.value = token; ids["signin"]!.fire("submit"); await settle(); } };
}
const settle = () => new Promise((resolve) => setTimeout(resolve, 30));

async function withFlag(displayName = "Mallory") {
  const env = setup();
  const player = newPlayer(displayName);
  const registered = (await (await env.call("/v1/register", { body: registration(player, { visibility: "public" }) })).json()) as Body;
  await env.call("/v1/ledger", { body: signedUpload(player, chainedHistory(1, 3), { character: displayName, realm: "Realm Name" }) });
  const playerId = registered["playerId"] as string;
  env.raw.prepare("INSERT INTO flags (id, player_id, kind, notes, created_at) VALUES ('flag1', ?, 'luck-hold', ?, ?)").run(playerId, "<b>bold</b> luck beyond 1 in 10^9", NOW);
  env.raw.prepare("DELETE FROM flags WHERE id <> 'flag1'").run(); // the upload may have raised flags of its own: keep only this one
  const fetchImpl = (async (path: string, init?: RequestInit) => env.api(new Request(BASE + path, init))) as unknown as typeof fetch;
  return { env, playerId, fetchImpl };
}

test("the review page exists only with an admin token, loads without one, and may run only its own script", async () => {
  const env = setup();
  const response = await env.call("/admin");
  assert.equal(response.status, 200);
  assert.equal(response.headers.get("cache-control"), "no-store");
  assert.match(response.headers.get("x-robots-tag") ?? "", /noindex/);
  const html = await response.text();
  const scripts = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)];
  assert.equal(scripts.length, 1, "exactly one script");
  assert.ok(!/<script[^>]+src=/.test(html) && !/https?:\/\//.test(html.replace(/<meta[^>]*>/g, "")), "nothing loaded from elsewhere");
  const hash = createHash("sha256").update(scripts[0]![1] as string).digest("base64");
  const policy = response.headers.get("content-security-policy") ?? "";
  assert.ok(policy.includes(`script-src 'sha256-${hash}'`), policy);
  assert.match(policy, /connect-src 'self'/);
  assert.match(policy, /default-src 'none'/);
  assert.ok(!html.includes(ADMIN_TOKEN), "the page holds no secret");
  // Without a token configured it does not exist; every call it makes needs the token.
  env.deps.adminToken = undefined;
  assert.equal((await env.call("/admin")).status, 404);
  assert.equal((await env.call("/admin", { method: "POST", body: {} })).status, 405);
});

test("the script never writes markup, evaluates text, or keeps the token", () => {
  assert.ok(!/innerHTML|outerHTML|insertAdjacentHTML|document\.write|eval\(|new Function|localStorage|sessionStorage|document\.cookie|location\./.test(ADMIN_SCRIPT));
});

test("with the right token the open flags are listed as text, and a wrong token is refused", async () => {
  const { fetchImpl } = await withFlag("<img src=x onerror=alert(1)>");
  const wrong = page(fetchImpl);
  await wrong.signIn("not the token");
  assert.equal(wrong.ids["message"]!.textContent, "That token is not right.");
  assert.equal(wrong.ids["flags"]!.children.length, 0);

  const right = page(fetchImpl);
  await right.signIn(ADMIN_TOKEN);
  assert.equal(right.ids["token"]!.value, "", "the token is cleared from the field once used");
  assert.equal(right.ids["message"]!.textContent, "1 flag.");
  const cards = right.ids["flags"]!.children;
  assert.equal(cards.length, 1);
  assert.match(cards[0]!.textContent, /<img src=x onerror=alert\(1\)>-Realm Name - luck-hold/, "a name with markup in it is shown as the text it is");
  assert.match(cards[0]!.textContent, /<b>bold<\/b> luck beyond/);
});

test("clearing a flag records the decision and the note, and takes the flag off the list", async () => {
  const { env, fetchImpl } = await withFlag();
  const view = page(fetchImpl);
  await view.signIn(ADMIN_TOKEN);
  const card = view.ids["flags"]!.children[0]!;
  const note = card.find((node) => node.tag === "textarea")[0]!;
  note.value = "Looked fine: a long streak, no pattern.";
  card.find((node) => node.tag === "button" && node.textContent.startsWith("Clear"))[0]!.fire("click");
  await settle();
  assert.equal(card.removed, true);
  assert.equal(view.ids["message"]!.textContent, "Flag cleared.");
  const row = env.raw.prepare("SELECT state, review_note AS note FROM flags WHERE id = 'flag1'").get() as { state: string; note: string };
  assert.deepEqual([row.state, row.note], ["cleared", "Looked fine: a long streak, no pattern."]);
});

test("banning asks first, and only an agreed ban is sent; the reports about a player can be read", async () => {
  const { env, playerId, fetchImpl } = await withFlag();
  const declined = page(fetchImpl, false);
  await declined.signIn(ADMIN_TOKEN);
  declined.ids["flags"]!.children[0]!.find((node) => node.textContent === "Ban")[0]!.fire("click");
  await settle();
  assert.equal(declined.confirms.length, 1);
  assert.match(declined.confirms[0]!, /^Ban Mallory.*\?/);
  assert.equal((env.raw.prepare("SELECT status FROM players WHERE id = ?").get(playerId) as { status: string }).status, "active");

  const agreed = page(fetchImpl, true);
  await agreed.signIn(ADMIN_TOKEN);
  const card = agreed.ids["flags"]!.children[0]!;
  card.find((node) => node.textContent === "Ban")[0]!.fire("click");
  await settle();
  assert.match(agreed.ids["message"]!.textContent, /^Banned Mallory.*\.$/);
  assert.equal((env.raw.prepare("SELECT status FROM players WHERE id = ?").get(playerId) as { status: string }).status, "banned");

  card.find((node) => node.textContent === "Reports about them")[0]!.fire("click");
  await settle();
  assert.match(card.find((node) => node.tag === "ul")[0]!.textContent, /No reports about this player/);
});
