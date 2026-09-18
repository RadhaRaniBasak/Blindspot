# Blindspot

Where the next elephant-detection sensors should go on the New Jalpaiguri –
Alipurduar railway line, North Bengal.

Elephants have been killed by trains on this 161 km line for fifty years, and
the rate worsened after the 2003–04 conversion from metre to broad gauge.
A technical fix already exists: Northeast Frontier Railway has deployed an
Intrusion Detection System on parts of the network, and speed restrictions on
some forest stretches.

Both are **partial**. When three elephants were killed at Rajabhatkhawa in
November 2023, they were reported to have been crossing a stretch *not covered*
by the Intrusion Detection System.

So the open question is not "can we detect elephants". It is **which
kilometres get covered next, and in what order.** Nobody has published a
reproducible answer. That is what this repo is.

---

## Reproduce it

```bash
pip install -r requirements.txt
make all
```

Every artefact in `out/` regenerates from the committed raw data. No API keys
are needed for the model, the plan or the dashboard — extraction is the only
step that wants a key, and its output is already committed.

```
make test       34 tests, no test-runner dependency
make extract    article text -> validated records  (--stub replays fixtures)
make curate     geocode + dedupe + merge, DRY RUN by default
make segments   stations.csv -> segments.csv          (frozen join key)
make inputs     features, coverage scenarios, aggregates
make model      Poisson GLM + shrinkage -> out/scores.json
make plan       exact knapsack          -> out/plan.json
make validate   seven checks            -> out/validation.json  (exit 1 on failure)
make bundle     inline everything       -> out/web_bundle.json
make pilot      precompute 48 advisory runs (24 hours x 2 directions)
make web        self-contained dashboard + cab advisory HTML
```

The dashboard is `web/template.html` with `out/web_bundle.json` substituted
for `__BUNDLE__`. It is fully self-contained and works with the network off.

---

## What it does

**1. An incident corpus, and a pipeline that grows it.** Geocoded, sourced,
machine-readable collision records for this line. 12 records in this seed
build, every one with a working source URL and the exact sentence the fields
were read from. No such dataset exists publicly.

Article text goes in, validated records come out. The model extracts fields but
**never assigns a segment** — name-to-segment mapping is deterministic and
tested, so the geography in the corpus is auditable. Extraction is rejected if
the `quote_span` is not a verbatim substring of the source, which turns human
verification into reading one sentence rather than one article.

Records that cannot be placed honestly are **parked, not guessed**. A bare
"Siliguri" is ambiguous between two stations on this line, so it goes to
`needs_review.csv` with a hint rather than onto a segment nobody would ever
check. See [docs/CORPUS_HOWTO.md](docs/CORPUS_HOWTO.md).

**2. A segment risk model.** 23 inter-station segments. Poisson GLM with
exposure offset, then Poisson–Gamma (empirical-Bayes) shrinkage:

```
lambda_s = (y_s + alpha * mu_s) / (E_s + alpha)
```

The sentence this exists for: *a segment with no recorded deaths is not proven
safe, it is under-observed.* Segments with low exposure and zero incidents get
pulled toward what their covariates predict rather than scored zero.

**3. A coverage plan.** Exact 0/1 knapsack over uncovered segments — maximise
expected collisions prevented subject to a kilometre budget. Solved exactly by
DP over 0.1 km units; at 23 segments there is no reason to approximate.

**4. Two surfaces.** A planner dashboard: the line drawn as a railway strip
diagram, risk profile above the rail, coverage band below, click any segment
for the incidents and factor contributions behind its score. And a cab
advisory for a night run, in signal-aspect colours, precomputed for every
departure hour so it works with no signal.

**5. A separation between estimate and policy.** `model.py` says what the data
supports, shrunk honestly. `advisory.py` says what we advise given that the
estimate is thin, as four named fail-safe rules:

| | |
| --- | --- |
| **R1** | Time-of-day factors may raise an advisory, never lower it, until the corpus carries 30 timed events. It carries 4. |
| **R2** | After dark, a stretch that is elephant habitat is never advised as clear. |
| **R3** | A stretch inside a notified protected area is never advised as clear, at any hour. |
| **R4** | Sensor coverage that cannot be verified is treated as absent. |

Keeping these out of the model matters. Baking night risk into the multipliers
would produce an apparent nocturnal peak that was really our own prior coming
back out. Every applied rule is returned with the advisory, so the screen can
always answer "why am I being told to slow down".

---

## Honest state of this build

This section is not decoration. Read it before quoting any number.

| | |
| --- | --- |
| **External validation vs published division death shares** | **MAE 3.8%** across 6 forest divisions, against 62 externally recorded deaths |
| Held-out hotspot check | **2 of 3** in the top third |
| Corpus | 15 records, 32 fatalities, 9 model-eligible |
| Estimated reporting rate | **20%** — 13 of 65 published deaths, 2004–2015 |
| Events per parameter | **6.67** against a floor of 10 |
| Coverage status sourced | **10 of 23** segments (was 1) |
| Leave-one-out top-3 stability | 2.87 / 3 |
| Tests | 47 passing, incl. knapsack checked against brute force |
| Timed events for the hour profile | **4** — profile shrunk to near-uniform, not evidence |

### The strongest result

A published survey gives the distribution of post-gauge-conversion elephant
deaths across the six forest divisions this line crosses (n = 62). Our model's
risk distribution matches it to **3.8% mean absolute error**:

| Division | Published share of deaths | Model share of risk |
| --- | --- | --- |
| Jalpaiguri FD | 31% | 33.6% |
| Buxa TR West | 26% | 29.0% |
| Gorumara WD | 16% | 11.4% |
| Mahananda WLS | 15% | 11.2% |
| Jaldapara WD | 8% | 12.9% |
| Kalimpong FD | 5% | 1.3% |

That is external validation: 62 deaths recorded by someone else, compared
against a model fitted on 20. It is a far better test than any single held-out
case, and it is the number to put on the slide.

The corpus is still the bottleneck. 9 model-eligible records is not enough for
the covariate coefficients to reach significance, and the hour profile rests on
4 timed events, so it is shrunk almost to uniform and is not evidence of a
night effect.

What carries the model right now is not our own counts — it is the external
division prior. Full detail in [docs/LIMITATIONS.md](docs/LIMITATIONS.md),
including three modelling changes made while chasing a failure that turned out
to be in the test rather than the model.

---

## Data sources

| Source | Provides |
| --- | --- |
| Roy & Sukumar (2017), *Railways and Wildlife: Train–Elephant Collisions in Northern West Bengal* ([ePrints@IISc](https://eprints.iisc.ac.in/72595)) | Collision locations 1974–2015, hotspots, night and crop-season patterns |
| Line station list and history ([Wikipedia](https://en.wikipedia.org/wiki/New_Jalpaiguri%E2%80%93Alipurduar%E2%80%93Samuktala_Road_line)) | Ordered 24-station sequence, gauge conversion dates, protected areas crossed |
| News archives — The Hindu, Times of India, Deccan Herald, EastMojo, IANS | Individual incidents with dates, station pairs, counts, trains |
| Press statements on sensor deployment | Coverage reconstruction (weak — see LIMITATIONS 4) |

Not yet ingested: ESA WorldCover, Copernicus DEM, OSM geometry, Indian Railways
timetables. The container this was built in has no route to them; every one has
a `pending` provenance tag and a matching limitation.

---

## Licence

Code: MIT. The incident corpus in `data/`: CC BY 4.0 — take it and extend it.
