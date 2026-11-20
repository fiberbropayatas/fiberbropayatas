(function () {
  "use strict";

  var app = document.getElementById("app");
  var db = null;
  var ready = false;
  var punching = false;
  var TOKEN_KEY = "fiberbro_kiosk_token";
  var MATCH_MAX = 0.45;
  var LIMIT_MS = 5000;
  var TICK_MS = 130;
  var LOST_MS = 700;
  var YAW_TURN = 0.18;
  var NOD_DOWN = 0.15;
  var NOD_BACK = 0.06;

  function esc(value) {
    return String(value == null ? "" : value).replace(/[&<>"']/g, function (ch) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;" }[ch];
    });
  }

  function text(error) {
    return (error && error.message) || String(error || "Something went wrong.");
  }

  function cameraMessage(error) {
    var name = error && error.name;
    if (name === "NotAllowedError" || name === "PermissionDeniedError") return "Payagan ang camera sa browser settings";
    if (name === "NotFoundError" || name === "DevicesNotFoundError") return "Walang camera na nakita";
    return text(error);
  }

  function token() {
    try { return localStorage.getItem(TOKEN_KEY) || ""; } catch (err) { return ""; }
  }

  function setToken(value) {
    localStorage.setItem(TOKEN_KEY, value);
  }

  function selfie(video) {
    var canvas = document.createElement("canvas");
    var width = video.videoWidth || 320;
    var height = video.videoHeight || 240;
    var scale = Math.min(1, 320 / width);
    canvas.width = Math.max(1, Math.round(width * scale));
    canvas.height = Math.max(1, Math.round(height * scale));
    canvas.getContext("2d").drawImage(video, 0, 0, canvas.width, canvas.height);
    var url = canvas.toDataURL("image/jpeg", 0.6);
    var comma = url.indexOf(",");
    return comma >= 0 ? url.slice(comma + 1) : "";
  }

  function dist(a, b) {
    var dx = a.x - b.x;
    var dy = a.y - b.y;
    return Math.sqrt(dx * dx + dy * dy);
  }

  function ear(points, a, b, c, d, e, f) {
    return (dist(points[b], points[f]) + dist(points[c], points[e])) / (2 * Math.max(1, dist(points[a], points[d])));
  }

  function metrics(landmarks) {
    var points = landmarks.positions;
    var left = ear(points, 36, 37, 38, 39, 40, 41);
    var right = ear(points, 42, 43, 44, 45, 46, 47);
    var eyeA = { x: (points[36].x + points[39].x) / 2, y: (points[36].y + points[39].y) / 2 };
    var eyeB = { x: (points[42].x + points[45].x) / 2, y: (points[42].y + points[45].y) / 2 };
    var mid = { x: (eyeA.x + eyeB.x) / 2, y: (eyeA.y + eyeB.y) / 2 };
    var span = Math.max(1, dist(eyeA, eyeB));
    return {
      ear: (left + right) / 2,
      yaw: (points[30].x - mid.x) / span,
      pitch: (points[30].y - mid.y) / span
    };
  }

  function bestMatch(api, descriptor, roster) {
    var best = null;
    var bestDist = MATCH_MAX;
    (roster || []).forEach(function (person) {
      if (!person.descriptor) return;
      var gap = api.euclideanDistance(descriptor, person.descriptor);
      if (gap < bestDist) {
        best = person;
        bestDist = gap;
      }
    });
    return best ? { person: best, distance: bestDist } : null;
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

  function paintChallenge(state) {
    var prompt = document.getElementById("kiosk-prompt");
    var count = document.getElementById("kiosk-count");
    var checks = document.getElementById("kiosk-checks");
    if (!prompt) return;
    prompt.hidden = false;
    var labels = { left: "Lumingon sa KALIWA", right: "Lumingon sa KANAN", nod: "Tumango" };
    if (!state.blinkDone) prompt.textContent = "Kumurap ka";
    else if (!state.moveDone) prompt.textContent = labels[state.move];
    else prompt.textContent = "Ayos na";
    var left = Math.max(0, Math.ceil((LIMIT_MS - (Date.now() - state.started)) / 1000));
    if (count) count.textContent = left + "s";
    if (checks) checks.textContent = (state.blinkDone ? "✓ Kurap" : "○ Kurap") + "   " + (state.moveDone ? "✓ Ulo" : "○ Ulo");
  }

  function runLiveness(video, api, roster) {
    return new Promise(function (resolve, reject) {
      var moves = ["left", "right", "nod"];
      var state = {
        move: moves[Math.floor(Math.random() * moves.length)],
        started: Date.now(),
        baseline: null,
        blinkClosed: false,
        blinkDone: false,
        nodDown: false,
        moveDone: false,
        lastSeen: Date.now(),
        identity: null,
        person: null,
        frames: []
      };
      var stopped = false;
      var opts = new api.TinyFaceDetectorOptions({ inputSize: 160, scoreThreshold: 0.4 });

      function finish(error, result) {
        if (stopped) return;
        stopped = true;
        if (error) reject(error);
        else resolve(result);
      }

      function keepFrame() {
        if (state.frames.length >= 4) return;
        var shot = selfie(video);
        if (shot && state.frames.indexOf(shot) < 0) state.frames.push(shot);
      }

      function step() {
        if (stopped) return;
        if (Date.now() - state.started > LIMIT_MS) {
          finish(new Error("Hindi pumasa ang liveness check, subukan ulit"));
          return;
        }
        paintChallenge(state);
        var wantDescriptor = !state.identity || (state.blinkDone && state.moveDone);
        var pending = api.detectAllFaces(video, opts).withFaceLandmarks(true);
        if (wantDescriptor) pending = pending.withFaceDescriptors();
        pending.then(function (faces) {
          if (stopped) return;
          if (!faces || faces.length !== 1) {
            if (faces && faces.length > 1) {
              finish(new Error("Isang mukha lang ang puwede."));
              return;
            }
            if (Date.now() - state.lastSeen > LOST_MS) {
              finish(new Error("Nawala ang mukha. Subukan ulit."));
              return;
            }
            setTimeout(step, TICK_MS);
            return;
          }
          state.lastSeen = Date.now();
          var face = faces[0];
          var pose = metrics(face.landmarks);
          if (!state.baseline) {
            state.baseline = pose;
            keepFrame();
          }
          if (face.descriptor) {
            var match = bestMatch(api, face.descriptor, roster);
            if (!match) {
              finish(new Error("No enrolled face matched."));
              return;
            }
            if (!state.identity) {
              state.identity = face.descriptor;
              state.person = match.person;
            } else if (api.euclideanDistance(state.identity, face.descriptor) >= MATCH_MAX || match.person.id !== state.person.id) {
              finish(new Error("Ibang mukha ang nakita. Subukan ulit."));
              return;
            }
          }
          var base = state.baseline;
          var closedAt = Math.min(0.21, base.ear * 0.72);
          if (!state.blinkClosed && pose.ear < closedAt) state.blinkClosed = true;
          if (state.blinkClosed && !state.blinkDone && pose.ear > base.ear * 0.9) {
            state.blinkDone = true;
            keepFrame();
          }
          // CSS mirrors the preview. Screen-left is raw image-right, so KALIWA is a rising yaw.
          if (state.move === "left" && pose.yaw - base.yaw > YAW_TURN) state.moveDone = true;
          if (state.move === "right" && base.yaw - pose.yaw > YAW_TURN) state.moveDone = true;
          if (state.move === "nod") {
            if (!state.nodDown && pose.pitch - base.pitch > NOD_DOWN) state.nodDown = true;
            if (state.nodDown && Math.abs(pose.pitch - base.pitch) < NOD_BACK) state.moveDone = true;
          }
          if (state.moveDone) keepFrame();
          if (state.blinkDone && state.moveDone && state.person) {
            keepFrame();
            finish(null, {
              person: state.person,
              move: state.move,
              duration: Date.now() - state.started,
              frames: state.frames.slice(0, 4)
            });
            return;
          }
          setTimeout(step, TICK_MS);
        }).catch(function (error) {
          finish(error);
        });
      }

      step();
    });
  }

  function openCamera() {
    if (!token()) return askToken();
    app.innerHTML = "<section class=\"panel\"><h1>Punch</h1><p class=\"muted\" id=\"kiosk-status\">Opening camera…</p>" +
      "<video id=\"cam\" autoplay playsinline muted width=\"320\"></video>" +
      "<p id=\"kiosk-prompt\" class=\"kiosk-prompt\" hidden></p>" +
      "<p id=\"kiosk-count\" class=\"kiosk-count\"></p>" +
      "<p id=\"kiosk-checks\" class=\"kiosk-checks\"></p>" +
      "<div class=\"actions\"><button type=\"button\" class=\"btn\" id=\"punch\">Match and punch</button>" +
      "<button type=\"button\" class=\"btn secondary\" id=\"forget\">Forget this phone</button></div>" +
      "<p id=\"kiosk-msg\"></p></section>";
    var video = document.getElementById("cam");
    document.getElementById("forget").onclick = function () {
      localStorage.removeItem(TOKEN_KEY);
      askToken();
    };
    var streamPromise;
    try {
      if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
        throw new Error("Walang camera na nakita");
      }
      streamPromise = navigator.mediaDevices.getUserMedia({ video: { facingMode: "user" }, audio: false });
    } catch (error) {
      document.getElementById("kiosk-status").textContent = cameraMessage(error);
      return;
    }
    streamPromise.then(function (stream) {
      video.srcObject = stream;
      document.getElementById("kiosk-status").textContent = ready ? "Ready." : "Loading face models…";
      return ready ? null : loadModels();
    }).then(function () {
      ready = true;
      document.getElementById("kiosk-status").textContent = "Tumingin sa camera, tapos punch.";
    }).catch(function (error) {
      document.getElementById("kiosk-status").textContent = cameraMessage(error);
    });
    document.getElementById("punch").onclick = function () {
      var api = window.faceapi;
      var status = document.getElementById("kiosk-msg");
      var button = document.getElementById("punch");
      if (punching) return;
      if (!api || !ready) {
        status.textContent = "Models are still loading.";
        return;
      }
      punching = true;
      button.disabled = true;
      status.textContent = "";
      db.rpc("kiosk_roster", { p_token: token() }).then(function (roster) {
        if (roster.error) throw roster.error;
        return runLiveness(video, api, roster.data || []);
      }).then(function (passed) {
        var primary = passed.frames[0] || selfie(video);
        return db.rpc("kiosk_punch", {
          p_token: token(),
          p_employee: passed.person.id,
          p_type: "next",
          p_selfie: primary,
          p_burst: passed.frames,
          p_liveness: {
            challenge: passed.move,
            passed: true,
            duration_ms: passed.duration,
            blink: true,
            head: passed.move
          }
        }).then(function (saved) {
          if (saved.error) throw saved.error;
          status.textContent = passed.person.name + " · " + ((saved.data && saved.data.punch_type) || "punched");
          var prompt = document.getElementById("kiosk-prompt");
          if (prompt) prompt.hidden = true;
        });
      }).catch(function (error) {
        status.textContent = text(error);
        var prompt = document.getElementById("kiosk-prompt");
        if (prompt) prompt.hidden = true;
      }).then(function () {
        punching = false;
        if (button) button.disabled = false;
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
