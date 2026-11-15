import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";

// Exercise the shipped renderer with delayed sync status and a tiny DOM, without any network polling.
test("the guild dropdown fills after the first sync, preserves selection, and explains an empty list", () => {
  class Element {
    id = ""; value = ""; textContent = ""; hidden = false; disabled = false; className = "";
    children: Element[] = [];
    classList = { toggle() {}, add() {}, remove() {} };
    get options() { return this.children; }
    replaceChildren(...children: Element[]) { this.children = children; this.value = ""; }
    append(...children: Element[]) { this.children.push(...children); if (!this.value && children[0]) this.value = children[0].value; }
    appendChild(child: Element) { this.append(child); }
    addEventListener() {}
    setAttribute() {}
  }
  const elements = new Map<string, Element>();
  const html = readFileSync(new URL("../electron/renderer/index.html", import.meta.url), "utf8");
  for (const match of html.matchAll(/\bid="([^"]+)"/g)) elements.set(match[1]!, new Element());
  const api = { onStatus() {}, status: () => new Promise(() => {}) };
  const context = vm.createContext({ document: { getElementById: (id: string) => elements.get(id), createElement: () => new Element(), querySelectorAll: () => [], querySelector: () => null }, window: { warcards: api }, location: { hash: "" }, setInterval() {}, console });
  vm.runInContext(readFileSync(new URL("../electron/renderer/renderer.js", import.meta.url), "utf8"), context);
  vm.runInContext('renderGuild({ signedIn: true, available: true, membership: null, requests: [], characters: [], roster: null, message: null })', context);
  assert.equal(elements.get("guild-request")!.disabled, true);
  assert.equal(elements.get("guild-character-hint")!.hidden, false);
  // A later sync updates the main status, without another guild API request or pressing Refresh.
  vm.runInContext('render({ ...demos.syncing, guildCharacters: ["alice-realmname", "bob-realmname"] })', context);
  const select = elements.get("guild-character")!;
  assert.deepEqual(select.options.map(o => o.value), ["alice-realmname", "bob-realmname"]);
  assert.equal(elements.get("guild-request")!.disabled, false);
  assert.equal(elements.get("guild-character-hint")!.hidden, true);
  select.value = "bob-realmname";
  vm.runInContext('render({ ...demos.syncing, guildCharacters: ["alice-realmname", "bob-realmname", "charlie-realmname"] })', context);
  assert.equal(select.value, "bob-realmname");
  vm.runInContext('render({ ...demos.syncing, guildCharacters: [] })', context);
  assert.equal(elements.get("guild-request")!.disabled, true);
  assert.match(select.options[0]!.textContent, /No Ranked characters/);
});
