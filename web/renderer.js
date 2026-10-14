/** Paint complete Ito cell frames. Layout stays in Lua/Ratatui, in cell coordinates. */

// The Wasm bridge bounds frames to these cells, so never ask for more.
const MOST = { width: 160, height: 120 };

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
      width: Math.max(1, Math.min(MOST.width, Math.floor(bounds.width / this.cellWidth))),
      height: Math.max(1, Math.min(MOST.height, Math.floor(bounds.height / this.cellHeight))),
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
      // Adjacent backgrounds meet on device pixels, without pale cell seams.
      const left = Math.round(x * ratio) / ratio;
      const right = Math.round((x + cellWidth) * ratio) / ratio;
      ctx.fillRect(left, y, right - left, this.cellHeight);
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
