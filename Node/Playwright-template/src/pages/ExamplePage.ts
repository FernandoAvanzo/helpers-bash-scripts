import type { Page, Locator } from '@playwright/test';

export class ExamplePage {
  readonly page: Page;
  readonly getStartedLink: Locator;

  constructor(page: Page) {
    this.page = page;
    this.getStartedLink = page.getByRole('link', { name: /get started/i });
  }

  async goto() {
    await this.page.goto('/');
  }

  async openGettingStarted() {
    await this.getStartedLink.click();
  }
}
