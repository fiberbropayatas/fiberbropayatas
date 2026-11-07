(function () {
  "use strict";

  var STAGES = [
    { id: "inquiry", label: "Inquiry" },
    { id: "in_progress", label: "In Progress" },
    { id: "encoded", label: "Encoded" },
    { id: "active", label: "Active" }
  ];

  var SECTIONS = [
    { title: "Account", fields: [
      ["account_number", "Account Number", "text"],
      ["account_status", "Account Status", "text"],
      ["name", "Name", "text"],
      ["first_name", "First name", "text"],
      ["last_name", "Last name", "text"],
      ["middle_initial", "M.I", "text"],
      ["birth_date", "Date of birth", "date"],
      ["contact_number", "Contact number", "text"],
      ["mobile", "Mobile", "text"],
      ["facebook_name", "Facebook name", "text"],
      ["messenger", "Messenger inbox link", "text"],
      ["email_address", "Email address", "email"],
      ["email", "Inquiry email", "email"]
    ]},
    { title: "Location and Network", fields: [
      ["address", "Address", "textarea"],
      ["area", "Area", "text"],
      ["landmark", "Landmark", "text"],
      ["pin_loc", "PIN LOC", "text"],
      ["sub_area", "SUB AREA", "text"],
      ["lp", "LP", "text"],
      ["nap", "NAP", "text"],
      ["port", "Port", "text"],
      ["pppoe", "PPPoE", "text"],
      ["latitude", "Latitude", "float"],
      ["longitude", "Longitude", "float"]
    ]},
    { title: "Installation", fields: [
      ["investor_id", "Investor", "investor"],
      ["referred_by", "Referred by", "text"],
      ["installed_by", "Activated/Installed by", "text"],
      ["installation_status", "Installation Status", "text"],
      ["installation_date", "Installation date", "date"],
      ["preferred_install_date", "Preferred install date", "date"],
      ["installation_remarks", "Installation remarks", "textarea"]
    ]},
    { title: "Plan", fields: [
      ["plan", "Plan", "text"],
      ["plan_type", "Plan Type", "text"],
      ["plan_speed", "Plan Speed", "text"],
      ["price", "Price", "money"],
      ["plan_status", "Plan Status", "text"]
    ]},
    { title: "Billing", fields: [
      ["due_date_number", "Due Date Number", "int"],
      ["original_due_date", "Original Due Date", "date"],
      ["monthly_bill", "Monthly Bill", "money"],
      ["current_bill", "Current Bill", "money"],
      ["total_payment", "Total Payment", "money"],
      ["total_balance", "Total Balance", "money"],
      ["balance_status", "Balance Status", "text"],
      ["current_month_year_bill", "Current Month Year Bill", "text"],
      ["prev_month_year_bill", "Prev Month Year Bill", "text"],
      ["previous_month_balance", "Previous month Balance", "money"],
      ["previous_month_payment", "Previous month payment", "money"],
      ["bill_generation", "Bill generation", "date"],
      ["current_due_date", "Current Due Date", "date"],
      ["bill_trigger", "Bill Trigger", "text"]
    ]},
    { title: "Collection", fields: [
      ["assigned_name", "Assigned Name", "text"],
      ["assigned_email", "Assigned Email", "email"],
      ["payment_collection_status", "Payment Collection Status", "text"],
      ["collection_timestamp", "Collection Timestamp", "datetime"],
      ["collection_date", "Collection Date", "date"],
      ["promissory_status", "Promissory Status", "text"],
      ["promissory_clearance", "Promissory Clearance", "text"],
      ["master_collection_timestamp", "Master Collection Timestamp", "datetime"],
      ["gcash", "Gcash", "text"],
      ["for_disconnection", "For Disconnection", "bool"],
      ["reminder", "Reminder", "textarea"],
      ["payment_mode", "Payment Mode", "text"]
    ]},
    { title: "Modem", fields: [
      ["modem_brand", "Modem Brand", "text"],
      ["modem_type", "Modem Type", "text"],
      ["mac_address", "Mac address", "text"],
      ["description", "Description", "textarea"]
    ]},
    { title: "Photos", fields: [
      ["landmark_picture_url", "Landmark Picture", "url"],
      ["modem_picture_front_url", "Modem Picture Front", "url"],
      ["modem_picture_back_url", "Modem Picture Back / GUI", "url"],
      ["lap_nap_picture_url", "LAP/NAP Picture", "url"],
      ["port_picture_url", "Port Picture", "url"],
      ["house_picture_url", "House Picture", "url"],
      ["acknowledgement_slip_url", "Acknowledgement Slip", "url"]
    ]}
  ];

  var FIBER_PLANS = [
    { value: "75–150 Mbps ₱1,000/month", speed: "75–150 Mbps", price: 1000, type: "Basic" },
    { value: "150–200 Mbps ₱1,200/month", speed: "150–200 Mbps", price: 1200, type: "Plus" },
    { value: "200–300 Mbps ₱1,400/month", speed: "200–300 Mbps", price: 1400, type: "Max" }
  ];
  var app = document.getElementById("app");
  if (app) {
    app.addEventListener("click", function (event) {
      var toggle = event.target.closest && event.target.closest(".section-toggle");
      if (!toggle || !app.contains(toggle)) return;
      var open = toggle.getAttribute("aria-expanded") === "true";
      toggle.setAttribute("aria-expanded", open ? "false" : "true");
      var card = toggle.closest(".section-card");
      if (card) card.classList.toggle("is-collapsed", open);
    });
  }
  var who = document.getElementById("who");
  var sideNav = document.getElementById("side-nav");
  var pageTitle = document.getElementById("page-title");
  var navToggle = document.getElementById("nav-toggle");
  var navScrim = document.getElementById("nav-scrim");
  var sidebarEl = document.getElementById("sidebar");
  wireAdminChrome();
  var cfg = window.FIBERBRO_SUPABASE;
  var db = null;
  var sessionEmail = "";
  var state = { customers: [], investors: [], technicians: [], tickets: [], admins: [], events: [], changes: [], ticket: null, customer: null };
  var ui = { q: "", stage: "all", area: "" };

  function esc(value) {
    return String(value == null ? "" : value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function stageLabel(id) {
    for (var i = 0; i < STAGES.length; i++) if (STAGES[i].id === id) return STAGES[i].label;
    return id || "";
  }

  function fieldLabel(key) {
    for (var s = 0; s < SECTIONS.length; s++) {
      var fields = SECTIONS[s].fields;
      for (var i = 0; i < fields.length; i++) {
        if (fields[i][0] === key) return fields[i][1];
      }
    }
    if (key === "stage") return "Status";
    if (key === "source") return "Source";
    if (key === "valid_id_path") return "Valid ID photo";
    if (key === "valid_id_type") return "Valid ID type";
    if (key === "valid_id_drive_url") return "Valid ID Drive link";
    if (key === "plan_split") return "Plan Split";
    if (key === "fb_account") return "Facebook account";
    return key || "Field";
  }

  function manilaTime(value) {
    var date = new Date(value);
    if (isNaN(date.getTime())) return "";
    return date.toLocaleString("en-US", {
      timeZone: "Asia/Manila",
      month: "short",
      day: "numeric",
      year: "numeric",
      hour: "numeric",
      minute: "2-digit"
    });
  }

  function historyValue(field, value) {
    if (field === "valid_id_path") {
      if (value == null || String(value).trim() === "") return "(blank)";
      return "ID photo uploaded";
    }
    if (value == null || String(value).trim() === "") return "(blank)";
    var text = String(value);
    if (field === "investor_id") text = investorName(value) || text;
    if (field === "stage") text = stageLabel(value) || text;
    if (field === "for_disconnection") {
      if (text === "true") text = "Yes";
      else if (text === "false") text = "No";
    }
    if (text.length > 120) text = text.slice(0, 117) + "...";
    return text;
  }

  function changeGroups(rows) {
    var groups = [];
    (rows || []).forEach(function (row) {
      var key = String(row.changed_at) + "|" + String(row.changed_by || "");
      var last = groups[groups.length - 1];
      if (!last || last.key !== key) {
        last = { key: key, changed_at: row.changed_at, changed_by: row.changed_by, items: [] };
        groups.push(last);
      }
      last.items.push(row);
    });
    return groups;
  }

  function changeHistoryHtml(rows) {
    var groups = changeGroups(rows);
    if (!groups.length) return "<p class=\"muted\">No changes recorded yet.</p>";
    return "<ul class=\"change-list\">" + groups.map(function (group) {
      var lines = group.items.map(function (row) {
        if (row.action === "created") return "<li>Created the record</li>";
        return "<li>" + esc(fieldLabel(row.field)) + ": " +
          esc(historyValue(row.field, row.old_value)) + " → " +
          esc(historyValue(row.field, row.new_value)) + "</li>";
      }).join("");
      return "<li class=\"change-item\"><div class=\"change-meta\">" +
        esc(manilaTime(group.changed_at)) + " · " + esc(group.changed_by || "website") +
        "</div><ul class=\"change-fields\">" + lines + "</ul></li>";
    }).join("") + "</ul>";
  }

  function flash(message, ok) {
    var el = document.getElementById("flash");
    if (!el) return;
    el.className = "flash" + (ok ? " ok" : "");
    el.textContent = message;
    el.hidden = false;
  }

  function errText(error) {
    if (!error) return "Something went wrong.";
    return error.message || error.details || "Something went wrong.";
  }

  function loadLib() {
    return import("https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm");
  }

  function route() {
    var hash = (location.hash || "#dashboard").replace(/^#\/?/, "");
    var parts = hash.split("/").filter(Boolean);
    return { name: parts[0] || "dashboard", id: parts[1] || "" };
  }

  function go(hash) {
    location.hash = hash;
  }

  var lastAutoPppoe = "";

  function foldLetters(value) {
    var text = String(value || "").replace(/ñ/g, "n").replace(/Ñ/g, "N");
    if (text.normalize) text = text.normalize("NFD").replace(/[\u0300-\u036f]/g, "");
    return text;
  }

  function titleWord(word) {
    if (!word) return "";
    return word.charAt(0).toUpperCase() + word.slice(1).toLowerCase();
  }

  function pppoeLastName(raw) {
    var suffixes = { jr: 1, sr: 1, ii: 1, iii: 1, iv: 1 };
    var words = foldLetters(raw).split(/\s+/).map(function (word) {
      return word.replace(/[^A-Za-z]/g, "");
    }).filter(Boolean);
    while (words.length && suffixes[words[words.length - 1].toLowerCase()]) words.pop();
    return words.map(titleWord).join("");
  }

  function pppoeFirstName(raw) {
    var letters = foldLetters(raw).replace(/[^A-Za-z]/g, "");
    if (!letters) return "";
    return titleWord(letters.slice(0, 5));
  }

  function selectedInvestor() {
    var select = document.getElementById("f-investor_id");
    if (!select || !select.value) return null;
    for (var i = 0; i < state.investors.length; i++) {
      if (state.investors[i].id === select.value) return state.investors[i];
    }
    return null;
  }

  function buildPppoe() {
    var inv = selectedInvestor();
    var code = inv && inv.code ? String(inv.code).trim().toUpperCase() : "";
    if (!code) return "";
    var firstEl = document.getElementById("f-first_name");
    var lastEl = document.getElementById("f-last_name");
    var first = pppoeFirstName(firstEl ? firstEl.value : "");
    var last = pppoeLastName(lastEl ? lastEl.value : "");
    if (!first || !last) return "";
    return (code + "-" + last + "-" + first).toUpperCase();
  }

  function applyPppoe(force) {
    var input = document.getElementById("f-pppoe");
    if (!input) return;
    var next = buildPppoe();
    if (!next) return;
    var current = input.value.trim();
    if (!force && current && current.toUpperCase() !== lastAutoPppoe) return;
    input.value = next;
    lastAutoPppoe = next;
  }

  function wirePppoe() {
    var select = document.getElementById("f-investor_id");
    var first = document.getElementById("f-first_name");
    var last = document.getElementById("f-last_name");
    if (select) select.onchange = function () { applyPppoe(true); };
    if (first) first.oninput = function () { applyPppoe(false); };
    if (last) last.oninput = function () { applyPppoe(false); };
  }

  function investorLabel(inv) {
    if (!inv) return "";
    var code = inv.code ? String(inv.code).trim() : "";
    if (code) return code + " — " + (inv.name || "");
    return inv.name || "";
  }

  function compareInvestors(a, b) {
    var ac = a.code ? String(a.code).trim().toUpperCase() : "";
    var bc = b.code ? String(b.code).trim().toUpperCase() : "";
    if (ac !== bc) {
      if (!ac) return 1;
      if (!bc) return -1;
      return ac.localeCompare(bc);
    }
    return String(a.name || "").localeCompare(String(b.name || ""));
  }

  function investorName(id) {
    for (var i = 0; i < state.investors.length; i++) {
      if (state.investors[i].id === id) return investorLabel(state.investors[i]);
    }
    return "";
  }

  function techName(id) {
    for (var i = 0; i < state.technicians.length; i++) {
      if (state.technicians[i].id === id) return state.technicians[i].name;
    }
    return "";
  }

  function sortedInvestors(area, currentId) {
    var needle = (area || "").trim().toLowerCase();
    return state.investors.slice().filter(function (inv) {
      return inv.active || inv.id === currentId;
    }).sort(function (a, b) {
      function rank(inv) {
        var areas = inv.areas || [];
        var match = needle && areas.some(function (item) {
          return String(item).trim().toLowerCase() === needle;
        });
        if (match && inv.active) return 0;
        if (inv.active) return 1;
        return 2;
      }
      var diff = rank(a) - rank(b);
      if (diff) return diff;
      return compareInvestors(a, b);
    });
  }

  var NAV_GROUPS = [
    ["Overview", [["dashboard", "Dashboard", "dashboard"]]],
    ["Customers", [
      ["customers", "Customers", "customers"],
      ["tickets", "Install tickets", "tickets"],
      ["repairs", "Repairs", "repairs"]
    ]],
    ["Billing", [
      ["billing", "Billing", "billing"],
      ["payments", "Payments", "payments"]
    ]],
    ["Network", [
      ["map", "Map", "map"],
      ["investors", "Investors", "investors"],
      ["technicians", "Technicians", "technicians"]
    ]],
    ["System", [
      ["settings", "Settings", "settings"],
      ["admins", "Admins", "admins"]
    ]]
  ];
  var PAGE_TITLES = {
    dashboard: "Dashboard",
    customers: "Customers",
    customer: "Customer",
    billing: "Billing",
    payments: "Payments",
    map: "Map",
    repairs: "Repairs",
    investors: "Investors",
    technicians: "Technicians",
    tickets: "Install tickets",
    settings: "Settings",
    admins: "Admins"
  };
  var ICON_SHAPES = {
    dashboard: "<path d=\"M4 11.5 12 4l8 7.5\"/><path d=\"M6 10.5V20h12v-9.5\"/>",
    customers: "<circle cx=\"9\" cy=\"8\" r=\"3\"/><path d=\"M3.5 19a5.5 5.5 0 0 1 11 0\"/><circle cx=\"17\" cy=\"9\" r=\"2.2\"/><path d=\"M21 19a4 4 0 0 0-4-4\"/>",
    billing: "<path d=\"M7 3h10v18l-2.5-1.5L12 21l-2.5-1.5L7 21z\"/><path d=\"M9.5 8h5M9.5 12h5\"/>",
    payments: "<rect x=\"3\" y=\"6\" width=\"18\" height=\"12\" rx=\"2\"/><path d=\"M3 10h18\"/>",
    map: "<path d=\"M12 21s7-6 7-11a7 7 0 1 0-14 0c0 5 7 11 7 11z\"/><circle cx=\"12\" cy=\"10\" r=\"1.6\"/>",
    repairs: "<path d=\"M14.7 6.3a4 4 0 0 0-5.4 5.4L4 17l3 3 5.3-5.3a4 4 0 0 0 5.4-5.4L15 12l-3-3z\"/>",
    investors: "<rect x=\"4\" y=\"7\" width=\"16\" height=\"12\" rx=\"1.5\"/><path d=\"M8 7V5h8v2\"/>",
    technicians: "<path d=\"M12 3 19 6v6c0 4.5-3 6.8-7 7.8C8 18.8 5 16.5 5 12V6z\"/>",
    tickets: "<path d=\"M8 3h8v4H8z\"/><path d=\"M7 7h10v14H7z\"/><path d=\"M9 12h6M9 16h4\"/>",
    settings: "<path d=\"M4 7h16M4 12h16M4 17h16\"/><circle cx=\"8\" cy=\"7\" r=\"1.3\"/><circle cx=\"16\" cy=\"12\" r=\"1.3\"/><circle cx=\"10\" cy=\"17\" r=\"1.3\"/>",
    admins: "<path d=\"M12 3 19 6v6c0 4.2-3 6.5-7 7.6C8 18.5 5 16.2 5 12V6z\"/><path d=\"M9 12l2 2 4-4\"/>"
  };
  var navPainted = "";

  function iconSvg(name, className) {
    return "<svg class=\"" + className + "\" viewBox=\"0 0 24 24\" aria-hidden=\"true\" focusable=\"false\">" + (ICON_SHAPES[name] || "") + "</svg>";
  }

  function mobileNav() {
    return window.matchMedia("(max-width: 959px)").matches;
  }

  function setNavOpen(open) {
    var show = !!open && mobileNav() && document.body.classList.contains("is-admin");
    document.body.classList.toggle("nav-open", show);
    if (navToggle) {
      navToggle.setAttribute("aria-expanded", show ? "true" : "false");
      navToggle.setAttribute("aria-label", show ? "Close menu" : "Open menu");
    }
    if (navScrim) navScrim.hidden = !show;
    if (sidebarEl) sidebarEl.inert = !document.body.classList.contains("is-admin") || (mobileNav() && !show);
    if (show && sideNav) {
      var first = sideNav.querySelector("a");
      if (first) first.focus();
    }
  }

  function setChrome(mode) {
    var admin = mode === "admin";
    document.body.classList.toggle("is-admin", admin);
    if (!admin) {
      navPainted = "";
      if (sideNav) sideNav.innerHTML = "";
      setNavOpen(false);
      return;
    }
    if (sidebarEl) sidebarEl.inert = mobileNav() && !document.body.classList.contains("nav-open");
  }

  function wireAdminChrome() {
    if (navToggle) navToggle.addEventListener("click", function () {
      setNavOpen(!document.body.classList.contains("nav-open"));
    });
    if (navScrim) navScrim.addEventListener("click", function () { setNavOpen(false); });
    document.addEventListener("keydown", function (event) {
      if (event.key === "Escape" && document.body.classList.contains("nav-open")) {
        setNavOpen(false);
        if (navToggle) navToggle.focus();
      }
    });
    if (sideNav) sideNav.addEventListener("click", function (event) {
      if (event.target.closest && event.target.closest("a")) setNavOpen(false);
    });
    window.addEventListener("resize", function () {
      if (!mobileNav()) setNavOpen(false);
    });
  }

  function paintNav() {
    if (!sideNav) return;
    var current = route().name;
    var active = current === "customer" ? "customers" : current;
    if (navPainted === active && sideNav.childElementCount) return;
    navPainted = active;
    sideNav.innerHTML = NAV_GROUPS.map(function (group) {
      var links = group[1].map(function (item) {
        var on = item[0] === active;
        return "<a href=\"#" + item[0] + "\"" + (on ? " class=\"active\" aria-current=\"page\"" : "") + ">" +
          iconSvg(item[2], "nav-icon") + "<span>" + item[1] + "</span></a>";
      }).join("");
      return "<p class=\"nav-label\">" + group[0] + "</p>" + links;
    }).join("");
  }

  function shell(body) {
    setChrome("admin");
    paintNav();
    var current = route().name;
    if (pageTitle) pageTitle.textContent = PAGE_TITLES[current] || "Dashboard";
    app.innerHTML = "<div id=\"flash\" class=\"flash\" role=\"status\" aria-live=\"polite\" hidden></div>" + body;
  }

  function renderSignedOut() {
    setChrome("guest");
    if (who) who.innerHTML = "";
    if (pageTitle) pageTitle.textContent = "Sign in";
    app.innerHTML = "<section class=\"panel sign-panel\"><picture><source type=\"image/webp\" srcset=\"/assets/img/fiberbro-logo.webp?v=20261107a\"><img class=\"sign-logo\" src=\"/assets/img/fiberbro-logo.png?v=20261107a\" width=\"1600\" height=\"501\" alt=\"FiberBro Internet Communication Services Corp.\"></picture><h1>FiberBro admin</h1><p>Sign in with the company Gmail account. Only emails on the admin allowlist can open records.</p><button type=\"button\" class=\"btn\" id=\"sign-in\">Sign in with Google</button></section>";
    document.getElementById("sign-in").onclick = function () {
      db.auth.signInWithOAuth({
        provider: "google",
        options: { redirectTo: location.origin + "/admin/" }
      });
    };
  }

  function renderDenied() {
    setChrome("guest");
    if (pageTitle) pageTitle.textContent = "FiberBro";
    who.innerHTML = "<span class=\"who-email\">" + esc(sessionEmail) + "</span><button type=\"button\" class=\"btn secondary\" id=\"sign-out\">Sign out</button>";
    app.innerHTML = "<section class=\"panel\"><h1>This Google account is not an admin</h1><p>" + esc(sessionEmail) + " can sign in, but it is not on the allowlist. Ask an existing admin to add it under Admins, or add the address in the Supabase <code>admins</code> table.</p></section>";
    document.getElementById("sign-out").onclick = signOut;
  }

  function signOut() {
    db.auth.signOut().then(function () { sessionEmail = ""; renderSignedOut(); });
  }

  function customerMatches(row) {
    if (ui.stage !== "all" && row.stage !== ui.stage) return false;
    if (ui.area && (row.area || "") !== ui.area) return false;
    if (!ui.q) return true;
    var blob = [row.name, row.first_name, row.last_name, row.account_number, row.mobile, row.contact_number, row.address, row.area, row.plan].join(" ").toLowerCase();
    return blob.indexOf(ui.q) !== -1;
  }

  function renderCustomers() {
    var areas = [];
    state.customers.forEach(function (row) {
      if (row.area && areas.indexOf(row.area) === -1) areas.push(row.area);
    });
    areas.sort();
    var counts = { all: state.customers.length };
    STAGES.forEach(function (stage) { counts[stage.id] = 0; });
    state.customers.forEach(function (row) { if (counts[row.stage] != null) counts[row.stage] += 1; });
    var tabs = "<button type=\"button\" data-stage=\"all\"" + (ui.stage === "all" ? " class=\"active\"" : "") + "><strong>" + counts.all + "</strong>All</button>" +
      STAGES.map(function (stage) {
        return "<button type=\"button\" data-stage=\"" + stage.id + "\"" + (ui.stage === stage.id ? " class=\"active\"" : "") + "><strong>" + counts[stage.id] + "</strong>" + esc(stage.label) + "</button>";
      }).join("");
    var areaOptions = "<option value=\"\">All areas</option>" + areas.map(function (area) {
      return "<option value=\"" + esc(area) + "\"" + (ui.area === area ? " selected" : "") + ">" + esc(area) + "</option>";
    }).join("");
    var rows = state.customers.filter(customerMatches).map(function (row) {
      var title = row.name || ((row.first_name || "") + " " + (row.last_name || "")).trim() || "Unnamed";
      return "<a class=\"row-card\" href=\"#customer/" + row.id + "\"><strong>" + esc(title) + "</strong><span class=\"meta\">" +
        esc(row.area || "No area") + " · " + esc(row.mobile || row.contact_number || "No mobile") + " · " + esc(investorName(row.investor_id) || "No investor") +
        "</span><div><span class=\"tag tag-" + esc(row.stage) + "\">" + esc(stageLabel(row.stage)) + "</span>" +
        ((row.valid_id_path || row.valid_id_drive_url) ? " <span class=\"tag\">ID</span>" : "") +
        "</div></a>";
    }).join("");
    shell(
      "<div class=\"toolbar\"><button type=\"button\" class=\"btn\" id=\"add-customer\">Add customer</button></div>" +
      "<div class=\"tabs\">" + tabs + "</div>" +
      "<div class=\"filters\"><input id=\"q\" placeholder=\"Search name, account, mobile, address\" value=\"" + esc(ui.q) + "\">" +
      "<select id=\"area\">" + areaOptions + "</select></div>" +
      "<div class=\"list\">" + (rows || "<p class=\"muted\">No customers in this view.</p>") + "</div>"
    );
    document.getElementById("q").addEventListener("input", function (event) {
      ui.q = event.target.value.trim().toLowerCase();
      renderCustomers();
      var box = document.getElementById("q");
      if (box) { box.focus(); box.selectionStart = box.selectionEnd = box.value.length; }
    });
    document.getElementById("area").addEventListener("change", function (event) {
      ui.area = event.target.value;
      renderCustomers();
    });
    app.querySelectorAll(".tabs button").forEach(function (button) {
      button.onclick = function () { ui.stage = button.getAttribute("data-stage"); renderCustomers(); };
    });
    document.getElementById("add-customer").onclick = function () { go("customer/new"); };
  }

  function inputHtml(field, customer) {
    var key = field[0];
    var label = field[1];
    var type = field[2];
    var value = customer[key];
    if (key === "email_address" && !value && customer.email) value = customer.email;
    var id = "f-" + key;
    if (key === "account_number" && !customer.id) {
      return "<div class=\"field\"><label for=\"" + id + "\">Account Number</label><input id=\"" + id + "\" data-key=\"account_number\" data-type=\"text\" type=\"text\" placeholder=\"Auto (next number)\" value=\"\"></div>";
    }
    if (type === "bool") {
      return "<div class=\"field check\"><input id=\"" + id + "\" data-key=\"" + key + "\" data-type=\"bool\" type=\"checkbox\"" + (value ? " checked" : "") + "><label for=\"" + id + "\">" + esc(label) + "</label></div>";
    }
    if (type === "investor") {
      var options = "<option value=\"\">Select an investor</option>";
      var list = sortedInvestors(customer.area, value);
      var sawMatchHeader = false;
      var sawOtherHeader = false;
      var needle = (customer.area || "").trim().toLowerCase();
      list.forEach(function (inv) {
        var match = needle && (inv.areas || []).some(function (item) {
          return String(item).trim().toLowerCase() === needle;
        });
        if (match && inv.active && !sawMatchHeader) {
          options += "<optgroup label=\"Matching area\">";
          sawMatchHeader = true;
        }
        if ((!match || !inv.active) && sawMatchHeader && !sawOtherHeader) {
          options += "</optgroup><optgroup label=\"Other investors\">";
          sawOtherHeader = true;
        }
        var suffix = inv.active ? "" : " (inactive)";
        options += "<option value=\"" + inv.id + "\"" + (inv.id === value ? " selected" : "") + ">" + esc(investorLabel(inv) + suffix) + "</option>";
      });
      if (sawMatchHeader || sawOtherHeader) options += "</optgroup>";
      return "<div class=\"field\"><label for=\"" + id + "\">" + esc(label) + "</label><select id=\"" + id + "\" data-key=\"" + key + "\" data-type=\"investor\">" + options + "</select><span class=\"muted\">Matching area is listed first. Any active investor can be chosen.</span></div>";
    }
    if (key === "facebook_name") {
      var inbox = customer.messenger && String(customer.messenger).trim().indexOf("http") === 0 ? String(customer.messenger).trim() : "";
      return "<div class=\"field\"><label for=\"" + id + "\">" + esc(label) + "</label>" +
        "<div class=\"name-with-action\">" +
        "<input id=\"" + id + "\" data-key=\"facebook_name\" data-type=\"text\" type=\"text\" value=\"" + esc(value || "") + "\">" +
        "<a id=\"messenger-open\" class=\"btn secondary messenger-open\" href=\"" + esc(inbox || "#") + "\" target=\"_blank\" rel=\"noopener\"" + (inbox ? "" : " hidden") + ">Open Messenger inbox</a>" +
        "</div></div>";
    }
    var control = "";
    if (type === "textarea") {
      control = "<textarea id=\"" + id + "\" data-key=\"" + key + "\" data-type=\"text\">" + esc(value || "") + "</textarea>";
    } else if (type === "datetime") {
      control = "<input id=\"" + id + "\" data-key=\"" + key + "\" data-type=\"datetime\" type=\"datetime-local\" value=\"" + esc(toLocalInput(value)) + "\">";
    } else if (type === "date") {
      control = "<input id=\"" + id + "\" data-key=\"" + key + "\" data-type=\"date\" type=\"date\" value=\"" + esc(value ? String(value).slice(0, 10) : "") + "\">";
    } else if (type === "money" || type === "int" || type === "float") {
      control = "<input id=\"" + id + "\" data-key=\"" + key + "\" data-type=\"" + type + "\" type=\"number\" step=\"" + (type === "float" ? "any" : (type === "int" ? "1" : "0.01")) + "\" value=\"" + esc(value == null ? "" : value) + "\">";
    } else {
      var htmlType = type === "email" || type === "url" ? type : "text";
      control = "<input id=\"" + id + "\" data-key=\"" + key + "\" data-type=\"text\" type=\"" + htmlType + "\" value=\"" + esc(value || "") + "\">";
    }
    var open = type === "url" && value ? " <a href=\"" + esc(value) + "\" target=\"_blank\" rel=\"noopener\">Open</a>" : "";
    var hint = key === "pppoe" ? "<span class=\"muted\">Auto-filled from investor code and name. You can edit it.</span>" : "";
    return "<div class=\"field\"><label for=\"" + id + "\">" + esc(label) + open + "</label>" + control + hint + "</div>";
  }

  function toLocalInput(value) {
    if (!value) return "";
    var date = new Date(value);
    if (isNaN(date.getTime())) return "";
    function pad(n) { return (n < 10 ? "0" : "") + n; }
    return date.getFullYear() + "-" + pad(date.getMonth() + 1) + "-" + pad(date.getDate()) + "T" + pad(date.getHours()) + ":" + pad(date.getMinutes());
  }

  function readForm() {
    var payload = {};
    app.querySelectorAll("[data-key]").forEach(function (el) {
      var key = el.getAttribute("data-key");
      var type = el.getAttribute("data-type");
      if (type === "bool") {
        payload[key] = el.checked;
        return;
      }
      var raw = el.value.trim();
      if (!raw) {
        payload[key] = null;
        return;
      }
      if (type === "money" || type === "int" || type === "float") payload[key] = Number(raw);
      else if (type === "datetime") payload[key] = new Date(raw).toISOString();
      else payload[key] = raw;
    });
    return payload;
  }

  function pesoAmount(value) {
    if (value == null || value === "") return "";
    var num = Number(value);
    if (isNaN(num)) return String(value);
    return num.toLocaleString("en-PH", { maximumFractionDigits: 2 });
  }

  function typeClass(planType) {
    var known = { Basic: "basic", Plus: "plus", Max: "max" };
    return known[planType] || "other";
  }

  function typeFromPlan(plan) {
    var speed = speedFromPlan(plan);
    if (speed.indexOf("75") === 0) return "Basic";
    if (speed.indexOf("150") === 0) return "Plus";
    if (speed.indexOf("200") === 0) return "Max";
    for (var i = 0; i < FIBER_PLANS.length; i++) {
      if (FIBER_PLANS[i].value === plan) return FIBER_PLANS[i].type;
    }
    return "";
  }

  function speedFromPlan(plan) {
    var match = String(plan || "").match(/^\s*(\d+)\s*[–-]\s*(\d+)\s*Mbps/i);
    if (!match) return "";
    return match[1] + "–" + match[2] + " Mbps";
  }

  function priceFromPlan(plan) {
    var match = String(plan || "").match(/₱\s*([\d,]+(?:\.\d+)?)/);
    if (!match) return "";
    var num = Number(match[1].replace(/,/g, ""));
    return isNaN(num) ? "" : num;
  }

  function planSummaryHtml(planValue, speed, price, planType) {
    var match = null;
    for (var i = 0; i < FIBER_PLANS.length; i++) {
      if (FIBER_PLANS[i].value === planValue) match = FIBER_PLANS[i];
    }
    var badge = speed || speedFromPlan(planValue) || (match ? match.speed : "") || "No plan";
    var amount = price === "" || price == null ? priceFromPlan(planValue) : price;
    if (amount === "" || amount == null) amount = match ? match.price : "";
    var priceText = amount === "" || amount == null ? "—" : ("₱" + pesoAmount(amount) + " / month");
    var chip = planType
      ? "<span class=\"status-chip status-" + typeClass(planType) + "\">" + esc(planType) + "</span>"
      : "<span class=\"status-chip status-blank\">No type</span>";
    return "<div class=\"plan-summary-row\"><span class=\"plan-pill\">" + esc(badge) + "</span>" +
      "<strong class=\"plan-price\">" + esc(priceText) + "</strong>" + chip + "</div>" +
      "<p class=\"muted plan-install\">One-time installation: ₱1,000</p>";
  }

  function planBySpeed(speed) {
    for (var i = 0; i < FIBER_PLANS.length; i++) {
      if (FIBER_PLANS[i].speed === speed) return FIBER_PLANS[i];
    }
    return null;
  }

  function planSectionHtml(customer) {
    var saved = customer.plan || "";
    var speed = customer.plan_speed || speedFromPlan(saved);
    var mapped = planBySpeed(speed);
    var price = customer.price == null || customer.price === ""
      ? (mapped ? mapped.price : priceFromPlan(saved))
      : customer.price;
    var planType = customer.plan_type || (mapped ? mapped.type : typeFromPlan(saved));
    var knownSpeed = false;
    var speedOptions = "<option value=\"\"></option>";
    FIBER_PLANS.forEach(function (item) {
      if (speed === item.speed) knownSpeed = true;
      speedOptions += "<option value=\"" + esc(item.speed) + "\"" + (speed === item.speed ? " selected" : "") + ">" + esc(item.speed) + "</option>";
    });
    if (speed && !knownSpeed) speedOptions += "<option value=\"" + esc(speed) + "\" selected>" + esc(speed) + "</option>";
    var inquiryLine = saved ? "<p class=\"muted plan-inquiry\">From inquiry: " + esc(saved) + "</p>" : "";
    return "<div class=\"plan-summary\" id=\"plan-summary\" data-inquiry=\"" + esc(saved) + "\">" +
      planSummaryHtml(saved, speed, price, planType) + "</div>" + inquiryLine +
      "<div class=\"grid two\">" +
      "<div class=\"field\"><label for=\"f-plan_speed\">Plan Speed</label><select id=\"f-plan_speed\" data-key=\"plan_speed\" data-type=\"text\">" + speedOptions + "</select></div>" +
      "<div class=\"field\"><span class=\"field-label\">Price</span><p class=\"plan-readonly\" id=\"plan-price-display\">" + esc(price === "" || price == null ? "—" : ("₱" + pesoAmount(price))) + "</p>" +
      "<input type=\"hidden\" id=\"f-price\" data-key=\"price\" data-type=\"money\" value=\"" + esc(price) + "\"></div>" +
      "<div class=\"field\"><span class=\"field-label\">Plan Type</span><p class=\"plan-readonly\" id=\"plan-type-display\">" + esc(planType || "—") + "</p>" +
      "<input type=\"hidden\" id=\"f-plan_type\" data-key=\"plan_type\" data-type=\"text\" value=\"" + esc(planType) + "\"></div>" +
      "</div>";
  }

  function refreshPlanSummary() {
    var summary = document.getElementById("plan-summary");
    var speed = document.getElementById("f-plan_speed");
    var price = document.getElementById("f-price");
    var planType = document.getElementById("f-plan_type");
    var priceText = document.getElementById("plan-price-display");
    var typeText = document.getElementById("plan-type-display");
    var speedVal = speed ? speed.value : "";
    var priceVal = price ? price.value : "";
    var typeVal = planType ? planType.value : "";
    if (summary) {
      summary.innerHTML = planSummaryHtml(summary.getAttribute("data-inquiry") || "", speedVal, priceVal, typeVal);
    }
    if (priceText) priceText.textContent = priceVal === "" ? "—" : ("₱" + pesoAmount(priceVal));
    if (typeText) typeText.textContent = typeVal || "—";
  }

  function wirePlan() {
    var speed = document.getElementById("f-plan_speed");
    var price = document.getElementById("f-price");
    var planType = document.getElementById("f-plan_type");
    if (!speed) return;
    speed.onchange = function () {
      var chosen = planBySpeed(speed.value);
      if (chosen) {
        if (price) price.value = String(chosen.price);
        if (planType) planType.value = chosen.type;
      }
      refreshPlanSummary();
    };
  }

  function formCard(title, body) {
    return "<section class=\"panel section-card\">" +
      "<button type=\"button\" class=\"section-toggle\" aria-expanded=\"true\">" +
      "<span>" + esc(title) + "</span><span class=\"chevron\" aria-hidden=\"true\"></span></button>" +
      "<div class=\"section-body\"><div class=\"section-body-inner\">" + body + "</div></div></section>";
  }

  function renderCustomer(customer, isNew) {
    var sections = SECTIONS.map(function (section) {
      var body = section.title === "Plan"
        ? planSectionHtml(customer)
        : "<div class=\"grid two\">" + section.fields.map(function (field) { return inputHtml(field, customer); }).join("") + "</div>";
      if (section.title === "Location and Network") {
        body += "<p><button type=\"button\" class=\"btn secondary\" id=\"pick-map\">Pick on map</button></p><div id=\"customer-mini-map\" class=\"mini-map\"></div>";
      }
      return formCard(section.title, body);
    }).join("");
    var history = state.events.map(function (event) {
      return "<li>" + esc(stageLabel(event.stage)) + " · " + esc(event.changed_by) + " · " + esc(new Date(event.changed_at).toLocaleString()) + "</li>";
    }).join("");
    var actions = "";
    if (!isNew && customer.stage === "inquiry") {
      actions += "<p class=\"muted\">Select an investor to move to In Progress.</p>";
    }
    if (!isNew && customer.stage === "in_progress") {
      actions += "<button type=\"button\" class=\"btn\" data-next=\"encoded\">Mark encoded in MikroTik</button>";
    }
    if (!isNew && customer.stage === "encoded") {
      actions += "<button type=\"button\" class=\"btn\" data-next=\"active\">Mark Active</button>";
      actions += "<span class=\"muted\">This creates the technician ticket.</span>";
    }
    if (!isNew && customer.stage === "active") {
      var ticketTech = state.ticket ? (techName(state.ticket.technician_id) || "Unassigned") : "No ticket yet";
      var ticketStatus = state.ticket ? state.ticket.status : "";
      actions += "<p class=\"muted\">Ticket: " + esc(ticketTech) + (ticketStatus ? " · " + esc(ticketStatus) : "") + "</p>";
      var techOptions = "<option value=\"\">Select technician</option>" + state.technicians.filter(function (tech) {
        return tech.active || (state.ticket && state.ticket.technician_id === tech.id);
      }).map(function (tech) {
        var selected = state.ticket && state.ticket.technician_id === tech.id ? " selected" : "";
        return "<option value=\"" + tech.id + "\"" + selected + ">" + esc(tech.name) + (tech.active ? "" : " (inactive)") + "</option>";
      }).join("");
      actions += "<select id=\"assign-tech\">" + techOptions + "</select><button type=\"button\" class=\"btn copper\" id=\"assign-ticket\">Assign ticket</button>";
    }
    var idBits = "<div class=\"field\"><label for=\"f-valid_id_type\">Valid ID type</label>" +
      "<input id=\"f-valid_id_type\" data-key=\"valid_id_type\" data-type=\"text\" type=\"text\" value=\"" +
      esc(customer.valid_id_type || "") + "\"></div>";
    if (!isNew && customer.valid_id_drive_url) {
      idBits += "<p><a href=\"" + esc(customer.valid_id_drive_url) + "\" target=\"_blank\" rel=\"noopener\">Open in Google Drive</a></p>";
    }
    if (!isNew && customer.valid_id_path) idBits += "<div id=\"valid-id-photo\"><p class=\"muted\">Loading photo…</p></div>";
    if (isNew || (!customer.valid_id_path && !customer.valid_id_drive_url)) idBits += "<p>No ID uploaded</p>";
    var idBlock = formCard("Valid ID", idBits);
    var heading = isNew ? "New customer" : (customer.name || ((customer.first_name || "") + " " + (customer.last_name || "")).trim() || "Customer");
    var accountNo = customer.account_number || (isNew ? "Auto" : "—");
    shell(
      "<section class=\"customer-sticky panel\">" +
      "<a class=\"back-link\" href=\"#customers\">Back to customers</a>" +
      "<div class=\"customer-id\"><h1>" + esc(heading) + "</h1>" +
      "<p>" + (isNew ? "" : "<span class=\"tag\">" + esc(stageLabel(customer.stage)) + "</span> ") +
      "<span class=\"acct\">Account " + esc(accountNo) + "</span></p></div>" +
      "<div class=\"actions\">" + actions + "<button type=\"button\" class=\"btn\" id=\"save-customer\">Save</button></div>" +
      "</section>" +
      (history ? formCard("Stage history", "<ul class=\"history\">" + history + "</ul>") : "") +
      sections +
      idBlock +
      (isNew ? "" : billsCard(customer)) +
      (isNew ? "" : formCard("Change history", state.changeError
        ? "<p class=\"muted\">" + esc(state.changeError) + "</p>"
        : changeHistoryHtml(state.changes)))
    );
    var area = document.getElementById("f-area");
    if (area) area.addEventListener("input", function () {
      customer.area = area.value;
      var select = document.getElementById("f-investor_id");
      if (!select) return;
      var current = select.value;
      var holder = document.createElement("div");
      holder.innerHTML = inputHtml(["investor_id", "Investor", "investor"], customer);
      select.innerHTML = holder.querySelector("select").innerHTML;
      select.value = current;
      wirePppoe();
    });
    lastAutoPppoe = "";
    wirePppoe();
    wirePlan();
    var generatedPppoe = buildPppoe();
    var pppoeInput = document.getElementById("f-pppoe");
    if (pppoeInput && generatedPppoe && pppoeInput.value.trim().toUpperCase() === generatedPppoe) lastAutoPppoe = generatedPppoe;
    if (!isNew && customer.valid_id_path) loadValidIdPhoto(customer.valid_id_path);
    initCustomerMiniMap();
    wireQuickBill(customer);
    var messengerInput = document.getElementById("f-messenger");
    var messengerOpen = document.getElementById("messenger-open");
    if (messengerInput && messengerOpen) {
      messengerInput.addEventListener("input", function () {
        var link = messengerInput.value.trim();
        if (link.indexOf("http") === 0) {
          messengerOpen.href = link;
          messengerOpen.hidden = false;
        } else {
          messengerOpen.hidden = true;
        }
      });
    }
    document.getElementById("save-customer").onclick = function () { saveCustomer(customer, isNew); };
    var next = app.querySelector("[data-next]");
    if (next) next.onclick = function () { moveStage(customer, next.getAttribute("data-next")); };
    var assign = document.getElementById("assign-ticket");
    if (assign) assign.onclick = function () { assignTicket(customer); };
  }

  function loadValidIdPhoto(path) {
    var box = document.getElementById("valid-id-photo");
    if (!box || !db) return;
    db.storage.from("valid-ids").createSignedUrl(path, 3600).then(function (result) {
      if (!box.parentNode) return;
      var url = result && result.data && result.data.signedUrl;
      if ((result && result.error) || !url) {
        box.innerHTML = "<p class=\"muted\">Could not load the ID photo.</p>";
        return;
      }
      box.innerHTML = "<p><img class=\"id-thumb\" src=\"" + esc(url) + "\" alt=\"Valid ID photo\"></p>" +
        "<p><a href=\"" + esc(url) + "\" target=\"_blank\" rel=\"noopener\">Open full size</a></p>";
    }).catch(function () {
      if (box.parentNode) box.innerHTML = "<p class=\"muted\">Could not load the ID photo.</p>";
    });
  }

  function saveCustomer(customer, isNew) {
    var payload = readForm();
    if (payload.first_name || payload.last_name) {
      var parts = [];
      if (payload.first_name) parts.push(payload.first_name);
      if (payload.middle_initial) parts.push(payload.middle_initial);
      if (payload.last_name) parts.push(payload.last_name);
      if (!payload.name) payload.name = parts.join(" ");
    }
    var query;
    if (!payload.account_number) delete payload.account_number;
    if (isNew) {
      delete payload.stage;
      payload.source = "admin";
      query = db.from("customers").insert(payload).select("id").single();
    } else {
      query = db.from("customers").update(payload).eq("id", customer.id);
    }
    query.then(function (result) {
      if (result.error) return flash(errText(result.error));
      flash("Saved.", true);
      if (isNew && result.data) go("customer/" + result.data.id);
      else loadCustomer(customer.id);
    });
  }

  function moveStage(customer, next) {
    var payload = readForm();
    payload.stage = next;
    db.from("customers").update(payload).eq("id", customer.id).then(function (result) {
      if (result.error) return flash(errText(result.error));
      flash("Stage updated.", true);
      loadCustomer(customer.id);
    });
  }

  function assignTicket(customer) {
    var techId = document.getElementById("assign-tech").value;
    if (!techId) return flash("Choose a technician.");
    var write = state.ticket
      ? db.from("tickets").update({ technician_id: techId, assigned_by: sessionEmail }).eq("id", state.ticket.id)
      : db.from("tickets").insert({ customer_id: customer.id, technician_id: techId, assigned_by: sessionEmail });
    write.then(function (result) {
      if (result.error) return flash(errText(result.error));
      flash("Ticket assigned.", true);
      loadCustomer(customer.id);
    });
  }

  function renderPeople(kind) {
    var rows = kind === "investors" ? state.investors.slice().sort(compareInvestors) : state[kind];
    var title = kind === "investors" ? "Investors" : "Technicians";
    var body = rows.map(function (row) {
      var extra = kind === "investors" ? esc((row.areas || []).join(", ")) : esc(row.mobile || row.email || "");
      var nameCell = kind === "investors" && row.code
        ? "<span class=\"tag\">" + esc(row.code) + "</span> " + esc(row.name)
        : esc(row.name);
      return "<tr><td data-label=\"Name\">" + nameCell + "</td><td data-label=\"Details\">" + extra + "</td><td data-label=\"Status\">" +
        (row.active ? "<span class=\"tag\">Active</span>" : "<span class=\"tag off\">Inactive</span>") +
        "</td><td data-label=\"\"><button type=\"button\" class=\"btn secondary\" data-edit=\"" + row.id + "\">Edit</button></td></tr>";
    }).join("");
    var form = kind === "investors"
      ? "<input id=\"p-name\" placeholder=\"Name\" required><input id=\"p-code\" class=\"code-input\" placeholder=\"e.g. AN\" maxlength=\"16\" autocapitalize=\"characters\"><input id=\"p-areas\" placeholder=\"Areas, comma separated\"><textarea id=\"p-notes\" placeholder=\"Notes\"></textarea>"
      : "<input id=\"p-name\" placeholder=\"Name\" required><input id=\"p-mobile\" placeholder=\"Mobile\"><input id=\"p-email\" placeholder=\"Email\"><textarea id=\"p-notes\" placeholder=\"Notes\"></textarea>";
    shell(
      "<section class=\"panel\"><h1>" + title + "</h1><form id=\"person-form\" class=\"grid\">" + form +
      "<label class=\"field check\"><input id=\"p-active\" type=\"checkbox\" checked> Active</label>" +
      "<input type=\"hidden\" id=\"p-id\"><div class=\"actions\"><button class=\"btn\" type=\"submit\">Save</button><button class=\"btn secondary\" type=\"button\" id=\"p-clear\">Clear</button></div></form></section>" +
      "<div class=\"table-card\"><table><thead><tr><th>Name</th><th>Details</th><th>Status</th><th></th></tr></thead><tbody>" + (body || "<tr><td colspan=\"4\">No records yet.</td></tr>") + "</tbody></table></div>"
    );
    document.getElementById("person-form").onsubmit = function (event) {
      event.preventDefault();
      var id = document.getElementById("p-id").value;
      var record = {
        name: document.getElementById("p-name").value.trim(),
        notes: document.getElementById("p-notes").value.trim() || null,
        active: document.getElementById("p-active").checked
      };
      if (!record.name) return flash("Name is required.");
      if (kind === "investors") {
        record.areas = document.getElementById("p-areas").value.split(",").map(function (part) { return part.trim(); }).filter(Boolean);
        var code = document.getElementById("p-code").value.trim().toUpperCase();
        record.code = code || null;
      } else {
        record.mobile = document.getElementById("p-mobile").value.trim() || null;
        record.email = document.getElementById("p-email").value.trim() || null;
      }
      var query = id ? db.from(kind).update(record).eq("id", id) : db.from(kind).insert(record);
      query.then(function (result) {
        if (result.error) {
          var errCode = result.error.code || "";
          var errBlob = (result.error.message || "") + " " + (result.error.details || "");
          if (errCode === "23505" || errBlob.indexOf("23505") !== -1 || errBlob.indexOf("investors_code_key") !== -1) {
            return flash("That investor code is already used.");
          }
          return flash(errText(result.error));
        }
        flash("Saved.", true);
        refresh().then(render);
      });
    };
    document.getElementById("p-clear").onclick = function () { renderPeople(kind); };
    app.querySelectorAll("[data-edit]").forEach(function (button) {
      button.onclick = function () {
        var row = rows.filter(function (item) { return item.id === button.getAttribute("data-edit"); })[0];
        if (!row) return;
        document.getElementById("p-id").value = row.id;
        document.getElementById("p-name").value = row.name || "";
        document.getElementById("p-notes").value = row.notes || "";
        document.getElementById("p-active").checked = !!row.active;
        if (kind === "investors") {
          document.getElementById("p-areas").value = (row.areas || []).join(", ");
          document.getElementById("p-code").value = row.code || "";
        }
        else {
          document.getElementById("p-mobile").value = row.mobile || "";
          document.getElementById("p-email").value = row.email || "";
        }
      };
    });
  }

  function renderTickets() {
    var body = state.tickets.map(function (ticket) {
      var customer = null;
      for (var i = 0; i < state.customers.length; i++) if (state.customers[i].id === ticket.customer_id) customer = state.customers[i];
      var name = customer ? (customer.name || customer.account_number || "Customer") : ticket.customer_id;
      return "<tr><td data-label=\"Customer\"><a href=\"#customer/" + ticket.customer_id + "\">" + esc(name) + "</a></td><td data-label=\"Stage\">" +
        esc(customer ? stageLabel(customer.stage) : "") + "</td><td data-label=\"Technician\">" + esc(techName(ticket.technician_id) || "Unassigned") +
        "</td><td data-label=\"Status\">" + statusPill(ticket.status) + "</td><td data-label=\"Assigned\">" + esc(ticket.assigned_by || "") + "</td></tr>";
    }).join("");
    shell("<section class=\"panel\"><h1>Install tickets</h1><p class=\"muted\">A ticket is created when an admin marks the customer Active. Assigning a technician updates the ticket only.</p></section>" +
      "<div class=\"table-card\"><table><thead><tr><th>Customer</th><th>Stage</th><th>Technician</th><th>Status</th><th>Assigned by</th></tr></thead><tbody>" +
      (body || "<tr><td colspan=\"5\">No tickets yet.</td></tr>") + "</tbody></table></div>");
  }

  function renderAdmins() {
    var body = state.admins.map(function (row) {
      return "<tr><td data-label=\"Email\">" + esc(row.email) + "</td><td data-label=\"\"><button type=\"button\" class=\"btn secondary\" data-remove=\"" + row.id + "\">Remove</button></td></tr>";
    }).join("");
    shell("<section class=\"panel\"><h1>Admins</h1><p class=\"muted\">Only these Gmail addresses can use the portal. The check is in the database, not only on this page.</p>" +
      "<form id=\"admin-form\" class=\"toolbar\"><input id=\"admin-email\" type=\"email\" placeholder=\"name@gmail.com\" required><button class=\"btn\" type=\"submit\">Add admin</button></form></section>" +
      "<div class=\"table-card\"><table><thead><tr><th>Email</th><th></th></tr></thead><tbody>" + (body || "<tr><td colspan=\"2\">No admins yet.</td></tr>") + "</tbody></table></div>");
    document.getElementById("admin-form").onsubmit = function (event) {
      event.preventDefault();
      var email = document.getElementById("admin-email").value.trim().toLowerCase();
      db.from("admins").insert({ email: email }).then(function (result) {
        if (result.error) return flash(errText(result.error));
        refresh().then(render);
      });
    };
    app.querySelectorAll("[data-remove]").forEach(function (button) {
      button.onclick = function () {
        var row = state.admins.filter(function (item) { return item.id === button.getAttribute("data-remove"); })[0];
        if (!row) return;
        if (row.email === sessionEmail.toLowerCase()) return flash("You cannot remove the account you are signed in with.");
        db.from("admins").delete().eq("id", row.id).then(function (result) {
          if (result.error) return flash(errText(result.error));
          refresh().then(render);
        });
      };
    });
  }

  function refresh() {
    return Promise.all([
      db.from("customers").select("*").order("created_at", { ascending: false }),
      db.from("investors").select("*").order("name"),
      db.from("technicians").select("*").order("name"),
      db.from("tickets").select("*").order("created_at", { ascending: false }),
      db.from("admins").select("*").order("email")
    ]).then(function (results) {
      var names = ["customers", "investors", "technicians", "tickets", "admins"];
      for (var i = 0; i < results.length; i++) {
        if (results[i].error) throw results[i].error;
        state[names[i]] = results[i].data || [];
      }
    });
  }

  function loadCustomer(id) {
    var gen = viewGen;
    return Promise.all([
      db.from("customers").select("*").eq("id", id).single(),
      db.from("customer_stage_events").select("*").eq("customer_id", id).order("changed_at"),
      db.from("tickets").select("*").eq("customer_id", id).maybeSingle(),
      db.from("customer_change_log").select("*").eq("customer_id", id).order("changed_at", { ascending: true }),
      db.from("invoices").select("*").eq("customer_id", id).order("period", { ascending: false }),
      db.from("payments").select("*").eq("customer_id", id).order("submitted_at", { ascending: false })
    ]).then(function (results) {
      if (results[0].error) throw results[0].error;
      if (gen !== viewGen) return;
      state.customer = results[0].data;
      state.events = results[1].data || [];
      state.ticket = results[2].data || null;
      state.changes = results[3].error ? [] : (results[3].data || []);
      state.changeError = results[3].error ? errText(results[3].error) : "";
      state.invoices = results[4] && !results[4].error ? (results[4].data || []) : [];
      state.pays = results[5] && !results[5].error ? (results[5].data || []) : [];
      renderCustomer(state.customer, false);
    }).catch(function (error) { flash(errText(error)); });
  }

  function statusPill(status) {
    var key = String(status || "").toLowerCase();
    var known = {
      unpaid: 1, pending: 1, paid: 1, void: 1,
      confirmed: 1, rejected: 1,
      open: 1, assigned: 1, closed: 1,
      low: 1, normal: 1, high: 1,
      ongoing: 1, resolved: 1
    };
    if (!known[key]) return esc(status || "");
    return "<span class=\"status-pill status-" + key + "\">" + esc(key) + "</span>";
  }

  function money(amount) {
    var num = Number(amount);
    if (isNaN(num)) return "—";
    return "₱" + num.toLocaleString("en-PH", { maximumFractionDigits: 2 });
  }

  function manilaPeriod(value) {
    var date = value ? new Date(value) : new Date();
    if (isNaN(date.getTime())) return "";
    return new Intl.DateTimeFormat("en-CA", {
      timeZone: "Asia/Manila",
      year: "numeric",
      month: "2-digit"
    }).format(date).slice(0, 7);
  }

  var viewGen = 0;

  function customerChoices() {
    return state.customers.map(function (row) {
      var label = (row.account_number ? row.account_number + " · " : "") + (row.name || row.first_name || "Customer");
      return "<option value=\"" + row.id + "\">" + esc(label) + "</option>";
    }).join("");
  }

  function barChart(pairs) {
    var max = 1;
    pairs.forEach(function (pair) { if (pair[1] > max) max = pair[1]; });
    var width = 360;
    var rowH = 36;
    var height = pairs.length * rowH + 4;
    var bars = pairs.map(function (pair, index) {
      var w = Math.round((pair[1] / max) * 168);
      var y = 6 + index * rowH;
      return "<text class=\"chart-label\" x=\"0\" y=\"" + (y + 16) + "\">" + esc(pair[0]) + "</text>" +
        "<rect x=\"112\" y=\"" + (y + 4) + "\" width=\"168\" height=\"12\" rx=\"6\" fill=\"#EEF0F3\"></rect>" +
        "<rect x=\"112\" y=\"" + (y + 4) + "\" width=\"" + (pair[1] ? Math.max(w, 8) : 0) + "\" height=\"12\" rx=\"6\" fill=\"#FF0000\"></rect>" +
        "<text class=\"chart-value\" x=\"292\" y=\"" + (y + 15) + "\">" + pair[1] + "</text>";
    }).join("");
    return "<svg class=\"chart\" viewBox=\"0 0 " + width + " " + height + "\" role=\"img\">" + bars + "</svg>";
  }

  function pieChart(pairs) {
    var total = pairs.reduce(function (sum, pair) { return sum + pair[1]; }, 0) || 1;
    var colors = ["#FF0000", "#B87333", "#5C6370", "#C5C8CE"];
    var angle = -Math.PI / 2;
      var slices = pairs.map(function (pair, index) {
      if (pair[1] === 0) return "";
      if (pair[1] === total) {
        return "<circle cx=\"70\" cy=\"70\" r=\"50\" fill=\"" + colors[index % colors.length] + "\"></circle>";
      }
      var sweep = (pair[1] / total) * Math.PI * 2;
      var x1 = 70 + Math.cos(angle) * 50;
      var y1 = 70 + Math.sin(angle) * 50;
      angle += sweep;
      var x2 = 70 + Math.cos(angle) * 50;
      var y2 = 70 + Math.sin(angle) * 50;
      var large = sweep > Math.PI ? 1 : 0;
      return "<path d=\"M70 70 L" + x1.toFixed(1) + " " + y1.toFixed(1) + " A50 50 0 " + large + " 1 " + x2.toFixed(1) + " " + y2.toFixed(1) + " Z\" fill=\"" + colors[index % colors.length] + "\"></path>";
    }).join("");
    var legend = pairs.map(function (pair, index) {
      return "<span class=\"legend-item\"><i style=\"background:" + colors[index % colors.length] + "\"></i>" + esc(pair[0]) + " " + pair[1] + "</span>";
    }).join("");
    return "<svg class=\"chart pie\" viewBox=\"0 0 140 140\" role=\"img\">" + slices + "</svg><div class=\"legend\">" + legend + "</div>";
  }

  function renderDashboard() {
    var gen = viewGen;
    shell("<section class=\"panel\"><h1>Dashboard</h1><p class=\"muted\">Loading…</p></section>");
    var month = manilaPeriod();
    Promise.all([
      db.from("customers").select("id, stage"),
      db.from("invoices").select("status, amount, period"),
      db.from("payments").select("status, amount, submitted_at, confirmed_at"),
      db.from("repair_tickets").select("status")
    ]).then(function (parts) {
      parts.forEach(function (part) { if (part.error) throw part.error; });
      var customers = parts[0].data || [];
      var invoices = parts[1].data || [];
      var payments = parts[2].data || [];
      var repairs = parts[3].data || [];
      var stageCounts = {};
      STAGES.forEach(function (stage) { stageCounts[stage.id] = 0; });
      customers.forEach(function (row) {
        if (stageCounts[row.stage] == null) stageCounts[row.stage] = 0;
        stageCounts[row.stage] += 1;
      });
      var unpaid = invoices.filter(function (row) { return row.status === "unpaid" || row.status === "pending"; });
      var unpaidTotal = unpaid.reduce(function (sum, row) { return sum + Number(row.amount || 0); }, 0);
      var pendingPays = payments.filter(function (row) { return row.status === "pending"; }).length;
      var collected = payments.filter(function (row) {
        return row.status === "confirmed" && manilaPeriod(row.confirmed_at || row.submitted_at) === month;
      }).reduce(function (sum, row) { return sum + Number(row.amount || 0); }, 0);
      var openRepairs = repairs.filter(function (row) { return row.status !== "resolved"; }).length;
      if (gen !== viewGen) return;
      var cards = [
        ["Customers", customers.length, "customers", "red"],
        ["Inquiry", stageCounts.inquiry || 0, "tickets", "gray"],
        ["In Progress", stageCounts.in_progress || 0, "repairs", "copper"],
        ["Encoded", stageCounts.encoded || 0, "settings", "gray"],
        ["Active", stageCounts.active || 0, "customers", "red"],
        ["Unpaid bills", unpaid.length + " · " + money(unpaidTotal), "billing", "red"],
        ["Pending payments", pendingPays, "payments", "copper"],
        ["Collected this month", money(collected), "payments", "copper"],
        ["Open repairs", openRepairs, "repairs", "red"]
      ].map(function (card) {
        return "<article class=\"stat-card\"><span class=\"stat-icon tone-" + card[3] + "\">" + iconSvg(card[2], "stat-svg") + "</span><div><p class=\"stat-label\">" + esc(card[0]) + "</p><p class=\"stat-value\">" + esc(card[1]) + "</p></div></article>";
      }).join("");
      var bars = barChart(STAGES.map(function (stage) { return [stage.label, stageCounts[stage.id] || 0]; }));
      var statuses = ["unpaid", "pending", "paid", "void"];
      var pie = pieChart(statuses.map(function (status) {
        return [status, invoices.filter(function (row) { return row.status === status; }).length];
      }));
      shell("<section class=\"panel\"><h1>Dashboard</h1><div class=\"stat-grid\">" + cards + "</div></section>" +
        "<div class=\"chart-grid\"><section class=\"panel\"><h2>Customers by stage</h2>" + bars + "</section>" +
        "<section class=\"panel\"><h2>Invoice status</h2>" + pie + "</section></div>");
    }).catch(function (error) { flash(errText(error)); });
  }

  function renderBilling() {
    var gen = viewGen;
    shell("<section class=\"panel\"><h1>Billing</h1><p class=\"muted\">Loading bills…</p></section>");
    db.from("invoices").select("*, customers(name, account_number, monthly_bill, price)").order("period", { ascending: false }).then(function (result) {
      if (result.error) return flash(errText(result.error));
      if (gen !== viewGen) return;
      var rows = result.data || [];
      var periods = [];
      rows.forEach(function (row) { if (periods.indexOf(row.period) === -1) periods.push(row.period); });
      var body = rows.map(function (row) {
        var person = row.customers || {};
        return "<tr data-search=\"" + esc(((person.name || "") + " " + (person.account_number || "")).toLowerCase()) + "\" data-status=\"" + esc(row.status) + "\" data-period=\"" + esc(row.period) + "\">" +
          "<td data-label=\"Customer\">" + esc(person.name || "") + "<br><span class=\"muted\">" + esc(person.account_number || "") + "</span></td>" +
          "<td data-label=\"Period\">" + esc(row.period) + "</td><td data-label=\"Amount\">" + esc(money(row.amount)) + "</td>" +
          "<td data-label=\"Due\">" + esc(row.due_date || "—") + "</td><td data-label=\"Status\">" + statusPill(row.status) + "</td>" +
          "<td data-label=\"\">" + (row.status === "void" ? "" : "<button type=\"button\" class=\"btn secondary\" data-void=\"" + row.id + "\">Void</button>") + "</td></tr>";
      }).join("");
      var month = manilaPeriod();
      shell("<section class=\"panel\"><h1>Billing</h1>" +
        "<div class=\"toolbar\"><button type=\"button\" class=\"btn\" id=\"generate-bills\">Generate bills for</button><input id=\"generate-period\" type=\"month\" value=\"" + month + "\"></div>" +
        "<form id=\"add-bill\" class=\"grid two\">" +
        "<div class=\"field\"><label for=\"bill-customer\">Customer</label><select id=\"bill-customer\" required><option value=\"\">Select</option>" + customerChoices() + "</select></div>" +
        "<div class=\"field\"><label for=\"bill-period\">Period</label><input id=\"bill-period\" type=\"month\" required value=\"" + month + "\"></div>" +
        "<div class=\"field\"><label for=\"bill-amount\">Amount</label><input id=\"bill-amount\" type=\"number\" min=\"0\" step=\"0.01\" required></div>" +
        "<div class=\"field\"><label for=\"bill-due\">Due date</label><input id=\"bill-due\" type=\"date\"></div>" +
        "<button class=\"btn\" type=\"submit\">Add bill</button></form></section>" +
        "<div class=\"filters\"><input id=\"bill-q\" placeholder=\"Search name or account\"><select id=\"bill-status\"><option value=\"\">All statuses</option><option>unpaid</option><option>pending</option><option>paid</option><option>void</option></select>" +
        "<select id=\"bill-period-filter\"><option value=\"\">All periods</option>" + periods.map(function (period) { return "<option>" + esc(period) + "</option>"; }).join("") + "</select></div>" +
        "<div class=\"table-card\"><table id=\"bill-table\"><thead><tr><th>Customer</th><th>Period</th><th>Amount</th><th>Due</th><th>Status</th><th></th></tr></thead><tbody>" + (body || "<tr><td colspan=\"6\">No bills yet.</td></tr>") + "</tbody></table></div>");
      document.getElementById("bill-customer").onchange = function (event) {
        var row = state.customers.filter(function (item) { return item.id === event.target.value; })[0];
        if (row) document.getElementById("bill-amount").value = row.monthly_bill || row.price || "";
      };
      document.getElementById("add-bill").onsubmit = function (event) {
        event.preventDefault();
        db.from("invoices").insert({
          customer_id: document.getElementById("bill-customer").value,
          period: document.getElementById("bill-period").value,
          amount: Number(document.getElementById("bill-amount").value),
          due_date: document.getElementById("bill-due").value || null,
          status: "unpaid",
          created_by: sessionEmail
        }).then(function (insert) {
          if (insert.error) return flash(errText(insert.error));
          flash("Bill added.", true);
          renderBilling();
        });
      };
      document.getElementById("generate-bills").onclick = function () {
        db.rpc("generate_invoices", { p_period: document.getElementById("generate-period").value }).then(function (rpc) {
          if (rpc.error) return flash(errText(rpc.error));
          flash("Generated " + (rpc.data || 0) + " bill(s).", true);
          renderBilling();
        });
      };
      function filterBills() {
        var q = document.getElementById("bill-q").value.trim().toLowerCase();
        var status = document.getElementById("bill-status").value;
        var period = document.getElementById("bill-period-filter").value;
        app.querySelectorAll("#bill-table tbody tr").forEach(function (row) {
          var show = (!q || row.getAttribute("data-search").indexOf(q) !== -1) &&
            (!status || row.getAttribute("data-status") === status) &&
            (!period || row.getAttribute("data-period") === period);
          row.hidden = !show;
        });
      }
      ["bill-q", "bill-status", "bill-period-filter"].forEach(function (id) {
        document.getElementById(id).addEventListener("input", filterBills);
        document.getElementById(id).addEventListener("change", filterBills);
      });
      app.querySelectorAll("[data-void]").forEach(function (button) {
        button.onclick = function () {
          db.from("invoices").update({ status: "void" }).eq("id", button.getAttribute("data-void")).then(function (update) {
            if (update.error) return flash(errText(update.error));
            renderBilling();
          });
        };
      });
    });
  }

  function proofThumb(path, target) {
    if (!path) return;
    db.storage.from("payment-proofs").createSignedUrl(path, 3600).then(function (signed) {
      var el = document.getElementById(target);
      if (!el || !signed.data || !signed.data.signedUrl) return;
      el.innerHTML = "<a href=\"" + esc(signed.data.signedUrl) + "\" target=\"_blank\" rel=\"noopener\"><img class=\"id-thumb\" alt=\"Payment proof\" src=\"" + esc(signed.data.signedUrl) + "\"></a>";
    });
  }

  function renderPayments() {
    var gen = viewGen;
    shell("<section class=\"panel\"><h1>Payments</h1><p class=\"muted\">Loading…</p></section>");
    db.from("payments").select("*, customers(name, account_number), invoices(period)").order("submitted_at", { ascending: false }).then(function (result) {
      if (result.error) return flash(errText(result.error));
      if (gen !== viewGen) return;
      var rows = result.data || [];
      var pending = rows.filter(function (row) { return row.status === "pending"; });
      var confirmed = rows.filter(function (row) { return row.status === "confirmed"; });
      function paymentCard(row, actions) {
        var person = row.customers || {};
        var bill = row.invoices || {};
        return "<article class=\"row-card\" data-payment=\"" + row.id + "\"><strong>" + esc(person.name || "Customer") + "</strong>" +
          "<p class=\"meta\">" + esc(person.account_number || "") + " · " + esc(bill.period || "") + " · " + esc(money(row.amount)) + " · " + esc(row.method) + "</p>" +
          "<p>Ref " + esc(row.reference_no || "—") + " · " + esc(manilaTime(row.submitted_at)) + " " + statusPill(row.status) + "</p>" +
          "<div id=\"proof-" + row.id + "\"></div>" + (actions || "") + "</article>";
      }
      shell("<section class=\"panel\"><h1>Payments</h1><div class=\"tabs\"><button type=\"button\" id=\"tab-pending\" class=\"active\">Pending</button><button type=\"button\" id=\"tab-confirmed\">Confirmed</button></div>" +
        "<div id=\"pending-list\" class=\"list\">" + (pending.map(function (row) {
          return paymentCard(row, "<div class=\"actions\"><button type=\"button\" class=\"btn\" data-confirm=\"" + row.id + "\">Confirm</button><button type=\"button\" class=\"btn secondary\" data-reject=\"" + row.id + "\">Reject</button></div>");
        }).join("") || "<p>No pending payments.</p>") + "</div>" +
        "<div id=\"confirmed-list\" class=\"list\" hidden>" + (confirmed.map(function (row) { return paymentCard(row); }).join("") || "<p>No confirmed payments yet.</p>") + "</div>" +
        "<h2>Record cash payment</h2><form id=\"cash-form\" class=\"grid two\">" +
        "<div class=\"field\"><label>Customer</label><select id=\"cash-customer\" required><option value=\"\">Select</option>" + customerChoices() + "</select></div>" +
        "<div class=\"field\"><label>Invoice</label><select id=\"cash-invoice\" required><option value=\"\">Select customer first</option></select></div>" +
        "<div class=\"field\"><label>Amount</label><input id=\"cash-amount\" type=\"number\" min=\"0.01\" step=\"0.01\" required></div>" +
        "<div class=\"field\"><label>Reference</label><input id=\"cash-ref\" required value=\"CASH\"></div>" +
        "<button class=\"btn\" type=\"submit\">Record cash payment</button></form></section>");
      pending.concat(confirmed).forEach(function (row) { if (row.proof_path) proofThumb(row.proof_path, "proof-" + row.id); });
      document.getElementById("tab-pending").onclick = function () {
        document.getElementById("pending-list").hidden = false;
        document.getElementById("confirmed-list").hidden = true;
        document.getElementById("tab-pending").classList.add("active");
        document.getElementById("tab-confirmed").classList.remove("active");
      };
      document.getElementById("tab-confirmed").onclick = function () {
        document.getElementById("pending-list").hidden = true;
        document.getElementById("confirmed-list").hidden = false;
        document.getElementById("tab-confirmed").classList.add("active");
        document.getElementById("tab-pending").classList.remove("active");
      };
      app.querySelectorAll("[data-confirm], [data-reject]").forEach(function (button) {
        button.onclick = function () {
          var confirming = button.hasAttribute("data-confirm");
          var id = button.getAttribute(confirming ? "data-confirm" : "data-reject");
          db.from("payments").update({
            status: confirming ? "confirmed" : "rejected",
            confirmed_by: sessionEmail,
            confirmed_at: new Date().toISOString()
          }).eq("id", id).then(function (update) {
            if (update.error) return flash(errText(update.error));
            renderPayments();
          });
        };
      });
      document.getElementById("cash-customer").onchange = function (event) {
        db.from("invoices").select("id, period, amount, status").eq("customer_id", event.target.value).in("status", ["unpaid", "pending"]).then(function (bills) {
          var select = document.getElementById("cash-invoice");
          select.innerHTML = (bills.data || []).map(function (bill) {
            return "<option value=\"" + bill.id + "\" data-amount=\"" + bill.amount + "\">" + esc(bill.period) + " · " + esc(money(bill.amount)) + "</option>";
          }).join("") || "<option value=\"\">No open bill</option>";
          var first = select.options[0];
          if (first && first.getAttribute("data-amount")) document.getElementById("cash-amount").value = first.getAttribute("data-amount");
        });
      };
      document.getElementById("cash-invoice").onchange = function (event) {
        var option = event.target.options[event.target.selectedIndex];
        var amount = option && option.getAttribute("data-amount");
        if (amount) document.getElementById("cash-amount").value = amount;
      };
      document.getElementById("cash-form").onsubmit = function (event) {
        event.preventDefault();
        db.from("payments").insert({
          customer_id: document.getElementById("cash-customer").value,
          invoice_id: document.getElementById("cash-invoice").value,
          amount: Number(document.getElementById("cash-amount").value),
          method: "cash",
          reference_no: document.getElementById("cash-ref").value.trim(),
          status: "confirmed",
          source: "admin",
          confirmed_by: sessionEmail,
          confirmed_at: new Date().toISOString()
        }).then(function (insert) {
          if (insert.error) return flash(errText(insert.error));
          flash("Cash payment recorded.", true);
          renderPayments();
        });
      };
    });
  }

  var NODE_COLORS = { OLT: "#FF0000", LCP: "#B87333", NAP: "#2C2F33", CLOSURE: "#6B6F76", POLE: "#D4A574", OTHER: "#111" };
  var STAGE_COLORS = { inquiry: "#6B6F76", in_progress: "#B87333", encoded: "#D4A574", active: "#FF0000" };

  function osmTiles() {
    return L.tileLayer("https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png", {
      maxZoom: 19,
      attribution: "&copy; OpenStreetMap contributors"
    });
  }

  function renderMap() {
    var gen = viewGen;
    shell("<section class=\"panel\"><h1>Network map</h1><div id=\"ops-map\" class=\"ops-map\"></div>" +
      "<div class=\"legend\" id=\"map-legend\"></div>" +
      "<form id=\"node-form\" class=\"grid two\" hidden>" +
      "<input type=\"hidden\" id=\"node-id\"><input type=\"hidden\" id=\"node-lat\"><input type=\"hidden\" id=\"node-lng\">" +
      "<div class=\"field\"><label>Type</label><select id=\"node-type\"><option>OLT</option><option>LCP</option><option>NAP</option><option>CLOSURE</option><option>POLE</option><option>OTHER</option></select></div>" +
      "<div class=\"field\"><label>Name</label><input id=\"node-name\" required></div>" +
      "<div class=\"field\"><label>Ports</label><input id=\"node-ports\" type=\"number\" min=\"0\" step=\"1\"></div>" +
      "<div class=\"field\"><label>Notes</label><input id=\"node-notes\"></div>" +
      "<div class=\"actions\"><button class=\"btn\" type=\"submit\">Save node</button><button class=\"btn secondary\" type=\"button\" id=\"node-cancel\">Cancel</button></div></form>" +
      "<p><button type=\"button\" class=\"btn secondary\" id=\"add-node\">Add node</button></p>" +
      "<div id=\"node-list\"></div></section>");
    if (!window.L) {
      flash("Map library did not load.");
      return;
    }
    var map = L.map("ops-map").setView([14.711, 121.110], 14);
    osmTiles().addTo(map);
    var adding = false;
    var editing = null;
    document.getElementById("add-node").onclick = function () {
      adding = true;
      this.textContent = "Click the map…";
    };
    document.getElementById("node-cancel").onclick = function () {
      document.getElementById("node-form").hidden = true;
      adding = false;
    };
    map.on("click", function (event) {
      if (!adding) return;
      document.getElementById("node-id").value = "";
      document.getElementById("node-lat").value = event.latlng.lat;
      document.getElementById("node-lng").value = event.latlng.lng;
      document.getElementById("node-form").hidden = false;
      adding = false;
      document.getElementById("add-node").textContent = "Add node";
    });
    Promise.all([
      db.from("network_nodes").select("*"),
      db.from("customers").select("id, name, account_number, stage, latitude, longitude")
    ]).then(function (parts) {
      if (gen !== viewGen) return;
      if (parts[0].error) throw parts[0].error;
      var nodes = parts[0].data || [];
      var legend = "";
      Object.keys(NODE_COLORS).forEach(function (type) {
        legend += "<span class=\"legend-item\"><i style=\"background:" + NODE_COLORS[type] + "\"></i>" + type + "</span>";
      });
      STAGES.forEach(function (stage) {
        legend += "<span class=\"legend-item\"><i style=\"background:" + (STAGE_COLORS[stage.id] || "#6B6F76") + "\"></i>" + esc(stage.label) + "</span>";
      });
      document.getElementById("map-legend").innerHTML = legend;
      nodes.forEach(function (node) {
        var marker = L.circleMarker([node.latitude, node.longitude], {
          radius: 8, color: NODE_COLORS[node.node_type] || "#111", fillOpacity: 0.9
        }).addTo(map);
        marker.bindPopup("<strong>" + esc(node.node_type) + "</strong> " + esc(node.name) +
          "<br><button type=\"button\" class=\"btn secondary\" id=\"edit-" + node.id + "\">Edit</button>");
        marker.on("popupopen", function () {
          var button = document.getElementById("edit-" + node.id);
          if (!button) return;
          button.onclick = function () {
            editing = node;
            document.getElementById("node-id").value = node.id;
            document.getElementById("node-type").value = node.node_type;
            document.getElementById("node-name").value = node.name;
            document.getElementById("node-ports").value = node.ports || "";
            document.getElementById("node-notes").value = node.notes || "";
            document.getElementById("node-lat").value = node.latitude;
            document.getElementById("node-lng").value = node.longitude;
            document.getElementById("node-form").hidden = false;
          };
        });
      });
      (parts[1].data || []).forEach(function (row) {
        if (row.latitude == null || row.longitude == null) return;
        L.circleMarker([row.latitude, row.longitude], {
          radius: 6, color: STAGE_COLORS[row.stage] || "#6B6F76", fillOpacity: 0.85
        }).addTo(map).bindPopup("<a href=\"#customer/" + row.id + "\">" + esc(row.name || row.account_number || "Customer") + "</a><br>" + esc(stageLabel(row.stage)));
      });
      function fillNodeForm(node) {
        document.getElementById("node-id").value = node ? node.id : "";
        document.getElementById("node-type").value = node ? node.node_type : "NAP";
        document.getElementById("node-name").value = node ? node.name : "";
        document.getElementById("node-ports").value = node && node.ports != null ? node.ports : "";
        document.getElementById("node-notes").value = node && node.notes ? node.notes : "";
        document.getElementById("node-lat").value = node ? node.latitude : "";
        document.getElementById("node-lng").value = node ? node.longitude : "";
        document.getElementById("node-form").hidden = false;
      }
      document.getElementById("node-list").innerHTML = nodes.map(function (node) {
        return "<p>" + esc(node.node_type) + " · " + esc(node.name) +
          " <button type=\"button\" class=\"btn secondary\" data-edit-node=\"" + node.id + "\">Edit</button>" +
          " <button type=\"button\" class=\"btn secondary\" data-del-node=\"" + node.id + "\">Delete</button></p>";
      }).join("");
      app.querySelectorAll("[data-edit-node]").forEach(function (button) {
        button.onclick = function () {
          var node = nodes.filter(function (item) { return item.id === button.getAttribute("data-edit-node"); })[0];
          if (node) {
            fillNodeForm(node);
            map.panTo([node.latitude, node.longitude]);
          }
        };
      });
      app.querySelectorAll("[data-del-node]").forEach(function (button) {
        button.onclick = function () {
          db.from("network_nodes").delete().eq("id", button.getAttribute("data-del-node")).then(function (del) {
            if (del.error) return flash(errText(del.error));
            renderMap();
          });
        };
      });
      setTimeout(function () { map.invalidateSize(); }, 200);
    }).catch(function (error) { flash(errText(error)); });
    document.getElementById("node-form").onsubmit = function (event) {
      event.preventDefault();
      var record = {
        node_type: document.getElementById("node-type").value,
        name: document.getElementById("node-name").value.trim(),
        ports: document.getElementById("node-ports").value === "" ? null : Number(document.getElementById("node-ports").value),
        notes: document.getElementById("node-notes").value.trim() || null,
        latitude: Number(document.getElementById("node-lat").value),
        longitude: Number(document.getElementById("node-lng").value)
      };
      var id = document.getElementById("node-id").value;
      var query = id ? db.from("network_nodes").update(record).eq("id", id) : db.from("network_nodes").insert(record);
      query.then(function (save) {
        if (save.error) return flash(errText(save.error));
        renderMap();
      });
    };
  }

  function renderRepairs() {
    var gen = viewGen;
    shell("<section class=\"panel\"><h1>Repairs</h1><p class=\"muted\">Loading…</p></section>");
    db.from("repair_tickets").select("*, customers(name, account_number), technicians(name)").order("created_at", { ascending: false }).then(function (result) {
      if (result.error) return flash(errText(result.error));
      if (gen !== viewGen) return;
      var rows = result.data || [];
      var titles = { pending: "Pending", ongoing: "Ongoing", resolved: "Resolved" };
      var columns = ["pending", "ongoing", "resolved"].map(function (status) {
        var cards = rows.filter(function (row) { return row.status === status; }).map(function (row) {
          var person = row.customers || {};
          var next = status === "pending" ? "ongoing" : (status === "ongoing" ? "resolved" : "");
          var prev = status === "resolved" ? "ongoing" : (status === "ongoing" ? "pending" : "");
          return "<article class=\"row-card\"><strong>" + esc(row.title) + "</strong><p class=\"meta\">" +
            esc(person.name || "No customer") + " · " + esc(row.priority) + (row.technicians ? " · " + esc(row.technicians.name) : "") + "</p>" +
            "<p>" + esc(row.description || "") + "</p>" +
            "<div class=\"actions\">" +
            (prev ? "<button type=\"button\" class=\"btn secondary\" data-repair=\"" + row.id + "\" data-status=\"" + prev + "\">Move to " + titles[prev] + "</button>" : "") +
            (next ? "<button type=\"button\" class=\"btn\" data-repair=\"" + row.id + "\" data-status=\"" + next + "\">Move to " + titles[next] + "</button>" : "") +
            "</div></article>";
        }).join("");
        return "<div class=\"kanban-col\"><h2>" + titles[status] + "</h2>" + (cards || "<p class=\"muted\">None</p>") + "</div>";
      }).join("");
      shell("<section class=\"panel\"><h1>Repairs</h1><form id=\"repair-form\" class=\"grid two\">" +
        "<div class=\"field\"><label>Customer</label><select id=\"repair-customer\"><option value=\"\">None</option>" + customerChoices() + "</select></div>" +
        "<div class=\"field\"><label>Technician</label><select id=\"repair-tech\"><option value=\"\">None</option>" + state.technicians.filter(function (tech) { return tech.active; }).map(function (tech) {
          return "<option value=\"" + tech.id + "\">" + esc(tech.name) + "</option>";
        }).join("") + "</select></div>" +
        "<div class=\"field\"><label>Title</label><input id=\"repair-title\" required></div>" +
        "<div class=\"field\"><label>Priority</label><select id=\"repair-priority\"><option>low</option><option selected>normal</option><option>high</option></select></div>" +
        "<div class=\"field\"><label>Description</label><textarea id=\"repair-desc\"></textarea></div>" +
        "<button class=\"btn\" type=\"submit\">Create ticket</button></form></section><div class=\"kanban\">" + columns + "</div>");
      document.getElementById("repair-form").onsubmit = function (event) {
        event.preventDefault();
        db.from("repair_tickets").insert({
          customer_id: document.getElementById("repair-customer").value || null,
          technician_id: document.getElementById("repair-tech").value || null,
          title: document.getElementById("repair-title").value.trim(),
          description: document.getElementById("repair-desc").value.trim() || null,
          priority: document.getElementById("repair-priority").value,
          created_by: sessionEmail
        }).then(function (insert) {
          if (insert.error) return flash(errText(insert.error));
          renderRepairs();
        });
      };
      app.querySelectorAll("[data-repair]").forEach(function (button) {
        button.onclick = function () {
          var status = button.getAttribute("data-status");
          var patch = { status: status, resolved_at: status === "resolved" ? new Date().toISOString() : null };
          db.from("repair_tickets").update(patch).eq("id", button.getAttribute("data-repair")).then(function (update) {
            if (update.error) return flash(errText(update.error));
            renderRepairs();
          });
        };
      });
    });
  }

  function renderSettings() {
    var gen = viewGen;
    shell("<section class=\"panel\"><h1>Settings</h1><p class=\"muted\">Loading…</p></section>");
    db.from("app_settings").select("*").order("key").then(function (result) {
      if (result.error) return flash(errText(result.error));
      if (gen !== viewGen) return;
      var fields = [
        ["gcash_number", "GCash number"],
        ["gcash_name", "GCash name"],
        ["gcash_qr_url", "GCash QR image URL"],
        ["payment_note", "Payment note"]
      ];
      var values = {};
      (result.data || []).forEach(function (row) { values[row.key] = row.value || ""; });
      shell("<section class=\"panel\"><h1>Settings</h1><form id=\"settings-form\" class=\"grid\">" +
        fields.map(function (field) {
          var input = field[0] === "payment_note"
            ? "<textarea id=\"set-" + field[0] + "\">" + esc(values[field[0]] || "") + "</textarea>"
            : "<input id=\"set-" + field[0] + "\" value=\"" + esc(values[field[0]] || "") + "\">";
          return "<div class=\"field\"><label for=\"set-" + field[0] + "\">" + esc(field[1]) + "</label>" + input + "</div>";
        }).join("") +
        "<button class=\"btn\" type=\"submit\">Save settings</button></form></section>");
      document.getElementById("settings-form").onsubmit = function (event) {
        event.preventDefault();
        var writes = fields.map(function (field) {
          return db.from("app_settings").upsert({
            key: field[0],
            value: document.getElementById("set-" + field[0]).value,
            is_public: true,
            updated_at: new Date().toISOString()
          });
        });
        Promise.all(writes).then(function (saved) {
          var failed = saved.filter(function (item) { return item.error; })[0];
          if (failed) return flash(errText(failed.error));
          flash("Settings saved.", true);
        });
      };
    });
  }

  function billsCard(customer) {
    var rows = (state.invoices || []).map(function (bill) {
      return "<li>" + esc(bill.period) + " · " + esc(money(bill.amount)) + " · " + statusPill(bill.status) + "</li>";
    }).join("");
    var pays = (state.pays || []).map(function (pay) {
      return "<li>" + esc(money(pay.amount)) + " · " + esc(pay.method) + " · " + statusPill(pay.status) + " · " + esc(pay.reference_no || "") + "</li>";
    }).join("");
    var month = manilaPeriod();
    return formCard("Bills & payments",
      "<ul class=\"history\">" + (rows || "<li>No bills yet.</li>") + "</ul>" +
      "<h3>Payments</h3><ul class=\"history\">" + (pays || "<li>No payments yet.</li>") + "</ul>" +
      "<form id=\"quick-bill\" class=\"grid two\">" +
      "<div class=\"field\"><label for=\"quick-period\">Period</label><input id=\"quick-period\" type=\"month\" value=\"" + month + "\" required></div>" +
      "<div class=\"field\"><label for=\"quick-amount\">Amount</label><input id=\"quick-amount\" type=\"number\" min=\"0\" step=\"0.01\" value=\"" + esc(customer.monthly_bill || customer.price || "") + "\"></div>" +
      "<div class=\"field\"><label for=\"quick-due\">Due date</label><input id=\"quick-due\" type=\"date\"></div>" +
      "<button class=\"btn\" type=\"submit\">Add bill</button></form>");
  }

  function wireQuickBill(customer) {
    var form = document.getElementById("quick-bill");
    if (!form || !customer || !customer.id) return;
    form.onsubmit = function (event) {
      event.preventDefault();
      db.from("invoices").insert({
        customer_id: customer.id,
        period: document.getElementById("quick-period").value,
        amount: Number(document.getElementById("quick-amount").value),
        due_date: document.getElementById("quick-due").value || null,
        status: "unpaid",
        created_by: sessionEmail
      }).then(function (insert) {
        if (insert.error) return flash(errText(insert.error));
        flash("Bill added.", true);
        loadCustomer(customer.id);
      });
    };
  }

  function initCustomerMiniMap() {
    var el = document.getElementById("customer-mini-map");
    if (!el || !window.L) return;
    var latInput = document.getElementById("f-latitude");
    var lngInput = document.getElementById("f-longitude");
    var lat = parseFloat(latInput && latInput.value) || 14.711;
    var lng = parseFloat(lngInput && lngInput.value) || 121.110;
    var map = L.map(el).setView([lat, lng], 16);
    osmTiles().addTo(map);
    var marker = L.circleMarker([lat, lng], { radius: 8, color: "#FF0000", fillColor: "#FF0000", fillOpacity: 0.9 }).addTo(map);
    var picking = false;
    var button = document.getElementById("pick-map");
    if (button) button.onclick = function () {
      picking = true;
      button.textContent = "Click the map…";
    };
    map.on("click", function (event) {
      if (!picking) return;
      if (latInput) latInput.value = event.latlng.lat.toFixed(6);
      if (lngInput) lngInput.value = event.latlng.lng.toFixed(6);
      marker.setLatLng(event.latlng);
      picking = false;
      if (button) button.textContent = "Pick on map";
    });
    setTimeout(function () { map.invalidateSize(); }, 250);
  }

  function render() {
    viewGen += 1;
    var current = route();
    if (current.name === "customer" && current.id === "new") {
      renderCustomer({ stage: "inquiry", source: "admin", for_disconnection: false }, true);
      return;
    }
    if (current.name === "customer" && current.id) {
      loadCustomer(current.id);
      return;
    }
    if (current.name === "investors") return renderPeople("investors");
    if (current.name === "technicians") return renderPeople("technicians");
    if (current.name === "tickets") return renderTickets();
    if (current.name === "admins") return renderAdmins();
    if (current.name === "billing") return renderBilling();
    if (current.name === "payments") return renderPayments();
    if (current.name === "map") return renderMap();
    if (current.name === "repairs") return renderRepairs();
    if (current.name === "settings") return renderSettings();
    if (current.name === "customers") return renderCustomers();
    return renderDashboard();
  }

  var bootedFor = "";
  function boot(email) {
    sessionEmail = email || "";
    if (!sessionEmail || bootedFor === sessionEmail.toLowerCase()) return;
    bootedFor = sessionEmail.toLowerCase();
    who.innerHTML = "<span class=\"who-email\">" + esc(sessionEmail) + "</span><button type=\"button\" class=\"btn secondary\" id=\"sign-out\">Sign out</button>";
    document.getElementById("sign-out").onclick = signOut;
    db.from("admins").select("email").eq("email", sessionEmail.toLowerCase()).maybeSingle().then(function (result) {
      if (result.error) {
        setChrome("guest");
        if (pageTitle) pageTitle.textContent = "FiberBro";
        app.innerHTML = "<section class=\"panel\"><h1>Could not open the admin list</h1><p>" + esc(errText(result.error)) + "</p><p class=\"muted\">Run supabase/schema.sql in the Supabase SQL editor, then reload.</p></section>";
        return;
      }
      if (!result.data) return renderDenied();
      refresh().then(render).catch(function (error) {
        shell("<section class=\"panel\"><h1>Could not load records</h1><p>" + esc(errText(error)) + "</p></section>");
      });
    });
  }

  window.addEventListener("hashchange", function () {
    setNavOpen(false);
    if (sessionEmail) render();
  });

  var status = document.getElementById("config-status");
  if (!cfg || typeof cfg.isConfigured !== "function" || !cfg.isConfigured()) {
    if (status) status.textContent = "The page script loaded and confirmed the database settings are still placeholders.";
    return;
  }

  loadLib().then(function (mod) {
    db = mod.createClient(cfg.url, cfg.anonKey, {
      auth: { detectSessionInUrl: true, persistSession: true }
    });
    db.auth.onAuthStateChange(function (event, session) {
      if (event === "SIGNED_OUT") {
        bootedFor = "";
        sessionEmail = "";
        renderSignedOut();
        return;
      }
      if (session && session.user) boot(session.user.email || "");
    });
    return db.auth.getSession();
  }).then(function (result) {
    if (!result || result.error) {
      setChrome("guest");
      if (pageTitle) pageTitle.textContent = "FiberBro";
      app.innerHTML = "<section class=\"panel\"><h1>Could not reach Supabase</h1><p>" + esc(errText(result && result.error)) + "</p></section>";
      return;
    }
    var session = result.data.session;
    if (!session) return renderSignedOut();
    boot(session.user.email || "");
  }).catch(function (error) {
    setChrome("guest");
    if (pageTitle) pageTitle.textContent = "FiberBro";
    app.innerHTML = "<section class=\"panel\"><h1>Could not load the admin portal</h1><p>" + esc(errText(error)) + "</p></section>";
  });
})();
