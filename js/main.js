(() => {
  const root = document.documentElement;
  root.classList.add('js');
  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;

  // Reveal on scroll.
  const reveals = document.querySelectorAll('.reveal');
  if ('IntersectionObserver' in window && !reduce) {
    const io = new IntersectionObserver((entries) => {
      for (const e of entries) {
        if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); }
      }
    }, { rootMargin: '0px 0px -8% 0px', threshold: 0.08 });
    reveals.forEach((el) => io.observe(el));
  } else {
    reveals.forEach((el) => el.classList.add('in'));
  }

  // Videos play only while on screen.
  const videos = document.querySelectorAll('video[data-autoplay]');
  if ('IntersectionObserver' in window) {
    const vio = new IntersectionObserver((entries) => {
      for (const e of entries) {
        const v = e.target;
        if (e.isIntersecting && !reduce) v.play().catch(() => {});
        else v.pause();
      }
    }, { threshold: 0.25 });
    videos.forEach((v) => vio.observe(v));
  }
  if (reduce) videos.forEach((v) => { v.controls = true; });

  // Statement: words light up with scroll.
  const statement = document.getElementById('statement');
  let words = [];
  if (statement) {
    const text = statement.textContent.trim().split(/\s+/);
    statement.textContent = '';
    text.forEach((t, i) => {
      const s = document.createElement('span');
      s.className = 'w';
      s.textContent = t;
      statement.append(s, i < text.length - 1 ? ' ' : '');
      words.push(s);
    });
  }

  // Hero film grows as it enters.
  const film = document.getElementById('heroFilm');

  let ticking = false;
  const update = () => {
    ticking = false;
    const vh = innerHeight;
    if (statement && !reduce) {
      const r = statement.getBoundingClientRect();
      const p = Math.min(1, Math.max(0, (vh * 0.85 - r.top) / (r.height + vh * 0.35)));
      const lit = Math.round(p * words.length);
      words.forEach((w, i) => w.classList.toggle('on', i < lit));
    }
    if (film && !reduce) {
      const r = film.getBoundingClientRect();
      const p = Math.min(1, Math.max(0, (vh - r.top) / (vh * 0.8)));
      film.style.transform = `scale(${0.86 + 0.14 * p})`;
    }
  };
  const onScroll = () => { if (!ticking) { ticking = true; requestAnimationFrame(update); } };
  addEventListener('scroll', onScroll, { passive: true });
  addEventListener('resize', onScroll);
  update();

  // Copy the install command.
  document.querySelectorAll('[data-copy]').forEach((btn) => {
    const hint = btn.querySelector('.install-hint');
    btn.addEventListener('click', async () => {
      try {
        await navigator.clipboard.writeText(btn.dataset.copy);
        hint.textContent = 'Copied';
      } catch {
        hint.textContent = 'Select it';
      }
      setTimeout(() => { hint.textContent = 'Copy'; }, 1600);
    });
  });
})();
