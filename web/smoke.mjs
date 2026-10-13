import assert from 'node:assert/strict';
// Set PLAYWRIGHT_MODULE to reuse an existing installation, or install playwright locally.
const { chromium } = await import(process.env.PLAYWRIGHT_MODULE || 'playwright');
const browser = await chromium.launch({ headless: true, executablePath: process.env.CHROMIUM_PATH });
let deadline;
try {
  const page = await browser.newPage({ viewport: { width: 1100, height: 800 }, deviceScaleFactor: 2 });
  const errors = [];
  page.on('pageerror', error => errors.push(error.message));
  page.on('console', message => { if (message.type() === 'error') errors.push(message.text()); });
  deadline = setTimeout(() => {
    console.error('Browser smoke timed out.', errors);
    browser.close();
  }, 30000);
  await page.goto(process.env.ITO_DEMO_URL || 'http://127.0.0.1:8080');
  await page.waitForFunction(() => document.documentElement.dataset.ready === 'true', null, { timeout: 15000 }).catch(async error => {
    console.error(await page.locator('body').innerText(), errors);
    throw error;
  });
  const text = () => page.evaluate(() => window.itoDemo.renderer.frame.cells.map(cell => cell.text).join(''));
  assert.match(await text(), /Ito, running on Canvas/);
  const initial = await page.evaluate(() => ({
    frame: window.itoDemo.renderer.frame,
    pixels: document.querySelector('canvas').width,
    css: document.querySelector('canvas').getBoundingClientRect().width,
  }));
  assert.equal(initial.pixels, Math.round(initial.css * 2));
  assert.equal(initial.frame.cells.find(cell => cell.text === '日').width, 2);
  assert.ok(initial.frame.cells.some(cell => cell.link === 'https://www.lua.org/'));

  await page.locator('canvas').focus();
  await page.keyboard.type('Hello Canvas');
  await page.keyboard.press('Enter');
  assert.match(await text(), /You wrote: Hello Canvas/);
  await page.locator('canvas').evaluate(canvas => {
    const data = new DataTransfer();
    data.setData('text/plain', ' ✓');
    canvas.dispatchEvent(new ClipboardEvent('paste', { clipboardData: data }));
  });
  await page.keyboard.press('Enter');
  assert.match(await text(), /You wrote: Hello Canvas ✓/);

  const click = await page.evaluate(() => {
    const renderer = window.itoDemo.renderer;
    const cell = renderer.frame.cells.find(cell => cell.text === 'C' && cell.col === 1 && cell.row > 5);
    const bounds = renderer.canvas.getBoundingClientRect();
    return { x: bounds.left + (cell.col + 0.5) * renderer.cellWidth, y: bounds.top + (cell.row + 0.5) * renderer.cellHeight };
  });
  await page.mouse.click(click.x, click.y);
  assert.match(await text(), /Clicks: 1/);
  const frames = await page.evaluate(() => new Promise(resolve => {
    let count = 0;
    const canvas = document.querySelector('canvas');
    const next = () => { if (++count === 3) { canvas.removeEventListener('ito:frame', next); resolve(count); } };
    canvas.addEventListener('ito:frame', next);
  }));
  assert.equal(frames, 3);
  await page.screenshot({ path: 'target/canvas-desktop.png' });

  await page.setViewportSize({ width: 390, height: 844 });
  await page.waitForFunction(width => window.itoDemo.renderer.frame.width < width, initial.frame.width);
  const narrow = await page.evaluate(() => window.itoDemo.renderer.frame);
  assert.ok(narrow.width > 20 && narrow.width < 40);
  assert.ok(narrow.cells.every(cell => cell.col + cell.width <= narrow.width));
  await page.screenshot({ path: 'target/canvas-mobile.png' });
  await page.evaluate(() => window.itoDemo.close());
  assert.deepEqual(errors, []);
  clearTimeout(deadline);
  console.log('Canvas smoke passed: Wasm load, HiDPI, wide text, links, keyboard, paste, click, animation, resize, cleanup.');
} finally {
  clearTimeout(deadline);
  await browser.close();
}
