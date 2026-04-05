# Cloudflare Geolocation Setup

Tickr can detect the user's country via Cloudflare's `CF-IPCountry` header instead of a third-party IP API. This is faster, more reliable, and uses your own infrastructure.

## How It Works

When a domain is proxied through Cloudflare, every request automatically gets a `CF-IPCountry` response header with the 2-letter country code (e.g., `US`, `GB`, `DE`). Tickr sends a lightweight `HEAD` request to your endpoint and reads this header — no body, no tracking, no third party.

## Setup (5 minutes)

### 1. Add your domain to Cloudflare

If `h4ux.com` (or your domain) isn't already on Cloudflare:

1. Go to [dash.cloudflare.com](https://dash.cloudflare.com/)
2. Add your site → follow the nameserver setup
3. Ensure the domain's DNS record has the **orange cloud (Proxied)** enabled

### 2. Enable IP Geolocation

1. Go to **dash.cloudflare.com** → your domain → **Network**
2. Toggle **IP Geolocation** to **ON**

This tells Cloudflare to add the `CF-IPCountry` header to all proxied requests.

### 3. Create a /geo endpoint

You need a URL that returns any response (the body doesn't matter — Tickr only reads the header). Options:

#### Option A: Cloudflare Worker (recommended, free)

Create a Worker at **Workers & Pages → Create → Worker**:

```javascript
export default {
  async fetch(request) {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Expose-Headers": "CF-IPCountry",
      },
    });
  },
};
```

Assign a route: `h4ux.com/geo` → this Worker.

#### Option B: Static page

Just create any page at `/geo` on your server (can be an empty HTML file). As long as the domain is proxied through Cloudflare, the header is added automatically.

#### Option C: Page Rule redirect

Add a **Page Rule** for `h4ux.com/geo`:
- Setting: **Always Online** (or just let it 404 — the header is still there)

### 4. Verify it works

```bash
curl -I https://h4ux.com/geo 2>&1 | grep -i cf-ipcountry
# Should output: cf-ipcountry: US (or your country)
```

### 5. Update the app

In `Tickr/Services/AdService.swift`, change:

```swift
private static let geoMethod = "cloudflare"
private static let geoEndpoint = "https://h4ux.com/geo"
```

That's it. The app will now use Cloudflare for country detection instead of ipapi.co.

## Comparison

| Method | Speed | Reliability | Privacy | Cost |
|--------|-------|-------------|---------|------|
| **Cloudflare** | ~50ms (HEAD request) | Very high (your infra) | Best (your domain, no 3rd party) | Free |
| **ipapi.co** | ~200ms (GET request) | Good (1000 req/day free) | OK (3rd party sees IP) | Free up to 1K/day |
| **System locale** | Instant | Low (language ≠ location) | Best (no network) | Free |

## Rate Limits

- **Cloudflare:** No limit on your own domain
- **ipapi.co:** 1,000 requests/day on free tier (enough for most apps since we cache)
