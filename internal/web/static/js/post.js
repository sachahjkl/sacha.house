// Blog posts: a viewer (pan, zoom, pinch, full screen) for diagrams and images, and the buttons of a diagram.
//
// The diagrams are drawn at build time (tools/diagrams.ts): the server inlines two SVGs per figure, one for each
// colour scheme, and the stylesheet shows the one of the reader's scheme. Nothing is drawn here, and no library
// is loaded. Without JavaScript the diagrams still show; only the buttons need it.
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

  // The figure holds the light and the dark drawing; the one the stylesheet shows is the one with a box.
  function visibleSvg(figure) {
    for (const svg of figure.querySelectorAll(".diagram-body svg")) {
      if (svg.getClientRects().length) return svg;
    }
    return figure.querySelector(".diagram-body svg");
  }

  function figureSource(figure) {
    const pre = figure.querySelector("pre.diagram-source");
    return pre ? pre.textContent : "";
  }

  function openDiagram(figure) {
    const svg = visibleSvg(figure);
    if (!svg) return;
    const copy = svg.cloneNode(true);
    const [width, height] = svgSize(svg);
    copy.removeAttribute("style");
    copy.removeAttribute("class");
    copy.setAttribute("width", width);
    copy.setAttribute("height", height);
    openViewer(copy, width, height, figure.dataset.title || "Diagram", figure.querySelector(".diagram-body"));
  }

  function downloadDiagram(figure) {
    const svg = visibleSvg(figure);
    if (!svg) return;
    const clone = svg.cloneNode(true);
    clone.removeAttribute("class");
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

  /* ------------------------------------------------------------------ boot */

  function start() {
    const root = document.querySelector("article.prose") || document.body;
    makeImagesZoomable(root);
    root.querySelectorAll("figure.diagram-ready").forEach(wireDiagram);
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start);
  else start();
})();
