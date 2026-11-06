// Christmas mode: from 25 November to 5 January the site gets a garland, falling snow with depth and wind, a
// frosted frame, a snowy ground with a tree and a snowman, Santa's sleigh crossing the sky, golden sparks on
// every click, fireworks for New Year, and a Santa hat on the portrait.
//
// It sets itself up from the visitor's own date. For testing and for fun:
//   ?xmas=1                  force it on outside the season      ?xmas=0   force it off
//   ?xmasDate=2026-12-24     pretend it is that day (also forces it on)
// The "decor" button of the chip turns it off and on again (kept in localStorage). Everything is decoration:
// it never takes a click, is hidden from the printed page, and with "reduce motion" nothing moves.
(function () {
  "use strict";

  const script = document.currentScript;
  const version = script && script.src ? new URL(script.src).searchParams.get("v") || "" : "";
  const params = new URLSearchParams(location.search);

  /* ------------------------------------------------------------------ dates */

  function parseDate(value) {
    const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value || "");
    return match ? new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]), 12) : null;
  }

  // What the season says today, or null outside it (unless it is forced, then the next Christmas counts down).
  function describe(date, forced) {
    const year = date.getFullYear();
    const month = date.getMonth();
    const day = date.getDate();
    let christmasYear = null;
    if ((month === 10 && day >= 25) || month === 11) christmasYear = year;
    else if (month === 0 && day <= 5) christmasYear = year - 1;
    else if (!forced) return null;
    else christmasYear = year;

    const today = new Date(year, month, day);
    const days = Math.round((new Date(christmasYear, 11, 25) - today) / 86400000);
    let text;
    let busy = false;
    let fireworks = false;
    if (month === 0 && day === 1) {
      text = `Happy New Year ${year}!`;
      fireworks = true;
    } else if (month === 0 && day > 1 && day <= 5) {
      text = `Happy New Year ${year}`;
    } else if (month === 11 && day === 31) {
      text = "New Year's Eve: fireworks tonight";
      fireworks = true;
    } else if (days > 1) {
      text = `${days} days until Christmas`;
    } else if (days === 1) {
      text = "Christmas Eve: Santa is on his way";
      busy = true;
    } else if (days === 0) {
      text = "Merry Christmas!";
      busy = true;
    } else {
      text = "Happy holidays";
    }
    return { text, busy, fireworks, days };
  }

  const simulated = parseDate(params.get("xmasDate"));
  const forced = params.get("xmas") === "1" || simulated !== null;
  if (params.get("xmas") === "0") return;
  const season = describe(simulated || new Date(), forced);
  if (!season) return;

  const reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  const darkQuery = window.matchMedia("(prefers-color-scheme: dark)");

  /* ----------------------------------------------------------------- helpers */

  const ICONS = "/static/icons/noto/";
  const random = (min, max) => min + Math.random() * (max - min);
  const pick = (list) => list[Math.floor(Math.random() * list.length)];
  const clamp = (value, min, max) => Math.min(Math.max(value, min), max);

  function el(tag, className, attributes) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (attributes) for (const [name, value] of Object.entries(attributes)) node.setAttribute(name, value);
    return node;
  }

  function icon(name, className) {
    const image = el("img", className, { src: `${ICONS}${name}.svg`, alt: "", width: "64", height: "64", "aria-hidden": "true", draggable: "false" });
    return image;
  }

  function store(value) {
    try {
      if (value === undefined) return localStorage.getItem("xmas");
      localStorage.setItem("xmas", value);
    } catch (error) {
      // private mode: the setting just does not stick
    }
    return null;
  }

  /* ------------------------------------------------------------- stylesheet */

  const link = el("link", "", { rel: "stylesheet", href: `/static/css/christmas.css${version ? "?v=" + version : ""}` });
  document.head.append(link);
  document.documentElement.classList.add("xmas");

  /* ------------------------------------------------------- DOM, once ready */

  let enabled = forced || store() !== "off";
  let stopSanta = null;
  let garland = null;
  let ground = null;
  let backCanvas = null;
  let frontCanvas = null;
  let chipText = null;
  let toggle = null;
  let resizeTimer = 0;

  function footerHeight() {
    const footer = document.querySelector("footer");
    // Only a footer pinned to the viewport takes room from the ground; one at the end of the page does not.
    return footer && getComputedStyle(footer).position === "fixed" ? footer.offsetHeight : 0;
  }

  const BULB_COLORS = ["#ff2b2b", "#39ff14", "#ffd24a", "#00b7ff", "#ff2bd6", "#ff8a00"];
  const ORNAMENTS = ["bell", "glowing-star", "candy", "cookie", "wrapped-gift"];

  function buildGarland() {
    const width = Math.max(320, document.documentElement.clientWidth);
    const height = 52;
    const swags = Math.max(2, Math.round(width / 300));
    const swagWidth = width / swags;
    const sag = 16;
    const top = 3;
    let path = `M0 ${top}`;
    for (let index = 0; index < swags; index++) {
      path += ` Q${((index + 0.5) * swagWidth).toFixed(1)} ${top + 2 * sag} ${((index + 1) * swagWidth).toFixed(1)} ${top}`;
    }
    const count = Math.floor(width / (width < 600 ? 34 : 44));
    let bulbs = "";
    let strings = "";
    garland.querySelectorAll(".xmas-ornament").forEach((node) => node.remove());
    for (let index = 0; index < count; index++) {
      const x = (index + 0.5) * (width / count);
      const t = (x % swagWidth) / swagWidth;
      const y = top + 4 * sag * t * (1 - t);
      const color = BULB_COLORS[index % BULB_COLORS.length];
      if (index % 5 === 2) {
        strings += `<line x1="${x.toFixed(1)}" y1="${y.toFixed(1)}" x2="${x.toFixed(1)}" y2="${(y + 8).toFixed(1)}" stroke="#7b8a7b" stroke-width="1"/>`;
        const ornament = icon(ORNAMENTS[(index / 5 | 0) % ORNAMENTS.length], "xmas-ornament");
        ornament.style.left = `${(x - 11).toFixed(1)}px`;
        ornament.style.top = `${(y + 8).toFixed(1)}px`;
        garland.append(ornament);
      } else {
        bulbs += `<g transform="translate(${x.toFixed(1)} ${y.toFixed(1)})"><rect class="xmas-socket" x="-2.2" y="0" width="4.4" height="6" rx="1"/>` +
          `<ellipse class="xmas-bulb b${index % 3}" cx="0" cy="11.5" rx="4.2" ry="6" style="color:${color}"/></g>`;
      }
    }
    const svg = `<svg class="xmas-wire" viewBox="0 0 ${width} ${height}" preserveAspectRatio="none" aria-hidden="true"><path d="${path}"/>${strings}${bulbs}</svg>`;
    const previous = garland.querySelector("svg.xmas-wire");
    if (previous) previous.remove();
    garland.insertAdjacentHTML("afterbegin", svg);
  }

  function buildGround() {
    const width = Math.max(320, document.documentElement.clientWidth);
    const wave = (x, offset) => 14 + offset + 4 * Math.sin(x / 61) + 3 * Math.sin(x / 23 + 1);
    let snow = "M0 34";
    let shade = "M0 34";
    for (let x = 0; x <= width + 16; x += 16) {
      snow += ` L${x} ${wave(x, 0).toFixed(1)}`;
      shade += ` L${x} ${wave(x, 6).toFixed(1)}`;
    }
    snow += ` L${width + 16} 34 Z`;
    shade += ` L${width + 16} 34 Z`;
    const bank = ground.querySelector(".xmas-bank");
    bank.setAttribute("viewBox", `0 0 ${width} 34`);
    bank.innerHTML = `<path class="shade" d="${shade}"/><path class="snow" d="${snow}"/>`;
  }

  function build() {
    garland = el("div", "xmas-garland", { "aria-hidden": "true" });
    document.body.prepend(garland);
    buildGarland();

    backCanvas = el("canvas", "xmas-snow back", { "aria-hidden": "true" });
    frontCanvas = el("canvas", "xmas-snow front", { "aria-hidden": "true" });
    const frost = el("div", "xmas-frost", { "aria-hidden": "true" });
    document.body.append(backCanvas, frontCanvas, frost);

    ground = el("div", "xmas-ground", { "aria-hidden": "true" });
    const bank = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    bank.setAttribute("class", "xmas-bank");
    bank.setAttribute("preserveAspectRatio", "none");
    ground.append(bank, icon("christmas-tree", "xmas-scene tree"), icon("wrapped-gift", "xmas-scene gift-a"),
      icon("wrapped-gift", "xmas-scene gift-b"), icon("snowman-without-snow", "xmas-scene snowman"), icon("cookie", "xmas-scene cookie"));
    const lights = el("div", "xmas-tree-lights");
    [[48, 28], [30, 44], [66, 48], [40, 62], [58, 66], [50, 80], [34, 82], [68, 82]].forEach(([x, y], index) => {
      const bulb = el("i");
      bulb.style.left = `${x}%`;
      bulb.style.top = `${y}%`;
      bulb.style.color = BULB_COLORS[index % BULB_COLORS.length];
      lights.append(bulb);
    });
    ground.append(lights);
    document.body.append(ground);
    buildGround();

    const chip = el("div", "xmas-chip");
    chip.append(icon("christmas-tree"));
    chipText = el("span", "", { role: "status" });
    chipText.textContent = season.text;
    toggle = el("button", "", { type: "button" });
    toggle.addEventListener("click", () => setEnabled(!enabled));
    chip.append(chipText, toggle);
    document.body.append(chip);

    layout();
    setEnabled(enabled, true);
  }

  function layout() {
    document.documentElement.style.setProperty("--xmas-footer", `${footerHeight()}px`);
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    for (const canvas of [backCanvas, frontCanvas]) {
      canvas.width = Math.round(innerWidth * dpr);
      canvas.height = Math.round(innerHeight * dpr);
      canvas.getContext("2d").setTransform(dpr, 0, 0, dpr, 0, 0);
    }
    engine.resize(innerWidth, innerHeight);
  }

  function setEnabled(value, initial) {
    enabled = value;
    document.documentElement.classList.toggle("xmas-off", !enabled);
    toggle.textContent = enabled ? "decor: on" : "decor: off";
    toggle.setAttribute("aria-pressed", String(enabled));
    toggle.title = enabled ? "Turn the Christmas decorations off" : "Bring the Christmas decorations back";
    if (!initial) store(enabled ? "on" : "off");
    if (enabled) {
      layout();
      engine.start();
      scheduleSanta(initial ? random(5000, 9000) : 1500);
    } else {
      engine.stop();
      if (stopSanta) stopSanta();
    }
  }

  /* ----------------------------------------------------------- snow engine */

  const engine = (function () {
    const flakes = [];
    const sparks = [];
    const rockets = [];
    const pointer = { x: -1000, y: -1000 };
    let width = innerWidth;
    let height = innerHeight;
    let frame = 0;
    let last = 0;
    let wind = 0;
    let windTarget = 0;
    let blizzardUntil = 0;
    let nextFirework = 0;
    let sprites = null;

    function makeSprites() {
      const flake = darkQuery.matches ? "255,255,255" : "100,150,210";
      const dot = document.createElement("canvas");
      dot.width = dot.height = 48;
      const dotContext = dot.getContext("2d");
      const gradient = dotContext.createRadialGradient(24, 24, 0, 24, 24, 24);
      gradient.addColorStop(0, `rgba(${flake},1)`);
      gradient.addColorStop(0.45, `rgba(${flake},0.7)`);
      gradient.addColorStop(1, `rgba(${flake},0)`);
      dotContext.fillStyle = gradient;
      dotContext.fillRect(0, 0, 48, 48);

      const crystal = document.createElement("canvas");
      crystal.width = crystal.height = 96;
      const context = crystal.getContext("2d");
      context.translate(48, 48);
      context.strokeStyle = `rgba(${flake},0.95)`;
      context.lineCap = "round";
      context.lineWidth = 3.2;
      for (let arm = 0; arm < 6; arm++) {
        context.save();
        context.rotate((arm * Math.PI) / 3);
        context.beginPath();
        context.moveTo(0, 0);
        context.lineTo(0, -40);
        for (const [at, length] of [[-14, 12], [-26, 9]]) {
          context.moveTo(0, at);
          context.lineTo(length * 0.8, at - length);
          context.moveTo(0, at);
          context.lineTo(-length * 0.8, at - length);
        }
        context.stroke();
        context.restore();
      }
      return { dot, crystal };
    }

    function spawn(layer, anywhere, temporary) {
      const spec = [
        { r: [0.8, 1.7], vy: [14, 26], alpha: [0.3, 0.5], wind: 0.3, amp: [4, 9] },
        { r: [1.6, 3.0], vy: [26, 46], alpha: [0.5, 0.75], wind: 0.6, amp: [6, 14] },
        { r: [3.6, 6.4], vy: [52, 92], alpha: [0.7, 0.95], wind: 1.1, amp: [10, 22] },
      ][layer];
      const flake = {
        layer,
        temporary: !!temporary,
        x: random(-20, width + 20),
        y: anywhere ? random(-10, height) : random(-40, -8),
        r: random(spec.r[0], spec.r[1]),
        vy: random(spec.vy[0], spec.vy[1]),
        alpha: random(spec.alpha[0], spec.alpha[1]),
        windK: spec.wind,
        amp: random(spec.amp[0], spec.amp[1]),
        phase: random(0, Math.PI * 2),
        sway: random(0.6, 1.8),
        angle: random(0, Math.PI * 2),
        spin: random(-1.2, 1.2),
        crystal: layer === 2 && Math.random() < 0.45,
      };
      flakes.push(flake);
      return flake;
    }

    function populate() {
      flakes.length = 0;
      const area = width * height;
      const total = clamp(Math.round(area / (width < 700 ? 12000 : 8500)), 60, 280);
      for (let index = 0; index < total; index++) {
        const roll = index / total;
        spawn(roll < 0.38 ? 0 : roll < 0.8 ? 1 : 2, true, false);
      }
    }

    function resize(w, h) {
      width = w;
      height = h;
      sprites = makeSprites();
      populate();
    }

    function addSpark(x, y, vx, vy, color, size, life, gravity) {
      sparks.push({ x, y, vx, vy, color, size, life, max: life, gravity: gravity === undefined ? 90 : gravity });
    }

    function sparkle(x, y) {
      const colors = ["#ffd24a", "#ffffff", "#ff4d4d", "#39ff14", "#00e5ff"];
      for (let index = 0; index < 22; index++) {
        const angle = random(0, Math.PI * 2);
        const speed = random(40, 190);
        addSpark(x, y, Math.cos(angle) * speed, Math.sin(angle) * speed - 30, pick(colors), random(2, 5), random(0.6, 1.3));
      }
    }

    function launchRocket(x, y) {
      const startX = clamp(x + random(-60, 60), 20, width - 20);
      rockets.push({ x: startX, y: height + 10, tx: x, ty: y, vx: (x - startX) / 0.9, vy: -(height - y) / 0.9, age: 0 });
    }

    function explode(x, y) {
      const palette = [["#ff4d4d", "#ffb3b3"], ["#39ff14", "#d9ffd0"], ["#00e5ff", "#c9f8ff"], ["#ffd24a", "#fff0b3"], ["#ff2bd6", "#ffc4f5"]];
      const [main, accent] = pick(palette);
      const count = 70 + Math.floor(random(0, 30));
      const ring = Math.random() < 0.4;
      for (let index = 0; index < count; index++) {
        const angle = (index / count) * Math.PI * 2 + random(-0.05, 0.05);
        const speed = ring ? 170 : random(60, 230);
        addSpark(x, y, Math.cos(angle) * speed, Math.sin(angle) * speed, index % 3 === 0 ? accent : main, random(1.6, 3.4), random(1, 1.9), 70);
      }
    }

    function blizzard(ms) {
      blizzardUntil = performance.now() + ms;
      windTarget = (Math.random() < 0.5 ? -1 : 1) * 2.2;
      for (let index = 0; index < 220; index++) spawn(index % 3, false, true).y = random(-height * 0.6, 0);
    }

    function update(dt, now) {
      const storm = now < blizzardUntil;
      const pointerWind = clamp((pointer.x / width - 0.5) * 2, -1, 1);
      const gust = 0.35 * Math.sin(now / 4300) + 0.2 * Math.sin(now / 1700 + 2);
      if (!storm) windTarget = pointer.x < 0 ? gust : pointerWind * 0.8 + gust;
      wind += (windTarget - wind) * Math.min(1, dt * 1.6);

      for (let index = flakes.length - 1; index >= 0; index--) {
        const flake = flakes[index];
        flake.phase += flake.sway * dt;
        flake.angle += flake.spin * dt;
        flake.y += flake.vy * dt * (storm ? 1.4 : 1);
        flake.x += (wind * 60 * flake.windK + Math.sin(flake.phase) * flake.amp) * dt;
        if (flake.layer === 2) {
          const dx = flake.x - pointer.x;
          const dy = flake.y - pointer.y;
          const distance = Math.hypot(dx, dy);
          if (distance < 90 && distance > 0.1) {
            flake.x += (dx / distance) * (90 - distance) * dt * 5;
            flake.y += (dy / distance) * (90 - distance) * dt * 5;
          }
        }
        if (flake.y > height + 12 || flake.x < -60 || flake.x > width + 60) {
          if (flake.temporary) {
            flakes.splice(index, 1);
          } else {
            flake.y = random(-30, -6);
            flake.x = random(-20, width + 20);
            if (wind > 0.8) flake.x -= wind * 80;
            if (wind < -0.8) flake.x += -wind * 80;
          }
        }
      }

      for (let index = sparks.length - 1; index >= 0; index--) {
        const spark = sparks[index];
        spark.life -= dt;
        if (spark.life <= 0) {
          sparks.splice(index, 1);
          continue;
        }
        spark.vy += spark.gravity * dt;
        spark.vx *= 1 - dt * 0.6;
        spark.x += spark.vx * dt;
        spark.y += spark.vy * dt;
      }

      for (let index = rockets.length - 1; index >= 0; index--) {
        const rocket = rockets[index];
        rocket.age += dt;
        rocket.x += rocket.vx * dt;
        rocket.y += rocket.vy * dt;
        addSpark(rocket.x + random(-1, 1), rocket.y, random(-14, 14), random(20, 60), "#ffe9a8", random(1.2, 2.4), random(0.25, 0.5), 20);
        if (rocket.y <= rocket.ty || rocket.age > 1.6) {
          explode(rocket.x, rocket.y);
          rockets.splice(index, 1);
        }
      }

      if (season.fireworks && now > nextFirework && !document.hidden) {
        launchRocket(random(width * 0.1, width * 0.9), random(height * 0.12, height * 0.5));
        nextFirework = now + random(1400, 3800);
      }
    }

    function drawStar(context, x, y, size) {
      context.beginPath();
      context.moveTo(x, y - size * 2);
      context.lineTo(x + size * 0.5, y - size * 0.5);
      context.lineTo(x + size * 2, y);
      context.lineTo(x + size * 0.5, y + size * 0.5);
      context.lineTo(x, y + size * 2);
      context.lineTo(x - size * 0.5, y + size * 0.5);
      context.lineTo(x - size * 2, y);
      context.lineTo(x - size * 0.5, y - size * 0.5);
      context.closePath();
      context.fill();
    }

    function draw() {
      const back = backCanvas.getContext("2d");
      const front = frontCanvas.getContext("2d");
      back.clearRect(0, 0, width, height);
      front.clearRect(0, 0, width, height);
      for (const flake of flakes) {
        const context = flake.layer === 2 ? front : back;
        context.globalAlpha = flake.alpha;
        if (flake.crystal) {
          context.save();
          context.translate(flake.x, flake.y);
          context.rotate(flake.angle);
          context.drawImage(sprites.crystal, -flake.r * 1.4, -flake.r * 1.4, flake.r * 2.8, flake.r * 2.8);
          context.restore();
        } else {
          context.drawImage(sprites.dot, flake.x - flake.r * 1.5, flake.y - flake.r * 1.5, flake.r * 3, flake.r * 3);
        }
      }
      front.globalAlpha = 1;
      front.globalCompositeOperation = "lighter";
      for (const spark of sparks) {
        front.globalAlpha = clamp(spark.life / spark.max, 0, 1);
        front.fillStyle = spark.color;
        if (spark.size > 2.6) drawStar(front, spark.x, spark.y, spark.size * 0.7);
        else front.fillRect(spark.x - spark.size / 2, spark.y - spark.size / 2, spark.size, spark.size);
      }
      front.globalCompositeOperation = "source-over";
      front.globalAlpha = 1;
      back.globalAlpha = 1;
    }

    function tick(now) {
      frame = requestAnimationFrame(tick);
      const dt = Math.min(0.05, (now - last) / 1000 || 0.016);
      last = now;
      update(dt, now);
      draw();
    }

    function start() {
      if (frame || reduced || document.hidden) return;
      sprites = sprites || makeSprites();
      if (!flakes.length) populate();
      last = performance.now();
      frame = requestAnimationFrame(tick);
    }

    function stop() {
      if (frame) cancelAnimationFrame(frame);
      frame = 0;
      sparks.length = 0;
      rockets.length = 0;
      if (backCanvas) {
        backCanvas.getContext("2d").clearRect(0, 0, width, height);
        frontCanvas.getContext("2d").clearRect(0, 0, width, height);
      }
    }

    darkQuery.addEventListener("change", () => {
      sprites = makeSprites();
    });
    document.addEventListener("visibilitychange", () => {
      if (document.hidden) {
        if (frame) cancelAnimationFrame(frame);
        frame = 0;
      } else if (enabled) {
        start();
      }
    });
    window.addEventListener("pointermove", (event) => {
      pointer.x = event.clientX;
      pointer.y = event.clientY;
    }, { passive: true });

    return { start, stop, resize, sparkle, launchRocket, blizzard, addSpark };
  })();

  /* ---------------------------------------------------------------- Santa */

  let santaTimer = 0;
  let santaBusy = false;

  function scheduleSanta(delay) {
    clearTimeout(santaTimer);
    if (reduced) return;
    santaTimer = setTimeout(() => {
      if (enabled && !document.hidden) flySanta();
      scheduleSanta(season.busy ? random(22000, 45000) : random(70000, 150000));
    }, delay);
  }

  function flySanta() {
    if (santaBusy) return;
    santaBusy = true;
    const leftward = Math.random() < 0.35;
    const santa = el("div", `xmas-santa${leftward ? " leftward" : ""}`, { "aria-hidden": "true" });
    const duration = clamp(innerWidth / 70, 12, 24);
    santa.style.setProperty("--xmas-fly", `${duration.toFixed(1)}s`);
    santa.style.top = `${random(8, 26).toFixed(1)}vh`;
    const inner = el("div", "xmas-santa-inner");
    inner.append(icon("deer", "deer"), icon("deer", "deer"), icon("deer", "deer"));
    const sleigh = el("div", "sleigh");
    sleigh.append(icon("sled", "sled"), icon("santa-claus", "claus"));
    sleigh.firstChild.style.width = "76px";
    sleigh.firstChild.style.height = "76px";
    inner.append(sleigh);
    santa.append(inner);
    document.body.append(santa);

    const trail = setInterval(() => {
      const box = santa.getBoundingClientRect();
      const x = leftward ? box.right - 14 : box.left + 14;
      for (let index = 0; index < 3; index++) {
        engine.addSpark(x + random(-6, 6), box.top + box.height * random(0.4, 0.9), (leftward ? 1 : -1) * random(10, 50), random(-20, 30), pick(["#ffd24a", "#ffffff", "#ff4d4d", "#39ff14"]), random(1.4, 3.6), random(0.7, 1.5), 40);
      }
    }, 60);

    santa.addEventListener("click", () => {
      const box = santa.getBoundingClientRect();
      bubble(box.left + box.width / 2 - 30, box.bottom + 4, "Ho ho ho!");
      engine.sparkle(box.left + box.width / 2, box.top + box.height / 2);
      for (let index = 0; index < 7; index++) {
        const gift = icon(pick(["wrapped-gift", "candy", "cookie", "bell", "glowing-star"]), "xmas-gift");
        gift.style.left = `${box.left + box.width * random(0.35, 0.7)}px`;
        gift.style.top = `${box.top + box.height * 0.7}px`;
        gift.style.setProperty("--xmas-dx", `${random(-90, 90).toFixed(0)}px`);
        gift.style.setProperty("--xmas-spin", `${random(-540, 540).toFixed(0)}deg`);
        gift.style.setProperty("--xmas-drop", `${random(1.6, 2.8).toFixed(2)}s`);
        gift.style.animationDelay = `${(index * 0.08).toFixed(2)}s`;
        gift.addEventListener("animationend", () => gift.remove());
        document.body.append(gift);
      }
    });

    // Turning the decor off hides Santa, which cancels the animation: animationend alone would never come.
    stopSanta = () => {
      clearInterval(trail);
      santa.remove();
      santaBusy = false;
      stopSanta = null;
    };
    santa.addEventListener("animationend", stopSanta);
  }

  function bubble(x, y, text) {
    const node = el("div", "xmas-bubble");
    node.textContent = text;
    node.style.left = `${clamp(x, 8, innerWidth - 120)}px`;
    node.style.top = `${clamp(y, 8, innerHeight - 40)}px`;
    node.addEventListener("animationend", () => node.remove());
    document.body.append(node);
  }

  /* --------------------------------------------------------------- events */

  document.addEventListener("pointerdown", (event) => {
    if (!enabled || reduced) return;
    if (event.target.closest && event.target.closest("a, button, input, textarea, select, summary, dialog, .xmas-santa")) return;
    if (season.fireworks) engine.launchRocket(event.clientX, event.clientY);
    else engine.sparkle(event.clientX, event.clientY);
  });

  // ↑ ↑ ↓ ↓ ← → ← → B A : a blizzard
  const KONAMI = ["ArrowUp", "ArrowUp", "ArrowDown", "ArrowDown", "ArrowLeft", "ArrowRight", "ArrowLeft", "ArrowRight", "b", "a"];
  let progress = 0;
  document.addEventListener("keydown", (event) => {
    if (event.target.closest && event.target.closest("input, textarea, select, [contenteditable]")) return;
    const key = event.key.length === 1 ? event.key.toLowerCase() : event.key;
    progress = key === KONAMI[progress] ? progress + 1 : key === KONAMI[0] ? (progress === 2 ? 2 : 1) : 0;
    if (progress === KONAMI.length) {
      progress = 0;
      if (enabled && !reduced) {
        engine.blizzard(10000);
        bubble(innerWidth / 2 - 60, innerHeight * 0.25, "Blizzard!");
      }
    }
  });

  window.addEventListener("resize", () => {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(() => {
      if (!garland) return;
      buildGarland();
      buildGround();
      layout();
    }, 150);
  });

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", build);
  else build();
})();
