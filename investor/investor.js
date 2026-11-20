(function () {
  "use strict";

  var app = document.getElementById("app");
  var db = null;

  function esc(value) {
    return String(value == null ? "" : value).replace(/[&<>"']/g, function (ch) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;" }[ch];
    });
  }

  function text(error) {
    return (error && error.message) || String(error || "Something went wrong.");
  }

  function money(value) {
    var num = Number(value || 0);
    return "₱" + num.toLocaleString("en-PH", { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  }

  function linesHtml(lines) {
    return (lines || []).map(function (row) {
      var shares = (row.shares || []).map(function (item) {
        return esc(item.party) + " " + esc(item.percent) + "% · " + esc(money(item.share));
      }).join("<br>");
      return "<p><strong>" + esc(row.code) + "</strong> · gross " + esc(money(row.gross)) + " · left " + esc(money(row.amount_left)) + "<br>" + shares + "</p>";
    }).join("") || "<p>No lines in this report.</p>";
  }

  function show(data) {
    var parties = data.parties || [];
    var cards = (data.accounts || []).map(function (row) {
      var statuses = Object.keys(row.by_status || {}).map(function (key) {
        return esc(key) + " " + esc(row.by_status[key]);
      }).join(", ");
      return "<article class=\"panel\"><h2>" + esc(row.code) + "</h2><p class=\"muted\">" + esc(row.label || "") + "</p><p>Customers: " + esc(row.customers) + (statuses ? " · " + statuses : "") + "</p></article>";
    }).join("");
    var draft = data.draft;
    var locked = data.locked || [];
    app.innerHTML = "<section class=\"panel\"><h1>" + esc(parties.join(", ") || "Investor") + "</h1>" +
      "<p class=\"muted\">Only the accounts where your parties have a split.</p>" +
      "<button type=\"button\" class=\"btn secondary\" id=\"out\">Sign out</button></section>" +
      (cards || "<section class=\"panel\"><p>No accounts for these parties.</p></section>") +
      "<section class=\"panel\"><h2>Draft</h2>" + (draft ? "<p>" + esc(draft.label) + " · " + esc(draft.cutoff_start) + " to " + esc(draft.cutoff_end) + "</p>" + linesHtml(draft.lines) : "<p>No draft.</p>") + "</section>" +
      "<section class=\"panel\"><h2>Locked</h2>" + (locked.length ? locked.map(function (row) {
        return "<h3>" + esc(row.cutoff_start) + " to " + esc(row.cutoff_end) + "</h3>" + linesHtml(row.lines);
      }).join("") : "<p>No locked report.</p>") + "</section>";
    document.getElementById("out").onclick = function () { db.auth.signOut(); };
  }

  function load() {
    db.rpc("investor_portal").then(function (result) {
      if (result.error) {
        app.innerHTML = "<section class=\"panel\"><h1>Not an investor login</h1><p>" + esc(text(result.error)) + "</p><p class=\"muted\">An admin adds the Gmail under staff with role investor and the party name, for example ALVIN or AINA.</p><button type=\"button\" class=\"btn secondary\" id=\"out\">Sign out</button></section>";
        document.getElementById("out").onclick = function () { db.auth.signOut(); };
        return;
      }
      show(result.data || {});
    });
  }

  function signIn() {
    db.auth.signInWithOAuth({
      provider: "google",
      options: { redirectTo: location.origin + "/investor/" }
    });
  }

  var cfg = window.FIBERBRO_SUPABASE;
  if (!cfg || typeof cfg.isConfigured !== "function" || !cfg.isConfigured()) {
    app.innerHTML = "<section class=\"panel\"><h1>Not configured</h1></section>";
    return;
  }
  import("https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm").then(function (mod) {
    db = mod.createClient(cfg.url, cfg.anonKey, { auth: { detectSessionInUrl: true, persistSession: true } });
    db.auth.onAuthStateChange(function (event, session) {
      if (event === "SIGNED_OUT") {
        app.innerHTML = "<section class=\"panel\"><h1>FiberBro investor</h1><p>Sign in with the Gmail linked to your party.</p><button type=\"button\" class=\"btn\" id=\"in\">Sign in with Google</button></section>";
        document.getElementById("in").onclick = signIn;
      } else if (session && session.user) load();
    });
    return db.auth.getSession();
  }).then(function (result) {
    if (!result || !result.data || !result.data.session) {
      app.innerHTML = "<section class=\"panel\"><h1>FiberBro investor</h1><p>Sign in with the Gmail linked to your party.</p><button type=\"button\" class=\"btn\" id=\"in\">Sign in with Google</button></section>";
      var button = document.getElementById("in");
      if (button) button.onclick = signIn;
    }
  }).catch(function (error) {
    app.innerHTML = "<section class=\"panel\"><h1>Could not load</h1><p>" + esc(text(error)) + "</p></section>";
  });
})();
