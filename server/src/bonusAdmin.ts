// Inserted into the existing authenticated admin panel; token handling and CSP stay there.
export const BONUS_ADMIN_HTML = `<section id="view-bonuses" hidden>
<h2>Bonus events</h2><p class="meta">Choose when a bonus starts and how long it lasts. Players load the schedule at login or /reload; it then starts and ends automatically. Published times and rules are fixed.</p>
<form id="bonus-form" class="card">
<p><label>Name <input id="bonus-title" required maxlength="48" value="Collector's Hour"></label></p>
<p><label>Starts (your local time) <input id="bonus-start" type="datetime-local" required></label></p>
<p><label>Minutes <input id="bonus-duration" type="number" min="5" max="1440" step="1" value="60" required></label>
<label>Card drops <select id="bonus-percent"><option value="150">1.5x</option><option value="200" selected>2x</option><option value="300">3x</option><option value="500">5x</option></select></label></p>
<p><label><input id="bonus-all" type="checkbox" checked> All collections</label></p>
<div id="bonus-sets" hidden style="max-height:180px;overflow:auto"></div>
<p class="meta">The strongest eligible event applies to each card. Campfire bonuses also apply. Packs and their contents keep their normal rules.</p>
<button type="submit" id="bonus-publish">Schedule event</button></form>
<button type="button" id="bonus-refresh">Refresh events</button><div id="bonus-list"></div></section>`;
export const BONUS_ADMIN_SCRIPT = `
  async function loadBonuses() {
    try {
      var reply = await api("/v1/admin/bonus-events");
      var sets = $("bonus-sets");
      if (!sets.children.length) reply.sets.forEach(function (set) {
        var label = el("label"), box = el("input"); box.type = "checkbox"; box.value = set.code;
        label.appendChild(box); label.appendChild(document.createTextNode(" " + set.title));
        var row = el("p", "meta"); row.appendChild(label); sets.appendChild(row);
      });
      var list = $("bonus-list"); list.replaceChildren();
      if (!reply.events.length) list.appendChild(el("p", "empty", "No events scheduled."));
      reply.events.forEach(function (event) {
        var card = el("article", "card"); card.appendChild(el("h2", "", event.title));
        line(card, "Time", when(event.startsAt) + " to " + when(event.endsAt));
        line(card, "Card drops", event.percent / 100 + "x");
        line(card, "Collections", event.sets.length ? event.sets.map(function (code) { var set = reply.sets.find(function (s) { return s.code === code; }); return set ? set.title : code; }).join(", ") : "All collections");
        list.appendChild(card);
      });
      if (!$("bonus-start").value) {
        var next = new Date(Math.ceil((Date.now() + 300000) / 3600000) * 3600000);
        $("bonus-start").value = new Date(next.getTime() - next.getTimezoneOffset() * 60000).toISOString().slice(0, 16);
      }
    } catch (e) { say(e.message, "bad"); }
  }
  $("bonus-all").addEventListener("change", function () { $("bonus-sets").hidden = this.checked; });
  $("bonus-refresh").addEventListener("click", loadBonuses);
  $("bonus-form").addEventListener("submit", async function (event) {
    event.preventDefault();
    var start = Math.floor(new Date($("bonus-start").value).getTime() / 1000);
    var duration = Number($("bonus-duration").value), percent = Number($("bonus-percent").value);
    var selected = $("bonus-all").checked ? [] : Array.from($("bonus-sets").querySelectorAll("input:checked")).map(function (box) { return box.value; });
    if (!Number.isSafeInteger(start) || start <= Date.now() / 1000 || !Number.isInteger(duration) || duration < 5 || duration > 1440 || (!$("bonus-all").checked && !selected.length)) { say("Choose a future start, a length from 5 to 1440 minutes, and at least one collection.", "bad"); return; }
    var title = $("bonus-title").value.trim();
    if (!window.confirm("Schedule " + title + " for " + new Date(start * 1000).toLocaleString() + ", lasting " + duration + " minutes at " + percent / 100 + "x card drops? These rules cannot be changed after publishing.")) return;
    $("bonus-publish").disabled = true;
    try {
      await api("/v1/admin/bonus-events", { method: "POST", body: JSON.stringify({ id: "bonus-" + Date.now().toString(36), title: title, startsAt: start, endsAt: start + duration * 60, effect: "card-drops", percent: percent, sets: selected }) });
      say("Event scheduled. Remind players to sync and load the schedule before it starts.", "good"); await loadBonuses();
    } catch (e) { say(e.message, "bad"); } finally { $("bonus-publish").disabled = false; }
  });
`;
