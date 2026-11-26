# Christmas mode

Christmas mode decorates every public page from 25 November to 5 January: a garland, falling snow, a frosted frame,
a snowy ground with a tree, Santa's sleigh, sparks on clicks and fireworks for New Year. The code is
`static/js/christmas.js` and `static/css/christmas.css`; `AGENTS.md` gives the preview parameters.

## Cost budget

The decoration must cost close to nothing while a visitor reads. A long post at 2560x1440, with the CPU slowed 4x,
must keep the frame rate of the page without the decoration. Each rule below removes a cost that a measurement found.

- **One snow canvas, at one device pixel per CSS pixel.** The flakes are soft dots; a canvas at the screen's DPR 2
  holds four times the pixels and clears them every frame for no visible gain. Two canvases (one behind the text, one
  above) doubled the clear, the commit and the composite. All the flakes now fall on the canvas above the text. The
  small, dim flakes of the far layer were behind the text before; above it, they do not change the look.
- **Sprites per radius.** Each flake size has its pre-drawn sprite, so a frame copies sprites without scaling them.
  A crystal sprite is a 96 px drawing scaled down once with the best filter: drawn small directly, or scaled with the
  per-frame filter, its thin arms break into dots. Crystals turn with `setTransform`, not with `save` and `restore`.
- **At most one frame of snow per display frame at 60 Hz.** A 144 Hz screen draws snow at most about 72 times per second.
- **A frame budget guard.** If the browser misses frames, the engine draws fewer flakes, down to 40 %, then draws one
  frame in two. When the frames are on time again, it comes back step by step. The flakes are spawned interleaved by
  depth, so the flakes that a cut leaves still hold every depth in the same proportions.
- **Snow waits during a fast scroll.** A scroll faster than one screen per second freezes the snow until the scroll
  stops, so the main thread is free for the scroll.
- **Twinkles animate opacity only, on layers painted once.** A bulb's glow is a filter. Animating the opacity of each
  bulb inside the garland SVG repainted the garland and its 100 filters every frame. The bulbs of one rhythm now share
  their own SVG layer, and that layer's opacity is animated, which the compositor does alone. The tree lights do the
  same: one layer per rhythm. The bulbs of one rhythm already twinkled in step, so the look is the same.
- **No filter on an animated element.** A filter on an element that moves is applied again each frame. The swing and
  the gallop move a wrapper; the drop shadow is on the image inside it, painted once.
- **The garland stops when it is off the screen.** An `IntersectionObserver` pauses its animations.
- **Santa's trail reads the animation, not the layout.** The sparks behind the sleigh take its position from the
  current time of its flight animation, not from `getBoundingClientRect`.

## Subtleties

- The frost is one fixed layer, painted once. It is composited every frame because the snow canvas under it changes;
  on a GPU this costs a blend. Splitting it into corners would save part of that blend in software compositing only.
- "Reduce motion" keeps the decoration and stops everything that moves: no snow, no Santa, no twinkle.
- The note highlights of `static/js/post.js` follow the reading position with an `IntersectionObserver`, not a scroll
  handler that measures each note number every frame.

## Refused

- **Snow as CSS layers.** Tiles of pre-drawn snow moved by compositor animations cost no script. They lose the wind
  that follows the pointer, the flakes that move away from it, the blizzard and the spinning crystals.
