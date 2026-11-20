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
        "<div class=\"field\"><label for=\"pay-method\">Paraan</label><select id=\"pay-method\"><option value=\"gcash\">GCash</option><option value=\"bank\">Bank</option></select></div>" +
        "<div class=\"field\"><label for=\"amount\">Amount</label><input id=\"amount\" type=\"number\" min=\"0.01\" step=\"0.01\" required value=\"" + esc(bills[0].amount) + "\"></div>" +
        "<div class=\"field\"><label for=\"reference\">Reference number</label><input id=\"reference\" required placeholder=\"GCash o bank reference\"></div>" +
        "<div class=\"field\"><label for=\"payer\">Pangalan ng nagbayad <span class=\"hint\">(opsyonal)</span></label><input id=\"payer\"></div>" +
        "<div class=\"field\"><label for=\"proof\">Screenshot ng resibo <span class=\"hint\">(JPG/PNG/WebP, max 2 MB)</span></label><input id=\"proof\" type=\"file\" accept=\"image/jpeg,image/png,image/webp\"></div>" +
        "<button class=\"btn btn-primary\" type=\"submit\">Ipadala ang bayad</button></form>";
      current = { invoiceId: bills[0].id, bills: bills };
    }
    var invoiceRows = invoices.map(function (bill) {
      return "<li>" + esc(bill.period) + " · " + esc(peso(bill.amount)) + " · " + esc(bill.status) + "</li>";
    }).join("") || "<li>Wala pang bill.</li>";
    function payLabel(status) {
      if (status === "pending") return "Pending";
      if (status === "confirmed") return "Confirmed";
      if (status === "rejected") return "Rejected";
      return status || "";
    }
    var paymentRows = payments.map(function (pay) {
      return "<li>" + esc(peso(pay.amount)) + " · " + esc(pay.method) + " · " + esc(payLabel(pay.status)) + " · " + esc(pay.reference_no || "") +
        (pay.reject_reason ? "<br><span class=\"pay-note\">" + esc(pay.reject_reason) + "</span>" : "") + "</li>";
    }).join("") || "<li>Wala pang payment.</li>";
    var history = ledger(invoices, payments);
    var historyRows = history.events.map(function (event) {
      return "<li>" + esc(event.kind) + " " + esc(event.label) + " · " + esc(peso(event.charge || event.credit)) + " · balance " + esc(peso(event.balance)) + "</li>";
    }).join("") || "<li>Wala pang transaction.</li>";
    var receipts = data.receipts || [];
    var receiptRows = receipts.map(function (row) {
      return "<li>" + esc(row.date || "") + " · " + esc(row.reference || "") + " · " + esc(peso(row.amount)) +
        " · " + esc(row.cutoff || "") + " <button type=\"button\" class=\"btn btn-secondary\" data-receipt=\"" + esc(row.id) + "\">Download receipt</button></li>";
    }).join("") || "<li>Wala pang acknowledgement receipt.</li>";
    var soaRows = invoices.filter(function (bill) {
      if (!bill.due_date || (bill.status !== "unpaid" && bill.status !== "pending")) return false;
      var due = new Date(String(bill.due_date).slice(0, 10) + "T00:00:00");
      var start = new Date();
      start.setHours(0, 0, 0, 0);
      var end = new Date(start.getTime());
      end.setDate(end.getDate() + 10);
      return due >= start && due <= end;
    }).map(function (bill) {
      return "<li>" + esc(bill.period_label || bill.period) + " · " + esc(bill.bill_number || "") +
        " <button type=\"button\" class=\"btn btn-secondary\" data-soa=\"" + esc(bill.id) + "\">Download SOA</button></li>";
    }).join("");
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
      "<section class=\"portal-block\"><h2>Bills</h2><ul>" + invoiceRows + "</ul>" +
      (soaRows ? "<h3>SOA ready</h3><ul>" + soaRows + "</ul>" : "") + "</section>" +
      "<section class=\"portal-block\"><h2>Receipts</h2><ul>" + receiptRows + "</ul></section>" +
      "<section class=\"portal-block\"><h2>Magbayad</h2>" + payForm + "</section>" +
      "<section class=\"portal-block\"><h2>Payments</h2><ul>" + paymentRows + "</ul></section>" +
      "<section class=\"portal-block\"><h2>Transaction history</h2><p class=\"pay-note\">Wallet credit: " + esc(peso(history.credit)) + "</p><ul>" + historyRows + "</ul></section>" +
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
    bodyEl.querySelectorAll("[data-receipt]").forEach(function (button) {
      button.onclick = function () { downloadPortalReceipt(button.getAttribute("data-receipt")); };
    });
    bodyEl.querySelectorAll("[data-soa]").forEach(function (button) {
      button.onclick = function () { downloadPortalSoa(button.getAttribute("data-soa"), data); };
    });
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

  function ledger(invoices, payments) {
    var events = [];
    (invoices || []).forEach(function (inv) {
      if (inv.status === "void") return;
      events.push({ at: inv.created_at || inv.due_date || inv.period || "", kind: "Bill", label: inv.period || "", charge: Number(inv.amount) || 0, credit: 0 });
    });
    (payments || []).forEach(function (pay) {
      events.push({
        at: pay.confirmed_at || pay.submitted_at || "",
        kind: "Payment",
        label: pay.reference_no || pay.method || "",
        charge: 0,
        credit: pay.status === "confirmed" ? (Number(pay.amount) || 0) : 0
      });
    });
    events.sort(function (a, b) { return String(a.at).localeCompare(String(b.at)); });
    var running = 0;
    events.forEach(function (event) {
      running += event.charge - event.credit;
      event.balance = running;
    });
    return { events: events, credit: events.length ? Math.max(0, -events[events.length - 1].balance) : 0 };
  }

  function blobToBase64(blob) {
    return new Promise(function (resolve, reject) {
      var reader = new FileReader();
      reader.onload = function () {
        var text = String(reader.result || "");
        var comma = text.indexOf(",");
        resolve(comma >= 0 ? text.slice(comma + 1) : text);
      };
      reader.onerror = function () { reject(new Error("Hindi mabasa ang larawan.")); };
      reader.readAsDataURL(blob);
    });
  }

  function submitPayment(event) {
    event.preventDefault();
    clearStatus();
    var amount = Number(document.getElementById("amount").value);
    var reference = document.getElementById("reference").value.trim();
    var payer = document.getElementById("payer").value.trim();
    var method = document.getElementById("pay-method").value;
    var file = document.getElementById("proof").files[0];
    var button = document.querySelector("#pay-form button");
    if (!reference) return showStatus("error", "Kailangan ang reference number.");
    button.disabled = true;
    button.textContent = "Ipinapadala…";
    getClient().then(function (client) {
      if (!client) throw new Error("Hindi makakonekta ngayon. Subukan muli.");
      if (!file) {
        return client.rpc("portal_submit_payment", {
          token: token,
          p_invoice: current.invoiceId,
          p_amount: amount,
          p_method: method,
          p_reference: reference,
          p_payer: payer,
          p_proof: null
        });
      }
      if (file.size > 8 * 1024 * 1024) throw new Error("Masyadong malaki ang larawan. Pumili ng mas maliit.");
      return compressImage(file).then(function (blob) {
        if (blob.size > 2 * 1024 * 1024) throw new Error("Ang screenshot ay dapat 2 MB pababa.");
        return blobToBase64(blob).then(function (image) {
          return client.rpc("portal_submit_proof", {
            token: token,
            p_invoice: current.invoiceId,
            p_amount: amount,
            p_method: method,
            p_reference: reference,
            p_payer: payer,
            p_image_base64: image,
            p_mime: "image/jpeg"
          });
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

  function loadPortalScript(src) {
    return new Promise(function (resolve, reject) {
      if (window.jspdf) return resolve();
      var script = document.createElement("script");
      script.src = src;
      script.onload = function () { resolve(); };
      script.onerror = function () { reject(new Error("Hindi ma-load ang PDF.")); };
      document.head.appendChild(script);
    });
  }

  function downloadPortalReceipt(id) {
    getClient().then(function (client) {
      if (!client) throw new Error("Hindi makakonekta.");
      return Promise.all([
        client.rpc("portal_receipt", { token: token, p_logbook: id }),
        loadPortalScript("https://cdn.jsdelivr.net/npm/jspdf@2.5.2/dist/jspdf.umd.min.js")
      ]);
    }).then(function (parts) {
      var result = parts[0];
      if (result.error) throw new Error(result.error.message || "Hindi mabuksan ang resibo.");
      var row = result.data || {};
      var JsPDF = window.jspdf && window.jspdf.jsPDF;
      if (!JsPDF) throw new Error("Hindi mabuksan ang PDF.");
      var doc = new JsPDF();
      doc.setTextColor(255, 0, 0);
      doc.setFontSize(16);
      doc.text("FiberBro", 14, 18);
      doc.setTextColor(30);
      doc.setFontSize(11);
      doc.text("Internet Communication Services Corp.", 14, 26);
      doc.text("Payatas, Quezon City", 14, 32);
      doc.setFontSize(13);
      doc.text("ACKNOWLEDGEMENT RECEIPT", 14, 44);
      doc.setFontSize(11);
      var lines = [
        "Name: " + (row.name || ""),
        "Date: " + (row.date || ""),
        "Reference number: " + (row.reference || ""),
        "Month payment: " + (row.month || ""),
        "Amount: " + peso(row.amount),
        "This month balance: " + peso(row.balance),
        "Balance status: " + (Number(row.balance) > 0 ? "With balance" : "Cleared"),
        "Cut-off: " + (row.cutoff || ""),
        "Payment Received - Thank You!"
      ];
      lines.forEach(function (line, index) { doc.text(String(line), 14, 56 + index * 7); });
      if (row.image_base64) {
        try { doc.addImage("data:" + (row.content_type || "image/jpeg") + ";base64," + row.image_base64, "JPEG", 120, 40, 75, 100); } catch (err) {}
      }
      doc.save("FiberBro-receipt.pdf");
    }).catch(function (err) { showStatus("error", err.message || "Hindi mabuksan ang resibo."); });
  }

  function downloadPortalSoa(invoiceId, data) {
    var account = data.account || {};
    var bill = (data.invoices || []).filter(function (row) { return row.id === invoiceId; })[0] || {};
    loadPortalScript("https://cdn.jsdelivr.net/npm/jspdf@2.5.2/dist/jspdf.umd.min.js").then(function () {
      var JsPDF = window.jspdf && window.jspdf.jsPDF;
      if (!JsPDF) throw new Error("Hindi mabuksan ang PDF.");
      var doc = new JsPDF();
      doc.setTextColor(255, 0, 0);
      doc.setFontSize(16);
      doc.text("FiberBro", 14, 18);
      doc.setTextColor(30);
      doc.setFontSize(11);
      doc.text("Internet Communication Services Corp.", 14, 26);
      doc.text("Payatas, Quezon City", 14, 32);
      doc.setFontSize(14);
      doc.text("Statement of Account", 14, 46);
      doc.setFontSize(11);
      doc.text(String(account.name || ""), 14, 56);
      doc.text("Account " + (account.account_number || ""), 14, 62);
      doc.text("Plan: " + (account.plan || ""), 14, 68);
      doc.text("Bill " + (bill.bill_number || ""), 14, 78);
      doc.text("Period " + (bill.period_label || bill.period || ""), 14, 84);
      doc.text("Previous balance " + peso(bill.previous_balance || 0), 14, 90);
      doc.text("This month " + peso(bill.amount), 14, 96);
      doc.text("Due " + (bill.due_date || ""), 14, 102);
      doc.save("FiberBro-SOA.pdf");
    }).catch(function (err) { showStatus("error", err.message || "Hindi mabuksan ang SOA."); });
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
