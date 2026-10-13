import createIto from './ito-web.js';

const KEYS = {
  Enter: 'enter', Escape: 'esc', Backspace: 'backspace', Delete: 'delete',
  Tab: 'tab', ArrowLeft: 'left', ArrowRight: 'right', ArrowUp: 'up', ArrowDown: 'down',
  Home: 'home', End: 'end', PageUp: 'pageup', PageDown: 'pagedown', Insert: 'insert',
};

/** Paint complete Ito cell frames. Layout stays in Lua/Ratatui, in cell coordinates. */
export class CanvasRenderer {
  constructor(canvas, { fontSize = 16, fontFamily = 'ui-monospace, SFMono-Regular, Menlo, Consolas, monospace', foreground = '#dce4e1', background = '#111916' } = {}) {
    this.canvas = canvas;
    this.context = canvas.getContext('2d');
    if (!this.context) throw new Error('Canvas 2D is unavailable');
    Object.assign(this, { fontSize, fontFamily, foreground, background });
    this.context.font = `${fontSize}px ${fontFamily}`;
    this.cellWidth = this.context.measureText('M').width;
    this.cellHeight = Math.ceil(fontSize * 1.5);
    this.frame = null;
  }

  size() {
    const bounds = this.canvas.getBoundingClientRect();
    return {
      width: Math.max(1, Math.min(512, Math.floor(bounds.width / this.cellWidth))),
      height: Math.max(1, Math.min(256, Math.floor(bounds.height / this.cellHeight))),
    };
  }

  position(event) {
    const bounds = this.canvas.getBoundingClientRect();
    const size = this.frame ?? this.size();
    return {
      col: Math.max(0, Math.min(size.width - 1, Math.floor((event.clientX - bounds.left) / this.cellWidth))),
      row: Math.max(0, Math.min(size.height - 1, Math.floor((event.clientY - bounds.top) / this.cellHeight))),
    };
  }

  linkAt(event) {
    const { row, col } = this.position(event);
    return this.frame?.cells.find(cell => cell.row === row && col >= cell.col && col < cell.col + cell.width)?.link;
  }

  paint(frame = this.frame, now = performance.now()) {
    if (!frame) return;
    this.frame = frame;
    const ctx = this.context;
    const bounds = this.canvas.getBoundingClientRect();
    const ratio = window.devicePixelRatio || 1;
    const width = Math.round(bounds.width * ratio), height = Math.round(bounds.height * ratio);
    if (this.canvas.width !== width || this.canvas.height !== height) {
      this.canvas.width = width;
      this.canvas.height = height;
    }
    ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
    ctx.globalAlpha = 1;
    ctx.fillStyle = this.background;
    ctx.fillRect(0, 0, bounds.width, bounds.height);
    ctx.textBaseline = 'middle';
    const blinkVisible = Math.floor(now / 500) % 2 === 0;
    for (const cell of frame.cells) {
      const flags = new Set(cell.modifiers);
      let fg = cell.fg ?? this.foreground, bg = cell.bg ?? this.background;
      if (flags.has('reverse')) [fg, bg] = [bg, fg];
      const x = cell.col * this.cellWidth, y = cell.row * this.cellHeight;
      const cellWidth = cell.width * this.cellWidth;
      ctx.fillStyle = bg;
      ctx.fillRect(x, y, cellWidth, this.cellHeight);
      if (flags.has('hidden') || (flags.has('blink') && !blinkVisible)) continue;
      ctx.save();
      ctx.beginPath();
      ctx.rect(x, y, cellWidth, this.cellHeight);
      ctx.clip();
      ctx.globalAlpha = flags.has('dim') ? 0.55 : 1;
      ctx.fillStyle = fg;
      ctx.font = `${flags.has('italic') ? 'italic ' : ''}${flags.has('bold') ? 'bold ' : ''}${this.fontSize}px ${this.fontFamily}`;
      ctx.fillText(cell.text, x, y + this.cellHeight / 2, cellWidth);
      if (flags.has('underline')) ctx.fillRect(x, y + this.cellHeight - 3, cellWidth, 1);
      if (flags.has('strikethrough')) ctx.fillRect(x, y + this.cellHeight / 2, cellWidth, 1);
      ctx.restore();
    }
    if (frame.cursor && frame.cursor.col < frame.width && frame.cursor.row < frame.height) {
      const { col, row, shape } = frame.cursor;
      const x = col * this.cellWidth, y = row * this.cellHeight;
      ctx.fillStyle = this.foreground;
      ctx.globalAlpha = shape === 'block' ? 0.45 : 1;
      if (shape === 'bar') ctx.fillRect(x, y, 2, this.cellHeight);
      else if (shape === 'underline') ctx.fillRect(x, y + this.cellHeight - 2, this.cellWidth, 2);
      else ctx.fillRect(x, y, this.cellWidth, this.cellHeight);
      ctx.globalAlpha = 1;
    }
  }
}

/** Mount a Lua chunk returning a nonblocking draw function on an HTML canvas. */
export async function mount(canvas, source, options = {}) {
  await document.fonts.ready;
  const renderer = new CanvasRenderer(canvas, options);
  const module = await createIto({ printErr: message => console.error(message) });
  const listeners = new AbortController();
  let timer, blinking, animation, disposed = false, pressed, blinkTimer;
  let size = renderer.size();
  const onError = options.onError ?? (error => console.error(error));

  function call(request) {
    if (disposed) return;
    const result = JSON.parse(module.ccall('ito_call', 'string', ['string'], [JSON.stringify({ ...request, now: performance.now() / 1000 })]));
    if (result.error) throw new Error(result.error);
    clearTimeout(timer);
    if (result.frame) {
      renderer.paint(result.frame);
      canvas.dispatchEvent(new CustomEvent('ito:frame', { detail: result.frame }));
      const needsBlink = result.frame.cells.some(cell => cell.modifiers.includes('blink'));
      if (needsBlink !== blinking) {
        clearInterval(blinkTimer);
        blinking = needsBlink;
        if (blinking) blinkTimer = setInterval(() => renderer.paint(), 500);
      }
    }
    if (typeof result.wake === 'number') timer = setTimeout(redraw, Math.max(16, result.wake * 1000));
    return result;
  }

  function safeCall(request) {
    try { return call(request); }
    catch (error) { clearTimeout(timer); onError(error); }
  }

  function redraw() {
    if (disposed || animation) return;
    animation = requestAnimationFrame(() => { animation = null; safeCall({ type: 'frame' }); });
  }

  function send(event) { return safeCall({ type: 'event', event }); }
  function listen(type, handle, extra = {}) { canvas.addEventListener(type, handle, { signal: listeners.signal, ...extra }); }
  function modifiers(event) { return { ctrl: event.ctrlKey, alt: event.altKey, shift: event.shiftKey }; }
  function mouse(event, kind, button = null) {
    send({ type: 'mouse', kind, button, ...renderer.position(event), ...modifiers(event) });
  }

  canvas.tabIndex = 0;
  canvas.setAttribute('role', 'application');
  if (!canvas.getAttribute('aria-label')) canvas.setAttribute('aria-label', 'Ito terminal. Click to focus and type.');
  listen('keydown', event => {
    if (event.isComposing || event.key === 'Dead') return;
    // Let the browser deliver clipboard events and keep its navigation shortcuts.
    if ((event.metaKey || event.ctrlKey) && ['c', 'v', 'x', 'r', 'l', 't', 'w', '+', '-', '0'].includes(event.key.toLowerCase())) return;
    let key = KEYS[event.key] ?? (/^F\d+$/.test(event.key) ? event.key.toLowerCase() : event.key);
    if (key === 'tab' && event.shiftKey) key = 'backtab';
    if (!KEYS[event.key] && !/^f\d+$/.test(key) && [...key].length !== 1) return;
    event.preventDefault();
    send({ type: 'key', key, ...modifiers(event), meta: event.metaKey, repeat: event.repeat });
  });
  listen('paste', event => {
    const text = event.clipboardData?.getData('text/plain');
    if (text) { event.preventDefault(); send({ type: 'paste', text }); }
  });
  listen('compositionend', event => { if (event.data) send({ type: 'paste', text: event.data }); });
  listen('focus', () => send({ type: 'focus', focused: true }));
  listen('blur', () => send({ type: 'focus', focused: false }));
  listen('contextmenu', event => event.preventDefault());
  const buttons = ['left', 'middle', 'right'];
  listen('pointerdown', event => {
    if (!buttons[event.button]) return;
    event.preventDefault();
    canvas.focus({ preventScroll: true });
    canvas.setPointerCapture(event.pointerId);
    pressed = { button: buttons[event.button], x: event.clientX, y: event.clientY, link: renderer.linkAt(event) };
    mouse(event, 'down', pressed.button);
  });
  listen('pointermove', event => {
    canvas.style.cursor = renderer.linkAt(event) ? 'pointer' : 'text';
    if (pressed) mouse(event, 'drag', pressed.button);
    else mouse(event, 'move');
  });
  listen('pointerup', event => {
    if (!pressed) return;
    const start = pressed;
    pressed = null;
    mouse(event, 'up', start.button);
    if (canvas.hasPointerCapture(event.pointerId)) canvas.releasePointerCapture(event.pointerId);
    if (start.button === 'left' && start.link && start.link === renderer.linkAt(event) && Math.hypot(event.clientX - start.x, event.clientY - start.y) < 4) {
      const url = new URL(start.link, location.href);
      if (['https:', 'http:', 'mailto:'].includes(url.protocol)) window.open(url.href, '_blank', 'noopener,noreferrer');
    }
  });
  listen('pointercancel', event => { if (pressed) mouse(event, 'up', pressed.button); pressed = null; });
  listen('wheel', event => {
    event.preventDefault();
    if (event.deltaY) mouse(event, event.deltaY > 0 ? 'scroll_down' : 'scroll_up');
    else if (event.deltaX) mouse(event, event.deltaX > 0 ? 'scroll_right' : 'scroll_left');
  }, { passive: false });

  function resize() {
    const next = renderer.size();
    if (size.width !== next.width || size.height !== next.height) {
      size = next;
      safeCall({ type: 'resize', ...size });
    } else renderer.paint();
  }
  const observer = new ResizeObserver(resize);
  const close = () => {
    if (disposed) return;
    clearTimeout(timer); clearInterval(blinkTimer); cancelAnimationFrame(animation);
    observer.disconnect(); listeners.abort();
    call({ type: 'close' });
    disposed = true;
  };
  try { call({ type: 'load', source, ...size }); }
  catch (error) { close(); throw error; }
  observer.observe(canvas);
  window.addEventListener('resize', resize, { signal: listeners.signal });
  return { renderer, redraw, send, close };
}
