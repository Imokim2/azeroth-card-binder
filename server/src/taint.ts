// Tracing cards that came from Casual play through more than one trade (roadmap D5: only Ranked counts).
//
// A copy received in a trade is not trusted when the player it came from has Casual drops, or (the new part) when that
// player is themselves holding copies of the same card they got from somewhere untrusted. That follows a card from a Casual
// account to a clean one to a third, however many steps it takes. It is deliberately cautious: the server does not know
// which of a player's copies they hand over, so if a player holds any untrusted copy of a card, every copy of that card
// they pass on is treated as untrusted. An honest player can lose a point to that, rarely; a cheater cannot launder
// a card by passing it through a clean account.
export type TradeHalf = {
  playerId: string;
  seq: number;
  key: string; // the card received
  state: "open" | "matched" | "unmatched";
  source: string | null; // the player who gave it, when the other half is known
};

const MAX_ROUNDS = 50;

// The received halves that are not trusted because of where the card came from. Halves that were never matched are not
// listed (they are excluded for that reason elsewhere), but they do make their owner's copies of the card untrusted.
export function computeTaint(halves: TradeHalf[], casualPlayers: string[]): { playerId: string; seq: number }[] {
  const casual = new Set(casualPlayers);
  const untrusted = new Set<string>(); // "player|card": the player holds an untrusted copy of this card
  for (const half of halves) if (half.state === "unmatched") untrusted.add(`${half.playerId}|${half.key}`);
  const tainted = new Map<string, { playerId: string; seq: number }>();
  for (let round = 0; round < MAX_ROUNDS; round++) {
    let changed = false;
    for (const half of halves) {
      const id = `${half.playerId}:${half.seq}`;
      if (tainted.has(id) || half.source === null || half.state === "unmatched") continue;
      if (casual.has(half.source) || untrusted.has(`${half.source}|${half.key}`)) {
        tainted.set(id, { playerId: half.playerId, seq: half.seq });
        untrusted.add(`${half.playerId}|${half.key}`);
        changed = true;
      }
    }
    if (!changed) break;
  }
  return [...tainted.values()];
}
