(function () {
  "use strict";

  var app = document.getElementById("app");
  var db = null;
  var email = "";
  var MATERIALS = ["SC Connector", "Changed Modem", "Rewiring", "Changed power adaptor", "other"];
  var STATUSES = ["Open", "Assigned", "In Progress", "Closed - Resolved"];

  function esc(value) {
    return String(value == null ? "" : value).replace(/[&<>"']/g, function (ch) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;" }[ch];
    });
  }

  function text(error) {
    if (!error) return "Something went wrong.";
    return error.message || String(error);
  }

  function show(html) {
    app.innerHTML = html;
  }

  function signIn() {
    db.auth.signInWithOAuth({
      provider: "google",
      options: { redirectTo: location.origin + "/tech/" }
    });
  }

  function load() {
    db.rpc("tech_my_work").then(function (result) {
      if (result.error) {
        show("<section class=\"panel\"><h1>Hindi pa tech account</h1><p>" + esc(text(result.error)) + "</p><p class=\"muted\">Ask an admin to add this Gmail under Staff with role tech. Admins can also open <a href=\"/admin/#ops\">Tickets</a>.</p><button type=\"button\" class=\"btn secondary\" id=\"out\">Sign out</button></section>");
        document.getElementById("out").onclick = function () { db.auth.signOut(); };
        return;
      }
      paint(result.data || {});
    });
  }

  function paint(data) {
    var duty = data.duty_status || "Off";
    var tickets = data.tickets || [];
    var cards = tickets.map(function (row) {
      var closed = row.status === "Closed - Resolved";
      return "<article class=\"panel\"><h2>" + esc(row.ticket_no) + "</h2>" +
        "<p class=\"muted\">" + esc(row.ticket_type) + " · " + esc(row.customer_name || "No name") + (row.account_number ? " · " + esc(row.account_number) : "") + "</p>" +
        "<p>" + esc(row.issue || "") + "</p>" +
        "<p>" + esc(row.address || "") + (row.area ? " · " + esc(row.area) : "") + (row.mobile ? "<br>" + esc(row.mobile) : "") + "</p>" +
        "<form class=\"grid\" data-status=\"" + row.id + "\">" +
        "<div class=\"field\"><label>Status</label><select>" + STATUSES.map(function (item) {
          return "<option" + (item === row.status ? " selected" : "") + ">" + esc(item) + "</option>";
        }).join("") + "</select></div>" +
        "<button class=\"btn\" type=\"submit\">Update status</button></form>" +
        "<p><strong>Materials</strong></p><ul>" + (row.materials || []).map(function (item) {
          return "<li>" + esc(item.item) + " × " + esc(item.qty) + "</li>";
        }).join("") + "</ul>" +
        (closed ? "" : "<form class=\"grid two\" data-material=\"" + row.id + "\"><div class=\"field\"><label>Item</label><select>" + MATERIALS.map(function (item) {
          return "<option>" + esc(item) + "</option>";
        }).join("") + "</select></div><div class=\"field\"><label>Qty</label><input type=\"number\" min=\"0.01\" step=\"0.01\" value=\"1\"></div><button class=\"btn\" type=\"submit\">Add material</button></form>") +
        "<p><strong>Notes</strong></p>" + (row.notes_log || []).map(function (item) {
          return "<p>" + esc(item.body) + "</p>";
        }).join("") +
        (closed ? "" : "<form data-note=\"" + row.id + "\"><div class=\"field\"><label>Note</label><textarea></textarea></div><button class=\"btn\" type=\"submit\">Add note</button></form>") +
        "<form data-photo=\"" + row.id + "\"><div class=\"field\"><label>Photo</label><input type=\"file\" accept=\"image/jpeg,image/png,image/webp\"></div><button class=\"btn secondary\" type=\"submit\">Upload photo</button></form>" +
        (row.photos || []).map(function (item) {
          return "<p><button type=\"button\" class=\"btn secondary\" data-view=\"" + esc(item.path) + "\">View photo</button></p>";
        }).join("") +
        (row.ticket_type === "INSTALLATION" && !closed
          ? "<form class=\"grid two\" data-done=\"" + row.id + "\"><h3>Installation tapos</h3>" +
            "<div class=\"field\"><label>LP</label><input data-k=\"lp\" value=\"" + esc(row.lp || "") + "\"></div>" +
            "<div class=\"field\"><label>NAP</label><input data-k=\"nap\" value=\"" + esc(row.nap || "") + "\"></div>" +
            "<div class=\"field\"><label>Port</label><input data-k=\"port\" value=\"" + esc(row.port || "") + "\"></div>" +
            "<div class=\"field\"><label>Modem serial</label><input data-k=\"serial\"></div>" +
            "<div class=\"field\"><label>Bayad</label><select data-k=\"method\"><option value=\"cash\">Cash</option><option value=\"gcash\">GCash</option></select></div>" +
            "<div class=\"field\"><label>Amount</label><input data-k=\"amount\" type=\"number\" min=\"0\" step=\"0.01\" placeholder=\"Installation fee\"></div>" +
            "<div class=\"field\"><label>GCash ref</label><input data-k=\"ref\"></div>" +
            "<button class=\"btn\" type=\"submit\">Mark installed</button></form>"
          : "") +
        (closed ? "<p class=\"muted\">Closed. " + esc(row.resolution || "") + "</p>" :
          "<form data-resolve=\"" + row.id + "\"><div class=\"field\"><label>Resolution</label><textarea></textarea></div><button class=\"btn\" type=\"submit\">Mark resolved</button></form>") +
        "</article>";
    }).join("");
    show("<section class=\"panel\"><h1>My tickets</h1><p>" + esc(email) + "</p>" +
      "<p class=\"muted\">Duty: " + esc(duty) + "</p>" +
      "<div class=\"actions\">" + ["Available", "On job", "Off"].map(function (item) {
        return "<button type=\"button\" class=\"btn" + (item === duty ? "" : " secondary") + "\" data-duty=\"" + item + "\">" + item + "</button>";
      }).join(" ") + " <button type=\"button\" class=\"btn secondary\" id=\"out\">Sign out</button></div></section>" +
      (cards || "<section class=\"panel\"><p>Walang assigned ticket.</p></section>"));
    document.getElementById("out").onclick = function () { db.auth.signOut(); };
    app.querySelectorAll("[data-duty]").forEach(function (button) {
      button.onclick = function () {
        db.rpc("tech_set_duty", { p_status: button.getAttribute("data-duty") }).then(function (result) {
          if (result.error) return show("<section class=\"panel\"><p>" + esc(text(result.error)) + "</p></section>");
          load();
        });
      };
    });
    app.querySelectorAll("[data-status]").forEach(function (form) {
      form.onsubmit = function (event) {
        event.preventDefault();
        db.rpc("tech_set_status", { p_ticket: form.getAttribute("data-status"), p_status: form.querySelector("select").value }).then(function (result) {
          if (result.error) return alert(text(result.error));
          load();
        });
      };
    });
    app.querySelectorAll("[data-material]").forEach(function (form) {
      form.onsubmit = function (event) {
        event.preventDefault();
        db.rpc("tech_add_material", {
          p_ticket: form.getAttribute("data-material"),
          p_item: form.querySelector("select").value,
          p_qty: Number(form.querySelector("input").value)
        }).then(function (result) {
          if (result.error) return alert(text(result.error));
          load();
        });
      };
    });
    app.querySelectorAll("[data-note]").forEach(function (form) {
      form.onsubmit = function (event) {
        event.preventDefault();
        db.rpc("tech_add_note", { p_ticket: form.getAttribute("data-note"), p_body: form.querySelector("textarea").value }).then(function (result) {
          if (result.error) return alert(text(result.error));
          load();
        });
      };
    });
    app.querySelectorAll("[data-photo]").forEach(function (form) {
      form.onsubmit = function (event) {
        event.preventDefault();
        var file = form.querySelector("input").files[0];
        var id = form.getAttribute("data-photo");
        if (!file) return;
        var path = "tickets/" + id + "/" + Date.now() + "-" + String(file.name || "photo.jpg").replace(/[^\w.]+/g, "-");
        db.storage.from("ticket-photos").upload(path, file, { contentType: file.type || "image/jpeg", upsert: false }).then(function (uploaded) {
          if (uploaded.error) throw uploaded.error;
          return db.from("ticket_photos").insert({ ticket_id: id, path: path, created_by: email });
        }).then(function (insert) {
          if (insert.error) throw insert.error;
          load();
        }).catch(function (error) { alert(text(error)); });
      };
    });
    app.querySelectorAll("[data-view]").forEach(function (button) {
      button.onclick = function () {
        db.storage.from("ticket-photos").createSignedUrl(button.getAttribute("data-view"), 3600).then(function (signed) {
          if (signed.error || !signed.data) return alert(text(signed.error));
          window.open(signed.data.signedUrl, "_blank", "noopener");
        });
      };
    });
    app.querySelectorAll("[data-done]").forEach(function (form) {
      form.onsubmit = function (event) {
        event.preventDefault();
        function val(key) { return form.querySelector("[data-k=\"" + key + "\"]").value; }
        var amount = val("amount");
        db.rpc("complete_installation", {
          p_ticket: form.getAttribute("data-done"),
          p_lp: val("lp").trim(),
          p_nap: val("nap").trim(),
          p_port: val("port").trim(),
          p_modem_serial: val("serial").trim(),
          p_pay_method: val("method"),
          p_pay_amount: amount === "" ? null : Number(amount),
          p_pay_ref: val("ref").trim()
        }).then(function (result) {
          if (result.error) return alert(text(result.error));
          alert("Installed. PPPoE " + ((result.data && result.data.pppoe) || ""));
          load();
        });
      };
    });
    app.querySelectorAll("[data-resolve]").forEach(function (form) {
      form.onsubmit = function (event) {
        event.preventDefault();
        db.rpc("resolve_ops_ticket", {
          p_ticket: form.getAttribute("data-resolve"),
          p_resolution: form.querySelector("textarea").value
        }).then(function (result) {
          if (result.error) return alert(text(result.error));
          load();
        });
      };
    });
  }

  var cfg = window.FIBERBRO_SUPABASE;
  if (!cfg || typeof cfg.isConfigured !== "function" || !cfg.isConfigured()) {
    show("<section class=\"panel\"><h1>Not configured</h1><p>admin/config.js is still a placeholder.</p></section>");
    return;
  }

  import("https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm").then(function (mod) {
    db = mod.createClient(cfg.url, cfg.anonKey, { auth: { detectSessionInUrl: true, persistSession: true } });
    db.auth.onAuthStateChange(function (event, session) {
      if (event === "SIGNED_OUT") {
        email = "";
        show("<section class=\"panel sign-panel\"><h1>FiberBro tech</h1><p>Sign in with the Gmail on the staff list.</p><button type=\"button\" class=\"btn\" id=\"in\">Sign in with Google</button></section>");
        document.getElementById("in").onclick = signIn;
      } else if (session && session.user) {
        email = session.user.email || "";
        load();
      }
    });
    return db.auth.getSession();
  }).then(function (result) {
    if (!result || result.error) {
      show("<section class=\"panel\"><h1>Could not reach Supabase</h1><p>" + esc(text(result && result.error)) + "</p></section>");
      return;
    }
    if (!result.data.session) {
      show("<section class=\"panel sign-panel\"><h1>FiberBro tech</h1><p>Sign in with the Gmail on the staff list.</p><button type=\"button\" class=\"btn\" id=\"in\">Sign in with Google</button></section>");
      document.getElementById("in").onclick = signIn;
      return;
    }
    email = result.data.session.user.email || "";
    load();
  }).catch(function (error) {
    show("<section class=\"panel\"><h1>Could not load</h1><p>" + esc(text(error)) + "</p></section>");
  });
})();
