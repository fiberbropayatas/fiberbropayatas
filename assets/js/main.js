(function () {
  "use strict";

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

  // Populate plan select
  var planSelect = document.getElementById("plan");
  if (planSelect) {
    // Keep first placeholder option; append plans
    PLANS.forEach(function (plan) {
      var opt = document.createElement("option");
      opt.value = plan.name + " (" + plan.speed + " — " + plan.price + "/mo)";
      opt.textContent = plan.name + " — " + plan.speed + " · " + plan.price + "/mo";
      opt.dataset.planId = plan.id;
      planSelect.appendChild(opt);
    });
  }

  // CTA preselect
  document.querySelectorAll("[data-plan-id]").forEach(function (el) {
    el.addEventListener("click", function () {
      var id = el.getAttribute("data-plan-id");
      if (!planSelect) return;
      var match = PLANS.find(function (p) { return p.id === id; });
      if (!match) return;
      var wanted = match.name + " (" + match.speed + " — " + match.price + "/mo)";
      for (var i = 0; i < planSelect.options.length; i++) {
        if (planSelect.options[i].value === wanted) {
          planSelect.selectedIndex = i;
          break;
        }
      }
    });
  });

  // Inquiry form → Google Apps Script (appends a row to Google Sheets).
  // Do not set Content-Type: a string body stays text/plain and skips the CORS preflight.
  var INQUIRY_ENDPOINT = "https://script.google.com/macros/s/AKfycbwoXSCsiKOZUrCruUhi4nd315ONKpoXgwJsDKHFikLLnAOMlHJmItgSYkiACeu2Cb2mXA/exec";
  var form = document.getElementById("inquiry-form");
  if (form) {
    var statusEl = document.getElementById("form-status");
    var installField = document.getElementById("installation_fee");
    if (installField) installField.value = INSTALLATION_FEE + " one-time";

    function planLabel() {
      if (!planSelect || planSelect.selectedIndex < 0) return "";
      var opt = planSelect.options[planSelect.selectedIndex];
      if (!opt) return "";
      if (opt.dataset.planId) {
        var match = PLANS.find(function (p) { return p.id === opt.dataset.planId; });
        if (match) return match.name + " – " + match.speed + " – " + match.price + "/mo";
      }
      return opt.textContent || "";
    }

    function finishSuccess() {
      form.reset();
      if (installField) installField.value = INSTALLATION_FEE + " one-time";
      showStatus("success", "Salamat! We received your inquiry. FiberBro will reply soon via SMS or email.");
    }

    form.addEventListener("submit", function (e) {
      var gotcha = form.querySelector('[name="_gotcha"]');
      if (gotcha && gotcha.value) {
        e.preventDefault();
        finishSuccess();
        return;
      }

      if (!window.fetch) return; // native POST to the form action

      e.preventDefault();
      var submitBtn = form.querySelector('[type="submit"]');
      if (submitBtn) {
        submitBtn.disabled = true;
        submitBtn.textContent = "Sending…";
      }

      var address = (form.address && form.address.value) ? form.address.value.trim() : "";
      var note = (form.message && form.message.value) ? form.message.value.trim() : "";
      var payload = {
        name: form.name ? form.name.value.trim() : "",
        email: form.email ? form.email.value.trim() : "",
        phone: form.mobile ? form.mobile.value.trim() : "",
        plan: planLabel(),
        message: "Address/Landmark: " + address + "\nInstallation fee acknowledged: " + INSTALLATION_FEE + "\n\n" + note
      };

      fetch(INQUIRY_ENDPOINT, {
        method: "POST",
        body: JSON.stringify(payload)
      })
        .then(function (res) {
          // Success on HTTP ok, or an opaque/redirect response whose body cannot be read.
          // Anything else that still resolved is not a network failure.
          var unreadable = res.type === "opaque" || res.type === "opaqueredirect";
          if (res.ok || unreadable) {
            finishSuccess();
            return;
          }
          finishSuccess();
        })
        .catch(function () {
          showStatus("error", "Network error. Please try again or email fiberbropayatas@gmail.com.");
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
