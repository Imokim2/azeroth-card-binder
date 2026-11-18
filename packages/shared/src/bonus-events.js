"use strict";
// Official schedules are immutable. Client clocks/labels never choose the multiplier or eligible sets.
function definition(input, catalog) {
    if (!input || typeof input !== "object" || Array.isArray(input)) throw new Error("invalid bonus event");
    const { id, title, startsAt, endsAt, effect, percent, sets } = input;
    if (typeof id !== "string" || !/^[a-z0-9][a-z0-9-]{0,31}$/.test(id)) throw new Error("invalid event id");
    if (typeof title !== "string" || !title.trim() || new TextEncoder().encode(title).length > 60 || /[|\x00-\x1f\x7f]/.test(title)) throw new Error("invalid event title");
    if (!Number.isSafeInteger(startsAt) || startsAt < 1 || !Number.isSafeInteger(endsAt) || endsAt > 4102444800 || endsAt - startsAt < 300 || endsAt - startsAt > 86400) throw new Error("event must last 5 minutes to 24 hours");
    if (effect !== "card-drops" || !Number.isInteger(percent) || percent < 101 || percent > 500) throw new Error("choose a card-drop multiplier from 1.01x to 5x");
    if (!Array.isArray(sets) || sets.length > 30 || sets.some(code => typeof code !== "string" || !/^[a-zA-Z0-9_-]{1,20}$/.test(code)) || new Set(sets).size !== sets.length) throw new Error("invalid event sets");
    if (catalog && sets.some(code => !catalog.sets.some(set => set.code === code))) throw new Error("unknown event set");
    return { id, title: title.trim(), startsAt, endsAt, effect, percent, sets: [...sets].sort() };
}
const isBonus = event => (event.kind === "drop" || event.kind === "miss") && (event.partner === "bonus" || event.partner === "camp-bonus");
function reference(event) {
    if (!isBonus(event)) return null;
    const fields = typeof event.trade === "string" && /^([a-z0-9][a-z0-9-]{0,31}):(\d{1,10}):(\d{1,10})$/.exec(event.trade);
    return fields ? { id: fields[1], first: Number(fields[2]), last: Number(fields[3]) } : null;
}
function forEvent(event, catalog, schedules, previousTime = 0, serverNow = Infinity) {
    const ref = reference(event);
    if (!ref || !["drop", "miss"].includes(event.kind) || event.tape < 1 || ref.first < previousTime || ref.first > ref.last || ref.last > event.t || ref.last > serverNow) return null;
    if (event.kind === "drop" && (ref.first !== ref.last || event.t - ref.last > 2)) return null;
    const schedule = schedules?.[ref.id];
    const raw = catalog.cards[event.key], card = raw && catalog.cards[raw.baseKey || event.key];
    if (!schedule || !card || ref.first < schedule.startsAt || ref.last >= schedule.endsAt || (schedule.sets.length && !schedule.sets.includes(card.set))) return null;
    return schedule;
}
function eventIDs(events) { return [...new Set(events.filter(isBonus).map(reference).filter(Boolean).map(ref => ref.id))]; }
module.exports = { definition, isBonus, reference, forEvent, eventIDs };
