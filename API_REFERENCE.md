# EmberSensor API Reference

Backend repo: [shauryarchs/embersensor-site](https://github.com/shauryarchs/embersensor-site)

## Site Pages

| Page | URL | Description |
|------|-----|-------------|
| Home | `/` | Landing page |
| Live Fire Risk | `/status.html` | Web dashboard |
| Live Camera | `/live.html` | Live camera feed |
| How It Works | `/how-it-works.html` | System explanation |
| Wildfire Analysis | `/fire-graph.html` | Neo4j fire causation knowledge graph |

---

## GET /api/status

Returns current fire risk assessment combining sensor data, weather, and satellite fire detections.

**Optional query params:**
- `refreshWeather=1` — force refresh weather data
- `refreshFirms=1` — force refresh FIRMS satellite data
- `t=<unix_timestamp>` — cache buster

**Response:**

```json
{
  "weatherTemperature": 72.5,
  "sensorTemperature": 74.2,
  "smoke": 150.0,
  "flame": 1,
  "humidity": 35.0,
  "wind": 3.2,
  "windDirection": 220.0,
  "raining": false,
  "condition": "Clear",
  "fireNearby": false,
  "windTowardsHome": false,
  "nearbyCount": 3,
  "closestFireDistanceMiles": 10.5,
  "riskIndex": 2,
  "calfireNearby": false,
  "calfireCount": 0,
  "calfireFires": [
    {
      "name": "Fire Name",
      "distanceMiles": 12.3,
      "acresBurned": 5000,
      "percentContained": 45,
      "state": "CA"
    }
  ],
  "scoreBreakdown": {
    "sensorScore": 0,
    "fireScore": 0,
    "weatherScore": 0,
    "windScore": 0
  },
  "generatedAt": "2026-04-06T..."
}
```

| Field | Type | Notes |
|-------|------|-------|
| `weatherTemperature` | Double | Fahrenheit |
| `sensorTemperature` | Double | Fahrenheit |
| `smoke` | Double | ppm |
| `flame` | Int | 0 = flame detected, non-zero = no flame |
| `humidity` | Double | Percentage |
| `wind` | Double | m/s |
| `windDirection` | Double | Degrees |
| `raining` | Bool | |
| `condition` | String | Weather condition |
| `fireNearby` | Bool | FIRMS satellite fire nearby |
| `windTowardsHome` | Bool | |
| `nearbyCount` | Int | Nearby FIRMS detections |
| `closestFireDistanceMiles` | Double? | Nullable |
| `riskIndex` | Int | 0-10 composite score |
| `calfireNearby` | Bool | CAL FIRE incident nearby |
| `calfireCount` | Int | CAL FIRE incidents |
| `calfireFires` | Array | CAL FIRE incident details |
| `scoreBreakdown` | Object | Sub-scores (sensor max 4, fire max 4, weather -2 to +3, wind max 2) |
| `generatedAt` | String | ISO 8601 timestamp |

> **Note:** The iOS app (`FireStatus.swift`) only decodes a subset. The `calfireNearby`, `calfireCount`, `calfireFires`, `scoreBreakdown`, and `generatedAt` fields are used by the web dashboard but not currently decoded by the iOS app.

---

## GET /api/fires

Returns FIRMS satellite fire hotspot detections within a geographic bounding box.

**Required query params:**
- `minLat` — south boundary latitude
- `maxLat` — north boundary latitude
- `minLon` — west boundary longitude
- `maxLon` — east boundary longitude

**Optional query params:**
- `refreshFirms=1` — force refresh
- `t=<unix_timestamp>` — cache buster

**Response:**

```json
{
  "count": 8,
  "fires": [
    {
      "latitude": 33.61379,
      "longitude": -117.82021,
      "distanceMiles": 35.89,
      "brightness": 296.43,
      "confidence": "n",
      "satellite": "N20",
      "acquiredDate": "2026-04-05",
      "acquiredTime": "1017"
    }
  ],
  "firmsSource": "kv-cache",
  "generatedAt": "2026-04-06T22:48:18.027Z"
}
```

| Field | Type | Notes |
|-------|------|-------|
| `count` | Int | Number of fire points |
| `fires[].latitude` | Double | |
| `fires[].longitude` | Double | |
| `fires[].distanceMiles` | Double | Distance from home |
| `fires[].brightness` | Double | Brightness temperature (Kelvin) |
| `fires[].confidence` | String | "n"=nominal, "l"=low, "h"=high |
| `fires[].satellite` | String | e.g. "N20" = NOAA-20 |
| `fires[].acquiredDate` | String | YYYY-MM-DD |
| `fires[].acquiredTime` | String | HHMM UTC |
| `firmsSource` | String? | "kv-cache" or "live" |
| `generatedAt` | String? | ISO 8601 |

---

## POST /api/graphQuery

Executes a Cypher query against the Neo4j fire causation knowledge graph.

**Request:**

```json
{
  "query": "MATCH (f:Fire)-[r]->(n) RETURN f AS Fire, type(r) AS rel, labels(n)[0] AS targetLabel, n AS target, elementId(f) AS fId, elementId(n) AS nId"
}
```

**Response:**

```json
{
  "results": [
    {
      "columns": ["Fire", "rel", "targetLabel", "target", "fId", "nId"],
      "data": [
        {
          "row": [
            {
              "name": "Camp Fire",
              "fireId": "F_CA_2018_CAMP",
              "year": 2018,
              "county": "Butte",
              "acresBurned": 153336,
              "containmentStatus": "Contained",
              "directCause": "Electrical transmission lines near Pulga",
              "directCauseCategory": "Utility equipment / transmission line",
              "sourcePrimaryOrg": "CAL FIRE + CPUC",
              "sourcePrimaryDoc": "...",
              "sourceEvidenceNotes": "..."
            },
            "HAS_DOCUMENTED_SPREAD_MECHANISM",
            "SpreadMechanism",
            {
              "name": "Parcel-to-Parcel / Community Fire Spread",
              "mechanismId": "M_PARCEL_TO_PARCEL",
              "mechanismType": "Fire spread pathway",
              "notes": "...",
              "sourceOrg": "NIST",
              "sourceDoc": "..."
            },
            "4:d2f4378a-...:0",
            "4:d2f4378a-...:11"
          ],
          "meta": [
            { "id": 0, "elementId": "4:...:0", "type": "node", "deleted": false },
            null,
            null,
            { "id": 11, "elementId": "4:...:11", "type": "node", "deleted": false },
            null,
            null
          ]
        }
      ]
    }
  ],
  "generatedAt": "2026-04-06T..."
}
```

### Graph Data Model

**Node types:**

| Label | Key Properties |
|-------|---------------|
| `Fire` | `name`, `fireId`, `year`, `county`, `acresBurned`, `containmentStatus`, `directCause`, `directCauseCategory`, source fields |
| `ContributingFactor` | `name`, `factorId`, source fields |
| `SpreadMechanism` | `name`, `mechanismId`, `mechanismType`, `notes`, source fields |
| `PropertyVulnerability` | `name`, `category`, `notes` |

**Relationship types:**
- `CONTRIBUTED_BY` — Fire → ContributingFactor
- `HAS_DOCUMENTED_SPREAD_MECHANISM` — Fire → SpreadMechanism

### Pre-built Queries (used by fire-graph.html Quick Analysis)

1. Fires in the last year
2. Fires spread by flying embers
3. Fires contributed by winds
4. Fires linked to drought
5. Fires caused by arson/human activity
6. Fires that burned 100,000+ acres
7. Most common contributing factors
8. Contributing factors shared by 3+ fires
9. Fires from 2020-2025

---

## POST /api/nl2cypher

Converts natural-language questions to Cypher via Llama 3.2 (Cloudflare Workers AI), then executes. Access-code protected.

**Request:**

```json
{
  "code": "1234",
  "question": "Which fires were caused by power lines?"
}
```

| Field | Type | Notes |
|-------|------|-------|
| `code` | String | 4-digit access code (required) |
| `question` | String | Natural language question (max 300 chars) |

**Success response:** Same as `/api/graphQuery` plus:

```json
{
  "cypher": "MATCH (f:Fire)-[r]->(n) WHERE ...",
  "results": [ ... ],
  "generatedAt": "..."
}
```

**Auth error (401):**

```json
{ "error": "Invalid access code" }
```

---

## fire-graph.html Page Structure

Interactive D3.js knowledge graph visualization loaded in the iOS app via `FireGraphView.swift` (WKWebView).

**Key DOM elements:**
- `#fire-graph` — SVG graph container (600px height, 420px on mobile, dark bg `#1a1f2e`)
- `.filter-panel` — Collapsible panel with 3 tabs:
  - `#tab-queries` — Quick Analysis (9 pre-built Cypher queries)
  - `#tab-filters` — Dropdowns: year, cause category, min acres, factor, spread mechanism, fire picker
  - `#tab-nlquery` — Ask AI (code-gated, 5-minute session timeout)
- `.layout-row` — Layout toggle buttons (Force, Tree LR, Tree TB, Radial, Cluster)
- `.label-toggle-row` — Label visibility toggles per node type
- `.graph-legend` — Color legend (Fire=orange, Factor=green, Spread=blue, Vulnerability=teal)
- `.graph-summary` — Auto-generated text summary
- `.graph-tooltip` — Hover tooltip (max-width 280px)

**Mobile breakpoint (700px):**
- Graph height: 420px
- Filters stack vertically
- Quick query grid: single column

**iOS app injects** (via `FireGraphView.swift` WKUserScript):
- Viewport meta tag
- CSS: hides `#site-header`/`#site-footer`, tightens padding, stacks filters
- DOM: moves `.layout-row` and `.label-toggle-row` outside `#fire-graph` to prevent overlap
- Landscape: 2-column quick query grid, side-by-side filters
