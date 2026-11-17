// src/utils/haversine.js
// Berechnet die Distanz zwischen zwei Koordinaten in Kilometern.

/**
 * @param {number} lat1 - Breitengrad Punkt 1
 * @param {number} lng1 - Längengrad Punkt 1
 * @param {number} lat2 - Breitengrad Punkt 2
 * @param {number} lng2 - Längengrad Punkt 2
 * @returns {number} Distanz in Kilometern
 */
function haversineDistance(lat1, lng1, lat2, lng2) {
  const R = 6371; // Erdradius in km

  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);

  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) *
      Math.cos(toRad(lat2)) *
      Math.sin(dLng / 2) *
      Math.sin(dLng / 2);

  const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));

  return R * c;
}

function toRad(deg) {
  return (deg * Math.PI) / 180;
}

// Umrechnung km <-> Meilen. Intern wird in km gerechnet, angezeigt/gefiltert wird in Meilen (US-Launch).
const KM_PER_MILE = 1.609344;

function kmToMiles(km) {
  return km / KM_PER_MILE;
}

function milesToKm(miles) {
  return miles * KM_PER_MILE;
}

// Distanz in Meilen (auf 0,1 gerundet) oder null, wenn eine Koordinate fehlt/ungueltig ist
function distanceMilesBetween(lat1, lng1, lat2, lng2) {
  const vals = [lat1, lng1, lat2, lng2];
  if (vals.some((v) => typeof v !== "number" || !Number.isFinite(v))) return null;
  return Math.round(kmToMiles(haversineDistance(lat1, lng1, lat2, lng2)) * 10) / 10;
}

module.exports = { haversineDistance, kmToMiles, milesToKm, KM_PER_MILE, distanceMilesBetween };
