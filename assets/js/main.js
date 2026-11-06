(function () {
  "use strict";

  var formLoadedAt = Date.now();

  /* ============================================================
     PLANS CONFIG — edit here when plans/prices change
     Installation fee is one-time ₱1,000 (Nov 2026)
     ============================================================ */
  var PLANS = [
    {
      id: "basic",
      name: "Basic",
      speed: "75–150 Mbps",
      price: "₱1,000",
      priceNote: "/month",
      install: "₱1,000",
      popular: false,
      features: [
        "Fiber connection to your home",
        "Local Payatas support",
        "Ideal for browsing and light streaming",
        "Unlimited data"
      ]
    },
    {
      id: "plus",
      name: "Plus",
      speed: "150–200 Mbps",
      price: "₱1,200",
      priceNote: "/month",
      install: "₱1,000",
      popular: true,
      features: [
        "Fiber connection to your home",
        "Local Payatas support",
        "Good for work-from-home and HD streaming",
        "Unlimited data"
      ]
    },
    {
      id: "max",
      name: "Max",
      speed: "200–300 Mbps",
      price: "₱1,400",
      priceNote: "/month",
      install: "₱1,000",
      popular: false,
      features: [
        "Fiber connection to your home",
        "Local Payatas support",
        "Built for multi-device households",
        "Unlimited data"
      ]
    }
  ];
  var INSTALLATION_FEE = "₱1,000";

  // Mobile nav
  var toggle = document.querySelector(".nav-toggle");
  var nav = document.querySelector(".site-nav");
  if (toggle && nav) {
    toggle.addEventListener("click", function () {
      var open = toggle.getAttribute("aria-expanded") === "true";
      toggle.setAttribute("aria-expanded", String(!open));
      nav.classList.toggle("is-open", !open);
    });
    nav.querySelectorAll("a").forEach(function (link) {
      link.addEventListener("click", function () {
        toggle.setAttribute("aria-expanded", "false");
        nav.classList.remove("is-open");
      });
    });
  }

  // Render plan cards if container exists
  var plansGrid = document.getElementById("plans-grid");
  if (plansGrid) {
    plansGrid.innerHTML = PLANS.map(function (plan) {
      var features = plan.features
        .map(function (f) { return "<li>" + f + "</li>"; })
        .join("");
      var badge = plan.popular ? '<span class="plan-badge">Most Popular</span>' : "";
      var popularClass = plan.popular ? " popular" : "";
      return (
        '<article class="plan-card' + popularClass + '" data-plan="' + plan.id + '">' +
          badge +
          '<h3 class="plan-name">' + plan.name + "</h3>" +
          '<p class="plan-speed">' + plan.speed + '<span>download speed range</span></p>' +
          '<p class="plan-price">' + plan.price + "<small>" + plan.priceNote + "</small></p>" +
          '<p class="plan-install">' + plan.install + " one-time installation</p>" +
          '<ul class="plan-features">' + features + "</ul>" +
          '<a class="btn btn-primary btn-block plan-cta" href="#inquire" data-plan-id="' + plan.id + '">Inquire about ' + plan.name + "</a>" +
        "</article>"
      );
    }).join("");
  }

  // Plan-card CTA checks the matching registration radio.
  document.querySelectorAll("a.plan-cta[data-plan-id]").forEach(function (el) {
    el.addEventListener("click", function () {
      var id = el.getAttribute("data-plan-id");
      var radio = document.querySelector('#inquiry-form input[name="plan"][data-plan-id="' + id + '"]');
      if (radio) radio.checked = true;
    });
  });

  // Inquiry form → Google Apps Script (appends a row to Google Sheets).
  // Do not set Content-Type: a string body stays text/plain and skips the CORS preflight.
  var INQUIRY_ENDPOINT = "https://script.google.com/macros/s/AKfycbwY9a5oRCCG_ztClnLn6Ku4N1fawzALZQV2_Q4sDhUvzRsw-Ha6EFGnObvB1Zu9SpQLBA/exec";
  var form = document.getElementById("inquiry-form");
  if (form) {
    var statusEl = document.getElementById("form-status");
    var installField = document.getElementById("installation_fee");
    if (installField) installField.value = INSTALLATION_FEE + " one-time";

    var installDateInput = document.getElementById("installDate");
    if (installDateInput) {
      var now = new Date();
      var month = String(now.getMonth() + 1);
      var day = String(now.getDate());
      if (month.length < 2) month = "0" + month;
      if (day.length < 2) day = "0" + day;
      installDateInput.min = now.getFullYear() + "-" + month + "-" + day;
    }

    function fieldValue(id) {
      var el = document.getElementById(id);
      return el && el.value ? el.value.trim() : "";
    }

    function selectedPlan() {
      var checked = form.querySelector('input[name="plan"]:checked');
      return checked ? checked.value : "";
    }

    var idInput = document.getElementById("idPhoto");
    var idDrop = document.getElementById("id-drop");
    var idPicked = document.getElementById("id-photo-picked");
    var idPreview = document.getElementById("id-photo-preview");
    var idChange = document.getElementById("id-photo-change");
    var idPreviewUrl = "";
    var ID_PHOTO_MAX_BYTES = 10 * 1024 * 1024;

    function clearIdPreview() {
      if (idPreviewUrl) {
        URL.revokeObjectURL(idPreviewUrl);
        idPreviewUrl = "";
      }
      if (idPreview) idPreview.removeAttribute("src");
      if (idPicked) idPicked.hidden = true;
      if (idDrop) idDrop.classList.remove("has-file");
    }

    function validateIdFile(file) {
      if (!file) return "Please upload a photo of your valid ID.";
      var type = file.type || "";
      if (type.indexOf("image/") !== 0) return "Please choose an image file (JPG or PNG).";
      if (file.size > ID_PHOTO_MAX_BYTES) return "That photo is larger than 10 MB. Please choose a smaller one.";
      return "";
    }

    function showIdPreview(file) {
      if (idPreviewUrl) URL.revokeObjectURL(idPreviewUrl);
      idPreviewUrl = URL.createObjectURL(file);
      if (idPreview) idPreview.src = idPreviewUrl;
      if (idPicked) idPicked.hidden = false;
      if (idDrop) idDrop.classList.add("has-file");
    }

    function nameForFile(value) {
      var cleaned = value.replace(/[^A-Za-z0-9]+/g, "");
      return cleaned || "name";
    }

    function photoStamp(date) {
      function pad(n) { return (n < 10 ? "0" : "") + n; }
      return String(date.getFullYear()) + pad(date.getMonth() + 1) + pad(date.getDate()) + "-" + pad(date.getHours()) + pad(date.getMinutes());
    }

    function compressIdPhoto(file) {
      return new Promise(function (resolve, reject) {
        var url = URL.createObjectURL(file);
        var img = new Image();
        img.onload = function () {
          var maxSide = 1600;
          var width = img.naturalWidth || img.width;
          var height = img.naturalHeight || img.height;
          var scale = Math.min(1, maxSide / Math.max(width, height));
          var canvas = document.createElement("canvas");
          canvas.width = Math.max(1, Math.round(width * scale));
          canvas.height = Math.max(1, Math.round(height * scale));
          var ctx = canvas.getContext("2d");
          ctx.fillStyle = "#fff";
          ctx.fillRect(0, 0, canvas.width, canvas.height);
          ctx.drawImage(img, 0, 0, canvas.width, canvas.height);
          URL.revokeObjectURL(url);
          var dataUrl = canvas.toDataURL("image/jpeg", 0.8);
          var comma = dataUrl.indexOf(",");
          resolve(comma === -1 ? "" : dataUrl.slice(comma + 1));
        };
        img.onerror = function () {
          URL.revokeObjectURL(url);
          reject(new Error("Could not read that photo. Please choose a JPG or PNG."));
        };
        img.src = url;
      });
    }

    if (idInput) {
      idInput.addEventListener("change", function () {
        var file = idInput.files && idInput.files[0];
        if (!file) {
          clearIdPreview();
          return;
        }
        var err = validateIdFile(file);
        if (err) {
          idInput.value = "";
          clearIdPreview();
          showStatus("error", err);
          return;
        }
        showIdPreview(file);
        if (statusEl) statusEl.hidden = true;
      });
    }
    if (idChange && idInput) {
      idChange.addEventListener("click", function () {
        idInput.click();
      });
    }

    var SAVE_ERROR = "We could not save your inquiry. Please try again or message us on Messenger.";

    function inquiryClient() {
      var cfg = window.FIBERBRO_SUPABASE;
      if (!cfg || typeof cfg.isConfigured !== "function" || !cfg.isConfigured()) {
        return Promise.resolve(null);
      }
      return import("https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm")
        .then(function (mod) {
          return mod.createClient(cfg.url, cfg.anonKey, {
            auth: { persistSession: false, autoRefreshToken: false, detectSessionInUrl: false }
          });
        });
    }

    function base64ToBlob(base64) {
      var clean = String(base64 || "").replace(/[^A-Za-z0-9+/=]/g, "");
      var binary = atob(clean);
      var bytes = new Uint8Array(binary.length);
      for (var i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
      return new Blob([bytes], { type: "image/jpeg" });
    }

    function idStoragePath(lastName, firstName) {
      function part(value) {
        var text = String(value || "").replace(/ñ/g, "n").replace(/Ñ/g, "N");
        if (text.normalize) text = text.normalize("NFD").replace(/[\u0300-\u036f]/g, "");
        text = text.replace(/[^A-Za-z0-9]/g, "").toUpperCase();
        return text || "NAME";
      }
      function pad(n) { return (n < 10 ? "0" : "") + n; }
      var now = new Date();
      var stamp = String(now.getFullYear()) + pad(now.getMonth() + 1) + pad(now.getDate()) + "-" + pad(now.getHours()) + pad(now.getMinutes()) + pad(now.getSeconds());
      var alphabet = "abcdefghijklmnopqrstuvwxyz0123456789";
      var rand = "";
      var bytes = null;
      if (window.crypto && window.crypto.getRandomValues) {
        bytes = new Uint8Array(6);
        window.crypto.getRandomValues(bytes);
      }
      for (var i = 0; i < 6; i++) {
        var n = bytes ? bytes[i] : Math.floor(Math.random() * alphabet.length);
        rand += alphabet.charAt(n % alphabet.length);
      }
      return "inquiries/" + part(lastName) + "_" + part(firstName) + "_" + stamp + "_" + rand + ".jpg";
    }

    function uploadValidId(client, base64, lastName, firstName) {
      var path = idStoragePath(lastName, firstName);
      return client.storage.from("valid-ids").upload(path, base64ToBlob(base64), {
        contentType: "image/jpeg",
        upsert: false
      }).then(function (result) {
        if (result && result.error) {
          console.error("Valid ID upload failed", result.error);
          return null;
        }
        return path;
      }).catch(function (err) {
        console.error("Valid ID upload failed", err);
        return null;
      });
    }

    function mirrorInquiry(row, base64, lastName, firstName) {
      return inquiryClient().then(function (client) {
        if (!client) return { ok: false };
        return uploadValidId(client, base64, lastName, firstName).then(function (path) {
          row.valid_id_path = path;
          return client.from("customers").insert(row, { returning: "minimal" });
        });
      }).then(function (result) {
        if (result && result.ok === false) return result;
        if (result && result.error) {
          console.error("Supabase inquiry insert failed", result.error);
          return { ok: false };
        }
        return { ok: true };
      }).catch(function (err) {
        console.error("Supabase inquiry insert failed", err);
        return { ok: false };
      });
    }

    function saveToSheet(payload) {
      return fetch(INQUIRY_ENDPOINT, {
        method: "POST",
        body: JSON.stringify(payload)
      }).then(function (res) {
        if (!res.ok) throw new Error(SAVE_ERROR);
        return res.json();
      }).then(function (body) {
        if (!body || body.ok !== true) throw new Error(SAVE_ERROR);
        return { ok: true };
      });
    }

    function finishSuccess() {
      form.reset();
      clearIdPreview();
      if (installField) installField.value = INSTALLATION_FEE + " one-time";
      showStatus("success", "Salamat! We received your inquiry. FiberBro will reply soon via SMS or email.");
    }

    form.addEventListener("submit", function (e) {
      if (!window.fetch) return; // native POST to the form action

      e.preventDefault();
      if (Date.now() - formLoadedAt < 2000) {
        showStatus("error", "Please wait a moment and try again.");
        return;
      }
      var file = idInput && idInput.files ? idInput.files[0] : null;
      var fileError = validateIdFile(file);
      if (fileError) {
        showStatus("error", fileError);
        if (idInput) idInput.focus();
        return;
      }

      var submitBtn = form.querySelector('[type="submit"]');
      if (submitBtn) {
        submitBtn.disabled = true;
        submitBtn.textContent = "Uploading…";
      }

      var firstName = fieldValue("firstName");
      var lastName = fieldValue("lastName");
      var middleInitial = fieldValue("middleInitial");
      var birthDate = fieldValue("birthDate");
      var facebookName = fieldValue("facebookName");
      var address = fieldValue("address");
      var landmark = fieldValue("landmark");
      var validId = fieldValue("validId");
      var installDate = fieldValue("installDate");
      var referredBy = fieldValue("referredBy");
      var phoneValue = fieldValue("phone");
      var nameParts = [];
      if (firstName) nameParts.push(firstName);
      if (middleInitial) nameParts.push(middleInitial);
      if (lastName) nameParts.push(lastName);

      compressIdPhoto(file).then(function (base64) {
        var payload = {
          name: nameParts.join(" "),
          email: fieldValue("email"),
          phone: "'" + phoneValue,
          plan: selectedPlan(),
          message: [
            "Date of Birth: " + birthDate,
            "Facebook Name: " + facebookName,
            "Address: " + address,
            "Landmark: " + landmark,
            "Valid ID: " + validId,
            "Preferred installation date: " + installDate,
            "Referred by: " + referredBy,
            "Installation fee acknowledged: " + INSTALLATION_FEE
          ].join("\n"),
          firstName: firstName,
          lastName: lastName,
          middleInitial: middleInitial,
          birthDate: birthDate,
          facebookName: facebookName,
          address: address,
          landmark: landmark,
          validId: validId,
          installDate: installDate,
          referredBy: referredBy,
          idFileName: nameForFile(lastName) + "_" + nameForFile(firstName) + "_" + photoStamp(new Date()) + ".jpg",
          idMimeType: "image/jpeg",
          idFile: base64
        };

        var inquiryRow = {
          first_name: firstName,
          last_name: lastName,
          middle_initial: middleInitial || null,
          birth_date: birthDate || null,
          mobile: phoneValue,
          contact_number: phoneValue,
          email: fieldValue("email") || null,
          facebook_name: facebookName || null,
          address: address,
          landmark: landmark || null,
          valid_id_type: validId,
          plan: selectedPlan(),
          preferred_install_date: installDate || null,
          referred_by: referredBy || null,
          name: nameParts.join(" "),
          source: "website"
        };

        return Promise.allSettled([
          saveToSheet(payload),
          mirrorInquiry(inquiryRow, base64, lastName, firstName)
        ]).then(function (results) {
          var sheetOk = results[0].status === "fulfilled" && results[0].value && results[0].value.ok === true;
          var supabaseOk = results[1].status === "fulfilled" && results[1].value && results[1].value.ok === true;
          if (sheetOk || supabaseOk) {
            finishSuccess();
            return;
          }
          showStatus("error", SAVE_ERROR);
        });
      })
        .catch(function (err) {
          var network = !err || err.name === "TypeError";
          showStatus("error", network
            ? "Network error. Please try again or email fiberbropayatas@gmail.com."
            : (err.message || "Could not read that photo. Please choose a JPG or PNG."));
        })
        .finally(function () {
          if (submitBtn) {
            submitBtn.disabled = false;
            submitBtn.textContent = "Send inquiry";
          }
        });
    });

    function showStatus(type, message) {
      if (!statusEl) return;
      statusEl.className = "form-status " + (type === "success" ? "is-success" : "is-error");
      statusEl.textContent = message;
      statusEl.hidden = false;
      statusEl.focus();
    }
  }

  // Year in footer if needed
  var yearEl = document.getElementById("year");
  if (yearEl) yearEl.textContent = String(new Date().getFullYear());
})();
