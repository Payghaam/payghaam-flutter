# Docs follow-up

Product docs live in [Payghaam/payghaam-mono](https://github.com/Payghaam/payghaam-mono). This repo is **public**, so mono’s scheduled job can `git clone` it with no PAT.

- PRs here get a bot comment pointing at `/docs/sdk/flutter/**`.
- Optional: org/repo secret `DOCS_DISPATCH_TOKEN` (fine-grained PAT, **Actions: write** on payghaam-mono) pings the watcher on push to `main`. Cron still runs without it.

See mono [`.github/DOCS-FOLLOW-UP.md`](https://github.com/Payghaam/payghaam-mono/blob/main/.github/DOCS-FOLLOW-UP.md).
