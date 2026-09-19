# Blindspot -- full pipeline from committed raw data to published artefacts.
# A stranger should be able to clone and run `make all`.

PY := python3
PIPE := pipeline

.PHONY: all test extract curate segments inputs corpus model plan validate sensitivity backtest costing claims figures bundle pilot digest web clean

all: segments inputs corpus model plan validate sensitivity backtest costing claims bundle pilot digest

# segments, features, divisions, aggregates -- all from the published
# Roy & Sukumar field survey
segments:
	cd $(PIPE) && $(PY) build_published.py

inputs: segments
	cd $(PIPE) && $(PY) build_inputs.py   # scenario-B coverage only

# incidents, sourced coverage, divisions, published aggregates
corpus: segments
	cd $(PIPE) && $(PY) revise_corpus.py

model: inputs corpus
	cd $(PIPE) && $(PY) model.py

plan: model
	cd $(PIPE) && $(PY) optimise.py --coverage coverage_documented.csv --budget-km 20 --out plan_documented.json
	cd $(PIPE) && $(PY) optimise.py --coverage coverage_scenario_b.csv  --budget-km 20 --out plan.json

validate: model
	cd $(PIPE) && $(PY) validate.py

# Monte Carlo over every uncertain input. 400 draws x 3 budgets, ~40s.
sensitivity: plan
	cd $(PIPE) && $(PY) sensitivity.py

# Would a plan drawn up in 2010 have covered where the next deaths happened?
backtest: model
	cd $(PIPE) && $(PY) backtest.py

# What the plan costs, from the published Gajraj programme figure.
costing: plan sensitivity backtest
	cd $(PIPE) && $(PY) costing.py

# Verify every quotable claim against the build. Exits non-zero on drift --
# run this before recording anything.
claims: costing validate sensitivity backtest
	cd $(PIPE) && $(PY) claims.py

# Every number worth quoting, read straight from out/. Check the script and
# the deck against this before recording anything.
figures: costing validate sensitivity backtest
	cd $(PIPE) && $(PY) figures.py

bundle: plan validate sensitivity backtest costing claims
	cd $(PIPE) && $(PY) build_web_bundle.py

test:
	$(PY) tests/test_pipeline.py

# Corpus growth loop. extract needs ANTHROPIC_API_KEY, or --stub to replay
# recorded fixture responses offline.
extract:
	cd $(PIPE) && $(PY) extract.py --stub

curate:
	cd $(PIPE) && $(PY) curate.py

curate-apply:
	cd $(PIPE) && $(PY) curate.py --apply

pilot: bundle
	cd $(PIPE) && $(PY) build_pilot_bundle.py

# Nightly per-division digest. Writes the exact message bodies to
# out/digests/ so the demo shows real composed output, not a mock.
# `--channel whatsapp` needs WHATSAPP_TOKEN and WHATSAPP_PHONE_ID and has
# never been run against the live API.
digest: bundle
	cd $(PIPE) && $(PY) digest.py --channel files

# Inline each bundle into its template. Self-contained output, no fetch at
# runtime -- the demo has to work with the network off.
web: bundle pilot
	$(PY) -c "import pathlib; \
	t=pathlib.Path('web/template.html').read_text(); \
	b=pathlib.Path('out/web_bundle.json').read_text(); \
	pathlib.Path('out/blindspot-dashboard.html').write_text(t.replace('__BUNDLE__',b))"
	$(PY) -c "import pathlib; \
	t=pathlib.Path('web/pilot_template.html').read_text(); \
	b=pathlib.Path('out/pilot_bundle.json').read_text(); \
	pathlib.Path('out/blindspot-cab-advisory.html').write_text(t.replace('__PILOT__',b))"
	@ls -la out/*.html
	@# Parsing is not running. The dashboard once shipped calling a
	@# function an edit had destroyed and node --check passed throughout.
	@node tests/smoke_dashboard.js out/blindspot-dashboard.html \
		claim evidence plan-body rank-body rank-head detail foot caveat-body plan-total
	@node tests/smoke_dashboard.js out/blindspot-cab-advisory.html \
		next rows tally note rules

clean:
	rm -f out/*.json out/*.html
