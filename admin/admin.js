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
      ["messenger", "Messenger", "text"],
      ["contact_number", "Contact number", "text"],
      ["mobile", "Mobile", "text"],
      ["fb_account", "Facebook account", "text"],
      ["facebook_name", "Facebook name", "text"],
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
      ["pppoe", "PPPoE", "text"]
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
      ["plan_speed", "Plan Speed", "text"],
      ["plan", "Inquiry plan", "text"],
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
    var hash = (location.hash || "#customers").replace(/^#\/?/, "");
    var parts = hash.split("/").filter(Boolean);
    return { name: parts[0] || "customers", id: parts[1] || "" };
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

  function shell(body) {
    var links = [
      ["customers", "Customers"],
      ["investors", "Investors"],
      ["technicians", "Technicians"],
      ["tickets", "Tickets"],
      ["admins", "Admins"]
    ];
    var current = route().name;
    var nav = links.map(function (item) {
      var cls = item[0] === current || (current === "customer" && item[0] === "customers") ? " class=\"active\"" : "";
      return "<a href=\"#" + item[0] + "\"" + cls + ">" + item[1] + "</a>";
    }).join("");
    app.innerHTML = "<nav class=\"nav\">" + nav + "</nav><div id=\"flash\" class=\"flash\" hidden></div>" + body;
  }

  function renderSignedOut() {
    who.innerHTML = "";
    app.innerHTML = "<section class=\"panel sign-panel\"><picture><source type=\"image/webp\" srcset=\"/assets/img/fiberbro-logo.webp?v=20261106p\"><img class=\"sign-logo\" src=\"/assets/img/fiberbro-logo.png?v=20261106p\" width=\"1600\" height=\"501\" alt=\"FiberBro Internet Communication Services Corp.\"></picture><h1>FiberBro admin</h1><p>Sign in with the company Gmail account. Only emails on the admin allowlist can open records.</p><button type=\"button\" class=\"btn\" id=\"sign-in\">Sign in with Google</button></section>";
    document.getElementById("sign-in").onclick = function () {
      db.auth.signInWithOAuth({
        provider: "google",
        options: { redirectTo: location.origin + "/admin/" }
      });
    };
  }

  function renderDenied() {
    who.innerHTML = "<button type=\"button\" id=\"sign-out\">Sign out</button>";
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
        "</span><div><span class=\"tag\">" + esc(stageLabel(row.stage)) + "</span>" +
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
    if (key === "fb_account" && !value && customer.facebook_name) value = customer.facebook_name;
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
    var control = "";
    if (type === "textarea") {
      control = "<textarea id=\"" + id + "\" data-key=\"" + key + "\" data-type=\"text\">" + esc(value || "") + "</textarea>";
    } else if (type === "datetime") {
      control = "<input id=\"" + id + "\" data-key=\"" + key + "\" data-type=\"datetime\" type=\"datetime-local\" value=\"" + esc(toLocalInput(value)) + "\">";
    } else if (type === "date") {
      control = "<input id=\"" + id + "\" data-key=\"" + key + "\" data-type=\"date\" type=\"date\" value=\"" + esc(value ? String(value).slice(0, 10) : "") + "\">";
    } else if (type === "money" || type === "int") {
      control = "<input id=\"" + id + "\" data-key=\"" + key + "\" data-type=\"" + type + "\" type=\"number\" step=\"" + (type === "int" ? "1" : "0.01") + "\" value=\"" + esc(value == null ? "" : value) + "\">";
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
      if (type === "money" || type === "int") payload[key] = Number(raw);
      else if (type === "datetime") payload[key] = new Date(raw).toISOString();
      else payload[key] = raw;
    });
    return payload;
  }

  function formCard(title, body) {
    return "<section class=\"panel section-card\">" +
      "<button type=\"button\" class=\"section-toggle\" aria-expanded=\"true\">" +
      "<span>" + esc(title) + "</span><span class=\"chevron\" aria-hidden=\"true\"></span></button>" +
      "<div class=\"section-body\"><div class=\"section-body-inner\">" + body + "</div></div></section>";
  }

  function renderCustomer(customer, isNew) {
    var sections = SECTIONS.map(function (section) {
      return formCard(section.title, "<div class=\"grid two\">" +
        section.fields.map(function (field) { return inputHtml(field, customer); }).join("") +
        "</div>");
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
      (isNew ? "" : formCard("Change history", state.changeError
        ? "<p class=\"muted\">" + esc(state.changeError) + "</p>"
        : changeHistoryHtml(state.changes))) +
      sections +
      idBlock
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
    var generatedPppoe = buildPppoe();
    var pppoeInput = document.getElementById("f-pppoe");
    if (pppoeInput && generatedPppoe && pppoeInput.value.trim().toUpperCase() === generatedPppoe) lastAutoPppoe = generatedPppoe;
    if (!isNew && customer.valid_id_path) loadValidIdPhoto(customer.valid_id_path);
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
      "<table><thead><tr><th>Name</th><th>Details</th><th>Status</th><th></th></tr></thead><tbody>" + body + "</tbody></table>"
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
        "</td><td data-label=\"Status\">" + esc(ticket.status) + "</td><td data-label=\"Assigned\">" + esc(ticket.assigned_by || "") + "</td></tr>";
    }).join("");
    shell("<section class=\"panel\"><h1>Tickets</h1><p class=\"muted\">A ticket is created when an admin marks the customer Active. Assigning a technician updates the ticket only.</p></section>" +
      "<table><thead><tr><th>Customer</th><th>Stage</th><th>Technician</th><th>Status</th><th>Assigned by</th></tr></thead><tbody>" +
      (body || "<tr><td>No tickets yet.</td></tr>") + "</tbody></table>");
  }

  function renderAdmins() {
    var body = state.admins.map(function (row) {
      return "<tr><td data-label=\"Email\">" + esc(row.email) + "</td><td data-label=\"\"><button type=\"button\" class=\"btn secondary\" data-remove=\"" + row.id + "\">Remove</button></td></tr>";
    }).join("");
    shell("<section class=\"panel\"><h1>Admins</h1><p class=\"muted\">Only these Gmail addresses can use the portal. The check is in the database, not only on this page.</p>" +
      "<form id=\"admin-form\" class=\"toolbar\"><input id=\"admin-email\" type=\"email\" placeholder=\"name@gmail.com\" required><button class=\"btn\" type=\"submit\">Add admin</button></form></section>" +
      "<table><thead><tr><th>Email</th><th></th></tr></thead><tbody>" + body + "</tbody></table>");
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
    return Promise.all([
      db.from("customers").select("*").eq("id", id).single(),
      db.from("customer_stage_events").select("*").eq("customer_id", id).order("changed_at"),
      db.from("tickets").select("*").eq("customer_id", id).maybeSingle(),
      db.from("customer_change_log").select("*").eq("customer_id", id).order("changed_at", { ascending: true })
    ]).then(function (results) {
      if (results[0].error) throw results[0].error;
      state.customer = results[0].data;
      state.events = results[1].data || [];
      state.ticket = results[2].data || null;
      state.changes = results[3].error ? [] : (results[3].data || []);
      state.changeError = results[3].error ? errText(results[3].error) : "";
      renderCustomer(state.customer, false);
    }).catch(function (error) { flash(errText(error)); });
  }

  function render() {
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
    renderCustomers();
  }

  var bootedFor = "";
  function boot(email) {
    sessionEmail = email || "";
    if (!sessionEmail || bootedFor === sessionEmail.toLowerCase()) return;
    bootedFor = sessionEmail.toLowerCase();
    who.innerHTML = "<span style=\"margin-right:.6rem\">" + esc(sessionEmail) + "</span><button type=\"button\" id=\"sign-out\">Sign out</button>";
    document.getElementById("sign-out").onclick = signOut;
    db.from("admins").select("email").eq("email", sessionEmail.toLowerCase()).maybeSingle().then(function (result) {
      if (result.error) {
        app.innerHTML = "<section class=\"panel\"><h1>Could not open the admin list</h1><p>" + esc(errText(result.error)) + "</p><p class=\"muted\">Run supabase/schema.sql in the Supabase SQL editor, then reload.</p></section>";
        return;
      }
      if (!result.data) return renderDenied();
      refresh().then(render).catch(function (error) {
        app.innerHTML = "<section class=\"panel\"><h1>Could not load records</h1><p>" + esc(errText(error)) + "</p></section>";
      });
    });
  }

  window.addEventListener("hashchange", function () {
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
      app.innerHTML = "<section class=\"panel\"><h1>Could not reach Supabase</h1><p>" + esc(errText(result && result.error)) + "</p></section>";
      return;
    }
    var session = result.data.session;
    if (!session) return renderSignedOut();
    boot(session.user.email || "");
  }).catch(function (error) {
    app.innerHTML = "<section class=\"panel\"><h1>Could not load the admin portal</h1><p>" + esc(errText(error)) + "</p></section>";
  });
})();
