// src/utils/geocode.js
// Wandelt einen Ortsstring in lat/lng um — nutzt OpenStreetMap Nominatim (kostenlos, kein API-Key)

/**
 * Gibt { lat, lng } zurück oder null wenn nichts gefunden wurde.
 * @param {string} location  z.B. "Berlin", "Stuttgart-Vaihingen", "Hamburg, Altona"
 */
async function geocodeLocation(location) {
  if (!location || !location.trim()) return null;

  try {
    const query = encodeURIComponent(location.trim());
    const url   = `https://nominatim.openstreetmap.org/search?q=${query}&format=json&limit=1&addressdetails=0`;

    const res = await fetch(url, {
      headers: {
        // Nominatim Terms of Service: User-Agent mit Projektname + Kontakt pflicht
        "User-Agent": "SwipeShift/1.0 (swipeshift-backend; contact@swipeshift.local)",
        "Accept-Language": "de,en",
      },
    });

    if (!res.ok) {
      console.warn(`geocode: HTTP ${res.status} für "${location}"`);
      return null;
    }

    const results = await res.json();

    if (!results.length) {
      console.warn(`geocode: Kein Ergebnis für "${location}"`);
      return null;
    }

    const { lat, lon } = results[0];
    return { lat: parseFloat(lat), lng: parseFloat(lon) };

  } catch (err) {
    console.error(`geocode: Fehler bei "${location}":`, err.message);
    return null;
  }
}

module.exports = { geocodeLocation };
