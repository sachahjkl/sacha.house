// Search highlighting, shared by every search of the site: the blog search and the filters of the admin.
//
// The matches are painted with the CSS Custom Highlight API (::highlight(search-match) in the stylesheet): the
// script marks text ranges, and never changes the DOM. A browser without the API shows the results unmarked.
//
// An element with data-highlight-terms is highlighted when the page loads, with the words of that attribute.
// Other scripts call window.searchHighlight.highlight(root, terms) after they filter a list.
(function () {
  "use strict";

  const NAME = "search-match";
  const supported = typeof CSS !== "undefined" && CSS.highlights && typeof Highlight !== "undefined";

  // rangesFor finds every occurrence of every term in the visible text of root, ignoring case.
  function rangesFor(root, terms) {
    const words = terms.map((term) => term.toLowerCase()).filter((term) => term !== "");
    const ranges = [];
    if (words.length === 0) return ranges;
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
      if (node.parentElement && node.parentElement.closest(".hidden, [hidden], script, style")) continue;
      const text = node.data.toLowerCase();
      // Lowercasing changes the length of a few characters: the offsets would be wrong, so skip such a node.
      if (text.length !== node.data.length) continue;
      for (const word of words) {
        for (let index = text.indexOf(word); index !== -1; index = text.indexOf(word, index + word.length)) {
          const range = new Range();
          range.setStart(node, index);
          range.setEnd(node, index + word.length);
          ranges.push(range);
        }
      }
    }
    return ranges;
  }

  // highlight replaces the highlighted matches of the page with the occurrences of terms in root.
  function highlight(root, terms) {
    if (!supported || !root) return;
    const ranges = rangesFor(root, terms);
    if (ranges.length === 0) CSS.highlights.delete(NAME);
    else CSS.highlights.set(NAME, new Highlight(...ranges));
  }

  window.searchHighlight = { highlight };

  function start() {
    for (const element of document.querySelectorAll("[data-highlight-terms]")) {
      highlight(element, element.dataset.highlightTerms.split(/\s+/));
    }
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start);
  else start();
})();
