// MathRender.ets — Local LaTeX-to-Unicode math text converter (zero dependency).
// ★ 0.151: render LaTeX math commands in AI replies as readable Unicode symbols:
//   \neq → ≠, \sum_{i=1}^{n} → ∑ᵢ₌₁ⁿ, \frac{a}{b} → (a)/(b), x^2 → x², \sqrt{x} → √(x).
//
// IMPORTANT: this conversion MUST run at the parseMarkdown layer, NOT the render layer.
// The selection-translate closure slices selected text by raw offsets of seg.content,
// so converting at parse time keeps displayed text / selection offsets / copy content
// consistent by construction. Code blocks (segment type 1) are skipped naturally.

// ---------- Simple command map (keys = command name without leading backslash) ----------
const SIMPLE_COMMANDS: Record<string, string> = {
  // Relations
  'neq': '≠', 'ne': '≠', 'approx': '≈', 'equiv': '≡', 'sim': '∼', 'simeq': '≃', 'cong': '≅',
  'leq': '≤', 'le': '≤', 'geq': '≥', 'ge': '≥', 'll': '≪', 'gg': '≫', 'propto': '∝',
  // Sets & logic
  'in': '∈', 'notin': '∉', 'ni': '∋',
  'subset': '⊂', 'subseteq': '⊆', 'supset': '⊃', 'supseteq': '⊇',
  'cup': '∪', 'cap': '∩', 'setminus': '∖', 'emptyset': '∅', 'varnothing': '∅',
  'infty': '∞', 'forall': '∀', 'exists': '∃', 'nexists': '∄',
  'neg': '¬', 'land': '∧', 'wedge': '∧', 'lor': '∨', 'vee': '∨',
  // Arrows
  'rightarrow': '→', 'to': '→', 'leftarrow': '←', 'gets': '←',
  'leftrightarrow': '↔', 'Rightarrow': '⇒', 'Leftarrow': '⇐', 'Leftrightarrow': '⇔',
  'mapsto': '↦', 'uparrow': '↑', 'downarrow': '↓',
  'longrightarrow': '⟶', 'longleftarrow': '⟵',
  // Operators
  'times': '×', 'div': '÷', 'pm': '±', 'mp': '∓', 'cdot': '·',
  'ast': '∗', 'star': '⋆', 'bullet': '∙', 'circ': '∘',
  'oplus': '⊕', 'otimes': '⊗', 'odot': '⊙',
  // Big operators & calculus
  'sum': '∑', 'prod': '∏', 'coprod': '∐',
  'int': '∫', 'iint': '∬', 'iiint': '∭', 'oint': '∮',
  'partial': '∂', 'nabla': '∇',
  // Function names (kept as plain text)
  'lim': 'lim', 'sin': 'sin', 'cos': 'cos', 'tan': 'tan', 'cot': 'cot',
  'sec': 'sec', 'csc': 'csc', 'arcsin': 'arcsin', 'arccos': 'arccos', 'arctan': 'arctan',
  'log': 'log', 'ln': 'ln', 'exp': 'exp', 'max': 'max', 'min': 'min',
  'sup': 'sup', 'inf': 'inf', 'det': 'det', 'dim': 'dim', 'arg': 'arg', 'gcd': 'gcd',
  // Geometry & misc
  'perp': '⊥', 'parallel': '∥', 'angle': '∠', 'triangle': '△', 'square': '□',
  'therefore': '∴', 'because': '∵',
  'dots': '…', 'ldots': '…', 'cdots': '⋯', 'vdots': '⋮', 'ddots': '⋱',
  'prime': '′', 'degree': '°',
  'langle': '⟨', 'rangle': '⟩', 'lfloor': '⌊', 'rfloor': '⌋', 'lceil': '⌈', 'rceil': '⌉',
  'ell': 'ℓ', 'hbar': 'ℏ', 'Re': 'ℜ', 'Im': 'ℑ', 'aleph': 'ℵ',
  'quad': '  ', 'qquad': '    ',
  // Layout no-ops
  'left': '', 'right': '', 'displaystyle': '', 'limits': '',
  // Greek lowercase
  'alpha': 'α', 'beta': 'β', 'gamma': 'γ', 'delta': 'δ',
  'epsilon': 'ε', 'varepsilon': 'ε', 'zeta': 'ζ', 'eta': 'η',
  'theta': 'θ', 'vartheta': 'ϑ', 'iota': 'ι', 'kappa': 'κ',
  'lambda': 'λ', 'mu': 'μ', 'nu': 'ν', 'xi': 'ξ', 'pi': 'π', 'varpi': 'ϖ',
  'rho': 'ρ', 'varrho': 'ϱ', 'sigma': 'σ', 'varsigma': 'ς', 'tau': 'τ',
  'upsilon': 'υ', 'phi': 'φ', 'varphi': 'ϕ', 'chi': 'χ', 'psi': 'ψ', 'omega': 'ω',
  // Greek uppercase
  'Gamma': 'Γ', 'Delta': 'Δ', 'Theta': 'Θ', 'Lambda': 'Λ', 'Xi': 'Ξ',
  'Pi': 'Π', 'Sigma': 'Σ', 'Upsilon': 'Υ', 'Phi': 'Φ', 'Psi': 'Ψ', 'Omega': 'Ω'
};

// ---------- Font/wrapper commands: extract braced content, drop the command name ----------
const FONT_COMMANDS: Record<string, string> = {
  'text': '', 'textrm': '', 'textbf': '', 'textit': '', 'texttt': '', 'mbox': '',
  'mathrm': '', 'mathbf': '', 'mathit': '', 'mathcal': '', 'mathbb': '',
  'mathscr': '', 'mathsf': '', 'mathtt': '', 'operatorname': ''
};

// ---------- Accent commands: braced content + combining diacritic ----------
const ACCENT_COMMANDS: Record<string, string> = {
  'hat': '\u0302', 'widehat': '\u0302', 'bar': '\u0304', 'overline': '\u0305',
  'vec': '\u20D7', 'tilde': '\u0303', 'widetilde': '\u0303',
  'dot': '\u0307', 'ddot': '\u0308'
};

// ---------- Superscript / subscript Unicode maps ----------
const SUP_MAP: Record<string, string> = {
  '0': '⁰', '1': '¹', '2': '²', '3': '³', '4': '⁴', '5': '⁵', '6': '⁶', '7': '⁷', '8': '⁸', '9': '⁹',
  '+': '⁺', '-': '⁻', '=': '⁼', '(': '⁽', ')': '⁾', 'n': 'ⁿ', 'i': 'ⁱ'
};

const SUB_MAP: Record<string, string> = {
  '0': '₀', '1': '₁', '2': '₂', '3': '₃', '4': '₄', '5': '₅', '6': '₆', '7': '₇', '8': '₈', '9': '₉',
  '+': '₊', '-': '₋', '=': '₌', '(': '₍', ')': '₎',
  'a': 'ₐ', 'e': 'ₑ', 'h': 'ₕ', 'i': 'ᵢ', 'j': 'ⱼ', 'k': 'ₖ', 'l': 'ₗ', 'm': 'ₘ',
  'n': 'ₙ', 'o': 'ₒ', 'p': 'ₚ', 'r': 'ᵣ', 's': 'ₛ', 't': 'ₜ', 'u': 'ᵤ', 'v': 'ᵥ', 'x': 'ₓ'
};

// ---------- Escaped punctuation (\{ \} \_ \, ...) ----------
const ESCAPE_PUNCT: Record<string, string> = {
  '{': '{', '}': '}', '_': '_', '&': '&', '%': '%', '#': '#', '$': '$',
  ',': ' ', ';': ' ', ':': ' ', '!': '', ' ': ' '
};

// ★ 0.152: fullwidth math punctuation → halfwidth (AI replies often mix them,
// e.g. ＿｛i=1｝ breaks script parsing). Conservative set: chars never used in Chinese prose.
const NORMALIZE_MAP: Record<string, string> = {
  '＼': '\\', '＿': '_', '＾': '^', '｛': '{', '｝': '}', '＆': '&'
};

// ★ 0.152: zero-width chars that may sneak between syntax chars and break parsing.
const ZERO_WIDTH: string[] = ['\u200B', '\u200C', '\u200D', '\uFEFF'];

// ★ 0.152: matrix-like environments \begin{env} ... \end{env} (delimiter pair, '' = none).
const ENV_DELIMITERS: Record<string, string> = {
  'pmatrix': '()', 'bmatrix': '[]', 'vmatrix': '||', 'Bmatrix': '{}',
  'matrix': '', 'cases': '{', 'aligned': '', 'align': '', 'array': ''
};

// ---------- Helpers ----------
class CmdResult {
  out: string;
  next: number;
  constructor(out: string, next: number) {
    this.out = out;
    this.next = next;
  }
}

class BracedGroup {
  content: string;
  end: number;
  constructor(content: string, end: number) {
    this.content = content;
    this.end = end;
  }
}

function isLetter(ch: string): boolean {
  const code = ch.charCodeAt(0);
  return (code >= 65 && code <= 90) || (code >= 97 && code <= 122);
}

function isDigit(ch: string): boolean {
  const code = ch.charCodeAt(0);
  return code >= 48 && code <= 57;
}

// ★ 0.152: normalize fullwidth math punctuation to halfwidth and drop zero-width chars.
function normalizeMathText(text: string): string {
  let out = '';
  for (let k = 0; k < text.length; k++) {
    const c = text.charAt(k);
    if (ZERO_WIDTH.indexOf(c) >= 0) {
      continue; // drop zero-width
    }
    const half: string | undefined = NORMALIZE_MAP[c];
    out += half !== undefined ? half : c;
  }
  return out;
}

// Parse a {…} group starting at pos (text[pos] must be '{').
// Returns null when missing or unbalanced.
function parseBraceGroup(text: string, pos: number): BracedGroup | null {
  if (pos >= text.length || text.charAt(pos) !== '{') {
    return null;
  }
  let depth = 0;
  let j = pos;
  while (j < text.length) {
    const c = text.charAt(j);
    if (c === '{') {
      depth++;
    } else if (c === '}') {
      depth--;
      if (depth === 0) {
        return new BracedGroup(text.substring(pos + 1, j), j + 1);
      }
    }
    j++;
  }
  return null; // unbalanced
}

// Convert every char via map; fall back to ^(…) when any char is unmappable.
function toSuperscript(s: string): string {
  let out = '';
  for (let k = 0; k < s.length; k++) {
    const m: string | undefined = SUP_MAP[s.charAt(k)];
    if (m === undefined) {
      return '^(' + s + ')';
    }
    out += m;
  }
  return out;
}

// Convert every char via map; fall back to _(…) when any char is unmappable.
function toSubscript(s: string): string {
  let out = '';
  for (let k = 0; k < s.length; k++) {
    const m: string | undefined = SUB_MAP[s.charAt(k)];
    if (m === undefined) {
      return '_(' + s + ')';
    }
    out += m;
  }
  return out;
}

// ★ 0.152: render a matrix-like environment body — rows split by \\, cells split by &.
function renderEnvBody(body: string, delim: string): string {
  const left = delim.length > 0 ? delim.charAt(0) : '';
  const right = delim.length > 1 ? delim.charAt(1) : '';
  const rawRows = body.split('\\\\');
  const renderedRows: string[] = [];
  for (const row of rawRows) {
    const cells = row.split('&');
    const renderedCells: string[] = [];
    for (const cell of cells) {
      renderedCells.push(renderMathText(cell.trim()).split('\n').join(' '));
    }
    renderedRows.push(left + renderedCells.join('  ') + right);
  }
  return renderedRows.join('\n');
}

// ★ 0.152: try to render \begin{env} ... \end{env} starting at text[start] === '\'.
// Returns null for unknown/unbalanced environments (caller keeps raw text).
function tryRenderEnvironment(text: string, start: number): CmdResult | null {
  const nameGroup = parseBraceGroup(text, start + 6); // '{env}' right after \begin
  if (nameGroup === null) {
    return null;
  }
  const envName = nameGroup.content.trim();
  const delim: string | undefined = ENV_DELIMITERS[envName];
  if (delim === undefined) {
    return null;
  }
  let bodyStart = nameGroup.end;
  // array takes an extra {col-spec} argument before the body
  if (envName === 'array') {
    const colSpec = parseBraceGroup(text, bodyStart);
    if (colSpec !== null) {
      bodyStart = colSpec.end;
    }
  }
  const endMarker = '\\end{' + envName + '}';
  const endIdx = text.indexOf(endMarker, bodyStart);
  if (endIdx < 0) {
    return null;
  }
  const body = text.substring(bodyStart, endIdx);
  return new CmdResult(renderEnvBody(body, delim), endIdx + endMarker.length);
}

// Try to render a command starting at text[start] === '\'.
// Returns null when a structural command has incomplete arguments (caller keeps raw text).
function tryRenderCommand(text: string, start: number): CmdResult | null {
  let j = start + 1;
  while (j < text.length && isLetter(text.charAt(j))) {
    j++;
  }
  const name = text.substring(start + 1, j);
  if (name.length === 0) {
    if (start + 1 >= text.length) {
      return new CmdResult('\\', start + 1); // lone trailing backslash: keep it
    }
    // Non-letter escape: \\ newline, \{ \} \_ \, ...
    const nxt = text.charAt(start + 1);
    if (nxt === '\\') {
      return new CmdResult('\n', start + 2);
    }
    const esc: string | undefined = ESCAPE_PUNCT[nxt];
    if (esc !== undefined) {
      return new CmdResult(esc, start + 2);
    }
    return new CmdResult(nxt, start + 2);
  }
  // ★ 0.152: \begin{env} ... \end{env} matrix-like environments
  if (name === 'begin') {
    return tryRenderEnvironment(text, start);
  }
  // \frac{a}{b} → (a)/(b)
  if (name === 'frac' || name === 'dfrac' || name === 'tfrac') {
    const g1 = parseBraceGroup(text, j);
    if (g1 !== null) {
      const g2 = parseBraceGroup(text, g1.end);
      if (g2 !== null) {
        return new CmdResult('(' + renderMathText(g1.content) + ')/(' + renderMathText(g2.content) + ')', g2.end);
      }
    }
    return null;
  }
  // \sqrt{x} → √(x), \sqrt[n]{x} → ⁿ√(x)
  if (name === 'sqrt') {
    let cursor = j;
    let rootIdx = '';
    if (cursor < text.length && text.charAt(cursor) === '[') {
      const closeIdx = text.indexOf(']', cursor);
      if (closeIdx > cursor) {
        rootIdx = renderMathText(text.substring(cursor + 1, closeIdx));
        cursor = closeIdx + 1;
      }
    }
    const g = parseBraceGroup(text, cursor);
    if (g !== null) {
      const prefix = rootIdx.length > 0 ? toSuperscript(rootIdx) + '√' : '√';
      return new CmdResult(prefix + '(' + renderMathText(g.content) + ')', g.end);
    }
    return null;
  }
  // Accent: \hat{x} → x̂ (content + combining mark)
  const accent: string | undefined = ACCENT_COMMANDS[name];
  if (accent !== undefined) {
    const g = parseBraceGroup(text, j);
    if (g !== null) {
      return new CmdResult(renderMathText(g.content) + accent, g.end);
    }
    return null;
  }
  // Font wrapper: \text{...} → ... (content only)
  const font: string | undefined = FONT_COMMANDS[name];
  if (font !== undefined) {
    const g = parseBraceGroup(text, j);
    if (g !== null) {
      return new CmdResult(renderMathText(g.content), g.end);
    }
    return null;
  }
  // Simple symbol command
  const mapped: string | undefined = SIMPLE_COMMANDS[name];
  if (mapped !== undefined) {
    return new CmdResult(mapped, j);
  }
  // Unknown command: keep raw "\name"
  return new CmdResult(text.substring(start, j), j);
}

// Try to render ^ / _ scripts starting at text[start].
// Braced forms convert unconditionally; bare forms only for digit runs with an
// optional +/- prefix, so snake_case / regex / plain text stays untouched.
function tryRenderScript(text: string, start: number, isSup: boolean): CmdResult | null {
  const next = start + 1;
  const g = parseBraceGroup(text, next);
  if (g !== null) {
    const inner = renderMathText(g.content);
    return new CmdResult(isSup ? toSuperscript(inner) : toSubscript(inner), g.end);
  }
  if (next < text.length) {
    const c = text.charAt(next);
    let k = next;
    if (c === '+' || c === '-') {
      k++;
    }
    if (k < text.length && isDigit(text.charAt(k))) {
      while (k < text.length && isDigit(text.charAt(k))) {
        k++;
      }
      const argStr = text.substring(next, k);
      return new CmdResult(isSup ? toSuperscript(argStr) : toSubscript(argStr), k);
    }
  }
  return null;
}

// ---------- Main entry ----------
// Convert LaTeX math commands in plain text to Unicode math symbols.
// Unrecognized constructs are kept as-is; code blocks never reach this function.
export function renderMathText(rawText: string): string {
  // ★ 0.152: normalize fullwidth math punctuation & drop zero-width chars first
  const text = normalizeMathText(rawText);
  // Fast path: nothing that looks like math syntax
  if (text.indexOf('\\') < 0 && text.indexOf('^') < 0 && text.indexOf('_') < 0) {
    return text;
  }
  let result = '';
  let i = 0;
  const len = text.length;
  while (i < len) {
    const ch = text.charAt(i);
    if (ch === '\\') {
      const r = tryRenderCommand(text, i);
      if (r !== null) {
        result += r.out;
        i = r.next;
      } else {
        // Structural command with incomplete args: keep raw "\name"
        let j = i + 1;
        while (j < len && isLetter(text.charAt(j))) {
          j++;
        }
        if (j === i + 1) {
          result += ch; // lone backslash
          i++;
        } else {
          result += text.substring(i, j);
          i = j;
        }
      }
      continue;
    }
    if (ch === '^' || ch === '_') {
      const r = tryRenderScript(text, i, ch === '^');
      if (r !== null) {
        result += r.out;
        i = r.next;
      } else {
        result += ch;
        i++;
      }
      continue;
    }
    result += ch;
    i++;
  }
  return result;
}
