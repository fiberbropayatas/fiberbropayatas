(function () {
  "use strict";

  var statusEl = document.getElementById("pay-status");
  var resultEl = document.getElementById("pay-result");
  var lookupForm = document.getElementById("lookup-form");
  var accountInput = document.getElementById("account");
  var clientPromise = null;
  var current = null;

  function esc(value) {
    return String(value == null ? "" : value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function showStatus(type, message) {
    statusEl.className = "form-status " + (type === "success" ? "is-success" : "is-error");
    statusEl.textContent = message;
    statusEl.hidden = false;
  }

  function peso(amount) {
    var num = Number(amount);
    if (isNaN(num)) return "";
    return "₱" + num.toLocaleString("en-PH", { maximumFractionDigits: 2 });
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

  function compressImage(file) {
    return new Promise(function (resolve, reject) {
      var url = URL.createObjectURL(file);
      var img = new Image();
      img.onload = function () {
        var maxSide = 1600;
        var scale = Math.min(1, maxSide / Math.max(img.width, img.height));
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

  function proofPath(ext) {
    var alphabet = "abcdefghijklmnopqrstuvwxyz0123456789";
    var rand = "";
    var bytes = new Uint8Array(12);
    if (window.crypto && window.crypto.getRandomValues) window.crypto.getRandomValues(bytes);
    for (var i = 0; i < bytes.length; i++) rand += alphabet.charAt(bytes[i] % alphabet.length);
    return "proofs/" + rand + "." + ext;
  }

  function renderBills(data, settings) {
    var invoices = data.invoices || [];
    if (!invoices.length) {
      resultEl.innerHTML = "<p><strong>" + esc(data.name) + "</strong></p><p>Wala kang balanse ngayon.</p>";
      return;
    }
    var qrUrl = (settings.gcash_qr_url || "").trim();
    var gcashBody = qrUrl
      ? "<img src=\"" + esc(qrUrl) + "\" alt=\"GCash QR\">"
      : "<p>Number: " + esc(settings.gcash_number || "Hindi pa naka-set") + "<br>Name: " + esc(settings.gcash_name || "") + "</p>";
    var gcash = "<div class=\"gcash-box\"><strong>GCash</strong>" + gcashBody +
      (settings.payment_note ? "<p class=\"pay-note\">" + esc(settings.payment_note) + "</p>" : "") +
      "</div>";
    var list = invoices.map(function (bill, index) {
      return "<button type=\"button\" class=\"bill-choice" + (index === 0 ? " is-selected" : "") + "\" data-id=\"" + esc(bill.id) + "\">" +
        "<span><strong>" + esc(bill.period) + "</strong><br><span class=\"pay-note\">Due " + esc(bill.due_date || "—") + " · " + esc(bill.status) + "</span></span>" +
        "<strong>" + esc(peso(bill.amount)) + "</strong></button>";
    }).join("");
    resultEl.innerHTML = "<p>Kumusta, <strong>" + esc(data.name) + "</strong>" +
      (data.plan ? " · " + esc(data.plan) : "") + "</p>" +
      "<h2>Bukas na bill</h2><div class=\"bill-list\">" + list + "</div>" + gcash +
      "<form id=\"pay-form\" class=\"form-grid\">" +
      "<div class=\"field\"><label for=\"amount\">Amount</label><input id=\"amount\" name=\"amount\" type=\"number\" min=\"0.01\" step=\"0.01\" required value=\"" + esc(invoices[0].amount) + "\"></div>" +
      "<div class=\"field\"><label for=\"reference\">Reference number</label><input id=\"reference\" name=\"reference\" required placeholder=\"GCash reference\"></div>" +
      "<div class=\"field\"><label for=\"payer\">Pangalan ng nagbayad <span class=\"hint\">(opsyonal)</span></label><input id=\"payer\" name=\"payer\"></div>" +
      "<div class=\"field\"><label for=\"proof\">Screenshot ng resibo <span class=\"hint\">(opsyonal, JPG/PNG, max 5 MB)</span></label><input id=\"proof\" name=\"proof\" type=\"file\" accept=\"image/jpeg,image/png,image/webp\"></div>" +
      "<button class=\"btn btn-primary\" type=\"submit\">Ipadala ang bayad</button></form>";
    current.invoiceId = invoices[0].id;
    resultEl.querySelectorAll(".bill-choice").forEach(function (button) {
      button.onclick = function () {
        resultEl.querySelectorAll(".bill-choice").forEach(function (el) { el.classList.remove("is-selected"); });
        button.classList.add("is-selected");
        current.invoiceId = button.getAttribute("data-id");
        var bill = invoices.filter(function (item) { return item.id === current.invoiceId; })[0];
        if (bill) document.getElementById("amount").value = bill.amount;
      };
    });
    document.getElementById("pay-form").onsubmit = function (event) {
      event.preventDefault();
      submitPayment();
    };
  }

  function submitPayment() {
    var amount = Number(document.getElementById("amount").value);
    var reference = document.getElementById("reference").value.trim();
    var payer = document.getElementById("payer").value.trim();
    var file = document.getElementById("proof").files[0];
    var button = document.querySelector("#pay-form button");
    if (!reference) return showStatus("error", "Kailangan ang reference number.");
    button.disabled = true;
    button.textContent = "Ipinapadala…";
    getClient().then(function (client) {
      if (!client) throw new Error("Hindi pa naka-connect ang Pay Bills page.");
      var proofPromise = Promise.resolve(null);
      if (file) {
        if (file.size > 10 * 1024 * 1024) throw new Error("Masyadong malaki ang larawan. Pumili ng mas maliit (max 10 MB bago i-compress).");
        proofPromise = compressImage(file).then(function (blob) {
          if (blob.size > 5 * 1024 * 1024) throw new Error("Masyadong malaki ang larawan pagkatapos i-compress. Max 5 MB.");
          var path = proofPath("jpg");
          return client.storage.from("payment-proofs").upload(path, blob, { contentType: "image/jpeg", upsert: false })
            .then(function (upload) {
              if (upload.error) throw new Error(upload.error.message || "Hindi na-upload ang screenshot.");
              return path;
            });
        });
      }
      return proofPromise.then(function (path) {
        return client.rpc("submit_payment", {
          acct: accountInput.value.trim(),
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
      var body = result.data;
      if (!body || body.ok !== true) throw new Error("Hindi naipadala ang bayad.");
      showStatus("success", "Salamat! Natanggap na namin ang iyong bayad. Hintayin ang confirmation.");
      resultEl.innerHTML = "";
    }).catch(function (err) {
      showStatus("error", err.message || "May problema. Subukan muli.");
    }).then(function () {
      if (button) {
        button.disabled = false;
        button.textContent = "Ipadala ang bayad";
      }
    });
  }

  lookupForm.addEventListener("submit", function (event) {
    event.preventDefault();
    statusEl.hidden = true;
    statusEl.className = "form-status";
    resultEl.innerHTML = "<p>Hinahanap…</p>";
    getClient().then(function (client) {
      if (!client) throw new Error("Hindi pa naka-connect ang Pay Bills page.");
      return Promise.all([
        client.rpc("lookup_bill", { acct: accountInput.value.trim() }),
        client.from("app_settings").select("key, value").in("key", ["gcash_number", "gcash_name", "gcash_qr_url", "payment_note"])
      ]);
    }).then(function (parts) {
      var looked = parts[0];
      if (looked.error) throw new Error(looked.error.message || "Hindi mabasa ang bill.");
      if (!looked.data) {
        resultEl.innerHTML = "";
        showStatus("error", "Hindi nahanap ang account number.");
        return;
      }
      current = { data: looked.data };
      var settings = {};
      (parts[1].data || []).forEach(function (row) { settings[row.key] = row.value; });
      renderBills(looked.data, settings);
    }).catch(function (err) {
      resultEl.innerHTML = "";
      showStatus("error", err.message || "May problema. Subukan muli.");
    });
  });
})();
