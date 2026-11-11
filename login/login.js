(function () {
  "use strict";

  var TOKEN_KEY = "fiberbro_portal_token";
  var form = document.getElementById("login-form");
  var statusEl = document.getElementById("login-status");
  var accountInput = document.getElementById("account");
  var pinInput = document.getElementById("pin");
  var toggle = document.getElementById("pin-toggle");
  var button = document.getElementById("login-button");
  var clientPromise = null;

  if (window.localStorage && localStorage.getItem(TOKEN_KEY)) {
    location.replace("/portal/");
    return;
  }

  function showStatus(type, message) {
    statusEl.className = "form-status " + (type === "success" ? "is-success" : "is-error");
    statusEl.textContent = message;
    statusEl.hidden = false;
  }

  function getClient() {
    if (clientPromise) return clientPromise;
    var cfg = window.FIBERBRO_SUPABASE;
    if (!cfg || typeof cfg.isConfigured !== "function" || !cfg.isConfigured()) {
      clientPromise = Promise.resolve(null);
      return clientPromise;
    }
    clientPromise = import("https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm").then(function (mod) {
      return mod.createClient(cfg.url, cfg.anonKey, {
        auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false }
      });
    });
    return clientPromise;
  }

  toggle.addEventListener("click", function () {
    var showing = pinInput.type === "text";
    pinInput.type = showing ? "password" : "text";
    toggle.textContent = showing ? "Show" : "Hide";
    toggle.setAttribute("aria-pressed", showing ? "false" : "true");
    toggle.setAttribute("aria-label", showing ? "Show PIN" : "Hide PIN");
    pinInput.focus();
  });

  form.addEventListener("submit", function (event) {
    event.preventDefault();
    statusEl.hidden = true;
    statusEl.className = "form-status";
    var account = accountInput.value.trim();
    var pin = pinInput.value.trim();
    if (!account || !pin) {
      showStatus("error", "Kailangan ang account number at PIN.");
      return;
    }
    if (!/^[0-9]{4,8}$/.test(pin)) {
      showStatus("error", "Ang PIN ay numero lang, 4 hanggang 8 digits.");
      return;
    }
    button.disabled = true;
    button.textContent = "Nagla-login…";
    getClient().then(function (client) {
      if (!client) throw new Error("Hindi pa naka-connect ang login page.");
      return client.rpc("portal_login", { account: account, pin: pin });
    }).then(function (result) {
      if (result.error) {
        var message = result.error.message || "";
        if (message.indexOf("Hindi magawang mag-login") === -1) {
          message = "Hindi magawang mag-login. Pakitingnan ang account number at PIN.";
        }
        throw new Error(message);
      }
      var body = result.data;
      if (!body || body.ok !== true || !body.token) {
        throw new Error("Hindi magawang mag-login. Pakitingnan ang account number at PIN.");
      }
      localStorage.setItem(TOKEN_KEY, body.token);
      location.assign("/portal/");
    }).catch(function (err) {
      showStatus("error", err.message || "Hindi makakonekta ngayon. Subukan muli.");
      button.disabled = false;
      button.textContent = "Log in";
    });
  });
})();
