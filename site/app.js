(() => {
  const $ = (s, r = document) => r.querySelector(s);
  const $$ = (s, r = document) => [...r.querySelectorAll(s)];
  const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
  const el = (tag, cls, text) => { const e = document.createElement(tag); if (cls) e.className = cls; if (text != null) e.textContent = text; return e; };

  /* OS-aware download order: the visitor's platform goes first and gets the solid button */
  const isWin = /Windows/i.test(navigator.userAgent);
  const mine = isWin ? 'win' : 'mac', other = isWin ? 'mac' : 'win';
  document.querySelectorAll('.hero-actions').forEach(row => {
    const a = row.querySelector(`[data-os="${mine}"]`), b = row.querySelector(`[data-os="${other}"]`);
    if (!a || !b) return;
    a.className = 'btn btn-lg btn-primary'; b.className = 'btn btn-lg btn-ghost';
    row.prepend(a);
  });
  const grid = document.querySelector('.dl-grid');
  if (grid) { const a = grid.querySelector(`[data-os="${mine}"]`); a.classList.add('primary'); grid.prepend(a); }

  /* nav border on scroll */
  const nav = $('.nav');
  const onScroll = () => nav.classList.toggle('scrolled', scrollY > 8);
  addEventListener('scroll', onScroll, { passive: true }); onScroll();

  /* ---------- hero stage ---------- */
  const shell = $('#stage-shell'), stage = $('#stage');
  const fit = () => {
    const s = Math.min(1, shell.clientWidth / stage.offsetWidth);
    stage.style.setProperty('--s', s);
    shell.style.height = stage.offsetHeight * s + 'px';
  };
  new ResizeObserver(fit).observe(shell); fit();

  const note = $('#note'), toast = $('#toast'), panel = $('#panel'), input = $('#panel-input');
  const keys = $('#keys'), key3 = $('#key3'), sel = $('#sel'), cnt = $('#cnt');
  const initialNote = note.innerHTML;
  let token = 0;            // bumps cancel the running demo
  let userMode = false;

  const sleep = (ms, t) => new Promise((res, rej) => setTimeout(() => (t === token ? res() : rej('cancel')), ms));
  const count = () => { cnt.textContent = `· 已记 ${$$('.entry', note).length} 条`; };
  const hhmm = () => { const d = new Date(); return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`; };

  function addEntry(text, src, { link = false, tag = '' } = {}) {
    const e = el('div', 'entry new');
    const p = el('p', null, text);
    if (tag) { p.append(' '); p.append(el('span', 'tag', tag)); }
    e.append(p);
    if (src) {
      const s = el('p', 'src');
      s.append(`${src.time} · `);
      s.append(link ? el('u', null, src.label) : src.label);
      e.append(s);
    } else {
      e.append(el('p', 'src', hhmm()));
    }
    note.append(e);
    requestAnimationFrame(() => { e.classList.add('flash'); setTimeout(() => e.classList.remove('flash'), 900); });
    while (note.scrollHeight > note.clientHeight + 2 && note.children.length > 2) note.children[1].remove();
    count();
  }
  function showToast(title, withSource) {
    toast.querySelector('b').textContent = title;
    toast.querySelector('.toast-src').style.display = withSource ? '' : 'none';
    toast.classList.add('on');
  }
  async function press(k, t) {
    key3.textContent = k;
    keys.classList.add('on'); await sleep(260, t);
    keys.classList.add('press'); await sleep(160, t);
    keys.classList.remove('press'); await sleep(520, t);
    keys.classList.remove('on');
  }
  function reset() {
    note.innerHTML = initialNote; count();
    toast.classList.remove('on'); panel.classList.remove('on'); keys.classList.remove('on', 'press');
    sel.classList.remove('on'); input.value = '';
  }

  async function demo() {
    const t = ++token;
    try {
      for (;;) {
        reset();
        await sleep(900, t);
        sel.classList.add('on');
        await sleep(1300, t);
        await press('K', t);
        addEntry('地方政府不只是“守夜人”，而是深度参与经济发展的“运动员”。', { time: '14:32', label: '置身事内 - 读书笔记' }, { link: true });
        showToast('已收录到今日日记', true);
        await sleep(2600, t);
        toast.classList.remove('on');
        await sleep(700, t);
        await press('J', t);
        panel.classList.add('on');
        await sleep(450, t);
        const text = '明天把第四章读完 #读书';
        for (const ch of text) { input.value += ch; await sleep(ch === ' ' ? 160 : 85, t); }
        await sleep(700, t);
        $('#panel-save').classList.add('press');
        panel.classList.remove('on');
        addEntry('明天把第四章读完', { time: '14:33', label: '随手记' }, { tag: '#读书' });
        showToast('已保存到今日日记', false);
        await sleep(2400, t);
        toast.classList.remove('on');
        await sleep(2600, t);
      }
    } catch (_) { /* cancelled */ }
  }
  function stopDemo() { token++; }

  function staticFinal() {
    reset(); sel.classList.add('on');
    addEntry('地方政府不只是“守夜人”，而是深度参与经济发展的“运动员”。', { time: '14:32', label: '置身事内 - 读书笔记' }, { link: true });
    addEntry('明天把第四章读完', { time: '14:33', label: '随手记' }, { tag: '#读书' });
    $$('.entry', note).forEach(e => e.classList.remove('new'));
  }

  if (reduce) staticFinal();
  else {
    let running = false;
    new IntersectionObserver(([en]) => {
      if (userMode) return;
      if (en.isIntersecting && !running) { running = true; demo(); }
      else if (!en.isIntersecting && running) { running = false; stopDemo(); }
    }, { threshold: .25 }).observe(shell);
  }

  /* try it yourself */
  function openPanel() {
    userMode = true; stopDemo();
    toast.classList.remove('on'); keys.classList.remove('on');
    if (!panel.classList.contains('on')) { input.value = ''; panel.classList.add('on'); }
    setTimeout(() => input.focus({ preventScroll: true }), 60);
  }
  function save() {
    const v = input.value.trim();
    if (!v) { input.focus(); return; }
    const m = v.match(/^(.*?)(\s+#\S+)?$/s);
    panel.classList.remove('on');
    addEntry(m[1], null, { tag: m[2] ? m[2].trim() : '' });
    input.value = '';
    showToast('已保存到今日日记', false);
    setTimeout(() => toast.classList.remove('on'), 2200);
    $('#try').focus({ preventScroll: true });
  }
  $('#try').addEventListener('click', () => {
    shell.scrollIntoView({ behavior: reduce ? 'auto' : 'smooth', block: 'center' });
    openPanel();
  });
  $('#panel-save').addEventListener('click', save);
  $('#panel-x').addEventListener('click', () => panel.classList.remove('on'));
  input.addEventListener('focus', () => { if (!userMode) openPanel(); });
  input.addEventListener('keydown', e => {
    if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) { e.preventDefault(); save(); }
    if (e.key === 'Escape') { e.preventDefault(); panel.classList.remove('on'); $('#try').focus({ preventScroll: true }); }
  });

  /* ---------- sources ---------- */
  const S = {
    web: {
      label: '在 Chrome 里选中', logo: 'brands/googlechrome',
      input: `<p>第三章讲的是政府投融资。<mark>地方政府不只是“守夜人”，而是深度参与经济发展的“运动员”。</mark>土地财政让基础设施得以快速推进，也埋下了债务的隐患。</p>`,
      out: `地方政府不只是“守夜人”，而是深度参与经济发展的“运动员”。\n<span class="md-dim">&gt; 14:32 · [</span><span class="md-link">置身事内 - 读书笔记</span><span class="md-dim">](https://example.com/book)</span>`,
      note: '网页内容转成 Markdown，标题和链接一起带上'
    },
    pdf: {
      label: '在「预览」里选中 PDF', logo: 'lucide/file-text',
      input: `<div class="doc"><div class="doc-h"><span>Attention Is All You Need.pdf</span><span>第 3 页</span></div><mark>The Transformer follows this overall architec-<br>ture using stacked self-attention and point-<br>wise, fully connected layers.</mark></div>`,
      out: `The Transformer follows this overall architecture using stacked self-attention and point-wise, fully connected layers.\n<span class="md-dim">&gt; 14:35 · 《Attention Is All You Need》 p.3</span>`,
      note: 'PDF 的断行和连字符自动修好，带上文件名和页码'
    },
    book: {
      label: '在 Apple Books 里选中', logo: 'lucide/book-open',
      input: `<div class="doc"><div class="doc-h"><span>置身事内</span><span>兰小欢</span></div>想要理解中国经济，就必须理解地方政府。<mark>经济发展是政府的头号任务，政府不仅是规则的制定者，也是参与者。</mark></div>`,
      out: `经济发展是政府的头号任务，政府不仅是规则的制定者，也是参与者。\n<span class="md-dim">&gt; 14:38 · 《置身事内》 兰小欢</span>`,
      note: 'Apple Books、Kindle 的摘录自动解析出书名和作者'
    },
    code: {
      label: '在 Cursor 里选中', logo: 'brands/cursor',
      input: `<div class="doc"><div class="doc-h"><span>capture.py</span><span>Python</span></div><pre><mark>def dedupe(items):
    seen = set()
    return [x for x in items
            if not (x in seen or seen.add(x))]</mark></pre></div>`,
      out: `<span class="md-dim">\`\`\`python</span>\ndef dedupe(items):\n    seen = set()\n    return [x for x in items\n            if not (x in seen or seen.add(x))]\n<span class="md-dim">\`\`\`</span>\n<span class="md-dim">&gt; 14:40 · \`capture.py\` · Cursor</span>`,
      note: '代码放进代码块，认出语言，带上文件名'
    },
    shot: {
      label: '刚截了一张屏，什么都没选', logo: 'lucide/app-window',
      input: `<div class="shot">## 本周复盘<br>- [x] 发布乔木闪记 1.5<br>好的工具让记录这件事消失</div>`,
      out: `![[截屏 2026-11-04 14.42.png]]\n<span class="md-dim">&gt; [!note]- 图中文字</span>\n<span class="md-dim">&gt;</span> ## 本周复盘\n<span class="md-dim">&gt;</span> - [x] 发布乔木闪记 1.5\n<span class="md-dim">&gt;</span> 好的工具让记录这件事消失`,
      note: '截图存进附件，本机识别出的文字折叠在下面，日后能搜到'
    },
    file: {
      label: '在 Finder 里选中文件', logo: 'lucide/folder',
      input: `<div class="files"><div><svg><use href="#i-folder"/></svg>下载</div><div class="on"><svg><use href="#i-file"/></svg>周报-第45周.pdf</div><div class="on"><svg><use href="#i-file"/></svg>设计稿 v2.png</div><div><svg><use href="#i-file"/></svg>发票.zip</div></div>`,
      out: `![[周报-第45周.pdf]]\n![[设计稿 v2.png]]`,
      note: '文件复制进附件文件夹，在笔记里嵌入'
    }
  };
  const srcTabs = $$('.src-tabs button'), srcApp = $('#src-app'), srcIn = $('#src-input'), srcOut = $('#src-output');
  let srcAuto = true, srcIdx = 0, srcTimer = 0;
  function showSrc(key) {
    const d = S[key];
    srcTabs.forEach(b => b.setAttribute('aria-selected', String(b.dataset.src === key)));
    srcApp.innerHTML = `<span class="logo" style="--src:url(assets/${d.logo}.svg)"></span>${d.label}`;
    srcIn.innerHTML = d.input;
    srcOut.innerHTML = d.out;
    srcOut.title = d.note;
    if (!reduce) [srcIn, srcOut].forEach(n => n.animate([{ opacity: 0, transform: 'translateY(6px)' }, { opacity: 1, transform: 'none' }], { duration: 380, easing: 'cubic-bezier(.2,.8,.2,1)' }));
  }
  srcTabs.forEach((b, i) => b.addEventListener('click', () => { srcAuto = false; clearInterval(srcTimer); srcIdx = i; showSrc(b.dataset.src); }));
  $('.src-tabs').addEventListener('keydown', e => {
    if (!['ArrowLeft', 'ArrowRight'].includes(e.key)) return;
    srcAuto = false; clearInterval(srcTimer);
    srcIdx = (srcIdx + (e.key === 'ArrowRight' ? 1 : -1) + srcTabs.length) % srcTabs.length;
    srcTabs[srcIdx].focus(); showSrc(srcTabs[srcIdx].dataset.src);
  });
  showSrc('web');
  if (!reduce) new IntersectionObserver(([en]) => {
    clearInterval(srcTimer);
    if (en.isIntersecting && srcAuto) srcTimer = setInterval(() => { srcIdx = (srcIdx + 1) % srcTabs.length; showSrc(srcTabs[srcIdx].dataset.src); }, 4200);
  }, { threshold: .4 }).observe($('.src-demo'));

  /* marquee */
  const apps = [['googlechrome', 'Chrome'], ['safari', 'Safari'], ['arc', 'Arc'], ['firefoxbrowser', 'Firefox'], ['brave', 'Brave'], ['wechat', '微信'], ['telegram', 'Telegram'], ['discord', 'Discord'], ['qq', 'QQ'],
    ['L:file-text', 'PDF'], ['L:book-open', 'Apple Books'], ['L:book-open', 'Kindle'], ['L:mail', '邮件'], ['notion', 'Notion'], ['obsidian', 'Obsidian'], ['evernote', 'Evernote'],
    ['cursor', 'Cursor'], ['windsurf', 'Windsurf'], ['zedindustries', 'Zed'], ['xcode', 'Xcode'], ['sublimetext', 'Sublime Text'], ['ghostty', 'Ghostty'], ['iterm2', 'iTerm2'], ['warp', 'Warp'],
    ['figma', 'Figma'], ['linear', 'Linear'], ['claude', 'Claude'], ['perplexity', 'Perplexity'], ['raycast', 'Raycast'], ['github', 'GitHub']];
  const track = $('#marquee');
  const row = apps.map(([k, n]) => `<span><span class="logo" style="--src:url(assets/${k.startsWith('L:') ? 'lucide/' + k.slice(2) : 'brands/' + k}.svg)"></span>${n}</span>`).join('');
  track.innerHTML = row + (reduce ? '' : row.replace(/<span>/g, '<span aria-hidden="true">'));

  /* ---------- scenes ---------- */
  const scenes = $$('.scene'), sceneOut = $('#scene-out');
  function hitScene(k) {
    const s = scenes.find(x => x.dataset.k === String(k)); if (!s) return;
    scenes.forEach(x => x.classList.remove('hit'));
    void s.offsetWidth; s.classList.add('hit');
    const name = s.querySelector('b').textContent, dest = s.querySelector('.scene-dest').textContent;
    const folder = dest.endsWith('/');
    sceneOut.innerHTML = `⌃⌥${k} → 收录到 <b>${dest}</b>${folder ? '，新建一篇笔记' : '，追加到末尾'}（场景「${name}」）`;
    clearTimeout(hitScene.t); hitScene.t = setTimeout(() => s.classList.remove('hit'), 1400);
  }
  scenes.forEach(s => s.addEventListener('click', () => hitScene(s.dataset.k)));
  addEventListener('keydown', e => {
    if (e.metaKey || e.ctrlKey || e.altKey || /INPUT|TEXTAREA/.test(document.activeElement?.tagName)) return;
    if (/^[1-6]$/.test(e.key)) {
      const r = $('#scenes').getBoundingClientRect();
      if (r.top < innerHeight && r.bottom > 0) hitScene(e.key);
    }
  });

  /* ---------- pinyin search ---------- */
  const seg = (s, py) => s.split('').map((c, i) => ({ t: c, py: py[i] ?? '' }));
  const mixed = (parts) => parts.flatMap(p => Array.isArray(p) ? seg(p[0], p[1]) : [{ t: p, py: p.trim().toLowerCase() }]);
  const DB = [
    { id: 'daily', type: 'cal', name: seg('今日日记', ['jin', 'ri', 'ri', 'ji']), meta: '✓ 追加到今天', grp: '默认' },
    { id: 'zssn', type: 'file', name: seg('置身事内', ['zhi', 'shen', 'shi', 'nei']), tag: '读书', meta: '3分钟前', grp: '最近', body: '土地财政 地方政府 运动员' },
    { id: 'inbox', type: 'folder', name: mixed(['Inbox']), meta: '3小时前', grp: '最近' },
    { id: 'zb', type: 'file', name: seg('周报', ['zhou', 'bao']), tag: '工作', meta: '2天前', grp: '最近', alias: 'weekly' },
    { id: 'root', type: 'folder', name: seg('仓库根目录', ['cang', 'ku', 'gen', 'mu', 'lu']), meta: '新建笔记', grp: '文件夹' },
    { id: 'ds', type: 'folder', name: seg('读书', ['du', 'shu']), meta: '新建笔记', grp: '文件夹' },
    { id: 'lg', type: 'file', name: seg('灵感', ['ling', 'gan']), tag: '随手', meta: '昨天', alias: 'ideas' },
    { id: 'dszl', type: 'file', name: seg('读书摘录', ['du', 'shu', 'zhai', 'lu']), tag: '读书', meta: '上周' },
    { id: 'ob', type: 'file', name: mixed(['Obsidian', ' ', ['工作流', ['gong', 'zuo', 'liu']]]), tag: '方法', meta: '上周' },
    { id: 'lxh', type: 'file', name: seg('兰小欢访谈', ['lan', 'xiao', 'huan', 'fang', 'tan']), tag: 'Clippings', meta: '10月', body: '为什么写《置身事内》这本书' },
    { id: 'zmjh', type: 'file', name: seg('周末计划', ['zhou', 'mo', 'ji', 'hua']), tag: '生活', meta: '3天前' },
    { id: 'cpzh', type: 'file', name: seg('产品周会', ['chan', 'pin', 'zhou', 'hui']), tag: '工作', meta: '周一', body: '周报模板 复盘' },
  ];
  const nameText = it => it.name.map(s => s.t).join('');
  function pyMatch(segs, q) {
    const hit = (si, qi, acc) => {
      if (qi === q.length) return acc;
      if (si >= segs.length) return null;
      const p = segs[si].py;
      if (!p) return hit(si + 1, qi, acc);
      for (let k = Math.min(p.length, q.length - qi); k >= 1; k--) {
        if (q.substr(qi, k) === p.slice(0, k)) { const r = hit(si + 1, qi + k, [...acc, si]); if (r) return r; }
      }
      return null;
    };
    for (let st = 0; st < segs.length; st++) { if (!segs[st].py) continue; const r = hit(st, 0, []); if (r) return { idx: r, start: st }; }
    return null;
  }
  function search(qRaw) {
    const q = qRaw.trim().toLowerCase().replace(/['\s]/g, '');
    if (!q) return null;
    const out = [];
    for (const it of DB) {
      const nm = nameText(it), low = nm.toLowerCase();
      let score = 0, idx = [], why = '';
      const at = low.replace(/\s/g, '').indexOf(q);
      if (low.includes(qRaw.trim().toLowerCase())) { const i = low.indexOf(qRaw.trim().toLowerCase()); score = 100 - i; idx = [...Array(qRaw.trim().length)].map((_, k) => i + k); }
      else if (/^[a-z]+$/.test(q)) {
        const m = pyMatch(it.name, q);
        if (m) { score = 90 - m.start * 3 - (m.idx.length !== q.length ? 4 : 0); idx = m.idx; why = /[一-鿿]/.test(nm) ? (m.idx.length === q.length ? '首字母' : '拼音') : ''; }
      }
      if (!score && it.alias && it.alias.startsWith(q)) { score = 70; why = '别名 ' + it.alias; }
      if (!score && it.body && it.body.includes(qRaw.trim())) { score = 50; why = '正文'; }
      if (score) out.push({ it, score, idx, why });
      void at;
    }
    return out.sort((a, b) => b.score - a.score);
  }
  const qIn = $('#q'), qList = $('#q-list');
  let qSel = 0;
  const ico = { cal: '#i-cal', file: '#i-file', folder: '#i-folder' };
  function renderName(it, idx) {
    const span = el('span', 'nm');
    it.name.forEach((s, i) => { if (idx.includes(i)) span.append(el('em', null, s.t)); else span.append(s.t); });
    return span;
  }
  function itemLi(it, idx = [], why = '') {
    const li = el('li', 'item');
    li.innerHTML = `<svg><use href="${ico[it.type]}"/></svg>`;
    li.append(renderName(it, idx));
    if (it.tag) li.append(el('span', 'tag', it.tag));
    if (why) li.append(el('span', 'why', why));
    li.append(el('span', 'meta', it.type === 'folder' && why ? '新建笔记' : it.meta));
    li.addEventListener('mouseenter', () => { qSel = $$('li.item', qList).indexOf(li); paintSel(); });
    li.addEventListener('click', () => choose(li));
    return li;
  }
  function paintSel() { $$('li.item', qList).forEach((l, i) => l.classList.toggle('on', i === qSel)); }
  function renderList() {
    const res = search(qIn.value);
    qList.innerHTML = ''; qSel = 0;
    if (!res) {
      let g = '';
      DB.filter(d => d.grp).forEach(d => { if (d.grp !== g) { g = d.grp; qList.append(el('li', 'grp', g)); } qList.append(itemLi(d)); });
    } else if (!res.length) {
      qList.append(el('li', 'empty', '没有找到。按 ↩ 会在当前文件夹新建这篇笔记'));
    } else res.forEach(r => qList.append(itemLi(r.it, r.idx, r.why)));
    paintSel();
    $$('#q-chips button').forEach(b => b.classList.toggle('on', b.dataset.q === qIn.value));
  }
  function choose(li) {
    const meta = li.querySelector('.meta');
    const old = meta.textContent;
    meta.textContent = old.includes('新建') ? '✓ 将在这里新建' : '✓ 将追加到末尾';
    setTimeout(() => (meta.textContent = old), 1400);
  }
  qIn.addEventListener('input', renderList);
  qIn.addEventListener('keydown', e => {
    const items = $$('li.item', qList);
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') { e.preventDefault(); if (!items.length) return; qSel = (qSel + (e.key === 'ArrowDown' ? 1 : -1) + items.length) % items.length; paintSel(); items[qSel].scrollIntoView({ block: 'nearest' }); }
    if (e.key === 'Enter' && items[qSel]) { e.preventDefault(); choose(items[qSel]); }
    if (e.key === 'Escape') { qIn.value = ''; renderList(); }
  });
  $$('#q-chips button').forEach(b => b.addEventListener('click', async () => {
    qIn.value = '';
    if (reduce) { qIn.value = b.dataset.q; renderList(); return; }
    for (const ch of b.dataset.q) { qIn.value += ch; renderList(); await new Promise(r => setTimeout(r, 90)); }
  }));
  renderList();

  /* ---------- modals ---------- */
  $$('[data-modal]').forEach(b => b.addEventListener('click', () => $('#' + b.dataset.modal).showModal()));
  $$('dialog.modal').forEach(d => {
    d.addEventListener('click', e => { if (e.target === d || e.target.closest('[data-close]')) d.close(); });
  });

  /* ---------- reveal on scroll ---------- */
  if (!reduce && 'IntersectionObserver' in window) {
    const targets = $$('.section .eyebrow, .section h2, .section .sub, .versus, .duo, .src-demo, .scenes, .picker, .bento > *, .gallery figure, .privacy, .start, .cta, .faq');
    const io = new IntersectionObserver(ens => ens.forEach(en => { if (en.isIntersecting) { en.target.classList.add('in'); io.unobserve(en.target); } }), { rootMargin: '0px 0px -8% 0px' });
    targets.forEach(t => { t.classList.add('reveal'); io.observe(t); });
  }
})();
