/* FiberBro Supabase config
   Project URL and anon public key from Supabase → Project Settings → Data API.
   This is the anon key, which is meant for browser code. Never put the service_role key here.
   If these are replaced with YOUR_PROJECT_REF / YOUR_SUPABASE_ANON_KEY placeholders,
   the admin portal shows a setup message and the inquiry form skips Supabase. */
(function (global) {
  var url = "https://lrzfaxhaujrrxivvphls.supabase.co";
  var anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxyemZheGhhdWpycnhpdnZwaGxzIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTM5NDUwNjksImV4cCI6MjEwOTUyMTA2OX0.xU2bFJrz0PM_CY3z5N0otOCog4lwoP6Jg4Quwv3sXp0";

  function isConfigured() {
    if (!url || !anonKey) return false;
    if (url.indexOf("YOUR_PROJECT_REF") !== -1) return false;
    if (anonKey.indexOf("YOUR_SUPABASE_ANON_KEY") !== -1) return false;
    if (!/^https:\/\/[a-z0-9-]+\.supabase\.co\/?$/i.test(url)) return false;
    if (anonKey.length < 20) return false;
    return true;
  }

  global.FIBERBRO_SUPABASE = {
    url: url.replace(/\/$/, ""),
    anonKey: anonKey,
    isConfigured: isConfigured
  };
})(window);
