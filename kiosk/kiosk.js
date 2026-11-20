(function () {
  "use strict";

  var app = document.getElementById("app");
  var db = null;
  var ready = false;
  var TOKEN_KEY = "fiberbro_kiosk_token";

  function esc(value) {
    return String(value == null ? "" : value).replace(/[&<>"']/g, function (ch) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;" }[ch];
    });
  }

  function text(error) {
    return (error && error.message) || String(error || "Something went wrong.");
  }

  function token() {
    try { return localStorage.getItem(TOKEN_KEY) || ""; } catch (err) { return ""; }
  }

  function setToken(value) {
    localStorage.setItem(TOKEN_KEY, value);
  }

  function selfie(video) {
    var canvas = document.createElement("canvas");
    canvas.width = video.videoWidth || 320;
    canvas.height = video.videoHeight || 240;
    canvas.getContext("2d").drawImage(video, 0, 0, canvas.width, canvas.height);
    var url = canvas.toDataURL("image/jpeg", 0.7);
    var comma = url.indexOf(",");
    return comma >= 0 ? url.slice(comma + 1) : "";
  }

  function loadModels() {
    return new Promise(function (resolve, reject) {
      var script = document.createElement("script");
      script.src = "https://cdn.jsdelivr.net/npm/face-api.js@0.22.2/dist/face-api.min.js";
      script.onload = function () { resolve(); };
      script.onerror = function () { reject(new Error("Face library did not load.")); };
      document.head.appendChild(script);
    }).then(function () {
      var api = window.faceapi;
      var weights = "https://cdn.jsdelivr.net/gh/justadudewhohacks/face-api.js@0.22.2/weights";
      return Promise.all([
        api.nets.tinyFaceDetector.loadFromUri(weights),
        api.nets.faceLandmark68TinyNet.loadFromUri(weights),
        api.nets.faceRecognitionNet.loadFromUri(weights)
      ]);
    });
  }

  function askToken() {
    app.innerHTML = "<section class=\"panel\"><h1>Office kiosk</h1><p>Paste the device token from Employees → Register office phone. This phone keeps it.</p>" +
      "<form id=\"tok\"><div class=\"field\"><label>Device token</label><input id=\"token\" required></div><button class=\"btn\" type=\"submit\">Save this phone</button></form></section>";
    document.getElementById("tok").onsubmit = function (event) {
      event.preventDefault();
      setToken(document.getElementById("token").value.trim());
      openCamera();
    };
  }

  function openCamera() {
    if (!token()) return askToken();
    app.innerHTML = "<section class=\"panel\"><h1>Punch</h1><p class=\"muted\" id=\"kiosk-status\">Opening camera…</p>" +
      "<video id=\"cam\" autoplay playsinline width=\"320\"></video>" +
      "<div class=\"actions\"><button type=\"button\" class=\"btn\" id=\"punch\">Match and punch</button>" +
      "<button type=\"button\" class=\"btn secondary\" id=\"forget\">Forget this phone</button></div>" +
      "<p id=\"kiosk-msg\"></p></section>";
    var video = document.getElementById("cam");
    document.getElementById("forget").onclick = function () {
      localStorage.removeItem(TOKEN_KEY);
      askToken();
    };
    navigator.mediaDevices.getUserMedia({ video: { facingMode: "user" } }).then(function (stream) {
      video.srcObject = stream;
      document.getElementById("kiosk-status").textContent = ready ? "Ready." : "Loading face models…";
      return ready ? null : loadModels();
    }).then(function () {
      ready = true;
      document.getElementById("kiosk-status").textContent = "Look at the camera, then punch.";
    }).catch(function (error) {
      document.getElementById("kiosk-status").textContent = text(error);
    });
    document.getElementById("punch").onclick = function () {
      var api = window.faceapi;
      var status = document.getElementById("kiosk-msg");
      if (!api || !ready) {
        status.textContent = "Models are still loading.";
        return;
      }
      status.textContent = "Matching…";
      api.detectSingleFace(video, new api.TinyFaceDetectorOptions()).withFaceLandmarks(true).withFaceDescriptor().then(function (found) {
        if (!found) throw new Error("No face in the camera.");
        return db.rpc("kiosk_roster", { p_token: token() }).then(function (roster) {
          if (roster.error) throw roster.error;
          var best = null;
          var bestDist = 0.45;
          (roster.data || []).forEach(function (person) {
            var dist = api.euclideanDistance(found.descriptor, person.descriptor);
            if (dist < bestDist) {
              best = person;
              bestDist = dist;
            }
          });
          if (!best) throw new Error("No enrolled face matched.");
          var shot = selfie(video);
          return db.rpc("kiosk_punch", {
            p_token: token(),
            p_employee: best.id,
            p_type: "next",
            p_selfie: shot
          }).then(function (saved) {
            if (saved.error) throw saved.error;
            status.textContent = best.name + " · " + ((saved.data && saved.data.punch_type) || "punched");
          });
        });
      }).catch(function (error) {
        status.textContent = text(error);
      });
    };
  }

  var cfg = window.FIBERBRO_SUPABASE;
  if (!cfg || typeof cfg.isConfigured !== "function" || !cfg.isConfigured()) {
    app.innerHTML = "<section class=\"panel\"><h1>Not configured</h1></section>";
    return;
  }
  import("https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm").then(function (mod) {
    db = mod.createClient(cfg.url, cfg.anonKey, { auth: { persistSession: false, detectSessionInUrl: false } });
    openCamera();
  }).catch(function (error) {
    app.innerHTML = "<section class=\"panel\"><h1>Could not load</h1><p>" + esc(text(error)) + "</p></section>";
  });
})();
