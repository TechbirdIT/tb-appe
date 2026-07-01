# Copyright (c) 2026, TechbirdIT and contributors
# For license information, please see license.txt

"""
Reverse geocoding (OpenStreetMap / Nominatim)
=============================================
lat/lng → human-readable address, done **server-side and cached** so we respect
Nominatim's usage policy (max ~1 req/s, descriptive User-Agent, no bulk hammering)
regardless of how many employees are being tracked.

Addresses are cached in Redis keyed by coordinates rounded to ~1.1 m precision,
so the same spot is only ever geocoded once. Google Maps is used for map
*display* in the app; geocoding stays on free OSM.
"""

import time

import frappe
import requests

_ENDPOINT = "https://nominatim.openstreetmap.org/reverse"
_USER_AGENT = "tb_appe/1.0 (TechbirdIT hotel HRMS; support@techbirdit.in)"
_CACHE_NS = "appe_geocode"
_LAST_CALL_KEY = "appe_geocode_last_call"
_MIN_INTERVAL = 1.1  # seconds between live Nominatim calls (policy: <= 1 req/s)


def _key(lat, lng):
    return f"{round(float(lat), 5)},{round(float(lng), 5)}"


def _throttle():
    """Space out live calls to honor Nominatim's 1 req/s policy."""
    last = frappe.cache().get_value(_LAST_CALL_KEY)
    if last:
        wait = _MIN_INTERVAL - (time.time() - float(last))
        if wait > 0:
            time.sleep(min(wait, _MIN_INTERVAL))
    frappe.cache().set_value(_LAST_CALL_KEY, time.time())


def _fetch(lat, lng):
    _throttle()
    try:
        resp = requests.get(
            _ENDPOINT,
            params={"format": "jsonv2", "lat": lat, "lon": lng, "zoom": 18, "addressdetails": 0},
            headers={"User-Agent": _USER_AGENT},
            timeout=8,
        )
        if resp.ok:
            return (resp.json() or {}).get("display_name")
    except Exception:
        frappe.log_error("Nominatim reverse geocode failed", "tb_appe.geocode")
    return None


def reverse_geocode(lat, lng):
    """Cached reverse geocode. Returns an address string or None."""
    if lat in (None, "") or lng in (None, ""):
        return None
    key = _key(lat, lng)
    cached = frappe.cache().hget(_CACHE_NS, key)
    if cached is not None:
        return cached or None  # "" is a cached miss — don't re-hit Nominatim
    address = _fetch(lat, lng)
    frappe.cache().hset(_CACHE_NS, key, address or "")
    return address


@frappe.whitelist()
def address_for(lat, lng):
    """Whitelisted single-point reverse geocode for the mobile client."""
    return {"status": True, "data": {"address": reverse_geocode(lat, lng)}}
