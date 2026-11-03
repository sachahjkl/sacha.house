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

  // Dark scheme: a retro terminal on black. Bright phosphor strokes (green, cyan, amber, magenta) on near-black
  // fills, not pastels. The light scheme has its own, muted palette (LIGHT_THEME).
  const DARK_THEME = {
    darkMode: true,
    background: "#000000",
    fontSize: "15px",
    // nodes and clusters
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
    // lines and labels
    lineColor: "#00e5ff",
    textColor: "#e6e6e6",
    edgeLabelBackground: "#000000",
    // sequence diagrams
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
    // states
    labelColor: "#d9ffd0",
    altBackground: "#0b0b0b",
    // pie
    pie1: "#39ff14", pie2: "#00e5ff", pie3: "#ffb000", pie4: "#ff2bd6", pie5: "#ff4d4d", pie6: "#f5ff3b",
    pie7: "#7a5cff", pie8: "#ff8a00", pie9: "#00ffa3", pie10: "#ff6ec7", pie11: "#5ad1ff", pie12: "#b6ff00",
    pieTitleTextColor: "#ffb000", pieSectionTextColor: "#000000", pieLegendTextColor: "#e6e6e6",
    pieStrokeColor: "#000000", pieOuterStrokeColor: "#39ff14", pieOpacity: "0.95",
    // timeline
    cScale0: "#39ff14", cScale1: "#00e5ff", cScale2: "#ffb000", cScale3: "#ff2bd6",
    cScale4: "#ff4d4d", cScale5: "#f5ff3b", cScale6: "#7a5cff", cScale7: "#00ffa3",
    cScaleLabel0: "#000000", cScaleLabel1: "#000000", cScaleLabel2: "#000000", cScaleLabel3: "#000000",
    cScaleLabel4: "#000000", cScaleLabel5: "#000000", cScaleLabel6: "#ffffff", cScaleLabel7: "#000000",
  };
  // Light scheme: colour, but muted. Tinted fills with a darker border of the same hue, so nothing is white or
  // shouting; "neutral" left the nodes almost white.
  const LIGHT_THEME = {
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

  function configure(mermaid) {
    const dark = darkQuery.matches;
    mermaid.initialize({
      startOnLoad: false,
      securityLevel: "strict",
      suppressErrorRendering: true,
      theme: "base",
      themeVariables: dark ? DARK_THEME : LIGHT_THEME,
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

  // A diagram's viewBox is computed from the size of the labels at layout time; if anything came out larger (a
  // font that arrived late, a wide edge label), it would be clipped. Grow the viewBox to the real content.
  function fitViewBox(svg) {
    if (!svg || !svg.viewBox || !svg.viewBox.baseVal) return;
    // Sequence diagrams size themselves from their actors and messages, and their lifelines would skew the box.
    if ((svg.getAttribute("aria-roledescription") || "").startsWith("sequence")) return;
    try {
      const view = svg.viewBox.baseVal;
      const box = svg.getBBox();
      const padding = 12;
      const left = Math.min(view.x, box.x - padding);
      const top = Math.min(view.y, box.y - padding);
      const right = Math.max(view.x + view.width, box.x + box.width + padding);
      const bottom = Math.max(view.y + view.height, box.y + box.height + padding);
      if (left === view.x && top === view.y && right === view.x + view.width && bottom === view.y + view.height) return;
      svg.setAttribute("viewBox", `${left} ${top} ${right - left} ${bottom - top}`);
      if (svg.style.maxWidth) svg.style.maxWidth = `${right - left}px`;
    } catch (error) {
      // getBBox needs the element to be rendered; leave the diagram as Mermaid made it
    }
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
    // Mermaid measures the labels while it lays the diagram out: with a fallback font the boxes come out the wrong
    // size, and the text is clipped once the real font is in. Wait for the fonts first.
    try {
      await Promise.race([
        Promise.all([document.fonts.load('400 15px "Fira Code"'), document.fonts.load('700 15px "Fira Code"')]),
        new Promise((resolve) => setTimeout(resolve, 4000)),
      ]);
      await document.fonts.ready;
    } catch (error) {
      // render with what is there
    }
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
        fitViewBox(body.querySelector("svg"));
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
