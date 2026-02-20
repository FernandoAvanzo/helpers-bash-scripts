import { test as base, expect } from '@playwright/test';
import { ExamplePage } from '../pages/ExamplePage';

type Fixtures = {
  examplePage: ExamplePage;
};

export const test = base.extend<Fixtures>({
  examplePage: async ({ page }, use) => {
    await use(new ExamplePage(page));
  },
});

export { expect };
