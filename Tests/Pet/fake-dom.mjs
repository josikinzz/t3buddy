// Just enough of a page for the orbit and effects to run under Node: elements keep their
// attributes, styles and children; a 2D canvas context accepts every call and draws nothing.

class FakeStyle {
  setProperty(name, value) { this[name] = String(value); }
  removeProperty(name) { delete this[name]; }
  getPropertyValue(name) { return this[name] ?? ''; }
}

class FakeElement {
  constructor(tag) {
    this.tagName = tag.toUpperCase();
    this.style = new FakeStyle();
    this.dataset = {};
    this.children = [];
    this.parentNode = null;
    this.className = '';
    const classes = new Set();
    this.classList = {
      add: (...names) => names.forEach((n) => classes.add(n)),
      remove: (...names) => names.forEach((n) => classes.delete(n)),
      toggle: (n, on = !classes.has(n)) => { if (on) classes.add(n); else classes.delete(n); return on; },
      contains: (n) => classes.has(n),
    };
  }
  append(...nodes) { for (const n of nodes) this.appendChild(n); }
  appendChild(node) { node.parentNode?.removeChild(node); node.parentNode = this; this.children.push(node); return node; }
  prepend(node) { this.appendChild(node); }
  removeChild(node) { this.children = this.children.filter((c) => c !== node); node.parentNode = null; return node; }
  remove() { this.parentNode?.removeChild(this); }
  addEventListener() {}
  getContext() { return context2d(); }
  set textContent(text) { this.children = []; this.text = text; }
  get textContent() { return this.text ?? ''; }
}

function context2d() {
  const calls = {
    createRadialGradient: () => ({ addColorStop() {} }),
    measureText: (text) => ({ width: String(text).length * 6 }),
  };
  return new Proxy({}, { get: (target, key) => (key in target ? target[key] : calls[key] ?? (() => {})) });
}

export function installFakeDom({ width = 1200, height = 800 } = {}) {
  const body = new FakeElement('body');
  globalThis.document = {
    body,
    createElement: (tag) => new FakeElement(tag),
    createElementNS: (ns, tag) => new FakeElement(tag),
  };
  globalThis.window = { innerWidth: width, innerHeight: height, devicePixelRatio: 1, addEventListener() {} };
  return { element: (tag = 'div') => new FakeElement(tag) };
}
