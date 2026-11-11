// Blog posts: a viewer (pan, zoom, pinch, full screen) for diagrams and images, and the buttons of a diagram.
//
// The diagrams are drawn at build time (tools/diagrams.ts) into two SVG files per figure, one for each colour
// scheme. The page only reserves their room: this script inlines the SVG of the reader's scheme when its figure
// comes near the screen, and swaps it when the scheme changes. The SVG is inlined, not shown as an image, because
// it uses the page's font. Without JavaScript the page shows the drawings as images.
(function () {
  "use strict";

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


  /* ---------------------------------------------------------------- diagrams */

  const darkScheme = window.matchMedia("(prefers-color-scheme: dark)");

  // drawDiagram inlines the drawing of the current scheme into the body of a figure, once per scheme.
  async function drawDiagram(body) {
    const scheme = darkScheme.matches ? "dark" : "light";
    if (body.dataset.drawn === scheme) return;
    if (body.drawing && body.drawing.scheme === scheme) return body.drawing.done;
    const done = (async () => {
      const response = await fetch(body.dataset[scheme]);
      if (!response.ok) throw new Error(response.status + " " + response.url);
      const parsed = new DOMParser().parseFromString(await response.text(), "image/svg+xml");
      const svg = parsed.documentElement;
      if (svg.localName !== "svg") throw new Error("not an SVG: " + response.url);
      if ((darkScheme.matches ? "dark" : "light") !== scheme) return;
      const current = body.querySelector(":scope > svg, :scope > .diagram-slot");
      const drawing = document.importNode(svg, true);
      if (current) current.replaceWith(drawing);
      else body.prepend(drawing);
      body.dataset.drawn = scheme;
    })();
    body.drawing = { scheme, done };
    try {
      await done;
    } catch (error) {
      console.error("diagram:", error);
    } finally {
      if (body.drawing && body.drawing.done === done) body.drawing = null;
    }
  }

  const nearScreen = "IntersectionObserver" in window
    ? new IntersectionObserver((entries) => {
      for (const entry of entries) {
        if (!entry.isIntersecting) continue;
        nearScreen.unobserve(entry.target);
        entry.target.dataset.near = "true";
        drawDiagram(entry.target);
      }
    }, { rootMargin: "800px 0px" })
    : null;

  function diagramBodies() {
    return document.querySelectorAll(".diagram-body[data-light]");
  }

  darkScheme.addEventListener("change", () => {
    for (const body of diagramBodies()) {
      if (body.dataset.near) drawDiagram(body);
    }
  });

  // Printing shows every diagram, even those the reader never scrolled to.
  window.addEventListener("beforeprint", () => {
    for (const body of diagramBodies()) drawDiagram(body);
  });

  async function figureSvg(figure) {
    const body = figure.querySelector(".diagram-body");
    if (!body) return null;
    await drawDiagram(body);
    return body.querySelector(":scope > svg");
  }

  function figureSource(figure) {
    const pre = figure.querySelector("pre.diagram-source");
    return pre ? pre.textContent : "";
  }

  async function openDiagram(figure) {
    const svg = await figureSvg(figure);
    if (!svg) return;
    const copy = svg.cloneNode(true);
    const [width, height] = svgSize(svg);
    copy.removeAttribute("style");
    copy.removeAttribute("class");
    copy.setAttribute("width", width);
    copy.setAttribute("height", height);
    openViewer(copy, width, height, figure.dataset.title || "Diagram", figure.querySelector(".diagram-body"));
  }

  async function downloadDiagram(figure) {
    const svg = await figureSvg(figure);
    if (!svg) return;
    const clone = svg.cloneNode(true);
    clone.setAttribute("xmlns", "http://www.w3.org/2000/svg");
    const url = URL.createObjectURL(new Blob([new XMLSerializer().serializeToString(clone)], { type: "image/svg+xml" }));
    const link = element("a");
    link.href = url;
    link.download = (figure.id || "diagram") + ".svg";
    link.click();
    URL.revokeObjectURL(url);
  }

  function wireDiagram(figure) {
    const body = figure.querySelector(".diagram-body");
    if (body) {
      body.title = "Click to open in the viewer";
      body.addEventListener("click", () => openDiagram(figure));
    }
    const tools = figure.querySelector(".diagram-tools");
    if (!tools) return;
    tools.addEventListener("click", async (event) => {
      const target = event.target.closest("button");
      if (!target) return;
      if (target.dataset.action === "expand") openDiagram(figure);
      if (target.dataset.action === "download") downloadDiagram(figure);
      if (target.dataset.action === "copy") {
        try {
          await navigator.clipboard.writeText(figureSource(figure));
          target.textContent = "copied";
        } catch (error) {
          target.textContent = "failed";
        }
        setTimeout(() => { target.textContent = "source"; }, 1500);
      }
    });
  }

  /* ------------------------------------------------------------------ notes */

  // A note is a number in the text and an item of the list after the post, which links back to the number. On a
  // wide screen the notes are also set in the margin, each beside its number, and the ones near the reading
  // position stand out. The margin copies are for the eye: screen readers and keyboards use the list.

  const WIDE_SCREEN = "(min-width: 84rem)";
  const NOTE_GAP = 12;

  function setupNotes(root) {
    const list = root.querySelector(".footnotes");
    if (!list) return;
    const wide = window.matchMedia(WIDE_SCREEN);
    const pairs = [];
    let column = null;

    function collect() {
      pairs.length = 0;
      for (const mark of root.querySelectorAll("sup > a.footnote-ref")) {
        const item = document.getElementById(mark.getAttribute("href").slice(1));
        if (!item) continue;
        const note = element("div", "sidenote");
        note.append(element("span", "sidenote-number", mark.textContent));
        for (const paragraph of item.querySelectorAll(":scope > p")) {
          const copy = paragraph.cloneNode(true);
          copy.querySelectorAll(".footnote-backref").forEach((link) => link.remove());
          note.append(copy);
        }
        pairs.push({ mark, sup: mark.parentElement, note });
      }
    }

    function highlight(pair, on) {
      pair.note.classList.toggle("is-active", on);
      pair.sup.classList.toggle("is-active", on);
    }

    function place() {
      if (!column) return;
      const origin = root.getBoundingClientRect().top + window.scrollY;
      let floor = 0;
      for (const pair of pairs) {
        const top = Math.max(pair.sup.getBoundingClientRect().top + window.scrollY - origin - 2, floor);
        pair.note.style.top = top + "px";
        floor = top + pair.note.offsetHeight + NOTE_GAP;
      }
    }

    function markNear() {
      if (!column) return;
      const from = window.innerHeight * 0.12;
      const to = window.innerHeight * 0.7;
      for (const pair of pairs) {
        const top = pair.sup.getBoundingClientRect().top;
        pair.note.classList.toggle("is-near", top >= from && top <= to);
      }
    }

    function build() {
      if (column) column.remove();
      column = null;
      if (!wide.matches) return;
      column = element("aside", "sidenotes");
      column.setAttribute("aria-hidden", "true");
      for (const pair of pairs) column.append(pair.note);
      root.append(column);
      place();
      markNear();
    }

    collect();
    for (const pair of pairs) {
      for (const node of [pair.sup, pair.note]) {
        node.addEventListener("mouseenter", () => highlight(pair, true));
        node.addEventListener("mouseleave", () => highlight(pair, false));
      }
      pair.mark.addEventListener("focus", () => highlight(pair, true));
      pair.mark.addEventListener("blur", () => highlight(pair, false));
      // With the note already beside the text, a click on its number shows it instead of jumping to the list.
      pair.mark.addEventListener("click", (event) => {
        if (!column || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return;
        event.preventDefault();
        highlight(pair, true);
        setTimeout(() => highlight(pair, false), 1600);
      });
    }

    let frame = 0;
    const refresh = () => {
      cancelAnimationFrame(frame);
      frame = requestAnimationFrame(() => {
        place();
        markNear();
      });
    };
    wide.addEventListener("change", build);
    window.addEventListener("scroll", () => requestAnimationFrame(markNear), { passive: true });
    window.addEventListener("resize", refresh);
    if (window.ResizeObserver) new ResizeObserver(refresh).observe(root);
    if (document.fonts && document.fonts.ready) document.fonts.ready.then(refresh);
    build();
  }

  /* ------------------------------------------------------------------ boot */

  function start() {
    const root = document.querySelector("article.prose") || document.body;
    makeImagesZoomable(root);
    setupNotes(root);
    root.querySelectorAll("figure.diagram-ready").forEach(wireDiagram);
    for (const body of diagramBodies()) {
      if (nearScreen) nearScreen.observe(body);
      else {
        body.dataset.near = "true";
        drawDiagram(body);
      }
    }
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start);
  else start();
})();
