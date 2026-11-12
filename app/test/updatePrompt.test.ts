import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import vm from "node:vm";

function screen() {
  const html = readFileSync(new URL("../electron/renderer/index.html", import.meta.url), "utf8");
  const element = () => ({ textContent: "", hidden: false, disabled: false, className: "", checked: false,
    classList: { toggle() {} }, replaceChildren() {}, append() {} });
  const elements = new Map([...html.matchAll(/\bid="([^"]+)"/g)].map(match => [match[1]!, element()]));
  const context = vm.createContext({ location: { hash: "#demo-setup" }, Date, console,
    document: { getElementById: (id: string) => elements.get(id), createElement: element } });
  vm.runInContext(readFileSync(new URL("../electron/renderer/renderer.js", import.meta.url), "utf8"), context);
  return { elements, draw(status: unknown) { context["testStatus"] = status; vm.runInContext("render(testStatus)", context); } };
}
const status = () => ({ version: "1.0.0", signedIn: true, gameFolder: "C:/Game", problem: null, needsNewBinder: false,
  accounts: [{ account: "Test", state: "Up to date", mode: "ranked" }], lastSyncAt: 1, standings: "fresh", visibility: "public",
  startAtLogin: false, busy: false, checkingUpdates: false, updateCheckMessage: null, updating: null, message: null,
  updates: { app: { state: "update", version: "1.0.0", latest: "2.0.0" },
    addon: { state: "update", installed: "0.5.0", latest: "0.6.0", reloadNeeded: false } },
  canUpdate: { app: true, addon: true }, newer: { app: "2.0.0", addon: "0.6.0" } });

test("the update prompt shows both available versions and actions even when the binder has synced", () => {
  const s = screen(); s.draw(status());
  assert.equal(s.elements.get("pill")!.textContent, "Update available");
  assert.equal(s.elements.get("update-prompt")!.hidden, false);
  assert.match(s.elements.get("update-note")!.textContent, /Companion 2\.0\.0/);
  assert.match(s.elements.get("update-note")!.textContent, /Addon 0\.6\.0/);
  assert.equal(s.elements.get("update-app")!.hidden, false);
  assert.equal(s.elements.get("update-addon")!.hidden, false);
});

test("a manual check disables update actions temporarily and a current installation hides the prompt", () => {
  const s = screen(), value = status(); value.checkingUpdates = true; s.draw(value);
  assert.equal(s.elements.get("update-app")!.disabled, true);
  assert.equal(s.elements.get("check-updates")!.disabled, true);
  value.checkingUpdates = false;
  value.canUpdate = { app: false, addon: false };
  value.updates.app.state = value.updates.addon.state = "current";
  s.draw(value);
  assert.equal(s.elements.get("update-prompt")!.hidden, true);
  assert.equal(s.elements.get("check-updates")!.disabled, false);
});

test("a binder mismatch remains visible while manual sync is available to check a restored save", () => {
  const s = screen(), value = status();
  value.needsNewBinder = true;
  value.canUpdate = { app: false, addon: false };
  value.accounts[0]!.state = "This saved binder differs from the server record. Your cards have been kept.";
  s.draw(value);
  assert.equal(s.elements.get("new-binder")!.hidden, false);
  assert.equal(s.elements.get("repair-sync")!.hidden, false);
  assert.equal(s.elements.get("repair-sync")!.disabled, false);
  assert.equal(s.elements.get("sync-now")!.disabled, false);
  assert.equal(s.elements.get("sync-state")!.textContent, "Needs attention");
  value.needsNewBinder = false;
  value.accounts[0]!.state = "Your saved binder and Ranked supply are out of step. Your cards have been kept.";
  s.draw(value);
  assert.equal(s.elements.get("sync-state")!.textContent, "Needs attention");
});
