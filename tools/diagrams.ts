// Prerender the Mermaid diagrams of the blog.
//
// The site does not draw diagrams in the browser: this tool draws each ```mermaid block of every post, in the
// light and in the dark scheme, and writes the result next to the post. The Go renderer inlines the SVG it finds
// and falls back to showing the source when a diagram was never drawn.
//
//   bun tools/diagrams.ts           draw every diagram, write assets/diagrams/index.json
//   bun tools/diagrams.ts --check   fail when a diagram is missing, stale, or no longer in the post
//
// Mermaid needs a real layout engine, so it runs in headless Chrome: set CHROME_PATH, or let the tool find
// chrome, chromium or edge.
import { createHash } from "node:crypto";
import { existsSync } from "node:fs";
import { mkdir, readdir, readFile, rm, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import puppeteer, { type Browser, type Page } from "puppeteer-core";

const ROOT = dirname(dirname(fileURLToPath(import.meta.url)));
const BLOG = join(ROOT, "data", "blog");
const MERMAID = join(ROOT, "node_modules", "mermaid", "dist", "mermaid.min.js");
const FONTS = join(ROOT, "node_modules", "@fontsource", "fira-code", "files");
const MANIFEST = "index.json";
const DIAGRAM_DIR = "diagrams";

// The two palettes of the site. They are the same colours the browser used to pass to Mermaid, so a diagram
// drawn here looks like the diagram readers saw before it was prerendered.
const DARK = {
  darkMode: true,
  background: "#000000",
  fontSize: "15px",
  primaryColor: "#06120a",
  primaryTextColor: "#d9ffd0",
  primaryBorderColor: "#39ff14",
  secondaryColor: "#0a0f14",
  secondaryTextColor: "#bff6ff",
  secondaryBorderColor: "#00e5ff",
  tertiaryColor: "#140f02",
  tertiaryTextColor: "#ffe3a0",
  tertiaryBorderColor: "#ffb000",
  mainBkg: "#06120a",
  nodeBorder: "#39ff14",
  nodeTextColor: "#d9ffd0",
  clusterBkg: "#0b0b0b",
  clusterBorder: "#ffb000",
  titleColor: "#ffb000",
  lineColor: "#00e5ff",
  textColor: "#e6e6e6",
  edgeLabelBackground: "#000000",
  actorBkg: "#06101a",
  actorBorder: "#00e5ff",
  actorTextColor: "#bff6ff",
  actorLineColor: "#3a6f7a",
  signalColor: "#39ff14",
  signalTextColor: "#d9ffd0",
  labelBoxBkgColor: "#140f02",
  labelBoxBorderColor: "#ffb000",
  labelTextColor: "#ffe3a0",
  loopTextColor: "#ffb000",
  noteBkgColor: "#190a14",
  noteBorderColor: "#ff2bd6",
  noteTextColor: "#ffd0f3",
  activationBkgColor: "#0a2a14",
  activationBorderColor: "#39ff14",
  sequenceNumberColor: "#000000",
  labelColor: "#d9ffd0",
  altBackground: "#0b0b0b",
  pie1: "#39ff14", pie2: "#00e5ff", pie3: "#ffb000", pie4: "#ff2bd6", pie5: "#ff4d4d", pie6: "#f5ff3b",
  pie7: "#7a5cff", pie8: "#ff8a00", pie9: "#00ffa3", pie10: "#ff6ec7", pie11: "#5ad1ff", pie12: "#b6ff00",
  pieTitleTextColor: "#ffb000", pieSectionTextColor: "#000000", pieLegendTextColor: "#e6e6e6",
  pieStrokeColor: "#000000", pieOuterStrokeColor: "#39ff14", pieOpacity: "0.95",
  cScale0: "#39ff14", cScale1: "#00e5ff", cScale2: "#ffb000", cScale3: "#ff2bd6",
  cScale4: "#ff4d4d", cScale5: "#f5ff3b", cScale6: "#7a5cff", cScale7: "#00ffa3",
  cScaleLabel0: "#000000", cScaleLabel1: "#000000", cScaleLabel2: "#000000", cScaleLabel3: "#000000",
  cScaleLabel4: "#000000", cScaleLabel5: "#000000", cScaleLabel6: "#ffffff", cScaleLabel7: "#000000",
};

const LIGHT = {
  darkMode: false,
  background: "#ffffff",
  fontSize: "15px",
  primaryColor: "#d3e1f0",
  primaryTextColor: "#1f2f44",
  primaryBorderColor: "#5a7fa8",
  secondaryColor: "#d6e8d8",
  secondaryTextColor: "#1f3a24",
  secondaryBorderColor: "#5d8f63",
  tertiaryColor: "#efe2c8",
  tertiaryTextColor: "#4a3511",
  tertiaryBorderColor: "#a8803a",
  mainBkg: "#d3e1f0",
  nodeBorder: "#5a7fa8",
  nodeTextColor: "#1f2f44",
  clusterBkg: "#f1ebdd",
  clusterBorder: "#b0894a",
  titleColor: "#7a5a1e",
  lineColor: "#4b5b70",
  textColor: "#1f2937",
  edgeLabelBackground: "#ffffff",
  actorBkg: "#d3e1f0",
  actorBorder: "#5a7fa8",
  actorTextColor: "#1f2f44",
  actorLineColor: "#9aa8b8",
  signalColor: "#3f7d6e",
  signalTextColor: "#1f2937",
  labelBoxBkgColor: "#efe2c8",
  labelBoxBorderColor: "#a8803a",
  labelTextColor: "#4a3511",
  loopTextColor: "#7a5a1e",
  noteBkgColor: "#f0d5df",
  noteBorderColor: "#b05c7c",
  noteTextColor: "#4a1f33",
  activationBkgColor: "#cfe3d0",
  activationBorderColor: "#5d8f63",
  sequenceNumberColor: "#ffffff",
  labelColor: "#1f2f44",
  altBackground: "#f3f1ea",
  pie1: "#5a7fa8", pie2: "#6aa070", pie3: "#c9a24f", pie4: "#b0698a", pie5: "#b86a64", pie6: "#5f9ea0",
  pie7: "#8aa24f", pie8: "#8a78b5", pie9: "#c9875a", pie10: "#5f9a90", pie11: "#a56fa8", pie12: "#b59a4a",
  pieTitleTextColor: "#1f2937", pieSectionTextColor: "#ffffff", pieLegendTextColor: "#1f2937",
  pieStrokeColor: "#ffffff", pieOuterStrokeColor: "#4b5b70", pieOpacity: "0.95",
  cScale0: "#5a7fa8", cScale1: "#6aa070", cScale2: "#c9a24f", cScale3: "#b0698a",
  cScale4: "#b86a64", cScale5: "#5f9ea0", cScale6: "#8a78b5", cScale7: "#8aa24f",
  cScaleLabel0: "#ffffff", cScaleLabel1: "#ffffff", cScaleLabel2: "#1f2937", cScaleLabel3: "#ffffff",
  cScaleLabel4: "#ffffff", cScaleLabel5: "#ffffff", cScaleLabel6: "#ffffff", cScaleLabel7: "#1f2937",
};

// Layout of the rendered SVG. Identical to the Mermaid configuration the browser used, except that the SVG keeps
// its natural size: the page scales it down with CSS, which is what useMaxWidth did in the browser.
const LAYOUT = {
  startOnLoad: false,
  securityLevel: "strict",
  suppressErrorRendering: true,
  theme: "base",
  fontFamily: '"Fira Code", ui-monospace, SFMono-Regular, Menlo, Consolas, monospace',
  // Text is drawn as <text>, not as HTML labels: foreignObject text is measured against the page's CSS and the
  // boxes come out wrong when the SVG is inlined somewhere else.
  htmlLabels: false,
  flowchart: { useMaxWidth: false, curve: "basis", htmlLabels: false, wrappingWidth: 360, nodeSpacing: 40, rankSpacing: 50 },
  sequence: { useMaxWidth: false, mirrorActors: false },
};

interface Diagram {
  title: string;
  width: number;
  height: number;
}

interface Manifest {
  [hash: string]: Diagram;
}

interface Block {
  line: number;
  source: string;
  hash: string;
  title: string;
}

function hash(source: string): string {
  return createHash("sha256").update(source.trim()).digest("hex").slice(0, 16);
}

// A fence opens a block; the block holds every line up to the closing fence of the same character. Fenced blocks
// of another language are skipped, and so are the indented ones, which this blog does not write.
function blocks(markdown: string): Block[] {
  const lines = markdown.replace(/\r\n?/g, "\n").split("\n");
  const found: Block[] = [];
  for (let index = 0; index < lines.length; index += 1) {
    const open = /^(\s*)(`{3,}|~{3,})\s*(\S*)/.exec(lines[index]);
    if (!open) continue;
    const [, indent, fence, info] = open;
    let close = index + 1;
    for (; close < lines.length; close += 1) {
      const candidate = /^\s*(`{3,}|~{3,})\s*$/.exec(lines[close]);
      if (candidate && candidate[1][0] === fence[0] && candidate[1].length >= fence.length) break;
    }
    if (info.toLowerCase().startsWith("mermaid")) {
      const source = lines
        .slice(index + 1, close)
        .map((line) => (line.startsWith(indent) ? line.slice(indent.length) : line))
        .join("\n");
      const title = /^\s*%%\s*title:\s*(.+)$/im.exec(source);
      found.push({ line: index + 1, source, hash: hash(source), title: (title?.[1] ?? "").trim() });
    }
    index = close;
  }
  return found;
}

function chromePath(): string {
  if (process.env.CHROME_PATH) return process.env.CHROME_PATH;
  const candidates: Record<string, string[]> = {
    win32: [
      "C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe",
      "C:\\Program Files (x86)\\Google\\Chrome\\Application\\chrome.exe",
      "C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe",
      "C:\\Program Files\\Microsoft\\Edge\\Application\\msedge.exe",
    ],
    darwin: [
      "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
      "/Applications/Chromium.app/Contents/MacOS/Chromium",
    ],
    linux: [],
  };
  for (const candidate of candidates[process.platform] ?? []) {
    if (existsSync(candidate)) return candidate;
  }
  for (const name of ["chromium", "chromium-browser", "google-chrome", "chrome"]) {
    const found = Bun.which(name);
    if (found) return found;
  }
  throw new Error("no Chrome found: set CHROME_PATH to a chrome, chromium or edge binary");
}

async function fontStyles(): Promise<string> {
  const embed = async (weight: number) => {
    const file = join(FONTS, `fira-code-latin-${weight}-normal.woff2`);
    const data = (await readFile(file)).toString("base64");
    return `@font-face{font-family:"Fira Code";font-style:normal;font-weight:${weight};font-display:block;src:url(data:font/woff2;base64,${data}) format("woff2")}`;
  };
  return [await embed(400), await embed(700)].join("\n");
}

async function openPage(browser: Browser): Promise<Page> {
  const page = await browser.newPage();
  await page.setViewport({ width: 1600, height: 1200, deviceScaleFactor: 1 });
  await page.setContent("<!doctype html><html><head><meta charset=\"utf-8\"></head><body></body></html>");
  await page.addStyleTag({ content: await fontStyles() });
  await page.addScriptTag({ path: MERMAID });
  // Mermaid measures the labels while it lays the diagram out: with a fallback font the boxes come out the wrong
  // size and the text is clipped once the real font is in. Wait for the font, like the browser used to.
  await page.evaluate(async () => {
    await Promise.all([document.fonts.load('400 15px "Fira Code"'), document.fonts.load('700 15px "Fira Code"')]);
    await document.fonts.ready;
  });
  return page;
}

async function draw(page: Page, block: Block): Promise<Record<"light" | "dark", string>> {
  const id = "d" + block.hash;
  const result = { light: "", dark: "" };
  for (const scheme of ["light", "dark"] as const) {
    result[scheme] = await page.evaluate(
      async ({ id, source, theme, layout, title, scheme }) => {
        const mermaid = (window as unknown as { mermaid: { initialize: (config: object) => void; render: (id: string, source: string) => Promise<{ svg: string }> } }).mermaid;
        mermaid.initialize({ ...layout, themeVariables: theme });
        const { svg } = await mermaid.render(id, source);

        const host = document.createElement("div");
        host.style.position = "absolute";
        host.style.left = "-100000px";
        host.innerHTML = svg;
        document.body.append(host);
        const element = host.querySelector("svg");
        if (!element) throw new Error("Mermaid returned no <svg>");
        // Mermaid leaves the scratch element it measured into behind it.
        document.querySelectorAll(`#${id}`).forEach((stale) => {
          if (!host.contains(stale)) stale.remove();
        });

        // A diagram's viewBox is computed from the size of the labels at layout time; if anything came out larger
        // (a wide edge label), it would be clipped. Grow the viewBox to the real content. Sequence diagrams size
        // themselves from their actors and messages, and their lifelines would skew the box.
        try {
          if (!(element.getAttribute("aria-roledescription") ?? "").startsWith("sequence")) {
            const view = element.viewBox.baseVal;
            const box = element.getBBox();
            const padding = 12;
            const left = Math.min(view.x, box.x - padding);
            const top = Math.min(view.y, box.y - padding);
            const right = Math.max(view.x + view.width, box.x + box.width + padding);
            const bottom = Math.max(view.y + view.height, box.y + box.height + padding);
            element.setAttribute("viewBox", `${left} ${top} ${right - left} ${bottom - top}`);
          }
        } catch {
          // getBBox needs the element to be rendered; leave the diagram as Mermaid made it
        }

        const view = element.viewBox.baseVal;
        const width = Math.ceil(view.width);
        const height = Math.ceil(view.height);
        element.setAttribute("width", String(width));
        element.setAttribute("height", String(height));
        element.removeAttribute("style");
        element.setAttribute("role", "img");
        if (title) {
          const node = document.createElementNS("http://www.w3.org/2000/svg", "title");
          node.textContent = title;
          element.prepend(node);
        }
        const markup = new XMLSerializer().serializeToString(element);
        host.remove();
        return `${scheme === "dark" ? "<!-- dark -->" : "<!-- light -->"}\n${markup}\n`;
      },
      { id, source: block.source, theme: scheme === "dark" ? DARK : LIGHT, layout: LAYOUT, title: block.title, scheme },
    );
  }
  return result;
}

async function posts(): Promise<string[]> {
  const entries = await readdir(BLOG, { withFileTypes: true });
  const found: string[] = [];
  for (const entry of entries) {
    if (!entry.isDirectory()) continue;
    if (existsSync(join(BLOG, entry.name, "content.md"))) found.push(entry.name);
  }
  return found.sort();
}

async function readManifest(slug: string): Promise<Manifest> {
  const file = join(BLOG, slug, "assets", DIAGRAM_DIR, MANIFEST);
  if (!existsSync(file)) return {};
  return JSON.parse(await readFile(file, "utf8")) as Manifest;
}

function encode(manifest: Manifest): string {
  const sorted: Manifest = {};
  for (const key of Object.keys(manifest).sort()) sorted[key] = manifest[key];
  return JSON.stringify(sorted, null, 2) + "\n";
}

async function main(): Promise<void> {
  const check = process.argv.includes("--check");
  const browser = await puppeteer.launch({
    executablePath: chromePath(),
    headless: true,
    args: ["--no-sandbox", "--disable-gpu", "--force-color-profile=srgb", "--font-render-hinting=none"],
  });
  const failures: string[] = [];
  let drawn = 0;
  try {
    const page = await openPage(browser);
    for (const slug of await posts()) {
      const markdown = await readFile(join(BLOG, slug, "content.md"), "utf8");
      const found = blocks(markdown);
      const directory = join(BLOG, slug, "assets", DIAGRAM_DIR);
      const manifest = await readManifest(slug);

      if (!found.length) {
        if (Object.keys(manifest).length) {
          if (check) failures.push(`${slug}: has a diagram manifest but no diagram`);
          else await rm(directory, { recursive: true, force: true });
        }
        continue;
      }

      const next: Manifest = {};
      for (const block of found) {
        const where = `${slug}:${block.line}`;
        if (check) {
          const entry = manifest[block.hash];
          if (!entry) failures.push(`${where}: not prerendered`);
          else if (!existsSync(join(directory, `${block.hash}-light.svg`)) || !existsSync(join(directory, `${block.hash}-dark.svg`))) {
            failures.push(`${where}: prerendered but its SVG files are missing`);
          }
        }
        if (check) {
          next[block.hash] = manifest[block.hash] ?? { title: block.title, width: 0, height: 0 };
          continue;
        }
        const svgs = await draw(page, block);
        await mkdir(directory, { recursive: true });
        for (const scheme of ["light", "dark"] as const) {
          await writeFile(join(directory, `${block.hash}-${scheme}.svg`), svgs[scheme], "utf8");
        }
        const width = Number(/width="(\d+)"/.exec(svgs.light)?.[1] ?? 0);
        const height = Number(/height="(\d+)"/.exec(svgs.light)?.[1] ?? 0);
        next[block.hash] = { title: block.title, width, height };
        drawn += 1;
        process.stdout.write(`  ${where}: ${block.title || block.hash} (${width}x${height})\n`);
      }

      if (check) {
        for (const stale of Object.keys(manifest)) {
          if (!next[stale]) failures.push(`${slug}: ${stale} is prerendered but no longer in the post`);
        }
        continue;
      }

      // Prune the diagrams the post no longer has, so a rename of a block does not leave an orphan file behind.
      for (const stale of Object.keys(manifest)) {
        if (next[stale]) continue;
        await rm(join(directory, `${stale}-light.svg`), { force: true });
        await rm(join(directory, `${stale}-dark.svg`), { force: true });
      }
      await writeFile(join(directory, MANIFEST), encode(next), "utf8");
    }
  } finally {
    await browser.close();
  }

  if (failures.length) {
    process.stderr.write(`diagrams out of date:\n${failures.map((line) => "  " + line).join("\n")}\nrun: just diagrams\n`);
    process.exit(1);
  }
  process.stdout.write(check ? "diagrams are up to date\n" : `drew ${drawn} diagrams\n`);
}

await main();
