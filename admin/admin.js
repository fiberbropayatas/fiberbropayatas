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
      ["account_status", "Account Status", "account_status"],
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
      ["installation_remarks", "Installation remarks", "textarea"],
      ["service_location", "Location", "location"],
      ["referral_source", "Referral source", "text"],
      ["referral_type", "Referral type", "text"],
      ["referral_name", "Referral name", "text"],
      ["privacy_consent", "Data privacy consent", "bool"]
    ]},
    { title: "Plan", fields: [
      ["plan", "Plan", "text"],
      ["plan_type", "Plan Type", "text"],
      ["plan_speed", "Plan Speed", "text"],
      ["price", "Price", "money"],
      ["plan_status", "Plan Status", "text"]
    ]},
    { title: "Billing", fields: [
      ["due_date_number", "Due day of month", "int"],
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
      ["modem_serial", "Modem serial", "text"],
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
  var billingTab = "bills";

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
    if (key === "portal_enabled") return "Portal access";
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
      ["payments", "Payments", "payments"],
      ["finance", "Finance", "billing"],
      ["gcash", "GCash refs", "payments"],
      ["logbook", "Logbook", "tickets"]
    ]],
    ["Operations", [
      ["ops", "Tickets", "tickets"],
      ["staff", "Staff", "technicians"],
      ["modems", "Modems", "repairs"]
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
    finance: "Finance",
    gcash: "GCash refs",
    logbook: "Logbook",
    map: "Map",
    repairs: "Repairs",
    investors: "Investors",
    technicians: "Technicians",
    tickets: "Install tickets",
    ops: "Tickets",
    staff: "Staff",
    modems: "Modems",
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
  var lastShellRoute = "";

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
      applySidebarCollapsed();
    });
    wireSidebarCollapse();
  }

  function applySidebarCollapsed() {
    var stored = false;
    try { stored = localStorage.getItem("fiberbro-admin-sidebar") === "1"; } catch (err) { stored = false; }
    var collapsed = stored && !mobileNav();
    document.body.classList.toggle("sidebar-collapsed", collapsed);
    var button = document.getElementById("sidebar-collapse");
    if (button) {
      button.setAttribute("aria-pressed", stored ? "true" : "false");
      button.setAttribute("aria-label", stored ? "Expand sidebar" : "Collapse sidebar");
    }
  }

  function wireSidebarCollapse() {
    applySidebarCollapsed();
    var button = document.getElementById("sidebar-collapse");
    if (!button) return;
    button.addEventListener("click", function () {
      var next = !document.body.classList.contains("sidebar-collapsed");
      if (mobileNav()) next = false;
      try { localStorage.setItem("fiberbro-admin-sidebar", next ? "1" : "0"); } catch (err) {}
      applySidebarCollapsed();
    });
  }

  function swapApp(html, title) {
    var routeName = "";
    try { routeName = route().name; } catch (err) { routeName = ""; }
    var changed = routeName !== lastShellRoute;
    lastShellRoute = routeName;
    document.body.classList.toggle("is-entering", changed);
    if (title && pageTitle) pageTitle.textContent = title;
    app.innerHTML = html;
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
    swapApp("<div id=\"flash\" class=\"flash\" role=\"status\" aria-live=\"polite\" hidden></div>" + body, PAGE_TITLES[current] || "Dashboard");
  }

  function renderSignedOut() {
    setChrome("guest");
    if (who) who.innerHTML = "";
    if (pageTitle) pageTitle.textContent = "Sign in";
    app.innerHTML = "<section class=\"panel sign-panel\"><picture><source type=\"image/webp\" srcset=\"/assets/img/fiberbro-logo.webp?v=20261121a\"><img class=\"sign-logo\" src=\"/assets/img/fiberbro-logo.png?v=20261121a\" width=\"1600\" height=\"501\" alt=\"FiberBro Internet Communication Services Corp.\"></picture><h1>FiberBro admin</h1><p>Sign in with the company Gmail account. Only emails on the admin allowlist can open records.</p><button type=\"button\" class=\"btn\" id=\"sign-in\">Sign in with Google</button></section>";
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
    if (type === "account_status") {
      var statuses = ["Inquiry", "In Progress", "Encoded", "Active", "Newly Installed", "Reconnected", "FREE"];
      if (value && statuses.indexOf(value) < 0) statuses.push(value);
      return "<div class=\"field\"><label for=\"" + id + "\">" + esc(label) + "</label><select id=\"" + id + "\" data-key=\"" + key + "\" data-type=\"text\">" +
        statuses.map(function (item) {
          return "<option" + (item === value ? " selected" : "") + ">" + esc(item) + "</option>";
        }).join("") + "</select><span class=\"muted\">Newly Installed, Reconnected, and FREE stay when you save. Other labels follow the stage.</span></div>";
    }
    if (type === "location") {
      var places = ["", "Payatas", "Maligaya", "Pampanga"];
      return "<div class=\"field\"><label for=\"" + id + "\">" + esc(label) + "</label><select id=\"" + id + "\" data-key=\"" + key + "\" data-type=\"text\">" +
        places.map(function (item) {
          return "<option value=\"" + esc(item) + "\"" + (item === (value || "") ? " selected" : "") + ">" + esc(item || "Not set") + "</option>";
        }).join("") + "</select></div>";
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
        body += "<div class=\"grid two\"><div class=\"field\"><label for=\"f-lp_id\">LP record</label><select id=\"f-lp_id\" data-key=\"lp_id\" data-type=\"text\"><option value=\"\">Not linked</option></select><span class=\"muted\">Text LP above is kept.</span></div>" +
          "<div class=\"field\"><label for=\"f-nap_id\">NAP record</label><select id=\"f-nap_id\" data-key=\"nap_id\" data-type=\"text\"><option value=\"\">Not linked</option></select><span class=\"muted\">Text NAP and port above are kept.</span></div></div>";
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
      (isNew ? "" : portalCard(customer)) +
      (isNew ? "" : billsCard(customer)) +
      (isNew ? "" : historyCard(customer)) +
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
    wireLpNap(customer);
    wireQuickBill(customer);
    wirePortalAccess(customer);
    wireHistory();
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
      unpaid: 1, pending: 1, paid: 1, void: 1, grace: 1, overdue: 1,
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

  function manilaDate(value) {
    var date = value ? new Date(value) : new Date();
    if (isNaN(date.getTime())) return "";
    return new Intl.DateTimeFormat("en-CA", {
      timeZone: "Asia/Manila",
      year: "numeric",
      month: "2-digit",
      day: "2-digit"
    }).format(date);
  }

  function maybeGenerateBills() {
    var key = "fiberbro-bills-" + manilaDate();
    try {
      if (localStorage.getItem(key)) return Promise.resolve();
    } catch (err) {}
    return db.rpc("generate_upcoming_bills").then(function () {
      try { localStorage.setItem(key, "1"); } catch (err) {}
    }).catch(function () {});
  }

  function renderDashboard() {
    var gen = viewGen;
    shell("<section class=\"panel\"><h1>Dashboard</h1><p class=\"muted\">Loading…</p></section>");
    var month = manilaPeriod();
    maybeGenerateBills().then(function () {
    return Promise.all([
      db.from("customers").select("id, stage"),
      db.from("invoices").select("status, amount, period, due_date, period_label, bill_number, customers(name, account_number)"),
      db.from("payments").select("status, amount, submitted_at, confirmed_at"),
      db.from("repair_tickets").select("status"),
      db.from("virtual_logbook").select("status").then(function (r) { return r.error ? { data: [] } : r; }).catch(function () { return { data: [] }; }),
      db.from("gcash_refs").select("status, duplicate_flag").then(function (r) { return r.error ? { data: [] } : r; }).catch(function () { return { data: [] }; })
    ]);
    }).then(function (parts) {
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
      var today = manilaDate();
      var todayTotal = payments.filter(function (row) {
        return row.status === "confirmed" && manilaDate(row.confirmed_at || row.submitted_at) === today;
      }).reduce(function (sum, row) { return sum + Number(row.amount || 0); }, 0);
      var unmatchedProofs = (parts[4].data || []).filter(function (row) { return row.status !== "processed"; }).length;
      var openRefs = (parts[5].data || []).filter(function (row) { return row.status !== "processed" && !row.duplicate_flag; }).length;
      var dueSoon = invoices.filter(function (row) {
        if (row.status !== "unpaid" && row.status !== "pending") return false;
        if (!row.due_date) return false;
        var start = new Date(today + "T00:00:00");
        var due = new Date(String(row.due_date).slice(0, 10) + "T00:00:00");
        var end = new Date(start.getTime());
        end.setDate(end.getDate() + 10);
        return due >= start && due <= end;
      });
      var soaList = dueSoon.map(function (row) {
        var person = row.customers || {};
        var message = "Hi " + (person.name || "customer") + ", ito ang SOA mo para sa " + (row.period_label || row.period || "") + ". Bill " + (row.bill_number || "—") + ". Amount " + money(row.amount) + ". Due " + (row.due_date || "—") + ". Pakibayad sa GCash. Salamat, FiberBro.";
        return "<p><strong>" + esc(person.name || "Customer") + "</strong> · " + esc(row.period_label || row.period || "") + " · " + esc(money(row.amount)) +
          " <button type=\"button\" class=\"btn secondary\" data-copy=\"" + esc(message) + "\">Copy message</button></p>";
      }).join("") || "<p class=\"muted\">Walang SOA na due sa susunod na 10 araw.</p>";
      var cards = [
        ["Today's collection", money(todayTotal), "payments", "red"],
        ["Unmatched proofs", unmatchedProofs, "tickets", "copper"],
        ["Unprocessed GCash refs", openRefs, "billing", "copper"],
        ["Bills due in 10 days", dueSoon.length, "customers", "red"],
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
        "<section class=\"panel\"><h2>Invoice status</h2>" + pie + "</section></div>" +
        "<section class=\"panel\"><h2>SOA ready to send</h2><p class=\"muted\">Bills due within 10 days. Copy the message, then send it on the Facebook page. Hindi ito auto-send.</p>" + soaList + "</section>");
      app.querySelectorAll("[data-copy]").forEach(function (button) {
        button.onclick = function () {
          var text = button.getAttribute("data-copy");
          if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(text).then(function () { flash("Message copied.", true); });
          } else {
            flash(text);
          }
        };
      });
    }).catch(function (error) { flash(errText(error)); });
  }

  function ledgerEvents(invoices, payments) {
    var events = [];
    (invoices || []).forEach(function (inv) {
      if (inv.status === "void") return;
      events.push({
        at: inv.created_at || inv.due_date || "",
        kind: "Bill",
        label: inv.period || "",
        method: "",
        status: inv.status || "",
        charge: Number(inv.amount) || 0,
        credit: 0
      });
    });
    (payments || []).forEach(function (pay) {
      events.push({
        at: pay.confirmed_at || pay.submitted_at || "",
        kind: "Payment",
        label: pay.reference_no || "",
        method: pay.method || "",
        status: pay.status || "",
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
    return events;
  }

  function historyCard(customer) {
    var events = ledgerEvents(state.invoices, state.pays);
    var credit = 0;
    if (events.length) credit = Math.max(0, -events[events.length - 1].balance);
    var years = [];
    events.forEach(function (event) {
      var year = String(event.at).slice(0, 4);
      if (year && years.indexOf(year) === -1) years.push(year);
    });
    var rows = events.map(function (event) {
      return "<tr data-year=\"" + esc(String(event.at).slice(0, 4)) + "\" data-month=\"" + esc(String(event.at).slice(5, 7)) + "\" data-method=\"" + esc(event.method) + "\">" +
        "<td data-label=\"When\">" + esc(manilaTime(event.at) || String(event.at).slice(0, 10) || "—") + "</td>" +
        "<td data-label=\"Type\">" + esc(event.kind) + " " + esc(event.label) + "</td>" +
        "<td data-label=\"Method\">" + esc(event.method || "—") + "</td>" +
        "<td data-label=\"Status\">" + statusPill(event.status) + "</td>" +
        "<td data-label=\"Charge\">" + (event.charge ? esc(money(event.charge)) : "—") + "</td>" +
        "<td data-label=\"Credit\">" + (event.credit ? esc(money(event.credit)) : "—") + "</td>" +
        "<td data-label=\"Balance\">" + esc(money(event.balance)) + "</td></tr>";
    }).join("");
    return formCard("Transaction history",
      "<p class=\"muted\">Running balance counts bills and confirmed payments. Wallet credit is overpayment carried forward. Stored wallet credit: " + esc(money(customer.wallet_credit || 0)) + ". Computed from this list: " + esc(money(credit)) + ".</p>" +
      "<div class=\"filters\"><select id=\"history-year\"><option value=\"\">All years</option>" + years.map(function (year) { return "<option>" + esc(year) + "</option>"; }).join("") + "</select>" +
      "<select id=\"history-month\"><option value=\"\">All months</option>" + ["01","02","03","04","05","06","07","08","09","10","11","12"].map(function (month) { return "<option value=\"" + month + "\">" + month + "</option>"; }).join("") + "</select>" +
      "<select id=\"history-method\"><option value=\"\">All methods</option><option>gcash</option><option>maya</option><option>bank</option><option>cash</option><option>other</option></select></div>" +
      "<div class=\"table-card\"><table id=\"history-table\"><thead><tr><th>When</th><th>Type</th><th>Method</th><th>Status</th><th>Charge</th><th>Credit</th><th>Balance</th></tr></thead><tbody>" +
      (rows || "<tr><td colspan=\"7\">No transactions yet.</td></tr>") + "</tbody></table></div>");
  }

  function wireHistory() {
    var table = document.getElementById("history-table");
    if (!table) return;
    function apply() {
      var year = document.getElementById("history-year").value;
      var month = document.getElementById("history-month").value;
      var method = document.getElementById("history-method").value;
      table.querySelectorAll("tbody tr").forEach(function (row) {
        if (!row.getAttribute("data-year")) return;
        row.hidden = (year && row.getAttribute("data-year") !== year) ||
          (month && row.getAttribute("data-month") !== month) ||
          (method && row.getAttribute("data-method") !== method);
      });
    }
    ["history-year", "history-month", "history-method"].forEach(function (id) {
      var el = document.getElementById(id);
      if (el) el.addEventListener("change", apply);
    });
  }

  function loadScript(src) {
    return new Promise(function (resolve, reject) {
      var existing = document.querySelector("script[src=\"" + src + "\"]");
      if (existing) {
        if (existing.getAttribute("data-loaded") === "1") return resolve();
        existing.addEventListener("load", function () { resolve(); });
        existing.addEventListener("error", reject);
        return;
      }
      var script = document.createElement("script");
      script.src = src;
      script.onload = function () { script.setAttribute("data-loaded", "1"); resolve(); };
      script.onerror = function () { reject(new Error("Could not load " + src)); };
      document.head.appendChild(script);
    });
  }

  function dayStart(value) {
    var date = value ? new Date(value) : new Date();
    if (isNaN(date.getTime()) && value) date = new Date(String(value).slice(0, 10) + "T00:00:00");
    date.setHours(0, 0, 0, 0);
    return date;
  }

  function billTiming(row, graceDays) {
    if (row.status === "paid" || row.status === "void") return row.status;
    if (!row.due_date) return "unpaid";
    var due = dayStart(row.due_date);
    var today = dayStart();
    if (due >= today) return "unpaid";
    var graceEnd = new Date(due.getTime());
    graceEnd.setDate(graceEnd.getDate() + graceDays);
    if (today <= graceEnd) return "grace";
    return "overdue";
  }

  function renderBilling() {
    var gen = viewGen;
    shell("<section class=\"panel\"><h1>Billing</h1><p class=\"muted\">Loading bills…</p></section>");
    Promise.all([
      db.from("invoices").select("*, customers(id, name, account_number, plan, plan_speed, address, monthly_bill, price)").order("due_date", { ascending: true }),
      db.from("payments").select("*, customers(name, account_number), invoices(period, id)").order("submitted_at", { ascending: false }),
      db.from("app_settings").select("key, value").in("key", ["grace_days"])
    ]).then(function (parts) {
      if (gen !== viewGen) return;
      if (parts[0].error) return flash(errText(parts[0].error));
      var invoices = parts[0].data || [];
      var payments = parts[1].error ? [] : (parts[1].data || []);
      var graceDays = 3;
      ((parts[2].data) || []).forEach(function (row) {
        if (row.key === "grace_days" && Number(row.value) > 0) graceDays = Number(row.value);
      });
      var today = dayStart();
      invoices.forEach(function (row) { row._bucket = billTiming(row, graceDays); });
      function sumOf(list) {
        return list.reduce(function (sum, row) { return sum + Number(row.amount || 0); }, 0);
      }
      var overdue = invoices.filter(function (row) { return row._bucket === "overdue"; });
      var grace = invoices.filter(function (row) { return row._bucket === "grace"; });
      var notDue = invoices.filter(function (row) { return row._bucket === "unpaid"; });
      var cards = [
        ["Overdue", overdue.length + " · " + money(sumOf(overdue))],
        ["Grace period", grace.length + " · " + money(sumOf(grace))],
        ["Unpaid, not yet due", notDue.length + " · " + money(sumOf(notDue))]
      ].map(function (card) {
        return "<article class=\"stat-card\"><div><p class=\"stat-label\">" + esc(card[0]) + "</p><p class=\"stat-value\">" + esc(card[1]) + "</p></div></article>";
      }).join("");
      var years = [];
      invoices.forEach(function (row) {
        var year = String(row.period || row.due_date || "").slice(0, 4);
        if (year && years.indexOf(year) === -1) years.push(year);
      });
      years.sort();
      function searchBlob(row) {
        var person = row.customers || {};
        return ((person.name || "") + " " + (person.account_number || "") + " " + (row.period || "") + " " + (row.id || "")).toLowerCase();
      }
      function billRow(row) {
        var person = row.customers || {};
        return "<tr data-search=\"" + esc(searchBlob(row)) + "\" data-status=\"" + esc(row.status) + "\" data-period=\"" + esc(row.period) + "\" data-month=\"" + esc(String(row.period || row.due_date || "").slice(5, 7)) + "\" data-year=\"" + esc(String(row.period || row.due_date || "").slice(0, 4)) + "\" data-bucket=\"" + esc(row._bucket) + "\">" +
          "<td data-label=\"Customer\">" + esc(person.name || "") + "<br><span class=\"muted\">" + esc(person.account_number || "") + "</span></td>" +
          "<td data-label=\"Period\">" + esc(row.period) + "</td><td data-label=\"Amount\">" + esc(money(row.amount)) + "</td>" +
          "<td data-label=\"Due\">" + esc(row.due_date || "—") + "</td><td data-label=\"Status\">" + statusPill(row._bucket === "grace" || row._bucket === "overdue" ? row._bucket : row.status) + "</td>" +
          "<td data-label=\"\">" +
          "<button type=\"button\" class=\"btn secondary\" data-soa=\"" + esc(person.id || row.customer_id) + "\" data-invoice=\"" + row.id + "\">Download SOA</button> " +
          (row.status === "void" ? "" : "<button type=\"button\" class=\"btn secondary\" data-void=\"" + row.id + "\">Void</button>") +
          "</td></tr>";
      }
      var dueRows = invoices.filter(function (row) {
        return (row.status === "unpaid" || row.status === "pending") && row.due_date && dayStart(row.due_date) >= today;
      }).slice().sort(function (a, b) { return String(a.due_date).localeCompare(String(b.due_date)); });
      var pendingPays = payments.filter(function (row) { return row.status === "pending"; });
      var confirmedPays = payments.filter(function (row) { return row.status === "confirmed"; });
      function payRow(row) {
        var person = row.customers || {};
        var bill = row.invoices || {};
        return "<tr data-search=\"" + esc(((person.name || "") + " " + (person.account_number || "") + " " + (bill.period || "") + " " + (row.id || "")).toLowerCase()) + "\" data-status=\"" + esc(row.status) + "\" data-month=\"" + esc(String(row.submitted_at || "").slice(5, 7)) + "\" data-year=\"" + esc(String(row.submitted_at || "").slice(0, 4)) + "\">" +
          "<td data-label=\"Customer\">" + esc(person.name || "") + "<br><span class=\"muted\">" + esc(person.account_number || "") + "</span></td>" +
          "<td data-label=\"Bill\">" + esc(bill.period || "") + "</td>" +
          "<td data-label=\"Amount\">" + esc(money(row.amount)) + "</td>" +
          "<td data-label=\"Method\">" + esc(row.method || "") + "</td>" +
          "<td data-label=\"Reference\">" + esc(row.reference_no || "—") + "</td>" +
          "<td data-label=\"When\">" + esc(manilaTime(row.submitted_at)) + "</td>" +
          "<td data-label=\"Status\">" + statusPill(row.status) + (row.reject_reason ? "<br><span class=\"muted\">" + esc(row.reject_reason) + "</span>" : "") + "</td>" +
          "<td data-label=\"Proof\"><div id=\"proof-" + row.id + "\"></div>" +
          (row.proof_path ? "" : "<button type=\"button\" class=\"btn secondary\" data-view-proof=\"" + row.id + "\">View</button>") + "</td>" +
          (row.status === "pending" ? "<td data-label=\"\"><input id=\"reject-" + row.id + "\" placeholder=\"Reject reason\"><div class=\"actions\"><button type=\"button\" class=\"btn\" data-confirm=\"" + row.id + "\">Confirm</button><button type=\"button\" class=\"btn secondary\" data-reject=\"" + row.id + "\">Reject</button></div></td>" : "<td></td>") +
          "</tr>";
      }
      var monthNow = manilaPeriod();
      var tabs = ["bills", "due", "proofs", "history"].map(function (tab) {
        var label = { bills: "Bills", due: "Due date", proofs: "Proof of payments", history: "Confirmed history" }[tab];
        return "<button type=\"button\" data-bill-tab=\"" + tab + "\"" + (billingTab === tab ? " class=\"active\"" : "") + ">" + label + "</button>";
      }).join("");
      shell("<section class=\"panel\"><h1>Billing</h1><div class=\"stat-grid\">" + cards + "</div>" +
        "<p class=\"muted\">Grace period is " + graceDays + " day(s) after the due date. Change it under Settings.</p>" +
        "<div class=\"toolbar\"><button type=\"button\" class=\"btn\" id=\"generate-bills\">Generate bills for</button><input id=\"generate-period\" type=\"month\" value=\"" + monthNow + "\"></div>" +
        "<form id=\"add-bill\" class=\"grid two\">" +
        "<div class=\"field\"><label for=\"bill-customer\">Customer</label><select id=\"bill-customer\" required><option value=\"\">Select</option>" + customerChoices() + "</select></div>" +
        "<div class=\"field\"><label for=\"bill-period\">Period</label><input id=\"bill-period\" type=\"month\" required value=\"" + monthNow + "\"></div>" +
        "<div class=\"field\"><label for=\"bill-amount\">Amount</label><input id=\"bill-amount\" type=\"number\" min=\"0\" step=\"0.01\" required></div>" +
        "<div class=\"field\"><label for=\"bill-due\">Due date</label><input id=\"bill-due\" type=\"date\"></div>" +
        "<button class=\"btn\" type=\"submit\">Add bill</button></form></section>" +
        "<div class=\"tabs\" id=\"bill-tabs\">" + tabs + "</div>" +
        "<div class=\"filters\"><input id=\"bill-q\" placeholder=\"Search name, account, or invoice\">" +
        "<select id=\"bill-status\"><option value=\"\">All statuses</option><option>unpaid</option><option>pending</option><option>paid</option><option>void</option><option>grace</option><option>overdue</option></select>" +
        "<select id=\"bill-month\"><option value=\"\">All months</option>" + ["01","02","03","04","05","06","07","08","09","10","11","12"].map(function (month) { return "<option value=\"" + month + "\">" + month + "</option>"; }).join("") + "</select>" +
        "<select id=\"bill-year\"><option value=\"\">All years</option>" + years.map(function (year) { return "<option>" + esc(year) + "</option>"; }).join("") + "</select></div>" +
        "<div class=\"table-card\" id=\"pane-bills\"" + (billingTab === "bills" ? "" : " hidden") + "><table id=\"bill-table\"><thead><tr><th>Customer</th><th>Period</th><th>Amount</th><th>Due</th><th>Status</th><th></th></tr></thead><tbody>" +
        (invoices.map(billRow).join("") || "<tr><td colspan=\"6\">No bills yet.</td></tr>") + "</tbody></table></div>" +
        "<div class=\"table-card\" id=\"pane-due\"" + (billingTab === "due" ? "" : " hidden") + "><table id=\"bill-due-table\"><thead><tr><th>Customer</th><th>Period</th><th>Amount</th><th>Due</th><th>Status</th><th></th></tr></thead><tbody>" +
        (dueRows.map(billRow).join("") || "<tr><td colspan=\"6\">No upcoming due dates.</td></tr>") + "</tbody></table></div>" +
        "<div class=\"table-card\" id=\"pane-proofs\"" + (billingTab === "proofs" ? "" : " hidden") + "><table id=\"bill-proof-table\"><thead><tr><th>Customer</th><th>Bill</th><th>Amount</th><th>Method</th><th>Reference</th><th>When</th><th>Status</th><th>Proof</th><th></th></tr></thead><tbody>" +
        (pendingPays.map(payRow).join("") || "<tr><td colspan=\"9\">No proofs waiting for review.</td></tr>") + "</tbody></table></div>" +
        "<div class=\"table-card\" id=\"pane-history\"" + (billingTab === "history" ? "" : " hidden") + "><table id=\"bill-history-table\"><thead><tr><th>Customer</th><th>Bill</th><th>Amount</th><th>Method</th><th>Reference</th><th>When</th><th>Status</th><th>Proof</th><th></th></tr></thead><tbody>" +
        (confirmedPays.map(payRow).join("") || "<tr><td colspan=\"9\">No confirmed payments yet.</td></tr>") + "</tbody></table></div>");
      if (parts[1].error) flash("Payments could not be loaded. Apply supabase/migrations/20261119_finance_billing.sql if reject reasons are missing. " + errText(parts[1].error));
      pendingPays.concat(confirmedPays).forEach(function (row) { if (row.proof_path) proofThumb(row.proof_path, "proof-" + row.id); });
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
      document.querySelectorAll("[data-bill-tab]").forEach(function (button) {
        button.onclick = function () {
          billingTab = button.getAttribute("data-bill-tab");
          ["bills", "due", "proofs", "history"].forEach(function (tab) {
            var pane = document.getElementById("pane-" + tab);
            if (pane) pane.hidden = tab !== billingTab;
            if (button.parentNode) {
              button.parentNode.querySelectorAll("button").forEach(function (el) { el.classList.toggle("active", el === button); });
            }
          });
        };
      });
      function filterBills() {
        var q = document.getElementById("bill-q").value.trim().toLowerCase();
        var status = document.getElementById("bill-status").value;
        var month = document.getElementById("bill-month").value;
        var year = document.getElementById("bill-year").value;
        app.querySelectorAll("#bill-table tbody tr, #bill-due-table tbody tr, #bill-proof-table tbody tr, #bill-history-table tbody tr").forEach(function (row) {
          if (!row.getAttribute("data-search")) return;
          var statusOk = !status || row.getAttribute("data-status") === status || row.getAttribute("data-bucket") === status;
          row.hidden = (q && row.getAttribute("data-search").indexOf(q) === -1) || !statusOk ||
            (month && row.getAttribute("data-month") !== month) ||
            (year && row.getAttribute("data-year") !== year);
        });
      }
      ["bill-q", "bill-status", "bill-month", "bill-year"].forEach(function (id) {
        var el = document.getElementById(id);
        if (!el) return;
        el.addEventListener("input", filterBills);
        el.addEventListener("change", filterBills);
      });
      app.querySelectorAll("[data-void]").forEach(function (button) {
        button.onclick = function () {
          db.from("invoices").update({ status: "void" }).eq("id", button.getAttribute("data-void")).then(function (update) {
            if (update.error) return flash(errText(update.error));
            renderBilling();
          });
        };
      });
      app.querySelectorAll("[data-soa]").forEach(function (button) {
        button.onclick = function () { downloadSoa(button.getAttribute("data-soa"), button.getAttribute("data-invoice")); };
      });
      app.querySelectorAll("[data-view-proof]").forEach(function (button) {
        button.onclick = function () { showStoredProof(button.getAttribute("data-view-proof")); };
      });
      app.querySelectorAll("[data-confirm]").forEach(function (button) {
        button.onclick = function () { reviewPayment(button.getAttribute("data-confirm"), "confirmed", ""); };
      });
      app.querySelectorAll("[data-reject]").forEach(function (button) {
        button.onclick = function () {
          var id = button.getAttribute("data-reject");
          var reasonEl = document.getElementById("reject-" + id);
          reviewPayment(id, "rejected", reasonEl ? reasonEl.value.trim() : "");
        };
      });
    }).catch(function (error) { flash(errText(error)); });
  }

  function reviewPayment(id, status, reason) {
    if (status === "rejected" && !reason) return flash("Add a reject reason.");
    var patch = {
      status: status,
      confirmed_by: sessionEmail,
      confirmed_at: new Date().toISOString()
    };
    if (status === "rejected") patch.reject_reason = reason;
    db.from("payments").update(patch).eq("id", id).then(function (update) {
      if (update.error) return flash(errText(update.error));
      flash(status === "confirmed" ? "Payment confirmed." : "Payment rejected.", true);
      renderBilling();
    });
  }

  function showStoredProof(paymentId) {
    var box = document.getElementById("proof-" + paymentId);
    if (!box) return;
    box.innerHTML = "<p class=\"muted\">Loading…</p>";
    db.from("payment_proof_files").select("content_type, image_base64").eq("payment_id", paymentId).maybeSingle().then(function (result) {
      if (result.error || !result.data) {
        box.innerHTML = "<p class=\"muted\">No stored screenshot for this payment.</p>";
        return;
      }
      var src = "data:" + result.data.content_type + ";base64," + result.data.image_base64;
      box.innerHTML = "<a href=\"" + src + "\" target=\"_blank\" rel=\"noopener\"><img class=\"id-thumb\" alt=\"Payment proof\" src=\"" + src + "\"></a>";
    });
  }

  function downloadSoa(customerId, invoiceId) {
    Promise.all([
      db.from("customers").select("name, account_number, plan, plan_speed, address, area").eq("id", customerId).single(),
      db.from("invoices").select("*").eq("customer_id", customerId).order("period"),
      db.from("payments").select("*").eq("customer_id", customerId).order("submitted_at"),
      loadScript("https://cdn.jsdelivr.net/npm/jspdf@2.5.2/dist/jspdf.umd.min.js")
    ]).then(function (parts) {
      if (parts[0].error) return flash(errText(parts[0].error));
      if (parts[1].error) return flash(errText(parts[1].error));
      var person = parts[0].data || {};
      var invoices = parts[1].data || [];
      var payments = parts[2].error ? [] : (parts[2].data || []);
      var JsPDF = window.jspdf && window.jspdf.jsPDF;
      if (!JsPDF) return flash("Could not load the PDF library.");
      var doc = new JsPDF();
      var y = 16;
      function line(text, size, color) {
        if (y > 280) { doc.addPage(); y = 16; }
        doc.setFontSize(size || 11);
        doc.setTextColor(color || 30);
        doc.text(String(text), 14, y);
        y += (size || 11) > 13 ? 8 : 6;
      }
      doc.setTextColor(255, 0, 0);
      doc.setFontSize(18);
      doc.text("FiberBro", 14, y);
      y += 8;
      line("Internet Communication Services Corp.", 12, 40);
      line("Payatas, Quezon City", 11, 80);
      y += 4;
      line("Statement of Account", 14, 20);
      line(person.name || "Customer", 12, 20);
      line("Account " + (person.account_number || "—"), 11, 60);
      line("Plan: " + (person.plan_speed || person.plan || "—"), 11, 60);
      if (person.address) line(person.address + (person.area ? ", " + person.area : ""), 11, 60);
      y += 2;
      line("Bills", 12, 20);
      var billed = 0;
      invoices.forEach(function (inv) {
        if (inv.status !== "void") billed += Number(inv.amount) || 0;
        var mark = inv.id === invoiceId ? "  < this invoice" : "";
        line((inv.period || "") + "   " + money(inv.amount) + "   due " + (inv.due_date || "—") + "   " + inv.status + mark, 10, 40);
      });
      y += 2;
      line("Payments", 12, 20);
      var paid = 0;
      payments.forEach(function (pay) {
        if (pay.status === "confirmed") paid += Number(pay.amount) || 0;
        line((pay.reference_no || pay.method || "Payment") + "   " + money(pay.amount) + "   " + (pay.method || "") + "   " + pay.status, 10, 40);
      });
      y += 2;
      line("Balance " + money(billed - paid), 13, 180);
      if (paid > billed) line("Wallet credit " + money(paid - billed), 12, 40);
      doc.save("FiberBro-SOA-" + (person.account_number || "account") + ".pdf");
    }).catch(function (error) { flash(errText(error)); });
  }

  function renderFinance() {
    var gen = viewGen;
    shell("<section class=\"panel\"><h1>Finance</h1><p class=\"muted\">Loading…</p></section>");
    var monthNow = manilaPeriod();
    Promise.all([
      db.from("invoices").select("status, amount, period, paid_at"),
      db.from("expenses").select("*").order("expense_date", { ascending: false }),
      db.from("customers").select("id, installation_date"),
      db.from("app_settings").select("key, value").eq("key", "installation_fee").maybeSingle()
    ]).then(function (parts) {
      if (gen !== viewGen) return;
      if (parts[1].error) return flash("Expenses are not available yet. Apply supabase/migrations/20261119_finance_billing.sql. " + errText(parts[1].error));
      var invoices = parts[0].error ? [] : (parts[0].data || []);
      var expenses = parts[1].data || [];
      var installs = parts[2].error ? [] : (parts[2].data || []);
      var fee = 1000;
      if (parts[3].data && Number(parts[3].data.value) > 0) fee = Number(parts[3].data.value);
      var years = [];
      function rememberYear(value) {
        var year = String(value || "").slice(0, 4);
        if (year && years.indexOf(year) === -1) years.push(year);
      }
      invoices.forEach(function (row) { rememberYear(row.period); });
      expenses.forEach(function (row) { rememberYear(row.expense_date); });
      if (years.indexOf(monthNow.slice(0, 4)) === -1) years.push(monthNow.slice(0, 4));
      years.sort();
      var categories = ["Gas", "Meals", "Materials", "Maintenance", "Office Supplies", "Transportation", "Repairs", "Others", "Operational", "Personal"];
      function paint(month, year, category, status) {
        var period = year && month ? year + "-" + month : "";
        var sales = invoices.filter(function (row) {
          return row.status === "paid" && (!year || String(row.period || "").slice(0, 4) === year) && (!month || String(row.period || "").slice(5, 7) === month);
        }).reduce(function (sum, row) { return sum + Number(row.amount || 0); }, 0);
        var installation = installs.filter(function (row) {
          var stamp = String(row.installation_date || "");
          return stamp && (!year || stamp.slice(0, 4) === year) && (!month || stamp.slice(5, 7) === month);
        }).length * fee;
        var shown = expenses.filter(function (row) {
          var stamp = String(row.expense_date || "");
          return (!year || stamp.slice(0, 4) === year) && (!month || stamp.slice(5, 7) === month) &&
            (!category || row.category === category) && (!status || row.status === status);
        });
        var approvedSpend = shown.filter(function (row) { return row.status === "approved"; }).reduce(function (sum, row) { return sum + Number(row.amount || 0); }, 0);
        var pending = expenses.filter(function (row) { return row.status === "pending"; });
        var pendingTotal = pending.reduce(function (sum, row) { return sum + Number(row.amount || 0); }, 0);
        var cards = [
          ["Total sales", money(sales)],
          ["Total installation", money(installation)],
          ["Total expenses", money(approvedSpend)],
          ["Net", money(sales + installation - approvedSpend)],
          ["Pending approval", pending.length + " · " + money(pendingTotal)]
        ].map(function (card) {
          return "<article class=\"stat-card\"><div><p class=\"stat-label\">" + esc(card[0]) + "</p><p class=\"stat-value\">" + esc(card[1]) + "</p></div></article>";
        }).join("");
        var body = shown.map(function (row) {
          return "<tr><td data-label=\"Date\">" + esc(row.expense_date || "") + "</td>" +
            "<td data-label=\"Category\">" + esc(row.category) + (row.account_code ? " · " + esc(row.account_code) : "") + (row.auto ? " · auto" : "") + "</td>" +
            "<td data-label=\"Amount\">" + esc(money(row.amount)) + "</td>" +
            "<td data-label=\"Remarks\">" + esc(row.remarks || "") + "</td>" +
            "<td data-label=\"Status\">" + statusPill(row.status) + "</td>" +
            "<td data-label=\"Receipt\">" + (row.receipt_path ? "<button type=\"button\" class=\"btn secondary\" data-receipt=\"" + esc(row.receipt_path) + "\">View</button>" : "—") + "</td>" +
            "<td data-label=\"\">" + (row.status === "pending" ? "<button type=\"button\" class=\"btn\" data-approve=\"" + row.id + "\">Approve</button> <button type=\"button\" class=\"btn secondary\" data-deny=\"" + row.id + "\">Reject</button>" : esc(row.approved_by || "")) + "</td></tr>";
        }).join("");
        shell("<section class=\"panel\"><h1>Finance</h1><div class=\"stat-grid\">" + cards + "</div>" +
          "<p class=\"muted\">Sales are paid invoices for the period. Installation is ₱" + esc(String(fee)) + " for each customer whose installation date is in that period. Net is sales plus installation minus approved expenses.</p>" +
          "<div class=\"filters\"><select id=\"fin-month\">" + ["","01","02","03","04","05","06","07","08","09","10","11","12"].map(function (item) {
            return "<option value=\"" + item + "\"" + (item === month ? " selected" : "") + ">" + (item || "All months") + "</option>";
          }).join("") + "</select>" +
          "<select id=\"fin-year\">" + ["",].concat(years).map(function (item) {
            return "<option value=\"" + esc(item) + "\"" + (item === year ? " selected" : "") + ">" + (item || "All years") + "</option>";
          }).join("") + "</select>" +
          "<select id=\"fin-category\"><option value=\"\">All categories</option>" + categories.map(function (item) {
            return "<option" + (item === category ? " selected" : "") + ">" + esc(item) + "</option>";
          }).join("") + "</select>" +
          "<select id=\"fin-status\"><option value=\"\">All statuses</option><option" + (status === "pending" ? " selected" : "") + ">pending</option><option" + (status === "approved" ? " selected" : "") + ">approved</option><option" + (status === "rejected" ? " selected" : "") + ">rejected</option></select>" +
          "<button type=\"button\" class=\"btn\" id=\"add-expense\">Add expense</button></div>" +
          "<div class=\"table-card\"><table><thead><tr><th>Date</th><th>Category</th><th>Amount</th><th>Remarks</th><th>Status</th><th>Receipt</th><th></th></tr></thead><tbody>" +
          (body || "<tr><td colspan=\"7\">No expenses for this filter.</td></tr>") + "</tbody></table></div>" +
          "<div id=\"expense-modal\" class=\"modal\" hidden><div class=\"modal-card\" role=\"dialog\" aria-labelledby=\"expense-title\">" +
          "<h2 id=\"expense-title\">Add expense</h2><form id=\"expense-form\" class=\"grid\">" +
          "<div class=\"field\"><label for=\"expense-category\">Category</label><select id=\"expense-category\" required>" + categories.map(function (item) { return "<option>" + esc(item) + "</option>"; }).join("") + "</select></div>" +
          "<div class=\"field\"><label for=\"expense-amount\">Amount</label><input id=\"expense-amount\" type=\"number\" min=\"0\" step=\"0.01\" required></div>" +
          "<div class=\"field\"><label for=\"expense-date\">Date</label><input id=\"expense-date\" type=\"date\" required value=\"" + new Date().toISOString().slice(0, 10) + "\"></div>" +
          "<div class=\"field\"><label for=\"expense-remarks\">Remarks</label><textarea id=\"expense-remarks\"></textarea></div>" +
          "<div class=\"field\"><label for=\"expense-receipt\">Receipt photo</label><input id=\"expense-receipt\" type=\"file\" accept=\"image/jpeg,image/png,image/webp\"></div>" +
          "<div class=\"actions\"><button class=\"btn\" type=\"submit\">Save expense</button><button type=\"button\" class=\"btn secondary\" id=\"expense-read\">Read amount</button><button type=\"button\" class=\"btn secondary\" id=\"expense-cancel\">Cancel</button></div>" +
          "</form></div></div></section>");
        ["fin-month", "fin-year", "fin-category", "fin-status"].forEach(function (id) {
          document.getElementById(id).onchange = function () {
            paint(document.getElementById("fin-month").value, document.getElementById("fin-year").value, document.getElementById("fin-category").value, document.getElementById("fin-status").value);
          };
        });
        document.getElementById("add-expense").onclick = function () { document.getElementById("expense-modal").hidden = false; };
        document.getElementById("expense-cancel").onclick = function () { document.getElementById("expense-modal").hidden = true; };
        document.getElementById("expense-read").onclick = readReceiptAmount;
        document.getElementById("expense-form").onsubmit = function (event) {
          event.preventDefault();
          saveExpense().then(function (ok) { if (ok) renderFinance(); });
        };
        app.querySelectorAll("[data-approve], [data-deny]").forEach(function (button) {
          button.onclick = function () {
            var approving = button.hasAttribute("data-approve");
            var id = button.getAttribute(approving ? "data-approve" : "data-deny");
            db.from("expenses").update({
              status: approving ? "approved" : "rejected",
              approved_by: sessionEmail,
              approved_at: new Date().toISOString()
            }).eq("id", id).then(function (update) {
              if (update.error) return flash(errText(update.error));
              renderFinance();
            });
          };
        });
        app.querySelectorAll("[data-receipt]").forEach(function (button) {
          button.onclick = function () {
            db.storage.from("expense-receipts").createSignedUrl(button.getAttribute("data-receipt"), 3600).then(function (signed) {
              if (signed.error || !signed.data) return flash(errText(signed.error));
              window.open(signed.data.signedUrl, "_blank", "noopener");
            });
          };
        });
      }
      paint(monthNow.slice(5, 7), monthNow.slice(0, 4), "", "");
    }).catch(function (error) { flash(errText(error)); });
  }

  function receiptPath(file) {
    var alphabet = "abcdefghijklmnopqrstuvwxyz0123456789";
    var rand = "";
    var bytes = new Uint8Array(8);
    if (window.crypto && window.crypto.getRandomValues) window.crypto.getRandomValues(bytes);
    for (var i = 0; i < bytes.length; i++) rand += alphabet.charAt(bytes[i] % alphabet.length);
    var ext = "jpg";
    if (file && file.type === "image/png") ext = "png";
    if (file && file.type === "image/webp") ext = "webp";
    return "receipts/" + rand + "." + ext;
  }

  function saveExpense() {
    var file = document.getElementById("expense-receipt").files[0];
    var record = {
      category: document.getElementById("expense-category").value,
      amount: Number(document.getElementById("expense-amount").value),
      expense_date: document.getElementById("expense-date").value,
      remarks: document.getElementById("expense-remarks").value.trim() || null,
      status: "pending",
      created_by: sessionEmail
    };
    var upload = Promise.resolve(null);
    if (file) {
      var path = receiptPath(file);
      upload = db.storage.from("expense-receipts").upload(path, file, { contentType: file.type || "image/jpeg", upsert: false }).then(function (result) {
        if (result.error) throw result.error;
        return path;
      });
    }
    return upload.then(function (path) {
      if (path) record.receipt_path = path;
      return db.from("expenses").insert(record);
    }).then(function (insert) {
      if (insert.error) { flash(errText(insert.error)); return false; }
      flash("Expense saved.", true);
      return true;
    }).catch(function (error) { flash(errText(error)); return false; });
  }

  function readReceiptAmount() {
    var file = document.getElementById("expense-receipt").files[0];
    if (!file) return flash("Choose a receipt photo first.");
    flash("Reading the receipt…", true);
    loadScript("https://cdn.jsdelivr.net/npm/tesseract.js@5.1.1/dist/tesseract.min.js").then(function () {
      if (!window.Tesseract) throw new Error("Receipt reader did not load.");
      return window.Tesseract.recognize(file, "eng");
    }).then(function (result) {
      var text = (result && result.data && result.data.text) || "";
      var matches = text.match(/\d{1,3}(?:,\d{3})*(?:\.\d{2})|\d+\.\d{2}/g) || [];
      var best = 0;
      matches.forEach(function (item) {
        var num = Number(String(item).replace(/,/g, ""));
        if (num > best && num < 1000000) best = num;
      });
      if (!best) return flash("No amount was found. Type it in.");
      document.getElementById("expense-amount").value = best.toFixed(2);
      flash("Amount filled from the receipt. You can edit it.", true);
    }).catch(function (error) { flash(errText(error)); });
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

  function customerPinColor(row, openBills) {
    if (row.for_disconnection) return "#9AA0A6";
    if (row.stage === "inquiry" || row.stage === "in_progress" || row.stage === "encoded") return "#B87333";
    var bills = openBills[row.id] || [];
    var today = new Date();
    today.setHours(0, 0, 0, 0);
    var overdue = bills.some(function (bill) {
      return bill.due_date && new Date(String(bill.due_date).slice(0, 10) + "T00:00:00") < today;
    });
    if (overdue) return "#FF0000";
    if (bills.length) return "#E07A3D";
    if (row.stage === "active") return "#2E7D32";
    return "#6B6F76";
  }

  function pinStatus(row, openBills) {
    if (row.for_disconnection) return "Disconnected";
    if (row.stage !== "active") return stageLabel(row.stage);
    var bills = openBills[row.id] || [];
    if (!bills.length) return "Active / paid";
    return "Unpaid";
  }

  function renderMap() {
    var gen = viewGen;
    shell("<section class=\"panel\"><h1>Network map</h1>" +
      "<div class=\"filters\">" +
      "<select id=\"map-area\"><option value=\"\">All areas</option></select>" +
      "<select id=\"map-investor\"><option value=\"\">All investors</option></select>" +
      "<select id=\"map-lp\"><option value=\"\">All LPs</option></select>" +
      "<select id=\"map-nap\"><option value=\"\">All NAPs</option></select>" +
      "<label class=\"field check\"><input id=\"layer-lp\" type=\"checkbox\" checked> LP to NAP</label>" +
      "<label class=\"field check\"><input id=\"layer-cust\" type=\"checkbox\" checked> NAP to customer</label>" +
      "<label class=\"field check\"><input id=\"layer-areas\" type=\"checkbox\" checked> Areas</label>" +
      "</div>" +
      "<div id=\"ops-map\" class=\"ops-map\"></div>" +
      "<div class=\"legend\" id=\"map-legend\"></div>" +
      "<p id=\"map-note\" class=\"muted\"></p>" +
      "<div class=\"actions\">" +
      "<button type=\"button\" class=\"btn secondary\" id=\"add-node\">Add node</button>" +
      "<button type=\"button\" class=\"btn secondary\" id=\"add-lp\">Add LP</button>" +
      "<button type=\"button\" class=\"btn secondary\" id=\"add-nap\">Add NAP</button>" +
      "<button type=\"button\" class=\"btn secondary\" id=\"draw-area\">Draw area</button>" +
      "<button type=\"button\" class=\"btn secondary\" id=\"use-location\">Use my current location</button>" +
      "</div>" +
      "<form id=\"node-form\" class=\"grid two\" hidden>" +
      "<input type=\"hidden\" id=\"node-id\"><input type=\"hidden\" id=\"node-lat\"><input type=\"hidden\" id=\"node-lng\">" +
      "<div class=\"field\"><label>Type</label><select id=\"node-type\"><option>OLT</option><option>LCP</option><option>NAP</option><option>CLOSURE</option><option>POLE</option><option>OTHER</option></select></div>" +
      "<div class=\"field\"><label>Name</label><input id=\"node-name\" required></div>" +
      "<div class=\"field\"><label>Ports</label><input id=\"node-ports\" type=\"number\" min=\"0\" step=\"1\"></div>" +
      "<div class=\"field\"><label>Notes</label><input id=\"node-notes\"></div>" +
      "<div class=\"actions\"><button class=\"btn\" type=\"submit\">Save node</button><button class=\"btn secondary\" type=\"button\" id=\"node-cancel\">Cancel</button></div></form>" +
      "<form id=\"lp-form\" class=\"grid two\" hidden>" +
      "<input type=\"hidden\" id=\"lp-id\"><input type=\"hidden\" id=\"lp-lat\"><input type=\"hidden\" id=\"lp-lng\">" +
      "<div class=\"field\"><label for=\"lp-code\">Code</label><input id=\"lp-code\" required></div>" +
      "<div class=\"field\"><label for=\"lp-name\">Name</label><input id=\"lp-name\" required></div>" +
      "<div class=\"field\"><label for=\"lp-area\">Area</label><input id=\"lp-area\"></div>" +
      "<div class=\"field\"><label for=\"lp-sub\">Sub area</label><input id=\"lp-sub\"></div>" +
      "<div class=\"field\"><label for=\"lp-ports\">Port capacity</label><input id=\"lp-ports\" type=\"number\" min=\"0\" step=\"1\"></div>" +
      "<div class=\"field\"><label for=\"lp-notes\">Notes</label><input id=\"lp-notes\"></div>" +
      "<div class=\"field\"><label for=\"lp-photo\">Photo</label><input id=\"lp-photo\" type=\"file\" accept=\"image/jpeg,image/png,image/webp\"></div>" +
      "<div class=\"actions\"><button class=\"btn\" type=\"submit\">Save LP</button><button class=\"btn secondary\" type=\"button\" id=\"lp-cancel\">Cancel</button></div></form>" +
      "<form id=\"nap-form\" class=\"grid two\" hidden>" +
      "<input type=\"hidden\" id=\"nap-id\"><input type=\"hidden\" id=\"nap-lat\"><input type=\"hidden\" id=\"nap-lng\">" +
      "<div class=\"field\"><label for=\"nap-lp\">Parent LP</label><select id=\"nap-lp\"></select></div>" +
      "<div class=\"field\"><label for=\"nap-code\">Code</label><input id=\"nap-code\" required></div>" +
      "<div class=\"field\"><label for=\"nap-name\">Name</label><input id=\"nap-name\" required></div>" +
      "<div class=\"field\"><label for=\"nap-area\">Area</label><input id=\"nap-area\"></div>" +
      "<div class=\"field\"><label for=\"nap-sub\">Sub area</label><input id=\"nap-sub\"></div>" +
      "<div class=\"field\"><label for=\"nap-ports\">Port capacity</label><input id=\"nap-ports\" type=\"number\" min=\"1\" step=\"1\" value=\"8\"></div>" +
      "<div class=\"field\"><label for=\"nap-notes\">Notes</label><input id=\"nap-notes\"></div>" +
      "<div class=\"field\"><label for=\"nap-photo\">Photo</label><input id=\"nap-photo\" type=\"file\" accept=\"image/jpeg,image/png,image/webp\"></div>" +
      "<div class=\"actions\"><button class=\"btn\" type=\"submit\">Save NAP</button><button class=\"btn secondary\" type=\"button\" id=\"nap-cancel\">Cancel</button></div></form>" +
      "<form id=\"area-form\" class=\"grid\" hidden>" +
      "<p class=\"muted\" id=\"area-count\">Click the map to add corners.</p>" +
      "<div class=\"field\"><label for=\"area-name\">Area name</label><input id=\"area-name\" required></div>" +
      "<div class=\"actions\"><button class=\"btn\" type=\"submit\">Save area</button><button class=\"btn secondary\" type=\"button\" id=\"area-cancel\">Cancel</button></div></form>" +
      "<div id=\"node-list\"></div><div id=\"full-naps\"></div></section>");
    if (!window.L) {
      flash("Map library did not load.");
      return;
    }
    var map = L.map("ops-map").setView([14.711, 121.110], 14);
    osmTiles().addTo(map);
    var adding = "";
    var areaPoints = [];
    var areaLine = null;
    document.getElementById("add-node").onclick = function () { adding = "node"; this.textContent = "Click the map…"; };
    document.getElementById("add-lp").onclick = function () { adding = "lp"; this.textContent = "Click the map…"; };
    document.getElementById("add-nap").onclick = function () { adding = "nap"; this.textContent = "Click the map…"; };
    document.getElementById("draw-area").onclick = function () {
      adding = "area";
      areaPoints = [];
      document.getElementById("area-form").hidden = false;
      document.getElementById("area-count").textContent = "Click the map to add corners.";
    };
    document.getElementById("node-cancel").onclick = function () { document.getElementById("node-form").hidden = true; adding = ""; };
    document.getElementById("lp-cancel").onclick = function () { document.getElementById("lp-form").hidden = true; adding = ""; };
    document.getElementById("nap-cancel").onclick = function () { document.getElementById("nap-form").hidden = true; adding = ""; };
    document.getElementById("area-cancel").onclick = function () {
      document.getElementById("area-form").hidden = true;
      adding = "";
      if (areaLine) map.removeLayer(areaLine);
    };
    document.getElementById("use-location").onclick = function () {
      if (!navigator.geolocation) return flash("This browser has no location.");
      navigator.geolocation.getCurrentPosition(function (pos) {
        var lat = pos.coords.latitude;
        var lng = pos.coords.longitude;
        ["node", "lp", "nap"].forEach(function (prefix) {
          var latEl = document.getElementById(prefix + "-lat");
          var lngEl = document.getElementById(prefix + "-lng");
          if (latEl && !document.getElementById(prefix + "-form").hidden) {
            latEl.value = lat;
            lngEl.value = lng;
          }
        });
        map.setView([lat, lng], 17);
        flash("Location set on the open form. Open Add LP or Add NAP first if none is open.", true);
      }, function () { flash("Location was blocked."); });
    };
    map.on("click", function (event) {
      if (adding === "node") {
        document.getElementById("node-id").value = "";
        document.getElementById("node-lat").value = event.latlng.lat;
        document.getElementById("node-lng").value = event.latlng.lng;
        document.getElementById("node-form").hidden = false;
        adding = "";
        document.getElementById("add-node").textContent = "Add node";
      } else if (adding === "lp") {
        document.getElementById("lp-id").value = "";
        document.getElementById("lp-lat").value = event.latlng.lat;
        document.getElementById("lp-lng").value = event.latlng.lng;
        document.getElementById("lp-form").hidden = false;
        adding = "";
        document.getElementById("add-lp").textContent = "Add LP";
      } else if (adding === "nap") {
        document.getElementById("nap-id").value = "";
        document.getElementById("nap-lat").value = event.latlng.lat;
        document.getElementById("nap-lng").value = event.latlng.lng;
        document.getElementById("nap-form").hidden = false;
        adding = "";
        document.getElementById("add-nap").textContent = "Add NAP";
      } else if (adding === "area") {
        areaPoints.push(event.latlng);
        if (areaLine) map.removeLayer(areaLine);
        areaLine = L.polyline(areaPoints, { color: "#B87333" }).addTo(map);
        document.getElementById("area-count").textContent = areaPoints.length + " corners. Click Save area when the shape is closed enough.";
      }
    });
    function quiet(builder) {
      return builder.then(function (result) { return result.error ? [] : (result.data || []); }).catch(function () { return []; });
    }
    Promise.all([
      db.from("network_nodes").select("*"),
      db.from("customers").select("id, name, account_number, stage, latitude, longitude, area, investor_id, plan, plan_speed, for_disconnection, lp_id, nap_id").then(function (result) {
        if (!result.error) return result;
        return db.from("customers").select("id, name, account_number, stage, latitude, longitude, area, investor_id, plan, plan_speed, for_disconnection");
      }),
      db.from("invoices").select("customer_id, status, amount, due_date").in("status", ["unpaid", "pending"]),
      quiet(db.from("distribution_points").select("*")),
      quiet(db.from("nap_boxes").select("*")),
      quiet(db.from("area_polygons").select("*"))
    ]).then(function (parts) {
      if (gen !== viewGen) return;
      if (parts[0].error) throw parts[0].error;
      var nodes = parts[0].data || [];
      var customers = parts[1].error ? [] : (parts[1].data || []);
      var invoices = parts[2].error ? [] : (parts[2].data || []);
      var lps = parts[3] || [];
      var naps = parts[4] || [];
      var areas = parts[5] || [];
      if (!lps.length && !naps.length) document.getElementById("map-note").textContent = "LP and NAP tables appear after supabase/migrations/20261120_network_map.sql is applied. Existing nodes and customer pins still show.";
      var openBills = {};
      invoices.forEach(function (bill) {
        if (!openBills[bill.customer_id]) openBills[bill.customer_id] = [];
        openBills[bill.customer_id].push(bill);
      });
      var used = {};
      customers.forEach(function (row) { if (row.nap_id) used[row.nap_id] = (used[row.nap_id] || 0) + 1; });
      var areaNames = [];
      customers.forEach(function (row) { if (row.area && areaNames.indexOf(row.area) === -1) areaNames.push(row.area); });
      areas.forEach(function (row) { if (areaNames.indexOf(row.area_name) === -1) areaNames.push(row.area_name); });
      areaNames.sort();
      document.getElementById("map-area").innerHTML = "<option value=\"\">All areas</option>" + areaNames.map(function (name) {
        var count = customers.filter(function (row) { return row.area === name; }).length;
        return "<option value=\"" + esc(name) + "\">" + esc(name) + " (" + count + ")</option>";
      }).join("");
      document.getElementById("map-investor").innerHTML = "<option value=\"\">All investors</option>" + state.investors.map(function (inv) {
        return "<option value=\"" + inv.id + "\">" + esc(investorLabel(inv)) + "</option>";
      }).join("");
      document.getElementById("map-lp").innerHTML = "<option value=\"\">All LPs</option>" + lps.map(function (row) {
        return "<option value=\"" + row.id + "\">" + esc(row.code + " · " + row.name) + "</option>";
      }).join("");
      document.getElementById("map-nap").innerHTML = "<option value=\"\">All NAPs</option>" + naps.map(function (row) {
        return "<option value=\"" + row.id + "\">" + esc(row.code + " · " + row.name) + "</option>";
      }).join("");
      document.getElementById("nap-lp").innerHTML = lps.map(function (row) {
        return "<option value=\"" + row.id + "\">" + esc(row.code + " · " + row.name) + "</option>";
      }).join("");
      var legend = "<span class=\"legend-item\"><i style=\"background:#2E7D32\"></i>Active / paid</span>" +
        "<span class=\"legend-item\"><i style=\"background:#FF0000\"></i>Unpaid / overdue</span>" +
        "<span class=\"legend-item\"><i style=\"background:#B87333\"></i>New</span>" +
        "<span class=\"legend-item\"><i style=\"background:#9AA0A6\"></i>Disconnected</span>";
      areaNames.forEach(function (name) {
        var count = customers.filter(function (row) { return row.area === name; }).length;
        legend += "<span class=\"legend-item\"><i style=\"background:#B87333\"></i>" + esc(name) + " " + count + "</span>";
      });
      document.getElementById("map-legend").innerHTML = legend;
      var lpLayer = L.layerGroup().addTo(map);
      var custLineLayer = L.layerGroup().addTo(map);
      var areaLayer = L.layerGroup().addTo(map);
      var cluster = L.markerClusterGroup ? L.markerClusterGroup({ chunkedLoading: true, maxClusterRadius: 45 }) : L.layerGroup();
      map.addLayer(cluster);
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
      function draw() {
        lpLayer.clearLayers();
        custLineLayer.clearLayers();
        areaLayer.clearLayers();
        cluster.clearLayers();
        var area = document.getElementById("map-area").value;
        var investor = document.getElementById("map-investor").value;
        var lpId = document.getElementById("map-lp").value;
        var napId = document.getElementById("map-nap").value;
        var visible = customers.filter(function (row) {
          return (!area || row.area === area) && (!investor || row.investor_id === investor) &&
            (!lpId || row.lp_id === lpId) && (!napId || row.nap_id === napId);
        });
        if (document.getElementById("layer-lp").checked) {
          naps.forEach(function (nap) {
            var parent = lps.filter(function (lp) { return lp.id === nap.lp_id; })[0];
            if (!parent) return;
            L.polyline([[parent.latitude, parent.longitude], [nap.latitude, nap.longitude]], { color: "#B87333", weight: 2 }).addTo(lpLayer);
          });
        }
        lps.forEach(function (lp) {
          L.circleMarker([lp.latitude, lp.longitude], { radius: 9, color: "#FF0000", fillColor: "#FF0000", fillOpacity: 0.9 }).addTo(lpLayer)
            .bindPopup("<strong>LP " + esc(lp.code) + "</strong><br>" + esc(lp.name) + "<br>" + esc(lp.area || ""));
        });
        naps.forEach(function (nap) {
          var count = used[nap.id] || 0;
          var cap = nap.port_capacity || 0;
          var badge = L.divIcon({
            className: "nap-badge",
            html: "<span>" + count + "/" + (cap || "–") + "</span>",
            iconSize: [46, 22],
            iconAnchor: [23, 11]
          });
          L.marker([nap.latitude, nap.longitude], { icon: badge }).addTo(lpLayer).bindPopup(
            "<strong>NAP " + esc(nap.code) + "</strong><br>" + esc(nap.name) + "<br>Ports " + count + "/" + (cap || "—")
          );
        });
        if (document.getElementById("layer-cust").checked) {
          visible.forEach(function (row) {
            if (row.latitude == null || row.longitude == null || !row.nap_id) return;
            var nap = naps.filter(function (item) { return item.id === row.nap_id; })[0];
            if (!nap) return;
            L.polyline([[nap.latitude, nap.longitude], [row.latitude, row.longitude]], { color: "#888", weight: 1, dashArray: "4 4" }).addTo(custLineLayer);
          });
        }
        visible.forEach(function (row) {
          if (row.latitude == null || row.longitude == null) return;
          var bills = openBillsFor(row.id);
          var balance = bills.reduce(function (sum, bill) { return sum + Number(bill.amount || 0); }, 0);
          var color = customerPinColor(row, openBills);
          var popup = "<strong>" + esc(row.name || "Customer") + "</strong><br>Account " + esc(row.account_number || "—") +
            "<br>" + esc(row.plan_speed || row.plan || "No plan") + "<br>" + esc(pinStatus(row, openBills)) +
            "<br>Balance " + esc(money(balance)) +
            "<br><a href=\"https://www.google.com/maps/search/?api=1&query=" + row.latitude + "," + row.longitude + "\" target=\"_blank\" rel=\"noopener\">Open in Google Maps</a>" +
            "<br><a href=\"#customer/" + row.id + "\">Open customer record</a>";
          L.circleMarker([row.latitude, row.longitude], { radius: 6, color: color, fillColor: color, fillOpacity: 0.9 })
            .bindPopup(popup).addTo(cluster);
        });
        if (document.getElementById("layer-areas").checked) {
          areas.forEach(function (poly) {
            var path = poly.path || [];
            if (path.length < 3) return;
            L.polygon(path.map(function (point) { return [point.lat, point.lng]; }), { color: "#FF0000", weight: 1, fillOpacity: 0.08 }).addTo(areaLayer)
              .bindPopup(esc(poly.area_name));
          });
        }
      }
      function openBillsFor(id) { return openBills[id] || []; }
      ["map-area", "map-investor", "map-lp", "map-nap", "layer-lp", "layer-cust", "layer-areas"].forEach(function (id) {
        document.getElementById(id).addEventListener("change", draw);
      });
      draw();
      document.getElementById("node-list").innerHTML = nodes.map(function (node) {
        return "<p>" + esc(node.node_type) + " · " + esc(node.name) +
          " <button type=\"button\" class=\"btn secondary\" data-edit-node=\"" + node.id + "\">Edit</button>" +
          " <button type=\"button\" class=\"btn secondary\" data-del-node=\"" + node.id + "\">Delete</button></p>";
      }).join("") + lps.map(function (lp) {
        return "<p>LP " + esc(lp.code) + " · " + esc(lp.name) + " <button type=\"button\" class=\"btn secondary\" data-del-lp=\"" + lp.id + "\">Delete</button></p>";
      }).join("") + naps.map(function (nap) {
        return "<p>NAP " + esc(nap.code) + " · " + esc(nap.name) + " <button type=\"button\" class=\"btn secondary\" data-del-nap=\"" + nap.id + "\">Delete</button></p>";
      }).join("");
      var full = naps.filter(function (nap) { return nap.port_capacity && (used[nap.id] || 0) >= nap.port_capacity; });
      document.getElementById("full-naps").innerHTML = "<h2>Full NAPs</h2>" + (full.map(function (nap) {
        return "<p>" + esc(nap.code) + " · " + (used[nap.id] || 0) + "/" + nap.port_capacity + "</p>";
      }).join("") || "<p class=\"muted\">No NAP is full.</p>");
      app.querySelectorAll("[data-del-node]").forEach(function (button) {
        button.onclick = function () {
          db.from("network_nodes").delete().eq("id", button.getAttribute("data-del-node")).then(function (del) {
            if (del.error) return flash(errText(del.error));
            renderMap();
          });
        };
      });
      app.querySelectorAll("[data-del-lp]").forEach(function (button) {
        button.onclick = function () {
          db.from("distribution_points").delete().eq("id", button.getAttribute("data-del-lp")).then(function (del) {
            if (del.error) return flash(errText(del.error));
            renderMap();
          });
        };
      });
      app.querySelectorAll("[data-del-nap]").forEach(function (button) {
        button.onclick = function () {
          db.from("nap_boxes").delete().eq("id", button.getAttribute("data-del-nap")).then(function (del) {
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
    function savePhoto(file) {
      if (!file) return Promise.resolve(null);
      var ext = file.type === "image/png" ? "png" : (file.type === "image/webp" ? "webp" : "jpg");
      var path = "assets/" + Date.now() + "-" + Math.floor(Math.random() * 10000) + "." + ext;
      return db.storage.from("network-photos").upload(path, file, { contentType: file.type || "image/jpeg", upsert: false }).then(function (result) {
        if (result.error) throw result.error;
        return path;
      });
    }
    document.getElementById("lp-form").onsubmit = function (event) {
      event.preventDefault();
      var file = document.getElementById("lp-photo").files[0];
      savePhoto(file).then(function (path) {
        var record = {
          code: document.getElementById("lp-code").value.trim(),
          name: document.getElementById("lp-name").value.trim(),
          area: document.getElementById("lp-area").value.trim() || null,
          sub_area: document.getElementById("lp-sub").value.trim() || null,
          port_capacity: document.getElementById("lp-ports").value === "" ? null : Number(document.getElementById("lp-ports").value),
          notes: document.getElementById("lp-notes").value.trim() || null,
          latitude: Number(document.getElementById("lp-lat").value),
          longitude: Number(document.getElementById("lp-lng").value)
        };
        if (path) record.photo_path = path;
        var id = document.getElementById("lp-id").value;
        var query = id ? db.from("distribution_points").update(record).eq("id", id) : db.from("distribution_points").insert(record);
        return query;
      }).then(function (save) {
        if (save.error) return flash(errText(save.error));
        renderMap();
      }).catch(function (error) { flash(errText(error)); });
    };
    document.getElementById("nap-form").onsubmit = function (event) {
      event.preventDefault();
      var file = document.getElementById("nap-photo").files[0];
      savePhoto(file).then(function (path) {
        var record = {
          lp_id: document.getElementById("nap-lp").value || null,
          code: document.getElementById("nap-code").value.trim(),
          name: document.getElementById("nap-name").value.trim(),
          area: document.getElementById("nap-area").value.trim() || null,
          sub_area: document.getElementById("nap-sub").value.trim() || null,
          port_capacity: document.getElementById("nap-ports").value === "" ? null : Number(document.getElementById("nap-ports").value),
          notes: document.getElementById("nap-notes").value.trim() || null,
          latitude: Number(document.getElementById("nap-lat").value),
          longitude: Number(document.getElementById("nap-lng").value)
        };
        if (path) record.photo_path = path;
        var id = document.getElementById("nap-id").value;
        var query = id ? db.from("nap_boxes").update(record).eq("id", id) : db.from("nap_boxes").insert(record);
        return query;
      }).then(function (save) {
        if (save.error) return flash(errText(save.error));
        renderMap();
      }).catch(function (error) { flash(errText(error)); });
    };
    document.getElementById("area-form").onsubmit = function (event) {
      event.preventDefault();
      if (areaPoints.length < 3) return flash("Add at least 3 corners.");
      db.from("area_polygons").insert({
        area_name: document.getElementById("area-name").value.trim(),
        path: areaPoints.map(function (point) { return { lat: point.lat, lng: point.lng }; })
      }).then(function (save) {
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
    Promise.all([
      db.from("app_settings").select("*").order("key"),
      db.from("material_prices").select("*").order("item")
    ]).then(function (parts) {
      var result = parts[0];
      if (result.error) return flash(errText(result.error));
      if (gen !== viewGen) return;
      var prices = parts[1].error ? [] : (parts[1].data || []);
      var fields = [
        ["gcash_number", "GCash number"],
        ["gcash_name", "GCash name"],
        ["gcash_qr_url", "GCash QR image URL"],
        ["payment_note", "Payment note"],
        ["grace_days", "Grace period (days)"],
        ["installation_fee", "Installation fee (₱)"],
        ["account_number_format", "Account number format"],
        ["ticket_issues", "Ticket issues (one per line)"]
      ];
      var values = {};
      (result.data || []).forEach(function (row) { values[row.key] = row.value || ""; });
      shell("<section class=\"panel\"><h1>Settings</h1><form id=\"settings-form\" class=\"grid\">" +
        fields.map(function (field) {
          var input = field[0] === "payment_note" || field[0] === "ticket_issues"
            ? "<textarea id=\"set-" + field[0] + "\">" + esc(values[field[0]] || "") + "</textarea>"
            : "<input id=\"set-" + field[0] + "\" value=\"" + esc(values[field[0]] || "") + "\">";
          return "<div class=\"field\"><label for=\"set-" + field[0] + "\">" + esc(field[1]) + "</label>" + input + "</div>";
        }).join("") +
        "<button class=\"btn\" type=\"submit\">Save settings</button></form>" +
        (parts[1].error ? "<p class=\"muted\">Material prices appear after supabase/migrations/20261121_phase2_ops.sql is applied.</p>" :
          "<h2>Material prices</h2><p class=\"muted\">SC connector starts at ₱28. Leave the others blank until you set a price. Blank prices are not posted as expenses.</p><form id=\"price-form\" class=\"grid two\">" +
          prices.map(function (row) {
            return "<div class=\"field\"><label for=\"price-" + esc(row.item) + "\">" + esc(row.item) + "</label><input id=\"price-" + esc(row.item) + "\" data-item=\"" + esc(row.item) + "\" type=\"number\" min=\"0\" step=\"0.01\" value=\"" + esc(row.unit_cost == null ? "" : row.unit_cost) + "\"></div>";
          }).join("") +
          "<button class=\"btn\" type=\"submit\">Save prices</button></form>") +
        "</section>");
      document.getElementById("settings-form").onsubmit = function (event) {
        event.preventDefault();
        var writes = fields.map(function (field) {
          var privateSetting = field[0] === "grace_days" || field[0] === "installation_fee" || field[0] === "account_number_format" || field[0] === "ticket_issues";
          return db.from("app_settings").upsert({
            key: field[0],
            value: document.getElementById("set-" + field[0]).value,
            is_public: !privateSetting,
            updated_at: new Date().toISOString()
          });
        });
        Promise.all(writes).then(function (saved) {
          var failed = saved.filter(function (item) { return item.error; })[0];
          if (failed) return flash(errText(failed.error));
          flash("Settings saved.", true);
        });
      };
      var priceForm = document.getElementById("price-form");
      if (priceForm) priceForm.onsubmit = function (event) {
        event.preventDefault();
        var writes = Array.prototype.map.call(priceForm.querySelectorAll("[data-item]"), function (input) {
          var raw = input.value.trim();
          return db.from("material_prices").upsert({
            item: input.getAttribute("data-item"),
            unit_cost: raw === "" ? null : Number(raw),
            updated_at: new Date().toISOString()
          });
        });
        Promise.all(writes).then(function (saved) {
          var failed = saved.filter(function (item) { return item.error; })[0];
          if (failed) return flash(errText(failed.error));
          flash("Prices saved.", true);
        });
      };
    });
  }

  function portalCard(customer) {
    var pinState = customer.portal_pin_hash ? "PIN is set" : "No PIN yet";
    var access = customer.portal_enabled ? "Enabled" : "Disabled";
    var lock = customer.locked_until && new Date(customer.locked_until).getTime() > Date.now()
      ? " · Locked until " + manilaTime(customer.locked_until)
      : "";
    return formCard("Portal access",
      "<p class=\"muted\">" + esc(pinState) + " · " + esc(access) + esc(lock) + "</p>" +
      "<form id=\"portal-form\" class=\"grid two\">" +
      "<div class=\"field\"><label for=\"portal-pin\">New PIN</label><input id=\"portal-pin\" inputmode=\"numeric\" autocomplete=\"new-password\" maxlength=\"8\" placeholder=\"4–8 digits\"></div>" +
      "<label class=\"field check\"><input id=\"portal-enabled\" type=\"checkbox\"" + (customer.portal_enabled ? " checked" : "") + "> Portal enabled</label>" +
      "<button class=\"btn\" type=\"submit\">Save portal access</button></form>" +
      "<p class=\"muted\">The customer signs in at Customer Login with this account number and PIN. Leave the PIN blank to only enable or disable access.</p>");
  }

  function wirePortalAccess(customer) {
    var form = document.getElementById("portal-form");
    if (!form || !customer || !customer.id) return;
    form.onsubmit = function (event) {
      event.preventDefault();
      var pin = document.getElementById("portal-pin").value.trim();
      var enabled = document.getElementById("portal-enabled").checked;
      db.rpc("admin_set_portal_pin", {
        customer_id: customer.id,
        pin: pin || null,
        p_enabled: enabled
      }).then(function (result) {
        if (result.error) return flash(errText(result.error));
        if (!result.data || result.data.ok !== true) return flash("Could not save portal access.");
        flash("Portal access saved.", true);
        loadCustomer(customer.id);
      });
    };
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

  function fillSelect(id, rows, selected, labelFn) {
    var el = document.getElementById(id);
    if (!el) return;
    var html = "<option value=\"\">Not linked</option>";
    (rows || []).forEach(function (row) {
      html += "<option value=\"" + row.id + "\"" + (row.id === selected ? " selected" : "") + ">" + esc(labelFn(row)) + "</option>";
    });
    el.innerHTML = html;
  }

  function wireLpNap(customer) {
    var lpSelect = document.getElementById("f-lp_id");
    var napSelect = document.getElementById("f-nap_id");
    if (!lpSelect || !napSelect || !db) return;
    Promise.all([
      db.from("distribution_points").select("id, code, name").order("code"),
      db.from("nap_boxes").select("id, code, name, lp_id").order("code")
    ]).then(function (parts) {
      if (parts[0].error || parts[1].error) return;
      var lps = parts[0].data || [];
      var naps = parts[1].data || [];
      fillSelect("f-lp_id", lps, customer.lp_id, function (row) { return row.code + " · " + row.name; });
      function refillNaps() {
        var lpId = document.getElementById("f-lp_id").value;
        var list = lpId ? naps.filter(function (row) { return row.lp_id === lpId; }) : naps;
        fillSelect("f-nap_id", list, customer.nap_id, function (row) { return row.code + " · " + row.name; });
      }
      document.getElementById("f-lp_id").onchange = refillNaps;
      refillNaps();
    }).catch(function () {});
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

  function copyText(text) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(function () { flash("Message copied.", true); });
    } else {
      flash(text);
    }
  }

  function ackMessage(row) {
    var balance = row.balance_status || (Number(row.remaining || 0) > 0 ? "With balance" : "Cleared");
    return "Hi " + (row.client_name || "customer") + ", natanggap na namin ang bayad mo.\n" +
      "Date: " + (row.collection_date || "") + "\nRef: " + (row.gcash_ref || "") + "\nMonth: " + (row.period_label || row.remarks || "") +
      "\nAmount: " + money(row.amount) + "\nBalance: " + balance + "\nSalamat, FiberBro!";
  }

  function downloadAck(row) {
    loadScript("https://cdn.jsdelivr.net/npm/jspdf@2.5.2/dist/jspdf.umd.min.js").then(function () {
      var JsPDF = window.jspdf && window.jspdf.jsPDF;
      if (!JsPDF) return flash("Could not load the PDF library.");
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
        "Name: " + (row.client_name || ""),
        "Date: " + (row.collection_date || ""),
        "Reference number: " + (row.gcash_ref || ""),
        "Month payment: " + (row.period_label || row.remarks || ""),
        "Amount: " + money(row.amount),
        "This month balance: " + money(row.remaining || 0),
        "Balance status: " + (Number(row.remaining || 0) > 0 ? "With balance" : "Cleared"),
        "Note: " + (row.match_reason || row.remarks || ""),
        "Cut-off: " + (row.cutoff || ""),
        "Payment Received - Thank You!"
      ];
      lines.forEach(function (line, index) { doc.text(line, 14, 56 + index * 7); });
      if (row.image_base64) {
        try {
          doc.addImage("data:" + (row.content_type || "image/jpeg") + ";base64," + row.image_base64, "JPEG", 120, 40, 75, 100);
          doc.text("Proof of Payment", 120, 36);
        } catch (err) {}
      }
      doc.save("FiberBro-receipt-" + (row.gcash_ref || "payment") + ".pdf");
    }).catch(function (error) { flash(errText(error)); });
  }

  function renderGcash() {
    var gen = viewGen;
    shell("<section class=\"panel\"><h1>GCash refs</h1><p class=\"muted\">Loading…</p></section>");
    Promise.all([
      db.from("gcash_accounts").select("*").order("name"),
      db.from("gcash_refs").select("*, gcash_accounts(name)").order("txn_date", { ascending: false })
    ]).then(function (parts) {
      if (gen !== viewGen) return;
      if (parts[0].error) return flash("GCash refs are not ready. Apply supabase/migrations/20261120_phase1_payments.sql. " + errText(parts[0].error));
      var accounts = parts[0].data || [];
      var refs = parts[1].error ? [] : (parts[1].data || []);
      var options = accounts.map(function (row) {
        return "<option value=\"" + row.id + "\">" + esc(row.name) + "</option>";
      }).join("");
      var body = refs.map(function (row) {
        var acct = (row.gcash_accounts && row.gcash_accounts.name) || "";
        return "<tr data-account=\"" + esc(row.gcash_account_id || "") + "\" data-date=\"" + esc(row.txn_date || "") + "\">" +
          "<td data-label=\"Account\">" + esc(acct) + "</td><td data-label=\"Date\">" + esc(row.txn_date || "") + "</td>" +
          "<td data-label=\"Ref\">" + esc(row.ref_number) + (row.duplicate_flag ? " <span class=\"tag\">duplicate</span>" : "") + "</td>" +
          "<td data-label=\"Amount\">" + esc(money(row.amount)) + "</td><td data-label=\"Status\">" + statusPill(row.status) + "</td></tr>";
      }).join("");
      shell("<section class=\"panel\"><h1>GCash refs</h1>" +
        "<p class=\"muted\">Paste lines like 2026-11-16 3047334127750 500.00. Spaces in the ref are removed. A repeated ref is saved with a duplicate flag and is not used for matching.</p>" +
        "<form id=\"gcash-account-form\" class=\"toolbar\"><input id=\"gcash-account-name\" placeholder=\"Receiving account\" required><button class=\"btn\" type=\"submit\">Add account</button></form>" +
        "<form id=\"gcash-one\" class=\"grid two\">" +
        "<div class=\"field\"><label for=\"gcash-account\">Receiving account</label><select id=\"gcash-account\" required>" + options + "</select></div>" +
        "<div class=\"field\"><label for=\"gcash-date\">Date</label><input id=\"gcash-date\" type=\"date\" required></div>" +
        "<div class=\"field\"><label for=\"gcash-ref\">Ref number</label><input id=\"gcash-ref\" required></div>" +
        "<div class=\"field\"><label for=\"gcash-amount\">Amount</label><input id=\"gcash-amount\" type=\"number\" min=\"0.01\" step=\"0.01\" required></div>" +
        "<button class=\"btn\" type=\"submit\">Add one ref</button></form>" +
        "<form id=\"gcash-bulk\" class=\"grid\"><div class=\"field\"><label for=\"gcash-lines\">Bulk paste</label><textarea id=\"gcash-lines\" placeholder=\"One payment per line\"></textarea></div>" +
        "<button class=\"btn secondary\" type=\"submit\">Save pasted lines</button></form></section>" +
        "<div class=\"filters\"><select id=\"gcash-filter-account\"><option value=\"\">All accounts</option>" + options + "</select><input id=\"gcash-filter-date\" type=\"date\"><strong id=\"gcash-total\"></strong></div>" +
        "<div class=\"table-card\"><table id=\"gcash-table\"><thead><tr><th>Account</th><th>Date</th><th>Ref</th><th>Amount</th><th>Status</th></tr></thead><tbody>" +
        (body || "<tr><td colspan=\"5\">No refs yet.</td></tr>") + "</tbody></table></div>");
      function totalVisible() {
        var account = document.getElementById("gcash-filter-account").value;
        var date = document.getElementById("gcash-filter-date").value;
        var sum = 0;
        var count = 0;
        app.querySelectorAll("#gcash-table tbody tr").forEach(function (row) {
          if (!row.getAttribute("data-date")) return;
          var show = (!account || row.getAttribute("data-account") === account) && (!date || row.getAttribute("data-date") === date);
          row.hidden = !show;
          if (show) {
            count += 1;
            var amount = row.children[3] ? row.children[3].textContent : "";
            sum += Number(String(amount).replace(/[^0-9.]/g, "")) || 0;
          }
        });
        document.getElementById("gcash-total").textContent = count + " rows · " + money(sum);
      }
      document.getElementById("gcash-filter-account").onchange = totalVisible;
      document.getElementById("gcash-filter-date").onchange = totalVisible;
      totalVisible();
      document.getElementById("gcash-account-form").onsubmit = function (event) {
        event.preventDefault();
        db.from("gcash_accounts").insert({ name: document.getElementById("gcash-account-name").value.trim() }).then(function (result) {
          if (result.error) return flash(errText(result.error));
          renderGcash();
        });
      };
      document.getElementById("gcash-one").onsubmit = function (event) {
        event.preventDefault();
        var line = document.getElementById("gcash-date").value + " " + document.getElementById("gcash-ref").value + " " + Number(document.getElementById("gcash-amount").value).toFixed(2);
        db.rpc("add_gcash_refs", { p_account: document.getElementById("gcash-account").value, p_lines: line }).then(function (result) {
          if (result.error) return flash(errText(result.error));
          flash("Saved. Inserted " + (result.data.inserted || 0) + ", duplicates " + (result.data.duplicates || 0) + ".", true);
          renderGcash();
        });
      };
      document.getElementById("gcash-bulk").onsubmit = function (event) {
        event.preventDefault();
        db.rpc("add_gcash_refs", {
          p_account: document.getElementById("gcash-account").value,
          p_lines: document.getElementById("gcash-lines").value
        }).then(function (result) {
          if (result.error) return flash(errText(result.error));
          flash("Saved. Inserted " + (result.data.inserted || 0) + ", duplicates " + (result.data.duplicates || 0) + ", skipped " + (result.data.skipped || 0) + ".", true);
          renderGcash();
        });
      };
    }).catch(function (error) { flash(errText(error)); });
  }

  function parseGcashText(text) {
    var refMatch = text.match(/ref\.?\s*no\.?\s*([0-9 ]{8,})/i);
    var dateMatch = text.match(/[A-Z][a-z]{2}\s+\d{1,2},\s+\d{4}/);
    var amounts = text.match(/\d{1,3}(?:,\d{3})*(?:\.\d{2})|\d+\.\d{2}/g) || [];
    var best = 0;
    amounts.forEach(function (item) {
      var num = Number(String(item).replace(/,/g, ""));
      if (num > best && num < 1000000) best = num;
    });
    var date = "";
    if (dateMatch) {
      var parsed = new Date(dateMatch[0]);
      if (!isNaN(parsed.getTime())) {
        var month = String(parsed.getMonth() + 1);
        var day = String(parsed.getDate());
        if (month.length < 2) month = "0" + month;
        if (day.length < 2) day = "0" + day;
        date = parsed.getFullYear() + "-" + month + "-" + day;
      }
    }
    return {
      ref: refMatch ? refMatch[1].replace(/\D/g, "") : "",
      amount: best ? best.toFixed(2) : "",
      date: date
    };
  }

  function renderLogbook() {
    var gen = viewGen;
    shell("<section class=\"panel\"><h1>Virtual logbook</h1><p class=\"muted\">Loading…</p></section>");
    Promise.all([
      db.from("virtual_logbook").select("*").order("created_at", { ascending: false }),
      db.from("customers").select("id, name, account_number")
    ]).then(function (parts) {
      if (gen !== viewGen) return;
      if (parts[0].error) return flash("Logbook is not ready. Apply supabase/migrations/20261120_phase1_payments.sql. " + errText(parts[0].error));
      var rows = parts[0].data || [];
      var people = parts[1].error ? state.customers : (parts[1].data || []);
      var choices = people.map(function (row) {
        return "<option value=\"" + row.id + "\">" + esc((row.account_number ? row.account_number + " · " : "") + (row.name || "Customer")) + "</option>";
      }).join("");
      var body = rows.map(function (row) {
        return "<tr><td data-label=\"Date\">" + esc(row.collection_date || "") + "</td>" +
          "<td data-label=\"Client\">" + esc(row.client_name || "") + "</td>" +
          "<td data-label=\"Ref\">" + esc(row.gcash_ref || "") + "</td>" +
          "<td data-label=\"Amount\">" + esc(money(row.amount)) + "</td>" +
          "<td data-label=\"Cut-off\">" + esc(row.cutoff || "") + "</td>" +
          "<td data-label=\"Status\">" + esc(row.status) + (row.match_reason ? "<br><span class=\"muted\">" + esc(row.match_reason) + "</span>" : "") + "</td>" +
          "<td data-label=\"\"><button type=\"button\" class=\"btn secondary\" data-log=\"" + row.id + "\">Open</button></td></tr>";
      }).join("");
      shell("<section class=\"panel\"><h1>Virtual logbook</h1>" +
        "<p class=\"muted\">Portal proofs and staff uploads wait here. Kapag tugma ang ref, amount, at date sa GCash ref, auto-process. Kung hindi, nandito ang reason.</p>" +
        "<form id=\"log-form\" class=\"grid two\">" +
        "<div class=\"field\"><label for=\"log-customer\">Customer</label><select id=\"log-customer\"><option value=\"\">Unknown for now</option>" + choices + "</select></div>" +
        "<div class=\"field\"><label for=\"log-date\">Collection date</label><input id=\"log-date\" type=\"date\" required></div>" +
        "<div class=\"field\"><label for=\"log-ref\">GCash ref</label><input id=\"log-ref\" required></div>" +
        "<div class=\"field\"><label for=\"log-amount\">Amount</label><input id=\"log-amount\" type=\"number\" min=\"0.01\" step=\"0.01\" required></div>" +
        "<div class=\"field\"><label for=\"log-month\">Month / remarks</label><input id=\"log-month\" placeholder=\"Nov_2026\"></div>" +
        "<div class=\"field\"><label for=\"log-file\">Screenshot from Messenger</label><input id=\"log-file\" type=\"file\" accept=\"image/jpeg,image/png,image/webp\"></div>" +
        "<div class=\"actions\"><button class=\"btn\" type=\"submit\">Save to queue</button><button type=\"button\" class=\"btn secondary\" id=\"log-ocr\">Read screenshot</button></div></form></section>" +
        "<div class=\"table-card\"><table><thead><tr><th>Date</th><th>Client</th><th>Ref</th><th>Amount</th><th>Cut-off</th><th>Status</th><th></th></tr></thead><tbody>" +
        (body || "<tr><td colspan=\"7\">Queue is empty.</td></tr>") + "</tbody></table></div>" +
        "<section class=\"panel\" id=\"log-detail\" hidden><h2>Review</h2><div id=\"log-detail-body\"></div></section>");
      document.getElementById("log-ocr").onclick = function () {
        var file = document.getElementById("log-file").files[0];
        if (!file) return flash("Choose a screenshot first.");
        flash("Reading the screenshot…", true);
        loadScript("https://cdn.jsdelivr.net/npm/tesseract.js@5.1.1/dist/tesseract.min.js").then(function () {
          return window.Tesseract.recognize(file, "eng");
        }).then(function (result) {
          var parsed = parseGcashText((result && result.data && result.data.text) || "");
          if (parsed.ref) document.getElementById("log-ref").value = parsed.ref;
          if (parsed.amount) document.getElementById("log-amount").value = parsed.amount;
          if (parsed.date) document.getElementById("log-date").value = parsed.date;
          flash(parsed.ref ? "Fields filled. Please check them." : "No ref was found. Type it in.", true);
        }).catch(function (error) { flash(errText(error)); });
      };
      document.getElementById("log-form").onsubmit = function (event) {
        event.preventDefault();
        var file = document.getElementById("log-file").files[0];
        var customerId = document.getElementById("log-customer").value || null;
        var person = people.filter(function (row) { return row.id === customerId; })[0];
        function save(image, mime) {
          var date = document.getElementById("log-date").value;
          var ref = document.getElementById("log-ref").value.replace(/\D/g, "");
          var amount = Number(document.getElementById("log-amount").value);
          db.from("virtual_logbook").insert({
            customer_id: customerId,
            collection_date: date,
            client_name: person ? person.name : null,
            mode: "gcash",
            amount: amount,
            gcash_ref: ref,
            remarks: document.getElementById("log-month").value.trim() || null,
            period_label: document.getElementById("log-month").value.trim() || null,
            image_base64: image,
            content_type: mime,
            source: "admin",
            logged_by: sessionEmail,
            entry_type: "Collection"
          }).then(function (insert) {
            if (insert.error) return flash(errText(insert.error));
            flash("Saved. Auto-match runs on the server.", true);
            renderLogbook();
          });
        }
        if (!file) return save(null, null);
        var reader = new FileReader();
        reader.onload = function () {
          var text = String(reader.result || "");
          var comma = text.indexOf(",");
          save(comma >= 0 ? text.slice(comma + 1) : text, file.type || "image/jpeg");
        };
        reader.readAsDataURL(file);
      };
      app.querySelectorAll("[data-log]").forEach(function (button) {
        button.onclick = function () {
          var row = rows.filter(function (item) { return item.id === button.getAttribute("data-log"); })[0];
          if (!row) return;
          var box = document.getElementById("log-detail");
          box.hidden = false;
          document.getElementById("log-detail-body").innerHTML =
            "<form id=\"log-edit\" class=\"grid two\">" +
            "<div class=\"field\"><label>Ref</label><input id=\"edit-ref\" value=\"" + esc(row.gcash_ref || "") + "\"></div>" +
            "<div class=\"field\"><label>Amount</label><input id=\"edit-amount\" type=\"number\" step=\"0.01\" value=\"" + esc(row.amount || "") + "\"></div>" +
            "<div class=\"field\"><label>Date</label><input id=\"edit-date\" type=\"date\" value=\"" + esc(row.collection_date || "") + "\"></div>" +
            "<div class=\"field\"><label>Customer</label><select id=\"edit-customer\"><option value=\"\">Unknown</option>" + people.map(function (person) {
              return "<option value=\"" + person.id + "\"" + (person.id === row.customer_id ? " selected" : "") + ">" + esc(person.name || person.account_number || "Customer") + "</option>";
            }).join("") + "</select></div>" +
            "<p class=\"muted\">" + esc(row.match_reason || row.status) + " · Cut-off " + esc(row.cutoff || "—") + "</p>" +
            "<div class=\"actions\"><button class=\"btn\" type=\"submit\">Save and match again</button>" +
            "<button type=\"button\" class=\"btn secondary\" id=\"log-override\">Process anyway</button>" +
            "<button type=\"button\" class=\"btn secondary\" id=\"log-receipt\">View receipt</button>" +
            "<button type=\"button\" class=\"btn secondary\" id=\"log-copy\">Copy message + note</button></div></form>";
          document.getElementById("log-edit").onsubmit = function (event) {
            event.preventDefault();
            var chosen = people.filter(function (person) { return person.id === document.getElementById("edit-customer").value; })[0];
            db.from("virtual_logbook").update({
              gcash_ref: document.getElementById("edit-ref").value.replace(/\D/g, ""),
              amount: Number(document.getElementById("edit-amount").value),
              collection_date: document.getElementById("edit-date").value,
              customer_id: document.getElementById("edit-customer").value || null,
              client_name: chosen ? chosen.name : row.client_name,
              status: "unmatched"
            }).eq("id", row.id).then(function (update) {
              if (update.error) return flash(errText(update.error));
              flash("Saved. The server matches it again.", true);
              renderLogbook();
            });
          };
          document.getElementById("log-override").onclick = function () {
            db.rpc("manual_process_logbook", { p_id: row.id }).then(function (result) {
              if (result.error) return flash(errText(result.error));
              flash("Processed.", true);
              renderLogbook();
            });
          };
          document.getElementById("log-receipt").onclick = function () { downloadAck(row); };
          document.getElementById("log-copy").onclick = function () { copyText(ackMessage(row)); };
        };
      });
    }).catch(function (error) { flash(errText(error)); });
  }

  var OPS_TYPES = [
    ["REP", "Repair"],
    ["INSTALLATION", "Installation"],
    ["PUL", "Pullout"],
    ["CHP", "Change plan"],
    ["MOD", "Change modem"],
    ["REL", "Relocation"],
    ["REW", "Rewiring"]
  ];
  var OPS_STATUSES = ["Open", "Assigned", "In Progress", "Closed - Resolved"];
  var MATERIAL_ITEMS = ["SC Connector", "Changed Modem", "Rewiring", "Changed power adaptor", "other"];

  function opsTypeLabel(code) {
    var found = OPS_TYPES.filter(function (item) { return item[0] === code; })[0];
    return found ? found[1] : code;
  }

  function uploadTicketPhoto(ticketId, file) {
    var safe = String(file.name || "photo.jpg").replace(/[^\w.]+/g, "-");
    var path = "tickets/" + ticketId + "/" + Date.now() + "-" + safe;
    return db.storage.from("ticket-photos").upload(path, file, { contentType: file.type || "image/jpeg", upsert: false }).then(function (result) {
      if (result.error) throw result.error;
      return db.from("ticket_photos").insert({ ticket_id: ticketId, path: path, created_by: sessionEmail });
    });
  }

  function renderStaff() {
    var gen = viewGen;
    shell("<section class=\"panel\"><h1>Staff</h1><p class=\"muted\">Loading…</p></section>");
    db.from("staff").select("*").order("name").then(function (result) {
      if (gen !== viewGen) return;
      if (result.error) return flash("Staff is not ready. Apply supabase/migrations/20261121_phase2_ops.sql. " + errText(result.error));
      var rows = result.data || [];
      var body = rows.map(function (row) {
        return "<tr><td data-label=\"Name\">" + esc(row.name) + "</td><td data-label=\"Email\">" + esc(row.email) + "</td><td data-label=\"Role\">" + esc(row.role) + "</td><td data-label=\"Duty\">" + esc(row.duty_status) + "</td><td data-label=\"Active\">" + (row.active ? "Yes" : "No") + "</td>" +
          "<td><button type=\"button\" class=\"btn secondary\" data-staff=\"" + row.id + "\">" + (row.active ? "Deactivate" : "Activate") + "</button></td></tr>";
      }).join("");
      shell("<section class=\"panel\"><h1>Staff</h1><p class=\"muted\">Tech accounts sign in with Google at <a href=\"/tech/\">/tech/</a> and only see tickets assigned to them. Admin access still comes from the Admins allowlist.</p>" +
        "<form id=\"staff-form\" class=\"grid two\">" +
        "<div class=\"field\"><label>Name</label><input id=\"staff-name\" required></div>" +
        "<div class=\"field\"><label>Gmail</label><input id=\"staff-email\" type=\"email\" required></div>" +
        "<div class=\"field\"><label>Role</label><select id=\"staff-role\"><option value=\"tech\">tech</option><option value=\"admin\">admin</option><option value=\"payroll_admin\">payroll_admin</option><option value=\"investor\">investor</option></select></div>" +
        "<button class=\"btn\" type=\"submit\">Add staff</button></form></section>" +
        "<div class=\"table-wrap\"><table><thead><tr><th>Name</th><th>Email</th><th>Role</th><th>Duty</th><th>Active</th><th></th></tr></thead><tbody>" +
        (body || "<tr><td colspan=\"6\">No staff yet.</td></tr>") + "</tbody></table></div>");
      document.getElementById("staff-form").onsubmit = function (event) {
        event.preventDefault();
        db.from("staff").insert({
          name: document.getElementById("staff-name").value.trim(),
          email: document.getElementById("staff-email").value.trim(),
          role: document.getElementById("staff-role").value
        }).then(function (insert) {
          if (insert.error) return flash(errText(insert.error));
          flash("Staff saved.", true);
          renderStaff();
        });
      };
      app.querySelectorAll("[data-staff]").forEach(function (button) {
        button.onclick = function () {
          var row = rows.filter(function (item) { return item.id === button.getAttribute("data-staff"); })[0];
          db.from("staff").update({ active: !row.active }).eq("id", row.id).then(function (update) {
            if (update.error) return flash(errText(update.error));
            renderStaff();
          });
        };
      });
    });
  }

  function renderModems() {
    var gen = viewGen;
    shell("<section class=\"panel\"><h1>Modems</h1><p class=\"muted\">Loading…</p></section>");
    Promise.all([
      db.from("modems").select("*, customers(name, account_number)").order("serial"),
      db.from("modem_log").select("*").order("created_at", { ascending: false }).limit(30),
      db.from("customers").select("id, name, account_number").order("name")
    ]).then(function (parts) {
      if (gen !== viewGen) return;
      if (parts[0].error) return flash("Modems are not ready. Apply supabase/migrations/20261121_phase2_ops.sql. " + errText(parts[0].error));
      var rows = parts[0].data || [];
      var log = parts[1].error ? [] : (parts[1].data || []);
      var people = parts[2].error ? [] : (parts[2].data || []);
      var body = rows.map(function (row) {
        var person = row.customers || {};
        return "<tr><td data-label=\"Serial\">" + esc(row.serial) + "</td><td data-label=\"Brand\">" + esc(row.brand) + "</td><td data-label=\"Type\">" + esc(row.modem_type) + "</td><td data-label=\"Condition\">" + esc(row.condition) + "</td><td data-label=\"Availability\">" + esc(row.availability) + "</td><td data-label=\"Customer\">" + esc(person.name || person.account_number || "—") + "</td></tr>";
      }).join("");
      var logBody = log.map(function (row) {
        return "<tr><td>" + esc(String(row.created_at || "").slice(0, 16).replace("T", " ")) + "</td><td>" + esc(row.action) + "</td><td>" + esc(row.note || "") + "</td><td>" + esc(row.actor || "") + "</td></tr>";
      }).join("");
      shell("<section class=\"panel\"><h1>Modems</h1><form id=\"modem-form\" class=\"grid two\">" +
        "<div class=\"field\"><label>Serial</label><input id=\"modem-serial\" required></div>" +
        "<div class=\"field\"><label>MAC</label><input id=\"modem-mac\"></div>" +
        "<div class=\"field\"><label>Brand</label><select id=\"modem-brand\"><option>IOT</option><option>SKYWORTH</option><option>HUAWEI</option><option>ZTE</option><option>FIBER HOME</option></select></div>" +
        "<div class=\"field\"><label>Type</label><select id=\"modem-type\"><option>GPON</option><option>GPON 5V5</option><option>GPON 1V5</option><option>XPON</option><option>EPON</option></select></div>" +
        "<div class=\"field\"><label>Condition</label><select id=\"modem-condition\"><option>100% Working</option><option>Faulty</option></select></div>" +
        "<button class=\"btn\" type=\"submit\">Add modem</button></form></section>" +
        "<div class=\"table-wrap\"><table><thead><tr><th>Serial</th><th>Brand</th><th>Type</th><th>Condition</th><th>Availability</th><th>Customer</th></tr></thead><tbody>" +
        (body || "<tr><td colspan=\"6\">No modems yet.</td></tr>") + "</tbody></table></div>" +
        "<section class=\"panel\"><h2>Pullout</h2><form id=\"pull-form\" class=\"grid two\">" +
        "<div class=\"field\"><label>Modem</label><select id=\"pull-modem\" required><option value=\"\">Select</option>" + rows.map(function (row) {
          return "<option value=\"" + row.id + "\">" + esc(row.serial) + "</option>";
        }).join("") + "</select></div>" +
        "<div class=\"field\"><label>Customer</label><select id=\"pull-customer\"><option value=\"\">None</option>" + people.map(function (person) {
          return "<option value=\"" + person.id + "\">" + esc(person.name || person.account_number || "Customer") + "</option>";
        }).join("") + "</select></div>" +
        "<div class=\"field\"><label>Type</label><select id=\"pull-type\"><option>Disconnection</option><option>Changed Modem</option></select></div>" +
        "<div class=\"field\"><label>Return fee</label><select id=\"pull-fee\"><option>0</option><option>290</option><option>300</option></select></div>" +
        "<div class=\"field\"><label>Date</label><input id=\"pull-date\" type=\"date\"></div>" +
        "<button class=\"btn\" type=\"submit\">Record pullout</button></form></section>" +
        "<section class=\"panel\"><h2>In / out log</h2><div class=\"table-wrap\"><table><thead><tr><th>When</th><th>Action</th><th>Note</th><th>By</th></tr></thead><tbody>" +
        (logBody || "<tr><td colspan=\"4\">No log yet.</td></tr>") + "</tbody></table></div></section>");
      document.getElementById("modem-form").onsubmit = function (event) {
        event.preventDefault();
        db.from("modems").insert({
          serial: document.getElementById("modem-serial").value.trim(),
          mac: document.getElementById("modem-mac").value.trim() || null,
          brand: document.getElementById("modem-brand").value,
          modem_type: document.getElementById("modem-type").value,
          condition: document.getElementById("modem-condition").value
        }).then(function (insert) {
          if (insert.error) return flash(errText(insert.error));
          flash("Modem added.", true);
          renderModems();
        });
      };
      document.getElementById("pull-form").onsubmit = function (event) {
        event.preventDefault();
        db.rpc("modem_pullout", {
          p_modem: document.getElementById("pull-modem").value,
          p_customer: document.getElementById("pull-customer").value || null,
          p_type: document.getElementById("pull-type").value,
          p_fee: Number(document.getElementById("pull-fee").value),
          p_date: document.getElementById("pull-date").value || null
        }).then(function (result) {
          if (result.error) return flash(errText(result.error));
          flash("Pullout recorded. Modem is Available again.", true);
          renderModems();
        });
      };
    });
  }

  function renderOps() {
    if (route().id) return renderOpsTicket(route().id);
    var gen = viewGen;
    shell("<section class=\"panel\"><h1>Tickets</h1><p class=\"muted\">Loading…</p></section>");
    Promise.all([
      db.from("ops_tickets").select("*, customers(name, account_number)").order("created_at", { ascending: false }),
      db.from("staff").select("id, name, role, active").eq("active", true).order("name"),
      db.from("app_settings").select("value").eq("key", "ticket_issues").maybeSingle(),
      db.from("investors").select("id, name, code, active").eq("active", true).order("name")
    ]).then(function (parts) {
      if (gen !== viewGen) return;
      if (parts[0].error) return flash("Tickets are not ready. Apply supabase/migrations/20261121_phase2_ops.sql. " + errText(parts[0].error));
      var rows = parts[0].data || [];
      var staff = parts[1].error ? [] : (parts[1].data || []);
      var issues = String((parts[2].data && parts[2].data.value) || "No internet\nOthers").split(/\r?\n/).map(function (item) { return item.trim(); }).filter(Boolean);
      var investors = parts[3].error ? state.investors : (parts[3].data || []);
      var techs = staff.filter(function (row) { return row.role === "tech"; });
      var body = rows.map(function (row) {
        var person = row.customers || {};
        var tech = staff.filter(function (item) { return item.id === row.assigned_to; })[0] || {};
        return "<tr><td data-label=\"Ticket\"><a href=\"#ops/" + row.id + "\">" + esc(row.ticket_no) + "</a></td><td data-label=\"Type\">" + esc(opsTypeLabel(row.ticket_type)) + "</td><td data-label=\"Customer\">" + esc(person.name || "—") + "</td><td data-label=\"Issue\">" + esc(row.issue || "") + "</td><td data-label=\"Status\">" + esc(row.status) + "</td><td data-label=\"Tech\">" + esc(tech.name || "—") + "</td></tr>";
      }).join("");
      shell("<section class=\"panel\"><h1>Tickets</h1><p class=\"muted\">Repair, installation, pullout, change plan, change modem, relocation, and rewiring. The old Install tickets list is unchanged.</p>" +
        "<form id=\"ops-form\" class=\"grid two\">" +
        "<div class=\"field\"><label>Type</label><select id=\"ops-type\">" + OPS_TYPES.map(function (item) { return "<option value=\"" + item[0] + "\">" + esc(item[1]) + "</option>"; }).join("") + "</select></div>" +
        "<div class=\"field\"><label>Customer</label><select id=\"ops-customer\"><option value=\"\">None yet</option>" + customerChoices() + "</select></div>" +
        "<div class=\"field\"><label>Issue</label><select id=\"ops-issue\">" + issues.map(function (item) { return "<option>" + esc(item) + "</option>"; }).join("") + "</select></div>" +
        "<div class=\"field\"><label>Tech</label><select id=\"ops-tech\"><option value=\"\">Unassigned</option>" + techs.map(function (row) { return "<option value=\"" + row.id + "\">" + esc(row.name) + "</option>"; }).join("") + "</select></div>" +
        "<button class=\"btn\" type=\"submit\">Open ticket</button></form></section>" +
        "<section class=\"panel\"><h2>Bagong client</h2><p class=\"muted\">Creates the customer and an installation ticket. Data privacy consent is required.</p>" +
        "<form id=\"intake-form\" class=\"grid two\">" +
        "<div class=\"field\"><label>Name</label><input id=\"in-name\" required></div>" +
        "<div class=\"field\"><label>Mobile</label><input id=\"in-mobile\"></div>" +
        "<div class=\"field\"><label>Location</label><select id=\"in-location\"><option value=\"\">Select</option><option>Payatas</option><option>Maligaya</option><option>Pampanga</option></select></div>" +
        "<div class=\"field\"><label>Investor</label><select id=\"in-investor\"><option value=\"\">None yet</option>" + investors.map(function (row) { return "<option value=\"" + row.id + "\">" + esc((row.code ? row.code + " · " : "") + row.name) + "</option>"; }).join("") + "</select></div>" +
        "<div class=\"field\"><label>Referral source</label><input id=\"in-source\"></div>" +
        "<div class=\"field\"><label>Referral type</label><input id=\"in-rtype\"></div>" +
        "<div class=\"field\"><label>Referral name</label><input id=\"in-rname\"></div>" +
        "<div class=\"field\"><label>Plan</label><input id=\"in-plan\"></div>" +
        "<div class=\"field\"><label>Address</label><input id=\"in-address\"></div>" +
        "<div class=\"field check\"><input id=\"in-consent\" type=\"checkbox\"><label for=\"in-consent\">Customer agreed to the data privacy notice</label></div>" +
        "<button class=\"btn\" type=\"submit\">Save client and open installation</button></form></section>" +
        "<div class=\"table-wrap\"><table><thead><tr><th>Ticket</th><th>Type</th><th>Customer</th><th>Issue</th><th>Status</th><th>Tech</th></tr></thead><tbody>" +
        (body || "<tr><td colspan=\"6\">No tickets yet.</td></tr>") + "</tbody></table></div>");
      document.getElementById("ops-form").onsubmit = function (event) {
        event.preventDefault();
        var tech = document.getElementById("ops-tech").value;
        db.from("ops_tickets").insert({
          ticket_type: document.getElementById("ops-type").value,
          customer_id: document.getElementById("ops-customer").value || null,
          issue: document.getElementById("ops-issue").value,
          assigned_to: tech || null,
          status: tech ? "Assigned" : "Open"
        }).then(function (insert) {
          if (insert.error) return flash(errText(insert.error));
          flash("Ticket opened.", true);
          renderOps();
        });
      };
      document.getElementById("intake-form").onsubmit = function (event) {
        event.preventDefault();
        db.rpc("intake_new_client", {
          p_name: document.getElementById("in-name").value.trim(),
          p_mobile: document.getElementById("in-mobile").value.trim(),
          p_location: document.getElementById("in-location").value,
          p_referral_source: document.getElementById("in-source").value.trim(),
          p_referral_type: document.getElementById("in-rtype").value.trim(),
          p_referral_name: document.getElementById("in-rname").value.trim(),
          p_consent: document.getElementById("in-consent").checked,
          p_investor: document.getElementById("in-investor").value || null,
          p_plan: document.getElementById("in-plan").value.trim(),
          p_address: document.getElementById("in-address").value.trim()
        }).then(function (result) {
          if (result.error) return flash(errText(result.error));
          var ticket = result.data && result.data.ticket_id;
          flash("Client saved.", true);
          if (ticket) go("ops/" + ticket);
          else renderOps();
        });
      };
    });
  }

  function renderOpsTicket(id) {
    var gen = viewGen;
    shell("<section class=\"panel\"><h1>Ticket</h1><p class=\"muted\">Loading…</p></section>");
    Promise.all([
      db.from("ops_tickets").select("*, customers(name, account_number, address, lp, nap, port)").eq("id", id).maybeSingle(),
      db.from("ticket_notes").select("*").eq("ticket_id", id).order("created_at"),
      db.from("ticket_materials").select("*").eq("ticket_id", id),
      db.from("ticket_photos").select("*").eq("ticket_id", id),
      db.from("staff").select("id, name, role, active").eq("active", true).order("name")
    ]).then(function (parts) {
      if (gen !== viewGen) return;
      if (parts[0].error || !parts[0].data) return flash(parts[0].error ? errText(parts[0].error) : "Ticket not found.");
      var row = parts[0].data;
      var person = row.customers || {};
      var notes = parts[1].error ? [] : (parts[1].data || []);
      var materials = parts[2].error ? [] : (parts[2].data || []);
      var photos = parts[3].error ? [] : (parts[3].data || []);
      var staff = parts[4].error ? [] : (parts[4].data || []);
      var techs = staff.filter(function (item) { return item.role === "tech"; });
      shell("<section class=\"panel\"><p><a href=\"#ops\">All tickets</a></p><h1>" + esc(row.ticket_no) + "</h1>" +
        "<p class=\"muted\">" + esc(opsTypeLabel(row.ticket_type)) + " · " + esc(person.name || "No customer") + (person.account_number ? " · " + esc(person.account_number) : "") + "</p>" +
        "<form id=\"ops-edit\" class=\"grid two\">" +
        "<div class=\"field\"><label>Status</label><select id=\"ops-status\">" + OPS_STATUSES.map(function (item) {
          return "<option" + (item === row.status ? " selected" : "") + ">" + esc(item) + "</option>";
        }).join("") + "</select></div>" +
        "<div class=\"field\"><label>Tech</label><select id=\"ops-assign\"><option value=\"\">Unassigned</option>" + techs.map(function (item) {
          return "<option value=\"" + item.id + "\"" + (item.id === row.assigned_to ? " selected" : "") + ">" + esc(item.name) + "</option>";
        }).join("") + "</select></div>" +
        "<div class=\"field\"><label>Helpers</label><select id=\"ops-helpers\" multiple size=\"4\">" + techs.map(function (item) {
          var on = (row.helpers || []).indexOf(item.id) >= 0;
          return "<option value=\"" + item.id + "\"" + (on ? " selected" : "") + ">" + esc(item.name) + "</option>";
        }).join("") + "</select></div>" +
        "<div class=\"field\"><label>Issue</label><input id=\"ops-issue\" value=\"" + esc(row.issue || "") + "\"></div>" +
        "<div class=\"field\"><label>Notes</label><textarea id=\"ops-notes\">" + esc(row.notes || "") + "</textarea></div>" +
        "<button class=\"btn\" type=\"submit\">Save assignment</button></form></section>" +
        "<section class=\"panel\"><h2>Materials na ginamit</h2><ul>" + (materials.map(function (item) {
          return "<li>" + esc(item.item) + " × " + esc(item.qty) + (item.unit_cost == null ? " (no price yet)" : " · ₱" + esc(item.unit_cost)) + "</li>";
        }).join("") || "<li>None yet</li>") + "</ul>" +
        "<form id=\"mat-form\" class=\"grid two\"><div class=\"field\"><label>Item</label><select id=\"mat-item\">" + MATERIAL_ITEMS.map(function (item) { return "<option>" + esc(item) + "</option>"; }).join("") + "</select></div>" +
        "<div class=\"field\"><label>Qty</label><input id=\"mat-qty\" type=\"number\" min=\"0.01\" step=\"0.01\" value=\"1\"></div>" +
        "<button class=\"btn\" type=\"submit\">Add material</button></form></section>" +
        "<section class=\"panel\"><h2>Notes</h2>" + notes.map(function (item) {
          return "<p><strong>" + esc(item.created_by || "note") + "</strong> · " + esc(item.body) + "</p>";
        }).join("") +
        "<form id=\"note-form\" class=\"grid\"><div class=\"field\"><label>Add note</label><textarea id=\"note-body\"></textarea></div><button class=\"btn\" type=\"submit\">Add note</button></form></section>" +
        "<section class=\"panel\"><h2>Photos</h2>" + photos.map(function (item) {
          return "<p><button type=\"button\" class=\"btn secondary\" data-photo=\"" + esc(item.path) + "\">View</button></p>";
        }).join("") +
        "<form id=\"photo-form\"><input id=\"photo-file\" type=\"file\" accept=\"image/jpeg,image/png,image/webp\" required> <button class=\"btn\" type=\"submit\">Upload</button></form></section>" +
        (row.ticket_type === "INSTALLATION" ? "<section class=\"panel\"><h2>Installation tapos</h2><p class=\"muted\">PPPoE is generated from the account number. Cash or GCash records the installation fee.</p>" +
          "<form id=\"done-form\" class=\"grid two\">" +
          "<div class=\"field\"><label>LP</label><input id=\"done-lp\" value=\"" + esc(person.lp || "") + "\"></div>" +
          "<div class=\"field\"><label>NAP</label><input id=\"done-nap\" value=\"" + esc(person.nap || "") + "\"></div>" +
          "<div class=\"field\"><label>Port</label><input id=\"done-port\" value=\"" + esc(person.port || "") + "\"></div>" +
          "<div class=\"field\"><label>Modem serial</label><input id=\"done-serial\"></div>" +
          "<div class=\"field\"><label>Bayad</label><select id=\"done-method\"><option value=\"cash\">Cash</option><option value=\"gcash\">GCash</option></select></div>" +
          "<div class=\"field\"><label>Amount</label><input id=\"done-amount\" type=\"number\" min=\"0\" step=\"0.01\" placeholder=\"Installation fee\"></div>" +
          "<div class=\"field\"><label>GCash ref</label><input id=\"done-ref\"></div>" +
          "<button class=\"btn\" type=\"submit\">Mark installed</button></form></section>" : "") +
        "<section class=\"panel\"><h2>Close ticket</h2><form id=\"resolve-form\" class=\"grid\"><div class=\"field\"><label>Resolution</label><textarea id=\"resolve-text\">" + esc(row.resolution || "") + "</textarea></div><button class=\"btn\" type=\"submit\">Mark resolved</button></form>" +
        "<p class=\"muted\">Closing posts Operational expenses for SC connector, modem, rewiring, and power adaptor when a price is set. The account code comes from the investor.</p></section>");
      document.getElementById("ops-edit").onsubmit = function (event) {
        event.preventDefault();
        var helpers = Array.prototype.map.call(document.getElementById("ops-helpers").selectedOptions, function (option) { return option.value; });
        db.from("ops_tickets").update({
          status: document.getElementById("ops-status").value,
          assigned_to: document.getElementById("ops-assign").value || null,
          helpers: helpers,
          issue: document.getElementById("ops-issue").value.trim() || null,
          notes: document.getElementById("ops-notes").value.trim() || null
        }).eq("id", id).then(function (update) {
          if (update.error) return flash(errText(update.error));
          flash("Saved.", true);
          renderOpsTicket(id);
        });
      };
      document.getElementById("mat-form").onsubmit = function (event) {
        event.preventDefault();
        db.rpc("tech_add_material", {
          p_ticket: id,
          p_item: document.getElementById("mat-item").value,
          p_qty: Number(document.getElementById("mat-qty").value)
        }).then(function (result) {
          if (result.error) return flash(errText(result.error));
          renderOpsTicket(id);
        });
      };
      document.getElementById("note-form").onsubmit = function (event) {
        event.preventDefault();
        db.rpc("tech_add_note", { p_ticket: id, p_body: document.getElementById("note-body").value }).then(function (result) {
          if (result.error) return flash(errText(result.error));
          renderOpsTicket(id);
        });
      };
      document.getElementById("photo-form").onsubmit = function (event) {
        event.preventDefault();
        var file = document.getElementById("photo-file").files[0];
        if (!file) return;
        uploadTicketPhoto(id, file).then(function (insert) {
          if (insert.error) return flash(errText(insert.error));
          flash("Photo saved.", true);
          renderOpsTicket(id);
        }).catch(function (error) { flash(errText(error)); });
      };
      app.querySelectorAll("[data-photo]").forEach(function (button) {
        button.onclick = function () {
          db.storage.from("ticket-photos").createSignedUrl(button.getAttribute("data-photo"), 3600).then(function (signed) {
            if (signed.error || !signed.data) return flash(errText(signed.error));
            window.open(signed.data.signedUrl, "_blank", "noopener");
          });
        };
      });
      var done = document.getElementById("done-form");
      if (done) done.onsubmit = function (event) {
        event.preventDefault();
        var amount = document.getElementById("done-amount").value;
        db.rpc("complete_installation", {
          p_ticket: id,
          p_lp: document.getElementById("done-lp").value.trim(),
          p_nap: document.getElementById("done-nap").value.trim(),
          p_port: document.getElementById("done-port").value.trim(),
          p_modem_serial: document.getElementById("done-serial").value.trim(),
          p_pay_method: document.getElementById("done-method").value,
          p_pay_amount: amount === "" ? null : Number(amount),
          p_pay_ref: document.getElementById("done-ref").value.trim()
        }).then(function (result) {
          if (result.error) return flash(errText(result.error));
          flash("Installed. PPPoE " + ((result.data && result.data.pppoe) || ""), true);
          renderOpsTicket(id);
        });
      };
      document.getElementById("resolve-form").onsubmit = function (event) {
        event.preventDefault();
        db.rpc("resolve_ops_ticket", { p_ticket: id, p_resolution: document.getElementById("resolve-text").value }).then(function (result) {
          if (result.error) return flash(errText(result.error));
          flash("Resolved. Expenses posted: " + ((result.data && result.data.expenses) || 0), true);
          renderOpsTicket(id);
        });
      };
    });
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
    if (current.name === "finance") return renderFinance();
    if (current.name === "gcash") return renderGcash();
    if (current.name === "logbook") return renderLogbook();
    if (current.name === "payments") return renderPayments();
    if (current.name === "map") return renderMap();
    if (current.name === "repairs") return renderRepairs();
    if (current.name === "ops") return renderOps();
    if (current.name === "staff") return renderStaff();
    if (current.name === "modems") return renderModems();
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
