// Blog posts: Mermaid diagrams, and a viewer (pan, zoom, pinch, full screen) for diagrams and images.
//
// The server marks a ```mermaid block as <figure class="diagram"><pre class="mermaid">source</pre></figure>.
// Mermaid is loaded only when a page has one, from a pinned version with a subresource integrity hash.
// Without JavaScript, or if the library does not load, the source stays visible as a code block.
(function () {
  "use strict";

  const MERMAID_URL = "https://cdn.jsdelivr.net/npm/mermaid@12.2.0/dist/mermaid.min.js";
  const MERMAID_SRI = "sha384-8xUhuLNMjW/cI2Dacg3DR4WliYznvIg0LVG1stctThKD/YVrJFI9TNCFxft5NYgp";

  /* ---------------------------------------------------------------- viewer */

  const MIN_SCALE = 0.05;
  const MAX_SCALE = 24;
  let viewer = null;

  function element(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text) node.textContent = text;
    return node;
  }

  function button(label, action, title) {
    const node = element("button", "", label);
    node.type = "button";
    node.dataset.action = action;
    node.title = title;
    node.setAttribute("aria-label", title);
    return node;
  }

  function createViewer() {
    const dialog = element("dialog", "lightbox");
    dialog.setAttribute("aria-label", "Viewer");

    const bar = element("div", "lightbox-bar");
    const title = element("span", "lightbox-title");
    bar.append(
      title,
      button("−", "zoom-out", "Zoom out (-)"),
      button("+", "zoom-in", "Zoom in (+)"),
      button("fit", "fit", "Fit to the window (0)"),
      button("1:1", "actual", "Actual size (1)"),
    );
    if (document.fullscreenEnabled) bar.append(button("full screen", "fullscreen", "Full screen (f)"));
    bar.append(button("close", "close", "Close (Esc)"));

    const stage = element("div", "lightbox-stage");
    stage.tabIndex = 0;
    const content = element("div", "lightbox-content");
    stage.append(content);
    dialog.append(bar, stage);
    document.body.append(dialog);

    const state = { dialog, title, stage, content, scale: 1, x: 0, y: 0, width: 1, height: 1 };
    const pointers = new Map();
    let gesture = null;

    const apply = () => {
      content.style.transform = `translate(${state.x}px, ${state.y}px) scale(${state.scale})`;
    };

    state.fit = () => {
      const box = stage.getBoundingClientRect();
      const padding = 24;
      const scale = Math.min((box.width - padding) / state.width, (box.height - padding) / state.height);
      state.scale = Math.min(Math.max(scale, MIN_SCALE), 3);
      state.x = (box.width - state.width * state.scale) / 2;
      state.y = (box.height - state.height * state.scale) / 2;
      apply();
    };

    state.zoomAt = (factor, clientX, clientY) => {
      const box = stage.getBoundingClientRect();
      const px = clientX - box.left;
      const py = clientY - box.top;
      const next = Math.min(Math.max(state.scale * factor, MIN_SCALE), MAX_SCALE);
      const ratio = next / state.scale;
      state.x = px - (px - state.x) * ratio;
      state.y = py - (py - state.y) * ratio;
      state.scale = next;
      apply();
    };

    state.zoomCentre = (factor) => {
      const box = stage.getBoundingClientRect();
      state.zoomAt(factor, box.left + box.width / 2, box.top + box.height / 2);
    };

    state.actual = () => {
      const box = stage.getBoundingClientRect();
      state.zoomAt(1 / state.scale, box.left + box.width / 2, box.top + box.height / 2);
    };

    bar.addEventListener("click", (event) => {
      const target = event.target.closest("button");
      if (!target) return;
      switch (target.dataset.action) {
        case "zoom-in": state.zoomCentre(1.4); break;
        case "zoom-out": state.zoomCentre(1 / 1.4); break;
        case "fit": state.fit(); break;
        case "actual": state.actual(); break;
        case "close": dialog.close(); break;
        case "fullscreen":
          if (document.fullscreenElement) document.exitFullscreen();
          else dialog.requestFullscreen().catch(() => {});
          break;
      }
    });

    stage.addEventListener("wheel", (event) => {
      event.preventDefault();
      const unit = event.deltaMode === 1 ? 16 : 1;
      state.zoomAt(Math.exp(-event.deltaY * unit * 0.0015), event.clientX, event.clientY);
    }, { passive: false });

    stage.addEventListener("pointerdown", (event) => {
      stage.setPointerCapture(event.pointerId);
      pointers.set(event.pointerId, { x: event.clientX, y: event.clientY });
      stage.classList.add("dragging");
      gesture = pointers.size === 2 ? pinchStart() : null;
    });

    stage.addEventListener("pointermove", (event) => {
      const previous = pointers.get(event.pointerId);
      if (!previous) return;
      const current = { x: event.clientX, y: event.clientY };
      pointers.set(event.pointerId, current);
      if (pointers.size === 1) {
        state.x += current.x - previous.x;
        state.y += current.y - previous.y;
        apply();
      } else if (pointers.size === 2 && gesture) {
        const [a, b] = [...pointers.values()];
        const distance = Math.hypot(a.x - b.x, a.y - b.y) || 1;
        const centre = { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 };
        state.x += centre.x - gesture.centre.x;
        state.y += centre.y - gesture.centre.y;
        state.zoomAt(distance / gesture.distance, centre.x, centre.y);
        gesture = { distance, centre };
      }
    });

    const release = (event) => {
      pointers.delete(event.pointerId);
      gesture = pointers.size === 2 ? pinchStart() : null;
      if (pointers.size === 0) stage.classList.remove("dragging");
    };
    stage.addEventListener("pointerup", release);
    stage.addEventListener("pointercancel", release);

    function pinchStart() {
      const [a, b] = [...pointers.values()];
      return { distance: Math.hypot(a.x - b.x, a.y - b.y) || 1, centre: { x: (a.x + b.x) / 2, y: (a.y + b.y) / 2 } };
    }

    stage.addEventListener("dblclick", (event) => state.zoomAt(2, event.clientX, event.clientY));

    dialog.addEventListener("keydown", (event) => {
      const step = 60;
      switch (event.key) {
        case "+": case "=": state.zoomCentre(1.4); break;
        case "-": case "_": state.zoomCentre(1 / 1.4); break;
        case "0": state.fit(); break;
        case "1": state.actual(); break;
        case "f": if (document.fullscreenEnabled) {
          if (document.fullscreenElement) document.exitFullscreen();
          else dialog.requestFullscreen().catch(() => {});
        } break;
        case "ArrowLeft": state.x += step; apply(); break;
        case "ArrowRight": state.x -= step; apply(); break;
        case "ArrowUp": state.y += step; apply(); break;
        case "ArrowDown": state.y -= step; apply(); break;
        default: return;
      }
      event.preventDefault();
    });

    document.addEventListener("fullscreenchange", () => {
      if (dialog.open) requestAnimationFrame(state.fit);
    });
    window.addEventListener("resize", () => {
      if (dialog.open) state.fit();
    });
    dialog.addEventListener("close", () => {
      content.replaceChildren();
      if (document.fullscreenElement === dialog) document.exitFullscreen();
      if (state.opener && document.contains(state.opener)) state.opener.focus();
    });

    return state;
  }

  function openViewer(node, width, height, label, opener) {
    if (!viewer) viewer = createViewer();
    viewer.title.textContent = label || "";
    viewer.content.replaceChildren(node);
    viewer.content.style.width = width + "px";
    viewer.content.style.height = height + "px";
    viewer.width = width;
    viewer.height = height;
    viewer.opener = opener;
    viewer.dialog.showModal();
    viewer.stage.focus();
    requestAnimationFrame(viewer.fit);
  }

  function svgSize(svg) {
    const box = svg.viewBox && svg.viewBox.baseVal;
    if (box && box.width && box.height) return [box.width, box.height];
    const rect = svg.getBoundingClientRect();
    return [rect.width || 800, rect.height || 600];
  }

  function openDiagram(figure) {
    const svg = figure.querySelector(".diagram-body svg");
    if (!svg) return;
    const copy = svg.cloneNode(true);
    const [width, height] = svgSize(svg);
    copy.removeAttribute("style");
    copy.setAttribute("width", width);
    copy.setAttribute("height", height);
    openViewer(copy, width, height, figure.dataset.title || "Diagram", figure.querySelector(".diagram-body"));
  }

  function openImage(image) {
    const copy = new Image();
    copy.alt = image.alt;
    copy.src = image.currentSrc || image.src;
    const show = () => openViewer(copy, copy.naturalWidth || image.naturalWidth || 800, copy.naturalHeight || image.naturalHeight || 600, image.alt, image);
    if (copy.complete) show();
    else copy.addEventListener("load", show, { once: true });
  }

  function makeImagesZoomable(root) {
    for (const image of root.querySelectorAll("img")) {
      if (image.closest("a")) continue;
      image.classList.add("zoomable");
      image.tabIndex = 0;
      image.setAttribute("role", "button");
      image.title = image.title || "Click to zoom";
      image.addEventListener("click", () => openImage(image));
      image.addEventListener("keydown", (event) => {
        if (event.key === "Enter" || event.key === " ") {
          event.preventDefault();
          openImage(image);
        }
      });
    }
  }

  /* --------------------------------------------------------------- Mermaid */

  const sources = new WeakMap();
  let mermaidPromise = null;

  function loadMermaid() {
    if (window.mermaid) return Promise.resolve(window.mermaid);
    if (!mermaidPromise) {
      mermaidPromise = new Promise((resolve, reject) => {
        const script = document.createElement("script");
        script.src = MERMAID_URL;
        script.integrity = MERMAID_SRI;
        script.crossOrigin = "anonymous";
        script.onload = () => resolve(window.mermaid);
        script.onerror = () => reject(new Error("Mermaid did not load"));
        document.head.append(script);
      });
    }
    return mermaidPromise;
  }

  const darkQuery = window.matchMedia("(prefers-color-scheme: dark)");

  // The site is black or white by the system's scheme; Mermaid's own dark theme is too dark on black.
  const DARK_THEME = {
    darkMode: true,
    background: "#000000",
    primaryColor: "#1b2a41",
    primaryTextColor: "#f2f2f2",
    primaryBorderColor: "#6ea8fe",
    secondaryColor: "#1f3d2f",
    tertiaryColor: "#2c2438",
    lineColor: "#c9c9c9",
    textColor: "#f2f2f2",
    noteBkgColor: "#3a3320",
    noteTextColor: "#f2f2f2",
    pie1: "#6ea8fe", pie2: "#7ee0a1", pie3: "#f0b36b", pie4: "#d98aea", pie5: "#f07f7f", pie6: "#8ad6d6",
    pie7: "#c4d96e", pie8: "#e0a0b4", pie9: "#9db4ff", pie10: "#ffd27d", pie11: "#a0e0c8", pie12: "#d4b0ff",
    pieTitleTextColor: "#f2f2f2", pieSectionTextColor: "#000000", pieLegendTextColor: "#f2f2f2",
    cScale0: "#2b5c9e", cScale1: "#2f7d5b", cScale2: "#9a6a24", cScale3: "#7b3f9a",
    cScale4: "#a03c3c", cScale5: "#2a7f86", cScale6: "#6b7f23", cScale7: "#9a4a73",
    cScaleLabel0: "#ffffff", cScaleLabel1: "#ffffff", cScaleLabel2: "#ffffff", cScaleLabel3: "#ffffff",
    cScaleLabel4: "#ffffff", cScaleLabel5: "#ffffff", cScaleLabel6: "#ffffff", cScaleLabel7: "#ffffff",
  };

  function configure(mermaid) {
    const dark = darkQuery.matches;
    mermaid.initialize({
      startOnLoad: false,
      securityLevel: "strict",
      suppressErrorRendering: true,
      theme: dark ? "base" : "neutral",
      themeVariables: dark ? DARK_THEME : {},
      fontFamily: '"Fira Code", ui-monospace, SFMono-Regular, Menlo, Consolas, monospace',
      // SVG text labels: HTML labels (foreignObject) are measured with the page's own CSS, which skews the layout.
      htmlLabels: false,
      flowchart: { useMaxWidth: true, curve: "basis", htmlLabels: false, wrappingWidth: 360, nodeSpacing: 40, rankSpacing: 50 },
      sequence: { useMaxWidth: true, mirrorActors: false },
    });
  }

  function addTools(figure) {
    if (figure.querySelector(".diagram-tools")) return;
    const tools = element("div", "diagram-tools");
    const label = element("span", "diagram-label", figure.dataset.title || "diagram");
    const expand = button("expand", "expand", "Open in the viewer: pan, zoom, full screen");
    const download = button("svg", "download", "Download the diagram as SVG");
    const copy = button("source", "copy", "Copy the Mermaid source");
    tools.append(label, expand, download, copy);
    figure.prepend(tools);
    tools.addEventListener("click", async (event) => {
      const target = event.target.closest("button");
      if (!target) return;
      if (target.dataset.action === "expand") openDiagram(figure);
      if (target.dataset.action === "download") {
        const svg = figure.querySelector(".diagram-body svg");
        const [width, height] = svgSize(svg);
        const clone = svg.cloneNode(true);
        clone.setAttribute("xmlns", "http://www.w3.org/2000/svg");
        clone.setAttribute("width", width);
        clone.setAttribute("height", height);
        const url = URL.createObjectURL(new Blob([new XMLSerializer().serializeToString(clone)], { type: "image/svg+xml" }));
        const link = element("a");
        link.href = url;
        link.download = (figure.id || "diagram") + ".svg";
        link.click();
        URL.revokeObjectURL(url);
      }
      if (target.dataset.action === "copy") {
        try {
          await navigator.clipboard.writeText(sources.get(figure) || "");
          target.textContent = "copied";
          setTimeout(() => { target.textContent = "source"; }, 1500);
        } catch (error) {
          target.textContent = "failed";
        }
      }
    });
  }

  async function renderDiagrams(figures) {
    let mermaid;
    try {
      mermaid = await loadMermaid();
    } catch (error) {
      for (const figure of figures) figure.classList.add("diagram-error");
      return;
    }
    configure(mermaid);
    let counter = 0;
    for (const figure of figures) {
      const source = sources.get(figure);
      try {
        const { svg } = await mermaid.render("diagram-" + Date.now() + "-" + counter++, source);
        let body = figure.querySelector(".diagram-body");
        if (!body) {
          body = element("div", "diagram-body");
          body.title = "Click to open in the viewer";
          body.addEventListener("click", () => openDiagram(figure));
          figure.append(body);
        }
        body.innerHTML = svg;
        figure.classList.add("diagram-ready");
        figure.classList.remove("diagram-error");
        addTools(figure);
      } catch (error) {
        figure.classList.add("diagram-error");
        figure.dataset.error = String(error && error.message ? error.message : error);
      }
    }
  }

  /* ------------------------------------------------------------------ boot */

  function start() {
    const root = document.querySelector("article.prose") || document.body;
    makeImagesZoomable(root);

    const figures = [...root.querySelectorAll("figure.diagram")];
    if (!figures.length) return;
    figures.forEach((figure, index) => {
      const pre = figure.querySelector("pre.mermaid");
      sources.set(figure, pre ? pre.textContent : "");
      const first = (sources.get(figure).split("\n").find((line) => /^\s*%%\s*title:/i.test(line)) || "");
      figure.dataset.title = first.replace(/^\s*%%\s*title:\s*/i, "").trim() || "Diagram " + (index + 1);
      figure.id = figure.id || "diagram-" + (index + 1);
    });
    renderDiagrams(figures);
    darkQuery.addEventListener("change", () => renderDiagrams(figures));
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start);
  else start();
})();
