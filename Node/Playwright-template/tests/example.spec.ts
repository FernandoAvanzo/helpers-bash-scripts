import { test, expect } from '../src/fixtures/test';

test('homepage has Playwright-template in the title', async ({ examplePage, page }) => {
  await examplePage.goto();
  await expect(page).toHaveTitle(/Playwright/);
});

test('can navigate to Getting Started', async ({ examplePage, page }) => {
  await examplePage.goto();
  await examplePage.openGettingStarted();
  await expect(page).toHaveURL(/\/docs\/intro/);
});
