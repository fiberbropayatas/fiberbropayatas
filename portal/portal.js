(function () {
  "use strict";

  var TOKEN_KEY = "fiberbro_portal_token";
  var statusEl = document.getElementById("portal-status");
  var bodyEl = document.getElementById("portal-body");
  var logoutButton = document.getElementById("logout");
  var clientPromise = null;
  var token = window.localStorage ? localStorage.getItem(TOKEN_KEY) : "";
  var current = null;

  function esc(value) {
    return String(value == null ? "" : value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function peso(amount) {
    var num = Number(amount);
    if (isNaN(num)) return "";
    return "₱" + num.toLocaleString("en-PH", { maximumFractionDigits: 2 });
  }

  function showStatus(type, message) {
    statusEl.className = "form-status " + (type === "success" ? "is-success" : "is-error");
    statusEl.textContent = message;
    statusEl.hidden = false;
  }

  function clearStatus() {
    statusEl.hidden = true;
    statusEl.className = "form-status";
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

  function leave() {
    if (window.localStorage) localStorage.removeItem(TOKEN_KEY);
    location.replace("/login/");
  }

  function compressImage(file) {
    return new Promise(function (resolve, reject) {
      var url = URL.createObjectURL(file);
      var img = new Image();
      img.onload = function () {
        var scale = Math.min(1, 1600 / Math.max(img.width, img.height));
        var canvas = document.createElement("canvas");
        canvas.width = Math.max(1, Math.round(img.width * scale));
        canvas.height = Math.max(1, Math.round(img.height * scale));
        var ctx = canvas.getContext("2d");
        ctx.fillStyle = "#fff";
        ctx.fillRect(0, 0, canvas.width, canvas.height);
        ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
        URL.revokeObjectURL(url);
        canvas.toBlob(function (blob) {
          if (!blob) reject(new Error("Hindi ma-compress ang larawan."));
          else resolve(blob);
        }, "image/jpeg", 0.8);
      };
      img.onerror = function () {
        URL.revokeObjectURL(url);
        reject(new Error("Hindi mabasa ang larawan. Pumili ng JPG o PNG."));
      };
      img.src = url;
    });
  }

  function proofPath() {
    var alphabet = "abcdefghijklmnopqrstuvwxyz0123456789";
    var rand = "";
    var bytes = new Uint8Array(12);
    if (window.crypto && window.crypto.getRandomValues) window.crypto.getRandomValues(bytes);
    for (var i = 0; i < bytes.length; i++) rand += alphabet.charAt(bytes[i] % alphabet.length);
    return "proofs/" + rand + ".jpg";
  }

  function openBills(invoices) {
    return (invoices || []).filter(function (bill) {
      return bill.status === "unpaid" || bill.status === "pending";
    });
  }

  function render(data, settings) {
    var account = data.account || {};
    var invoices = data.invoices || [];
    var payments = data.payments || [];
    var tickets = data.tickets || [];
    var bills = openBills(invoices);
    var qrUrl = (settings.gcash_qr_url || "").trim();
    var gcashBody = qrUrl
      ? "<img src=\"" + esc(qrUrl) + "\" alt=\"GCash QR\">"
      : "<p>Number: " + esc(settings.gcash_number || "Hindi pa naka-set") + "<br>Name: " + esc(settings.gcash_name || "") + "</p>";
    var payForm = "";
    if (!bills.length) {
      payForm = "<p>Wala kang balanse ngayon.</p>";
    } else {
      var list = bills.map(function (bill, index) {
        return "<button type=\"button\" class=\"bill-choice" + (index === 0 ? " is-selected" : "") + "\" data-id=\"" + esc(bill.id) + "\">" +
          "<span><strong>" + esc(bill.period) + "</strong><br><span class=\"pay-note\">Due " + esc(bill.due_date || "—") + " · " + esc(bill.status) + "</span></span>" +
          "<strong>" + esc(peso(bill.amount)) + "</strong></button>";
      }).join("");
      payForm = "<div class=\"bill-list\">" + list + "</div>" +
        "<div class=\"gcash-box\"><strong>GCash</strong>" + gcashBody +
        (settings.payment_note ? "<p class=\"pay-note\">" + esc(settings.payment_note) + "</p>" : "") +
        "</div>" +
        "<form id=\"pay-form\" class=\"form-grid\">" +
        "<div class=\"field\"><label for=\"amount\">Amount</label><input id=\"amount\" type=\"number\" min=\"0.01\" step=\"0.01\" required value=\"" + esc(bills[0].amount) + "\"></div>" +
        "<div class=\"field\"><label for=\"reference\">Reference number</label><input id=\"reference\" required placeholder=\"GCash reference\"></div>" +
        "<div class=\"field\"><label for=\"payer\">Pangalan ng nagbayad <span class=\"hint\">(opsyonal)</span></label><input id=\"payer\"></div>" +
        "<div class=\"field\"><label for=\"proof\">Screenshot ng resibo <span class=\"hint\">(opsyonal, JPG/PNG)</span></label><input id=\"proof\" type=\"file\" accept=\"image/jpeg,image/png,image/webp\"></div>" +
        "<button class=\"btn btn-primary\" type=\"submit\">Ipadala ang bayad</button></form>";
      current = { invoiceId: bills[0].id, bills: bills };
    }
    var invoiceRows = invoices.map(function (bill) {
      return "<li>" + esc(bill.period) + " · " + esc(peso(bill.amount)) + " · " + esc(bill.status) + "</li>";
    }).join("") || "<li>Wala pang bill.</li>";
    var paymentRows = payments.map(function (pay) {
      return "<li>" + esc(peso(pay.amount)) + " · " + esc(pay.method) + " · " + esc(pay.status) + " · " + esc(pay.reference_no || "") + "</li>";
    }).join("") || "<li>Wala pang payment.</li>";
    var ticketRows = tickets.map(function (ticket) {
      return "<li><strong>" + esc(ticket.title) + "</strong> · " + esc(ticket.status) + "<br>" + esc(ticket.description || "") + "</li>";
    }).join("") || "<li>Wala pang repair request.</li>";
    bodyEl.innerHTML =
      "<section class=\"portal-block\"><h2>Account</h2>" +
      "<p><strong>" + esc(account.name || "Customer") + "</strong><br>Account " + esc(account.account_number || "—") +
      (account.plan ? "<br>" + esc(account.plan) : "") +
      (account.address ? "<br>" + esc(account.address) : "") +
      (account.area ? " · " + esc(account.area) : "") +
      (account.mobile ? "<br>" + esc(account.mobile) : "") + "</p></section>" +
      "<section class=\"portal-block\"><h2>Bills</h2><ul>" + invoiceRows + "</ul></section>" +
      "<section class=\"portal-block\"><h2>Magbayad</h2>" + payForm + "</section>" +
      "<section class=\"portal-block\"><h2>Payments</h2><ul>" + paymentRows + "</ul></section>" +
      "<section class=\"portal-block\"><h2>Technical inquiry</h2>" +
      "<p class=\"pay-note\">Ipapakita ito sa FiberBro repairs.</p>" +
      "<form id=\"ticket-form\" class=\"form-grid\">" +
      "<div class=\"field\"><label for=\"category\">Uri ng problema</label><select id=\"category\" required>" +
      "<option value=\"\">Pumili</option><option>Walang internet</option><option>Mabagal ang connection</option><option>Modem</option><option>Iba pa</option>" +
      "</select></div>" +
      "<div class=\"field\"><label for=\"description\">Detalye</label><textarea id=\"description\" required></textarea></div>" +
      "<button class=\"btn btn-primary\" type=\"submit\">Ipadala</button></form>" +
      "<ul>" + ticketRows + "</ul></section>";
    wirePay();
    document.getElementById("ticket-form").onsubmit = submitTicket;
  }

  function wirePay() {
    var form = document.getElementById("pay-form");
    if (!form || !current) return;
    bodyEl.querySelectorAll(".bill-choice").forEach(function (button) {
      button.onclick = function () {
        bodyEl.querySelectorAll(".bill-choice").forEach(function (el) { el.classList.remove("is-selected"); });
        button.classList.add("is-selected");
        current.invoiceId = button.getAttribute("data-id");
        var bill = current.bills.filter(function (item) { return item.id === current.invoiceId; })[0];
        if (bill) document.getElementById("amount").value = bill.amount;
      };
    });
    form.onsubmit = submitPayment;
  }

  function submitPayment(event) {
    event.preventDefault();
    clearStatus();
    var amount = Number(document.getElementById("amount").value);
    var reference = document.getElementById("reference").value.trim();
    var payer = document.getElementById("payer").value.trim();
    var file = document.getElementById("proof").files[0];
    var button = document.querySelector("#pay-form button");
    if (!reference) return showStatus("error", "Kailangan ang reference number.");
    button.disabled = true;
    button.textContent = "Ipinapadala…";
    getClient().then(function (client) {
      if (!client) throw new Error("Hindi makakonekta ngayon. Subukan muli.");
      var proofPromise = Promise.resolve(null);
      if (file) {
        if (file.size > 10 * 1024 * 1024) throw new Error("Masyadong malaki ang larawan. Pumili ng mas maliit.");
        proofPromise = compressImage(file).then(function (blob) {
          if (blob.size > 5 * 1024 * 1024) throw new Error("Masyadong malaki ang larawan pagkatapos i-compress. Max 5 MB.");
          var path = proofPath();
          return client.storage.from("payment-proofs").upload(path, blob, { contentType: "image/jpeg", upsert: false })
            .then(function (upload) {
              if (upload.error) throw new Error(upload.error.message || "Hindi na-upload ang screenshot.");
              return path;
            });
        });
      }
      return proofPromise.then(function (path) {
        return client.rpc("portal_submit_payment", {
          token: token,
          p_invoice: current.invoiceId,
          p_amount: amount,
          p_method: "gcash",
          p_reference: reference,
          p_payer: payer,
          p_proof: path
        });
      });
    }).then(function (result) {
      if (result.error) throw new Error(result.error.message || "Hindi naipadala ang bayad.");
      if (!result.data || result.data.ok !== true) throw new Error("Hindi naipadala ang bayad.");
      showStatus("success", "Salamat! Natanggap na namin ang iyong bayad. Hintayin ang confirmation.");
      load();
    }).catch(function (err) {
      if (err.message && err.message.indexOf("login expired") !== -1) return leave();
      showStatus("error", err.message || "May problema. Subukan muli.");
      if (button) {
        button.disabled = false;
        button.textContent = "Ipadala ang bayad";
      }
    });
  }

  function submitTicket(event) {
    event.preventDefault();
    clearStatus();
    var button = document.querySelector("#ticket-form button");
    button.disabled = true;
    button.textContent = "Ipinapadala…";
    getClient().then(function (client) {
      if (!client) throw new Error("Hindi makakonekta ngayon. Subukan muli.");
      return client.rpc("portal_submit_ticket", {
        token: token,
        category: document.getElementById("category").value,
        description: document.getElementById("description").value.trim()
      });
    }).then(function (result) {
      if (result.error) throw new Error(result.error.message || "Hindi naipadala ang inquiry.");
      if (!result.data || result.data.ok !== true) throw new Error("Hindi naipadala ang inquiry.");
      showStatus("success", "Naipadala na ang inquiry. Titingnan ito ng FiberBro.");
      load();
    }).catch(function (err) {
      if (err.message && err.message.indexOf("login expired") !== -1) return leave();
      showStatus("error", err.message || "May problema. Subukan muli.");
      button.disabled = false;
      button.textContent = "Ipadala";
    });
  }

  function load() {
    getClient().then(function (client) {
      if (!client) throw new Error("Hindi pa naka-connect ang portal.");
      return Promise.all([
        client.rpc("portal_me", { token: token }),
        client.from("app_settings").select("key, value").in("key", ["gcash_number", "gcash_name", "gcash_qr_url", "payment_note"])
      ]);
    }).then(function (parts) {
      var me = parts[0];
      if (me.error || !me.data || !me.data.account) return leave();
      var settings = {};
      (parts[1].data || []).forEach(function (row) { settings[row.key] = row.value; });
      render(me.data, settings);
    }).catch(function () { leave(); });
  }

  if (!token) {
    leave();
    return;
  }

  logoutButton.onclick = function () {
    logoutButton.disabled = true;
    getClient().then(function (client) {
      if (!client) return null;
      return client.rpc("portal_logout", { token: token });
    }).catch(function () { return null; }).then(function () { leave(); });
  };

  load();
})();
