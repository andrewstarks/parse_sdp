// nav.js — sticky-bar section navigation: hamburger menu on narrow screens,
// bar height exposed as --bar-h for scroll offsets, and the current section
// marked with aria-current as the page scrolls.

export function initNav(header) {
  const toggle = header.querySelector("#nav-toggle");
  const nav = header.querySelector("#site-nav");
  const links = [...nav.querySelectorAll("a[href^='#']")];
  const sections = links.map((a) => document.querySelector(a.getAttribute("href"))).filter(Boolean);

  function setOpen(open) {
    nav.classList.toggle("is-open", open);
    toggle.setAttribute("aria-expanded", String(open));
  }
  toggle.addEventListener("click", () => setOpen(toggle.getAttribute("aria-expanded") !== "true"));
  nav.addEventListener("click", (e) => { if (e.target.closest("a")) setOpen(false); });
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && toggle.getAttribute("aria-expanded") === "true") {
      setOpen(false);
      toggle.focus();
    }
  });
  document.addEventListener("click", (e) => { if (!header.contains(e.target)) setOpen(false); });

  // Keep --bar-h in step with the bar's rendered height (it wraps on
  // narrow screens), so scroll-margin-top and the observer stay accurate.
  const measure = () => document.documentElement.style.setProperty("--bar-h", `${header.offsetHeight}px`);
  measure();
  new ResizeObserver(measure).observe(header);

  function markCurrent() {
    const barH = header.offsetHeight;
    const probe = barH + window.innerHeight * 0.25;
    let current = sections[0];
    for (const s of sections) if (s.getBoundingClientRect().top <= probe) current = s;
    if (window.innerHeight + window.scrollY >= document.documentElement.scrollHeight - 2) current = sections[sections.length - 1];
    for (const a of links) {
      const isCurrent = current && a.getAttribute("href") === `#${current.id}`;
      if (isCurrent) a.setAttribute("aria-current", "true");
      else a.removeAttribute("aria-current");
    }
  }
  const observer = new IntersectionObserver(markCurrent, { threshold: [0, 0.1, 0.25, 0.5, 0.75, 1] });
  for (const s of sections) observer.observe(s);
  window.addEventListener("scroll", markCurrent, { passive: true });
  markCurrent();

  return { close: () => setOpen(false) };
}
