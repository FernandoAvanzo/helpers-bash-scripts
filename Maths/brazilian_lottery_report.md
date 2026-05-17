# Deep Research Report on How the Brazilian Lottery Works and How to Build a Mega-Sena Research Bot

## How the Brazilian lottery system and Mega-Sena work

Brazil’s federal lottery products are operated under the CAIXA lottery system, and the official lottery rules page lists current CAIXA modalities such as Mega-Sena, Lotofácil, Quina, Lotomania, Dia de Sorte, Dupla Sena, Timemania, Super Sete, +Milionária, Loteca, and Loteria Federal. Mega-Sena is the flagship numeric lottery and is currently drawn three times per week, on Tuesdays, Thursdays, and Saturdays, starting at 21:00 Brasília time. CAIXA says the draws are held at the Espaço da Sorte in São Paulo, are live-streamed, and are validated by two volunteer public auditors. citeturn5view0turn4view0

For Mega-Sena specifically, the player chooses from 6 to 20 numbers out of 60. The minimum ticket is a 6-number bet costing R$ 6,00. CAIXA also offers “Surpresinha” so the system picks the numbers, “Teimosinha” so the same ticket is replayed across multiple contests, and “Bolão” group betting with rules on minimum pool values, quota sizes, and maximum participant counts. citeturn4view0turn8view1

The draw process is physically simple and important for modeling. CAIXA’s official rules state that Mega-Sena uses one globe loaded with balls numbered 01 to 60, and that numbers do not repeat within the same contest. The rules page also states that a ball only counts when it is fully ejected while the globe is operating and loaded with all required balls, and that interventions are supervised together with public auditors. That is the key reason the closest “official” mathematical model is a fair sample without replacement from 60 labeled balls. citeturn5view0

Mega-Sena’s prize pool is not just an ad hoc jackpot. CAIXA says the gross prize corresponds to 43.79% of the amount wagered. Of that gross prize amount, 40% goes to the 6-hit tier, 13% to the 5-hit tier, 15% to the 4-hit tier, 22% is accumulated for final-0-or-5 contests, and 10% is accumulated for Mega da Virada. CAIXA also states that prizes unclaimed after 90 days are transferred to the national treasury for FIES, and the Mega-Sena page lists the social-repass percentages funded by the game. citeturn8view1turn10view0

## The probabilistic model that is closest to the official process

The exact official-style probabilistic model for a single Mega-Sena contest is:

\[
\Omega = \{A \subset \{1,\dots,60\}:\ |A|=6\}
\]

with

\[
\Pr(A)=\frac{1}{\binom{60}{6}}
\]

for every unordered 6-number combination \(A\). Since \(\binom{60}{6}=50{,}063{,}860\), the jackpot probability for a simple 6-number ticket is exactly \(1/50{,}063{,}860\), which matches CAIXA’s official odds table. In plain language, the closest official model is a **uniform random combination of 6 distinct numbers chosen from 60 without replacement**. citeturn4view0turn8view1

If you want the closest statistical representation of one draw in indicator-vector form, define \(X_i \in \{0,1\}\) for numbers \(i=1,\dots,60\), where \(X_i=1\) if number \(i\) appeared. Then \(\sum_i X_i=6\) always, each marginal probability is \(\Pr(X_i=1)=6/60=0.1\), and the indicators are negatively dependent inside a draw because numbers are sampled without replacement. The mathematically closest named family here is the **multivariate hypergeometric / simple random sample without replacement** model. Over repeated contests, the closest official statistical assumption is that these draws are **independent and identically distributed across contests** if the physical process is fair and stable. That is much closer to CAIXA’s rules than any ARIMA model, Markov chain, “hot/cold” heuristic, or deep-learning sequence predictor. citeturn5view0turn4view0

For larger tickets, the correct combinatorial formulas are straightforward. If a player marks \(m\) numbers, then:

\[
\Pr(\text{Sena})=\frac{\binom{m}{6}}{\binom{60}{6}}
\]

\[
\Pr(\text{Quina})=\frac{\binom{m}{5}\binom{60-m}{1}}{\binom{60}{6}}
\]

\[
\Pr(\text{Quadra})=\frac{\binom{m}{4}\binom{60-m}{2}}{\binom{60}{6}}
\]

These formulas reproduce CAIXA’s published odds table for 6 to 20 selected numbers. So the official price/probability sheet is already a consistency check that the game is modeled as combinations without replacement, not as weighted or learned sequences. citeturn8view1

The most defensible “near-official but slightly more flexible” research model is a **weighted without-replacement urn** model. In that extension, each ball \(i\) has weight \(w_i\), and under the fair-null hypothesis all weights equal 1. If you ever wanted to test for slight mechanical bias, the right modeling family is not an LSTM or a generic classifier; it is a **biased urn / noncentral hypergeometric / Plackett-Luce top-k style model** with strong shrinkage of weights toward \(w_i=1\). This is the only principled way to depart from the official random-urn interpretation while still respecting the physical draw mechanism. That statement is an inference from the official draw rules. citeturn5view0turn4view0

The practical implication is blunt: if CAIXA’s process is fair, **no AI model can materially increase the true chance of hitting the exact next 6-number result**. A decade of Mega-Sena provides only roughly 1,500 to 1,600 contests at three draws per week, while the state space has 50,063,860 equally likely simple combinations. That is far too little information for stable predictive learning over exact outcomes. What a bot can do well is backtesting, anomaly detection, portfolio construction, and human-bias avoidance. citeturn4view0turn5view0

## How to get the last decade of results and winners

The best official source is the Mega-Sena contest page on CAIXA’s portal. The page exposes a standardized result block with contest number, draw date, next-prize estimate, amount collected, prize-tier summaries, and a winner-detail area. It also exposes contest navigation with “search by contest,” “previous,” and “next,” which strongly suggests that building a deterministic contest-by-contest crawler is feasible. citeturn4view0turn8view1

The same page is useful not only for winning numbers but also for winner-result data. CAIXA’s result layout includes a “Detalhamento” area with municipality, state, and number of winning bets for the top tier, and the page explicitly says “Clique e conheça os detalhes das apostas ganhadoras.” For a “last decade of winners” dataset, that means your wrapper should extract at least the official contest ID, draw date, winning numbers, payout tiers, and the city/UF breakdown of winning Sena tickets where CAIXA publishes it. citeturn4view0

A second official source is the same Mega-Sena page’s **Download de resultados** section. In the page text CAIXA clearly exposes that such a section exists, although the exact downloadable file link did not render in the page text I could inspect. The safest interpretation is that CAIXA offers or is prepared to offer a download-based results flow, but you should verify the concrete file URL manually before automating against it. I did **not** find a publicly documented official JSON API in the pages reviewed, so my high-confidence recommendation is to treat CAIXA as an **official HTML/download source**, not as a formally documented API provider. That is an evidence-based inference rather than a documented CAIXA statement. citeturn10view0turn11view0

The official draw-rules page also says that CAIXA live-streams these draws and keeps draw videos on the official YouTube channel. That makes YouTube a useful verification source for spot-auditing suspicious contests or validating ingestion failures, but it should not be your primary historical dataset because the portal page is more structured and easier to normalize. citeturn5view0

A robust result wrapper should therefore look like this:

```yaml
ContestResult:
  modality: "megasena"
  contest_id: int
  draw_date: date
  draw_location: string
  draw_city_uf: string
  numbers: [int, int, int, int, int, int]
  accumulated: bool
  next_draw_date: date | null
  next_prize_estimate_brl: decimal | null
  amount_collected_brl: decimal | null
  amount_accumulated_0_5_brl: decimal | null
  amount_accumulated_special_brl: decimal | null
  notes: string | null
  prize_tiers:
    - tier: "sena" | "quina" | "quadra"
      winners: int
      prize_brl: decimal | null
  winner_regions:
    - city: string
      state: string
      winners: int
      tier: "sena"
  source_url: string
  source_hash: string
  ingested_at: timestamp
```

The ingestion methods should be just as explicit:

```python
fetch_latest() -> ContestResult
fetch_contest(contest_id: int) -> ContestResult
fetch_range(start_contest: int, end_contest: int) -> list[ContestResult]
fetch_since(date: date) -> list[ContestResult]
validate(result: ContestResult) -> ValidationReport
upsert(result: ContestResult) -> None
```

For scraping, the recommended order is:

1. Use the official contest page as the source of truth.
2. Seed with the latest contest.
3. Walk backward by contest ID until you cross the ten-year cutoff.
4. Parse and normalize numbers, payouts, and winner-detail blocks.
5. Save raw HTML alongside normalized JSON for reproducibility.
6. Run validation rules such as “exactly 6 distinct numbers,” “three prize tiers present,” and “amount-collected field parsed or null with reason.”

Because CAIXA’s official web experience is page-first rather than API-first, the most sustainable long-term design is to create **your own internal stable API** around your scraper output. In other words, the “API” your bot should truly depend on is the one you own.

## What a realistic Mega-Sena bot can and cannot do

The single most important product decision is this: the bot should not be presented as a system that can genuinely “beat” a fair Mega-Sena draw. Under the official random-without-replacement model, every simple 6-number ticket has the same jackpot probability. A credible bot can still be useful, but its value proposition should be reframed as **research, monitoring, and ticket portfolio construction**, not magical next-number prediction. citeturn5view0turn4view0

The strongest mathematical approach is a two-layer system. The first layer is a **fair-null model**:

\[
P_0(A)=\frac{1}{\binom{60}{6}}
\]

for any 6-set \(A\). The second layer is a **bias-estimation model** that only activates if historical evidence suggests persistent deviations from the null. One clean formulation is a weighted-without-replacement model:

\[
P_\theta(A) \propto \prod_{i \in A} w_i
\]

subject to \(w_i>0\) and strong regularization toward \(w_i=1\). The weights can be static or time-varying, for example \(w_{i,t}=\exp(\alpha_i + z_{i,t})\), where \(z_{i,t}\) is a small state-space term. In practice, you should impose a prior so strong that unless there is statistically meaningful evidence, the posterior collapses back toward the fair-null urn. That makes the system scientifically honest. citeturn5view0turn4view0

The strongest AI approach is not a large language model and not a deep sequence model on raw draws. With only about a decade of data, a compact **candidate-generator plus scorer** design is more defensible. First generate candidate 6-number tickets under combinatorial constraints. Then score them with a small supervised or Bayesian model that ingests features such as per-number recency gap, trailing frequency, pair frequency, parity balance, low/high split, decade-bucket entropy, consecutive-number count, ticket sum, spread, and overlap with previously recommended tickets. Finally sample or optimize a portfolio of tickets under diversity constraints. The key point is that the AI’s main job is ranking and portfolio design, not discovering nonexistent deterministic next-draw rules. This is an inference from the official odds and the limited volume of historical draws. citeturn4view0turn5view0

A particularly useful objective is not pure hit probability, because under the fair-null model that is equal for every simple ticket. The more realistic utility function is:

\[
U(x) = \alpha \log P_\theta(x) - \beta \, \text{PopularityPenalty}(x) + \gamma \, \text{DiversityBonus}(x)
\]

Here, \(P_\theta(x)\) comes from the bias-estimation urn model, \(\text{PopularityPenalty}(x)\) estimates how likely humans are to choose the same ticket, and \(\text{DiversityBonus}(x)\) prevents your own recommended ticket set from clustering. This is where a bot can create practical value: not by changing your raw chance of a six-hit, but by reducing the probability of splitting a prize if you ever do win.

The popularity penalty should be based on human-choice heuristics, not on official draw mechanics. CAIXA gives players “Surpresinha,” but many players still choose numbers manually, which makes some patterns unattractive if your goal is “less shared” wins: all-low tickets, birthdays-only ranges, straight sequences, visible diagonals from printed cards, repeated endings, or aesthetically pleasing clusters. Your internal Google Drive spreadsheets already show a version of this philosophy with parity balance, low/high balance, decade-bucket spread, and entropy-like scoring, which is directionally useful as a **sharing-risk minimizer**, not as a true jackpot predictor.

The engine specification should therefore separate modes very clearly:

```yaml
GuessNumberEngine:
  modes:
    - name: "fair_random"
      purpose: "uniform benchmark and fallback"
    - name: "bias_research"
      purpose: "estimate tiny deviations from iid fair draws"
    - name: "low_sharing_portfolio"
      purpose: "construct diversified tickets with low popularity risk"
  inputs:
    historical_results
    current_contest_metadata
    feature_store
    policy_config
  outputs:
    ranked_tickets
    ticket_scores
    explanation_report
    backtest_metrics
    confidence_flags
  hard_rules:
    - "exactly 6 unique numbers"
    - "numbers between 1 and 60"
    - "never claim improved jackpot odds under fair-null"
```

The evaluation stack also needs to be honest. Exact-jackpot backtesting is nearly useless because it almost never happens. Better evaluation metrics are per-number calibration, log loss on number-selection probabilities, coverage/diversity of ticket sets, and outcome-distribution benchmarks such as the expected rates of 0, 1, 2, 3, 4, 5, and 6 matches. Any “AI” model that fails to beat the fair-null benchmark on proper scoring rules should automatically revert to the fair-random or low-sharing mode.

## Software architecture and repository template

The cleanest architecture is an event-driven monorepo with explicit boundaries between ingestion, normalization, features, modeling, optimization, serving, and infrastructure. For this kind of bot, the most maintainable design is a thin production system around a small scientific core rather than a giant microservice mesh.

A good logical architecture is:

```text
official CAIXA pages
        |
        v
collector / scraper
        |
        v
raw store  ---> validation ---> normalized store
                                  |
                                  v
                             feature builder
                                  |
                                  v
                       model trainer + backtester
                                  |
                                  v
                    ticket optimizer / portfolio engine
                                  |
                                  v
                        API service + scheduler + UI
                                  |
                                  v
                        logs, metrics, alerts, reports
```

The repository template should be opinionated, compact, and automation-friendly:

```text
mega-sena-bot/
  README.md
  LICENSE
  .gitignore
  pyproject.toml
  Makefile
  docker-compose.yml
  .env.example

  docs/
    architecture.md
    threat-model.md
    adr/
    runbooks/

  apps/
    api/
      main.py
      routes/
      schemas/
      services/
    worker/
      jobs/
      tasks/

  pkg/
    collector/
      caixa_client.py
      parsers.py
      validators.py
      models.py
    storage/
      repositories.py
      object_store.py
      metadata_store.py
    features/
      build_features.py
      popularity_features.py
      quality_checks.py
    modeling/
      fair_null.py
      weighted_urn.py
      scoring.py
      backtest.py
    optimizer/
      portfolio.py
      constraints.py
    explain/
      reports.py
      plots.py

  infra/
    terraform/
      aws/
      gcp/
    github/
      workflows/

  tests/
    unit/
    integration/
    fixtures/

  data_contracts/
    contest_result.schema.json
    ticket_recommendation.schema.json

  notebooks/
    exploratory/
    backtests/
```

For CI/CD, GitHub Actions is the most natural fit because it is natively built for repository workflows and CI/CD. GitHub’s documentation also explicitly supports OpenID Connect so workflows can exchange short-lived cloud tokens instead of storing long-lived secrets. That is the right deployment security model for both AWS and GCP. citeturn32view0turn33view0turn33view2

The minimum viable workflow set should be:

- `ci.yml` for lint, type checks, tests, and schema validation.
- `build.yml` for container builds and artifact publication.
- `deploy-aws.yml` using GitHub Actions OIDC to deploy infrastructure and application changes to AWS.
- `deploy-gcp.yml` using GitHub Actions OIDC to deploy to GCP.
- `retrain.yml` for scheduled backtests and model refreshes.
- `data-backfill.yml` for one-time historical imports.

## AWS and GCP deployment guides with cost outlook

For AWS, the leanest production design is **API Gateway + Lambda + EventBridge Scheduler + object storage + logs/metrics**. Lambda is a serverless compute service, and EventBridge is a serverless event-routing and scheduling service; those two fit this workload well because Mega-Sena draws happen only three times per week and the active compute footprint is small. API Gateway’s HTTP API pricing is request-based, and EventBridge Scheduler has a very large free tier for invocations. citeturn27view0turn27view1turn30view5turn30view3

A practical AWS guide looks like this:

1. Create an API Lambda for `GET /latest`, `GET /contest/{id}`, and `POST /recommendations`.
2. Create a worker Lambda for `ingest_latest`, `retrain_model`, and `publish_report`.
3. Use EventBridge Scheduler to run ingestion after each official draw window and to schedule weekly retraining. EventBridge Scheduler offers 14,000,000 invocations per month free. citeturn30view3
4. Store raw contest pages and model artifacts in cheap object storage; keep normalized metadata in a small key-value or document store if you need low-latency querying.
5. Put the public HTTP interface behind API Gateway HTTP APIs.
6. Use CloudWatch for logs, custom metrics, and alarms.
7. Use GitHub Actions with OIDC to assume an AWS role and deploy without long-lived AWS secrets. citeturn33view0turn33view2

For GCP, the leanest production design is **Cloud Run service + Cloud Run job + Cloud Scheduler + Firestore + logs/metrics**. Cloud Run is a fully managed application platform that runs code or containers, and it supports both request-serving services and job-style executions. Firestore is a fully managed serverless document database with strong free-tier allowances that are more than enough for a tiny lottery-history metadata footprint. Cloud Scheduler can trigger scheduled runs, and GitHub Actions OIDC can be used instead of static service-account keys. citeturn28view0turn28view2turn28view3turn21view0turn33view0turn33view2

A practical GCP guide looks like this:

1. Deploy the read/write API as a Cloud Run service.
2. Deploy ingestion and retraining as Cloud Run jobs.
3. Trigger both with Cloud Scheduler.
4. Store normalized results, recommendations, and reports in Firestore; store larger raw artifacts in object storage if desired.
5. Use Google Cloud Logging and Monitoring for observability.
6. Use GitHub Actions OIDC to mint short-lived GCP credentials for deployment. citeturn28view0turn21view0turn33view0turn33view2

The cost outlook is favorable if you keep the design serverless and CPU-only. On AWS, Lambda includes 1 million free requests and 400,000 GB-seconds per month, API Gateway gives new customers 1 million HTTP API calls per month for 12 months, and EventBridge Scheduler includes 14 million free invocations per month. For a low-traffic personal research bot, that usually translates into roughly **$0 to $5 per month** in steady state, excluding extras like custom domains, heavy logs, or managed SQL. At moderate usage, the official Lambda example rate of $0.20 per million requests plus roughly $0.0000166667 per GB-second, together with HTTP API pricing around $1.00 per million in the first tier, implies that a lightweight 10-million-request/month setup can still land around **$40 to $55 per month** before any premium add-ons. citeturn30view1turn30view2turn30view5turn30view6turn30view3turn30view0

On GCP, Cloud Run request-based services include a free tier of 2 million requests, 180,000 vCPU-seconds, and 360,000 GiB-seconds per month; Cloud Scheduler gives 3 jobs per month free; and Firestore’s free tier includes 1 GiB stored, 50,000 reads per day, and 20,000 writes per day. That means a low-traffic research bot can also be essentially free or only a few dollars per month. For moderate traffic, Cloud Run’s published request and compute rates support a rough estimate of **about $20 to $35 per month** for a lightweight service before heavier logging, networking, or premium data layers. citeturn31view2turn31view3turn31view0turn31view1turn19view5turn21view0turn21view1

The cost breakpoint is architectural, not algorithmic. If you add an always-on managed SQL instance, heavy log retention, or GPU-based model training, costs rise materially. Given the tiny volume of lottery data, none of those premium choices are necessary at the beginning.

## Roadmap and action plan

A realistic roadmap has seven phases.

First, establish the data source contract. Build the official CAIXA wrapper, define the JSON schema, and backfill ten years of contests. The goal is a reproducible, validated dataset containing contest IDs, dates, six numbers, prize tiers, and winner-region detail where available. citeturn4view0

Second, build the baseline math engine. Implement the fair-null model, exact combinatorial probability functions, and the benchmark ticket sampler. This is the foundation that every more complex model must beat or at least justify.

Third, build the research model. Add the weighted-urn bias model, strong regularization toward fairness, and rolling-window backtests with calibration plots and proper scoring rules. Do not deploy ticket recommendations from this model until it proves stable and not just noise-fitting.

Fourth, build the practical recommendation layer. Create a popularity-penalty model, a diversity-aware portfolio optimizer, and an explanation report that says why a given ticket set was recommended. This is the part most likely to provide real user value.

Fifth, productize it. Add a clean REST API, a minimal dashboard, daily and post-draw scheduling, and exportable reports. This is also where you define abuse limits, audit logging, and response caching.

Sixth, automate deployment. Add GitHub Actions pipelines, OIDC trust to AWS and GCP, infrastructure as code, environment separation, and one-click rollback. GitHub’s own documentation explicitly recommends OIDC-based short-lived cloud tokens instead of long-lived repository secrets. citeturn33view0turn33view2

Seventh, define success and stop conditions. The bot should only continue in “prediction” mode if it consistently beats the fair-null benchmark on honest backtests. Otherwise, formally downgrade it to a low-sharing portfolio bot and anomaly monitor. That is not failure; it is the statistically honest product outcome.

A concrete execution plan could look like this:

1. Week one: data contract, wrapper, manual validation on 20 contests.
2. Week two: ten-year backfill and regression tests.
3. Week three: fair-null model, odds functions, benchmark reports.
4. Week four: bias-research model plus backtesting framework.
5. Week five: popularity scorer and portfolio optimizer.
6. Week six: API, scheduler, and observability.
7. Week seven: AWS and GCP deployment paths.
8. Week eight: documentation, runbooks, and launch decision.

## Open questions and limitations

The biggest unresolved point from the official sources I reviewed is this: CAIXA clearly exposes an official Mega-Sena results page and a “Download de resultados” section, but I did **not** identify a publicly documented official JSON API endpoint in those pages. For production use, I would therefore treat the official CAIXA site as an HTML/download source and wrap it with your own stable internal API. citeturn10view0turn11view0

The selected GitHub repository and Google Drive connectors were useful as context, especially because your Drive contains Mega-Sena analysis spreadsheets, but they are not authoritative enough to replace the official CAIXA rules and result pages for this report.

The most important product limitation remains mathematical, not infrastructural: if the official draw process is fair, the bot cannot legitimately improve the true exact-match probability over any other specific ticket. What it can do credibly is formalize probabilities, monitor randomness, automate historical ingestion, and generate diversified low-sharing portfolios under transparent assumptions. citeturn5view0turn4view0

## References
 - [realistic utility function](https://www.notion.so/fernando-avanzo/realistic-utility-function-362b3def3e7c81e08c8de6fb540f1765?source=copy_link)
 - [Official-style probabilistic model for a single Mega-Sena contest](https://www.notion.so/fernando-avanzo/Official-style-probabilistic-model-for-a-single-Mega-Sena-contest-362b3def3e7c81bc9b4ee8626b46acb8?source=copy_link)
 - [Correct combinatorial formulas are straightforward](https://www.notion.so/fernando-avanzo/Correct-combinatorial-formulas-are-straightforward-362b3def3e7c81c9a212cef6e0a807c3?source=copy_link)
 - [fair-null model](https://www.notion.so/fernando-avanzo/fair-null-model-363b3def3e7c81df9fdff3d8de4ee4bc?source=copy_link)
 - [One clean formulation is a weighted-without-replacement model](https://www.notion.so/fernando-avanzo/One-clean-formulation-is-a-weighted-without-replacement-model-363b3def3e7c813a8885dd7021069b7a?source=copy_link)
