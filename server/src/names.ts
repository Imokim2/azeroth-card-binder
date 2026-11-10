// Character names in the form the add-on uses between players ("name-realmname", lower case, no spaces, apostrophes
// or dashes in the realm), so a trade partner, a ledger event and a stored character can be compared.
export function peerName(character: string, realm?: string): string {
  let name = character;
  let server = realm;
  if (server === undefined) {
    const at = character.indexOf("-");
    name = at < 0 ? character : character.slice(0, at);
    server = at < 0 ? "" : character.slice(at + 1);
  }
  return `${name.toLowerCase()}-${server.replace(/[\s'-]/g, "").toLowerCase()}`;
}
