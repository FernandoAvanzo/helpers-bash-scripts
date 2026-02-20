# Playwright Test Template (TypeScript)

This is a small-but-solid Playwright Test starter with:
- TypeScript + Playwright Test
- Page Object Model (POM) example under `src/pages/`
- Custom fixtures under `src/fixtures/`
- GitHub Actions CI workflow

## Quick start

1) Install deps

```bash
npm install
```

2) Install browsers (first time)

```bash
npx playwright install
```

3) Run tests

```bash
npm test
```

## Useful commands

- UI mode: `npm run test:ui`
- Headed mode: `npm run test:headed`
- Debug mode: `npm run test:debug`
- Open HTML report: `npm run report`

## Configure base URL

Copy `.env.example` to `.env` and set your target:

```bash
cp .env.example .env
# edit BASE_URL=...
```

`BASE_URL` defaults to `https://playwright.dev` if unset.
