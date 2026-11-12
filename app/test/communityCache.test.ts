import assert from "node:assert/strict";
import test from "node:test";
import { cachedStandings } from "../src/communityCache.ts";
import { syncFileText } from "../src/syncFile.ts";

test("last-known leaderboard display survives a restart without restoring wanted or executable content", () => {
  const standings = { leaderboard: [{rank:1,name:"Alice-Realm",score:100,cards:4,sets:0}], firsts: [], verified: ["alice-realm"], you: {rank:1,score:100,cards:4,sets:0} };
  const text = syncFileText({syncedAt:123,acks:[],...standings,wanted:[{name:"Old list",characters:[],cards:["npc:589"]}]});
  assert.deepEqual(cachedStandings(text),standings);
  assert.equal(cachedStandings(text + '\nos.execute("something")'),undefined);
  assert.equal(cachedStandings(text.replace("score = 100", 'score = "bad"')),undefined);
  assert.equal(cachedStandings("not a sync file"),undefined);
});

test("an empty leaderboard is valid cached display data", () => {
  const standings={leaderboard:[],firsts:[],verified:[],you:null};
  assert.deepEqual(cachedStandings(syncFileText({syncedAt:123,acks:[],...standings})),standings);
});
