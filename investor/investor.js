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

  function show(data) {
    var cards = (data.accounts || []).map(function (row) {
      var statuses = Object.keys(row.by_status || {}).map(function (key) {
        return esc(key) + " " + esc(row.by_status[key]);
      }).join(", ");
      return "<article class=\"panel\"><h2>" + esc(row.code) + "</h2>" +
        "<p class=\"muted\">" + esc(row.label || "") + "</p>" +
        "<p>Customers: " + esc(row.customers) + (statuses ? " · " + statuses : "") + "</p>" +
        "<p>Collections " + esc(money(row.collections)) + " · Operational " + esc(money(row.operational)) + "</p>" +
        "<p>Gross " + esc(money(row.gross)) + " · Amount left " + esc(money(row.amount_left)) + "</p>" +
        "<p>Your share " + esc(row.my_percent == null ? "—" : row.my_percent + "%") + " · " + esc(money(row.my_share)) + "</p>" +
        "<p class=\"muted\">Personal expenses already taken off: " + esc(money(row.my_personal)) + "</p></article>";
    }).join("");
    app.innerHTML = "<section class=\"panel\"><h1>" + esc(data.party || "Investor") + "</h1>" +
      "<p class=\"muted\">Only the accounts where this party has a split. MAL and AL are not included.</p>" +
      "<button type=\"button\" class=\"btn secondary\" id=\"out\">Sign out</button></section>" +
      (cards || "<section class=\"panel\"><p>No accounts for this party yet. An admin builds the cut-off report first.</p></section>");
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
