const STORAGE_KEY = 'lumen-mvp-state-v1';

const seedPosts = [
  {
    id: 'p1', type: 'original', author: '林屿', authorId: 'u2', city: '上海', avatar: '林',
    title: '月升陆家嘴', description: '提前查好月升方位，日落后约 25 分钟是天空和建筑亮度最接近的时刻。建议带脚架，避开周末人流。',
    image: '/assets/bund-night.svg', createdAt: '2026-07-11T18:42:00+08:00', likes: 286,
    tags: ['城市风光', '蓝调时刻'], allowRemake: true,
    location: { name: '外滩观景平台', city: '上海', privacy: 'exact', lat: 31.239, lng: 121.49, advice: '建议 18:40–19:20' },
    metadata: { camera: 'Sony A7 IV', lens: 'FE 24–70mm F2.8 GM II', focal: '70 mm', aperture: 'f/8', shutter: '1/2 s', iso: 'ISO 100', capturedAt: '2026-07-11 18:42', source: 'confirmed' },
    shootingNotes: '使用长焦压缩月亮与建筑的距离。先确定月升方位，再微调机位，让月亮从楼群右侧进入画面。',
    editingNotes: '降低高光，轻微增加阴影中的冷色，保留建筑灯光的暖色。'
  },
  {
    id: 'p2', type: 'original', author: '沈禾', authorId: 'u3', city: '杭州', avatar: '沈',
    title: '北山街晨雾', description: '雨后清晨的湖面容易出现薄雾，使用中长焦保留层次。',
    image: '/assets/lake-morning.svg', createdAt: '2026-07-10T05:26:00+08:00', likes: 194,
    tags: ['自然', '晨雾'], allowRemake: true,
    location: { name: '北山街临湖步道', city: '杭州', privacy: 'approximate', lat: 30.255, lng: 120.15, advice: '建议日出前 30 分钟' },
    metadata: { camera: 'Fujifilm X-T5', lens: 'XF 50–140mm', focal: '92 mm', aperture: 'f/5.6', shutter: '1/160 s', iso: 'ISO 400', capturedAt: '2026-07-10 05:26', source: 'confirmed' },
    shootingNotes: '沿湖寻找前景比较干净的位置，曝光以雾气高光不过曝为准。', editingNotes: '降低对比度，让雾气层次保持柔和。'
  },
  {
    id: 'p3', type: 'original', author: '周野', authorId: 'u4', city: '上海', avatar: '周',
    title: '雨夜武康路', description: '雨停后的十五分钟，路面反光最完整。低机位可以拉长灯光倒影。',
    image: '/assets/street-rain.svg', createdAt: '2026-07-09T21:15:00+08:00', likes: 158,
    tags: ['街拍', '雨夜'], allowRemake: true,
    location: { name: '武康路街区', city: '上海', privacy: 'approximate', lat: 31.205, lng: 121.438, advice: '建议雨停后 15 分钟' },
    metadata: { camera: 'Leica Q3', lens: 'Summilux 28mm', focal: '28 mm', aperture: 'f/2', shutter: '1/125 s', iso: 'ISO 1600', capturedAt: '2026-07-09 21:15', source: 'confirmed' },
    shootingNotes: '注意来车，站在人行道内取景。利用招牌和车灯制造冷暖对比。', editingNotes: '压低整体曝光，局部提高路面倒影。'
  },
  {
    id: 'a1', type: 'assignment', originalId: 'p1', author: '周野', authorId: 'u4', city: '上海', avatar: '周',
    title: '月升陆家嘴 · 复刻作业', description: '沿用原作机位和蓝调时间，把焦段改成 85mm，让月亮与建筑的比例更突出。',
    image: '/assets/bund-night.svg', createdAt: '2026-07-12T18:48:00+08:00', likes: 52, recommended: true,
    location: { name: '外滩观景平台', city: '上海', privacy: 'exact', lat: 31.239, lng: 121.49 },
    metadata: { camera: 'Canon EOS R6 II', lens: 'RF 85mm F2', focal: '85 mm', aperture: 'f/8', shutter: '1/4 s', iso: 'ISO 160', capturedAt: '2026-07-12 18:48', source: 'confirmed' },
    reused: '原作机位、拍摄时间和光圈', adjusted: '焦段改为 85mm，快门提高到 1/4 秒', notes: '当天风比较大，提高快门后建筑轮廓更稳定。'
  }
];

const seedComments = {
  p1: [
    { id: 'c1', author: '阿澈', avatar: '澈', text: '参数和时间都很清楚，已经加入周末计划。' },
    { id: 'c2', author: '周野', avatar: '周', text: '跟着拍了一次，85mm 的画面也很有意思。' }
  ],
  a1: [{ id: 'c3', author: '林屿', avatar: '林', text: '构图更集中，月亮位置很好。下次可以再提前一点到，保留更多天空层次。' }]
};

function initialState() {
  return {
    posts: seedPosts,
    comments: seedComments,
    likes: [],
    favorites: [],
    plans: ['p1', 'p2'],
    follows: [],
    currentUser: { id: 'me', name: '小野同学', avatar: '野', city: '上海', bio: '用镜头记录城市光线' }
  };
}

function loadState() {
  try {
    const saved = JSON.parse(localStorage.getItem(STORAGE_KEY));
    if (saved?.posts && saved?.currentUser) return saved;
  } catch (error) {
    console.warn('Unable to load saved state', error);
  }
  return initialState();
}

let state = loadState();
let searchQuery = '';
let selectedMapPostId = 'p1';
let toastTimer;
let uploadDraft = null;

const main = document.querySelector('#main-content');
const backButton = document.querySelector('#back-button');
const pageTitle = document.querySelector('#page-title');
const pageSubtitle = document.querySelector('#page-subtitle');
const searchPanel = document.querySelector('#search-panel');
const searchInput = document.querySelector('#search-input');
const navLinks = [...document.querySelectorAll('[data-nav]')];

const titles = {
  home: ['光迹', 'LUMEN FIELD NOTES'], map: ['地图找机位', 'DISCOVER LOCATIONS'], publish: ['发布作品', 'NEW PHOTOGRAPH'],
  plans: ['拍摄计划', 'YOUR SHOOTING LIST'], profile: ['我的', 'PHOTOGRAPHER PROFILE'], detail: ['作品详情', 'ORIGINAL WORK'],
  submit: ['提交作业', 'REMAKE SUBMISSION'], compare: ['原作与作业', 'SIDE BY SIDE']
};

function saveState() {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(state));
  } catch (error) {
    showToast('本地空间不足，图片未能持久保存');
    console.warn('Unable to persist state', error);
  }
}

function escapeHtml(value = '') {
  return String(value).replace(/[&<>'"]/g, character => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' })[character]);
}

function icon(name) {
  const paths = {
    heart: '<path d="M20.8 4.6a5.5 5.5 0 0 0-7.8 0L12 5.6l-1-1a5.5 5.5 0 0 0-7.8 7.8l1 1L12 21l7.8-7.6 1-1a5.5 5.5 0 0 0 0-7.8Z"/>',
    message: '<path d="M21 15a4 4 0 0 1-4 4H8l-5 3V7a4 4 0 0 1 4-4h10a4 4 0 0 1 4 4Z"/>',
    bookmark: '<path d="M6 3h12a1 1 0 0 1 1 1v17l-7-4-7 4V4a1 1 0 0 1 1-1Z"/>',
    camera: '<path d="M14.5 4 16 7h4a1 1 0 0 1 1 1v11a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V8a1 1 0 0 1 1-1h4l1.5-3Z"/><circle cx="12" cy="13" r="4"/>',
    navigation: '<path d="m3 11 19-9-9 19-2-8Z"/>',
    upload: '<path d="M12 16V4m-5 5 5-5 5 5M5 20h14"/>',
    check: '<path d="m5 12 4 4L19 6"/>',
    image: '<rect x="3" y="3" width="18" height="18" rx="2"/><circle cx="8.5" cy="8.5" r="1.5"/><path d="m21 15-5-5L5 21"/>',
    map: '<path d="m9 18-6 3V6l6-3 6 3 6-3v15l-6 3Z"/><path d="M9 3v15m6-12v15"/>',
    trash: '<path d="M3 6h18M8 6V4h8v2m3 0-1 15H6L5 6m5 4v7m4-7v7"/>'
  };
  return `<svg viewBox="0 0 24 24" aria-hidden="true">${paths[name] || ''}</svg>`;
}

function showToast(message) {
  const toast = document.querySelector('#toast');
  toast.textContent = message;
  toast.classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => toast.classList.remove('show'), 2200);
}

function getRoute() {
  const value = location.hash.replace(/^#/, '') || 'home';
  const [name, id] = value.split('/');
  return { name, id };
}

function postById(id) { return state.posts.find(post => post.id === id); }
function assignmentsFor(originalId) { return state.posts.filter(post => post.type === 'assignment' && post.originalId === originalId); }
function isLiked(id) { return state.likes.includes(id); }
function isPlanned(id) { return state.plans.includes(id); }

function metadataStrip(metadata = {}) {
  return [metadata.focal, metadata.aperture, metadata.shutter, metadata.iso].filter(Boolean).map(item => `<span>${escapeHtml(item)}</span>`).join('');
}

function timeLabel(dateValue) {
  const date = new Date(dateValue);
  const days = Math.floor((Date.now() - date.getTime()) / 86400000);
  if (days <= 0) return '今天';
  if (days === 1) return '昨天';
  if (days < 7) return `${days} 天前`;
  return date.toLocaleDateString('zh-CN', { month: '2-digit', day: '2-digit' });
}

function renderFeedCard(post, index) {
  const assignments = post.type === 'original' ? assignmentsFor(post.id) : [];
  const original = post.type === 'assignment' ? postById(post.originalId) : null;
  const targetHash = post.type === 'assignment' ? `#compare/${post.id}` : `#detail/${post.id}`;
  return `
    <article class="feed-card">
      <div class="author-row">
        <span class="avatar">${escapeHtml(post.avatar)}</span>
        <div class="grow"><div class="name">${escapeHtml(post.author)}</div><div class="small muted">${escapeHtml(post.city)} · ${timeLabel(post.createdAt)}</div></div>
        ${post.recommended ? '<span class="badge">原作者推荐</span>' : `<button class="text-button" data-follow="${escapeHtml(post.authorId)}">${state.follows.includes(post.authorId) ? '已关注' : '关注'}</button>`}
      </div>
      <a class="photo-frame feed" href="${targetHash}">
        <img src="${escapeHtml(post.image)}" alt="${escapeHtml(post.title)}">
        <span class="photo-index">${post.type === 'assignment' ? 'REMAKE' : 'FIELD NOTE'} · ${String(index + 1).padStart(2, '0')}</span>
        <div class="photo-overlay"><h2>${escapeHtml(post.title)}</h2><p>${escapeHtml(post.location?.name || post.city)} · ${post.type === 'original' ? `${assignments.length} REMAKES` : `FROM ${escapeHtml(original?.title || 'ORIGINAL')}`}</p></div>
      </a>
      <div class="feed-copy">
        <span class="eyebrow">${post.type === 'assignment' ? 'REMAKE STUDY' : 'SHOOTING NOTE'}</span>
        <p>${escapeHtml(post.description)}</p>
        <div class="meta-strip">${metadataStrip(post.metadata)}</div>
      </div>
      <div class="action-row">
        <button class="text-button ${isLiked(post.id) ? 'is-planned' : ''}" data-like="${post.id}">${icon('heart')} ${post.likes + (isLiked(post.id) ? 1 : 0)}</button>
        <a class="text-button" href="${targetHash}">${icon('message')} ${(state.comments[post.id] || []).length}</a>
        ${post.type === 'original' ? `<button class="text-button ${isPlanned(post.id) ? 'is-planned' : ''}" data-plan="${post.id}">${icon('bookmark')} ${isPlanned(post.id) ? '已在计划' : '待复刻'}</button>` : `<a class="text-button" href="#detail/${post.originalId}">查看原作</a>`}
      </div>
    </article>`;
}

function renderHome() {
  const query = searchQuery.trim().toLowerCase();
  const posts = state.posts.filter(post => !query || [post.title, post.description, post.city, post.location?.name, post.author, ...(post.tags || [])].join(' ').toLowerCase().includes(query));
  main.innerHTML = `<div class="page">
    <div class="segmented"><button class="active">推荐</button><button>关注</button><button>附近</button></div>
    <div id="feed-list">${posts.length ? posts.map(renderFeedCard).join('') : `<div class="empty-state"><div>${icon('image')}<h2>没有找到相关作品</h2><p class="muted">换一个关键词试试</p></div></div>`}</div>
  </div>`;
}

function renderRecipe(metadata = {}) {
  const items = [
    ['相机', metadata.camera], ['镜头', metadata.lens], ['焦段', metadata.focal],
    ['光圈', metadata.aperture], ['快门', metadata.shutter], ['感光度', metadata.iso]
  ];
  return items.filter(([, value]) => value).map(([label, value]) => `<div class="recipe-item"><span>${label}</span><strong>${escapeHtml(value)}</strong></div>`).join('');
}

function renderComments(postId) {
  const comments = state.comments[postId] || [];
  return `<div class="comments">${comments.map(comment => `<div class="comment-row"><span class="avatar">${escapeHtml(comment.avatar)}</span><div><strong class="small">${escapeHtml(comment.author)}</strong><p class="small">${escapeHtml(comment.text)}</p></div></div>`).join('') || '<p class="small muted">还没有评论，来留下第一条建议。</p>'}</div>
    <form class="comment-form" data-comment-form="${postId}"><input name="comment" maxlength="180" placeholder="友善、具体地交流拍摄经验" required><button class="primary-button" type="submit">发送</button></form>`;
}

function renderDetail(id) {
  const post = postById(id);
  if (!post) return renderNotFound();
  if (post.type === 'assignment') { location.hash = `compare/${post.id}`; return; }
  const assignments = assignmentsFor(post.id);
  main.innerHTML = `<article class="page">
    <div class="photo-frame detail"><img src="${escapeHtml(post.image)}" alt="${escapeHtml(post.title)}"><span class="photo-index">ORIGINAL · ${escapeHtml(post.id.toUpperCase())}</span><div class="photo-overlay"><h2>${escapeHtml(post.title)}</h2><p>${escapeHtml(post.author)} · ${new Date(post.createdAt).toLocaleDateString('zh-CN')}</p></div></div>
    <section class="section">
      <div class="author-row" style="padding:0"><span class="avatar">${escapeHtml(post.avatar)}</span><div class="grow"><div class="name">${escapeHtml(post.author)}</div><div class="small muted">${escapeHtml(post.city)} · 摄影爱好者</div></div><button class="secondary-button" data-follow="${post.authorId}">${state.follows.includes(post.authorId) ? '已关注' : '关注'}</button></div>
      <p style="margin-top:16px;line-height:1.7">${escapeHtml(post.description)}</p>
    </section>
    <section class="section"><div class="section-head"><h3>拍摄配方</h3><span class="badge">${post.metadata?.source === 'manual' ? '手动填写' : 'EXIF 已确认'}</span></div><div class="recipe-grid">${renderRecipe(post.metadata)}</div></section>
    <section class="section"><div class="section-head"><h3>拍摄思路</h3></div><p class="small" style="line-height:1.7">${escapeHtml(post.shootingNotes || '作者暂未补充拍摄思路。')}</p>${post.editingNotes ? `<p class="small muted" style="line-height:1.7"><strong>后期：</strong>${escapeHtml(post.editingNotes)}</p>` : ''}</section>
    <section class="section"><div class="location-box"><div><strong>${escapeHtml(post.location?.name || '未公开地点')}</strong><div class="small muted">${post.location?.privacy === 'exact' ? '精确机位' : post.location?.privacy === 'approximate' ? '模糊区域' : '地点不公开'}${post.location?.advice ? ` · ${escapeHtml(post.location.advice)}` : ''}</div></div>${post.location?.privacy !== 'private' ? `<button class="secondary-button" data-open-map="${post.id}">${icon('navigation')}地图</button>` : ''}</div></section>
    <section class="section"><div class="section-head"><h3>复刻作业</h3><span class="small muted">${assignments.length} 份</span></div>${assignments.length ? assignments.map(item => `<a class="assignment-link" href="#compare/${item.id}"><span class="thumb"><img src="${escapeHtml(item.image)}" alt="${escapeHtml(item.title)}"></span><span class="grow"><strong>${escapeHtml(item.author)}的作业</strong><span class="small muted" style="display:block">${item.recommended ? '原作者推荐 · ' : ''}${escapeHtml(item.adjusted || '查看参数对比')}</span></span></a>`).join('') : '<p class="small muted">还没有人提交作业，成为第一个复刻者。</p>'}</section>
    <section class="section"><div class="section-head"><h3>评论</h3><span class="small muted">${(state.comments[post.id] || []).length} 条</span></div>${renderComments(post.id)}</section>
    <div class="detail-actions"><button class="secondary-button ${isPlanned(post.id) ? 'is-planned' : ''}" data-plan="${post.id}">${icon('bookmark')}${isPlanned(post.id) ? '已加入计划' : '加入计划'}</button><a class="primary-button" href="#submit/${post.id}">${icon('camera')}交作业</a></div>
  </article>`;
}

function renderMap() {
  const locations = state.posts.filter(post => post.type === 'original' && post.location?.privacy !== 'private').slice(0, 3);
  const selected = postById(selectedMapPostId) || locations[0];
  main.innerHTML = `<div class="page"><div class="map-stage" aria-label="机位地图示意">
    <label class="search-box map-search">${icon('map')}<input type="search" placeholder="搜索城市、地点或机位" aria-label="搜索地图"></label>
    ${locations.map((post, index) => `<button class="map-pin ${['one','two','three'][index]}" data-map-pin="${post.id}" aria-label="${escapeHtml(post.location.name)}"><span>${assignmentsFor(post.id).length + 1}</span></button>`).join('')}
    ${selected ? `<div class="map-card"><span class="thumb"><img src="${escapeHtml(selected.image)}" alt=""></span><div class="grow"><strong>${escapeHtml(selected.location.name)}</strong><div class="small muted">${escapeHtml(selected.location.city)} · ${selected.location.privacy === 'exact' ? '精确机位' : '模糊区域'}</div></div><a class="secondary-button" href="#detail/${selected.id}">查看</a></div>` : ''}
  </div></div>`;
}

function uploadMarkup(isAssignment = false) {
  return `<div class="upload-zone" id="upload-zone"><input id="photo-input" type="file" accept="image/jpeg,image/png,image/webp,image/heic"><div class="upload-prompt">${icon('upload')}<strong>${isAssignment ? '上传你的拍摄成果' : '选择一张满意的照片'}</strong><span class="small muted">JPEG 可自动读取拍摄参数</span><label class="primary-button" for="photo-input">选择照片</label></div></div>`;
}

function formFields(isAssignment = false, original = null) {
  if (isAssignment) {
    return `<div class="field"><label for="reused">我沿用了</label><input id="reused" name="reused" placeholder="例如：机位、拍摄时间、光圈"></div>
      <div class="field"><label for="adjusted">我做了调整</label><input id="adjusted" name="adjusted" placeholder="例如：焦段改为 85mm"></div>
      <div class="field"><label for="notes">拍摄心得</label><textarea id="notes" name="notes" placeholder="这次遇到了什么问题？有什么新的发现？"></textarea></div>`;
  }
  return `<div class="field"><label for="title">作品标题</label><input id="title" name="title" maxlength="40" placeholder="给作品起个名字" required></div>
    <div class="field"><label for="description">作品说明</label><textarea id="description" name="description" maxlength="1000" placeholder="这张照片背后的故事"></textarea></div>
    <div class="field"><label for="shooting-notes">拍摄思路</label><textarea id="shooting-notes" name="shootingNotes" maxlength="1000" placeholder="机位、构图、光线和现场经验"></textarea></div>
    <div class="field"><label for="editing-notes">后期说明</label><textarea id="editing-notes" name="editingNotes" maxlength="500" placeholder="可选：软件、调色或裁切思路"></textarea></div>`;
}

function metadataFields() {
  return `<div class="form-note" id="exif-status">上传照片后，系统会自动读取可用 EXIF；所有结果都可以修改。</div>
    <div class="form-grid">
      <div class="field"><label for="camera">相机</label><input id="camera" name="camera" placeholder="未识别，可手动填写"></div>
      <div class="field"><label for="lens">镜头</label><input id="lens" name="lens" placeholder="未识别，可手动填写"></div>
      <div class="field"><label for="focal">焦段</label><input id="focal" name="focal" placeholder="例如 50 mm"></div>
      <div class="field"><label for="aperture">光圈</label><input id="aperture" name="aperture" placeholder="例如 f/2.8"></div>
      <div class="field"><label for="shutter">快门</label><input id="shutter" name="shutter" placeholder="例如 1/125 s"></div>
      <div class="field"><label for="iso">ISO</label><input id="iso" name="iso" placeholder="例如 ISO 400"></div>
    </div>`;
}

function locationFields(original = null) {
  return `<div class="field"><label for="location-name">拍摄地点</label><input id="location-name" name="locationName" value="${escapeHtml(original?.location?.name || '')}" placeholder="地点名称"></div>
    <div class="field"><label for="location-privacy">地点公开范围</label><select id="location-privacy" name="locationPrivacy"><option value="exact">精确地点</option><option value="approximate">模糊区域</option><option value="private">不公开</option></select></div>`;
}

function renderPublish(originalId = null) {
  const isAssignment = Boolean(originalId);
  const original = originalId ? postById(originalId) : null;
  if (isAssignment && !original) return renderNotFound();
  uploadDraft = null;
  main.innerHTML = `<form class="page form-page" id="publish-form" data-assignment="${isAssignment}" data-original-id="${escapeHtml(originalId || '')}">
    <div class="progress"><span class="done"></span><span></span><span></span></div>
    ${isAssignment ? `<section class="section"><div class="section-head"><div><span class="eyebrow">REMAKE OF</span><h2>${escapeHtml(original.title)}</h2></div><span class="badge">已关联</span></div></section>` : ''}
    ${uploadMarkup(isAssignment)}
    <div class="form-stack">
      ${formFields(isAssignment, original)}
      <div class="section-head" style="margin:4px 0 0"><h3>拍摄参数</h3><span class="badge">可修改</span></div>
      ${metadataFields()}
      <div class="section-head" style="margin:4px 0 0"><h3>地点与权限</h3></div>
      ${locationFields(original)}
      ${!isAssignment ? '<label class="switch-row"><span><strong class="small">允许他人复刻</strong><span class="small muted" style="display:block">作品会显示“交作业”入口</span></span><input name="allowRemake" type="checkbox" checked></label>' : ''}
    </div>
    <div class="form-actions"><button class="secondary-button" type="button" data-save-draft>保存草稿</button><button class="primary-button accent" type="submit">${isAssignment ? '发布作业' : '发布作品'}</button></div>
  </form>`;
  wirePublishForm();
}

function renderPlans() {
  const posts = state.plans.map(postById).filter(Boolean);
  main.innerHTML = `<div class="page"><div class="segmented"><button class="active">待拍摄 ${posts.length}</button><button>已交作业 ${state.posts.filter(post => post.type === 'assignment' && post.authorId === 'me').length}</button><button>收藏 ${state.favorites.length}</button></div>
    ${posts.length ? `<div class="plan-list">${posts.map(post => `<article class="plan-item"><a class="thumb" href="#detail/${post.id}"><img src="${escapeHtml(post.image)}" alt="${escapeHtml(post.title)}"></a><div class="plan-copy"><h3>${escapeHtml(post.title)}</h3><p class="small muted">${escapeHtml(post.location?.name || '地点未公开')}</p><p class="small">${escapeHtml(post.location?.advice || '查看原作拍摄建议')}</p></div><div><span class="badge">待拍摄</span><a class="primary-button" style="margin-top:8px" href="#submit/${post.id}">交作业</a></div></article>`).join('')}</div>` : `<div class="empty-state"><div>${icon('bookmark')}<h2>还没有拍摄计划</h2><p class="muted">从作品详情加入一个想复刻的作品</p><a class="primary-button" href="#home">去发现作品</a></div></div>`}
  </div>`;
}

function renderProfile() {
  const mine = state.posts.filter(post => post.authorId === 'me');
  const originals = mine.filter(post => post.type === 'original');
  const assignments = mine.filter(post => post.type === 'assignment');
  main.innerHTML = `<div class="page"><section class="profile-hero"><span class="avatar large">${escapeHtml(state.currentUser.avatar)}</span><h2>${escapeHtml(state.currentUser.name)}</h2><p class="small muted">${escapeHtml(state.currentUser.city)} · ${escapeHtml(state.currentUser.bio)}</p><div class="profile-stats"><div><strong>${originals.length}</strong><span class="small muted">作品</span></div><div><strong>${assignments.length}</strong><span class="small muted">作业</span></div><div><strong>${mine.reduce((sum, post) => sum + post.likes, 0)}</strong><span class="small muted">获赞</span></div></div></section>
    <div class="segmented"><button class="active">作品</button><button>作业</button><button>收藏</button></div>
    ${mine.length ? `<div class="profile-grid">${mine.map(post => `<button data-open-post="${post.id}" aria-label="${escapeHtml(post.title)}"><img src="${escapeHtml(post.image)}" alt=""></button>`).join('')}</div>` : `<div class="empty-state"><div>${icon('camera')}<h2>发布第一张作品</h2><p class="muted">分享拍摄参数和你的创作经验</p><a class="primary-button" href="#publish">开始发布</a></div></div>`}
    <section class="section"><button class="text-button" data-reset-demo>${icon('trash')}恢复初始演示数据</button></section></div>`;
}

function renderCompare(assignmentId) {
  const assignment = postById(assignmentId);
  const original = assignment && postById(assignment.originalId);
  if (!assignment || !original) return renderNotFound();
  main.innerHTML = `<article class="page"><div class="compare-grid"><figure><img src="${escapeHtml(original.image)}" alt="原作：${escapeHtml(original.title)}"><figcaption><strong>原作 · ${escapeHtml(original.author)}</strong><div class="muted">${metadataStrip(original.metadata)}</div></figcaption></figure><figure><img src="${escapeHtml(assignment.image)}" alt="作业：${escapeHtml(assignment.title)}"><figcaption><strong>作业 · ${escapeHtml(assignment.author)}</strong><div class="muted">${metadataStrip(assignment.metadata)}</div></figcaption></figure></div>
    <section class="section"><div class="section-head"><h3>这次的调整</h3>${assignment.recommended ? '<span class="badge">原作者推荐</span>' : ''}</div><p class="small"><strong>沿用：</strong>${escapeHtml(assignment.reused || '未填写')}</p><p class="small"><strong>调整：</strong>${escapeHtml(assignment.adjusted || '未填写')}</p><p class="small muted" style="line-height:1.7">${escapeHtml(assignment.notes || assignment.description)}</p></section>
    <section class="section"><div class="section-head"><h3>参数对比</h3></div><div class="recipe-grid">${renderRecipe(assignment.metadata)}</div></section>
    <section class="section"><div class="section-head"><h3>评论</h3><span class="small muted">${(state.comments[assignment.id] || []).length} 条</span></div>${renderComments(assignment.id)}</section>
    <div class="detail-actions"><a class="secondary-button" href="#detail/${original.id}">查看原作</a><a class="primary-button" href="#submit/${original.id}">${icon('camera')}我也来拍</a></div></article>`;
}

function renderNotFound() {
  main.innerHTML = `<div class="empty-state"><div><h2>内容不存在</h2><p class="muted">它可能已被删除或暂时不可见</p><a class="primary-button" href="#home">返回首页</a></div></div>`;
}

function render() {
  const route = getRoute();
  const config = titles[route.name] || titles.home;
  pageTitle.textContent = config[0];
  pageSubtitle.textContent = config[1];
  backButton.hidden = ['home', 'map', 'publish', 'plans', 'profile'].includes(route.name);
  navLinks.forEach(link => link.classList.toggle('active', link.dataset.nav === route.name));
  searchPanel.hidden = true;

  if (route.name === 'home') renderHome();
  else if (route.name === 'detail') renderDetail(route.id);
  else if (route.name === 'map') renderMap();
  else if (route.name === 'publish') renderPublish();
  else if (route.name === 'submit') renderPublish(route.id);
  else if (route.name === 'plans') renderPlans();
  else if (route.name === 'profile') renderProfile();
  else if (route.name === 'compare') renderCompare(route.id);
  else renderNotFound();
  window.scrollTo({ top: 0, behavior: 'instant' });
  main.focus({ preventScroll: true });
}

function fraction(value) {
  if (!Number.isFinite(value) || value <= 0) return '';
  if (value >= 1) return `${Number(value.toFixed(1))} s`;
  return `1/${Math.round(1 / value)} s`;
}

function extractExif(arrayBuffer) {
  try {
    const view = new DataView(arrayBuffer);
    if (view.getUint16(0, false) !== 0xffd8) return {};
    let offset = 2;
    while (offset + 4 < view.byteLength) {
      if (view.getUint8(offset) !== 0xff) break;
      const marker = view.getUint8(offset + 1);
      const length = view.getUint16(offset + 2, false);
      if (marker === 0xe1 && offset + 10 < view.byteLength && view.getUint32(offset + 4, false) === 0x45786966) {
        return parseTiff(view, offset + 10);
      }
      offset += 2 + length;
    }
  } catch (error) {
    console.warn('EXIF parse failed', error);
  }
  return {};
}

function parseTiff(view, tiffStart) {
  const little = view.getUint16(tiffStart, false) === 0x4949;
  const get16 = offset => view.getUint16(offset, little);
  const get32 = offset => view.getUint32(offset, little);
  const typeSizes = { 1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 7: 1, 9: 4, 10: 8 };

  function readValue(entry, type, count) {
    const size = (typeSizes[type] || 1) * count;
    const valueOffset = size <= 4 ? entry + 8 : tiffStart + get32(entry + 8);
    if (valueOffset < 0 || valueOffset + size > view.byteLength) return null;
    if (type === 2) {
      let text = '';
      for (let i = 0; i < count - 1; i++) text += String.fromCharCode(view.getUint8(valueOffset + i));
      return text.trim();
    }
    if (type === 3) return count === 1 ? get16(valueOffset) : Array.from({ length: count }, (_, i) => get16(valueOffset + i * 2));
    if (type === 4) return count === 1 ? get32(valueOffset) : Array.from({ length: count }, (_, i) => get32(valueOffset + i * 4));
    if (type === 5) {
      const values = Array.from({ length: count }, (_, i) => {
        const numerator = get32(valueOffset + i * 8);
        const denominator = get32(valueOffset + i * 8 + 4);
        return denominator ? numerator / denominator : 0;
      });
      return count === 1 ? values[0] : values;
    }
    if (type === 10) {
      const numerator = view.getInt32(valueOffset, little);
      const denominator = view.getInt32(valueOffset + 4, little);
      return denominator ? numerator / denominator : 0;
    }
    return view.getUint8(valueOffset);
  }

  function readIfd(ifdOffset) {
    const result = {};
    const absolute = tiffStart + ifdOffset;
    if (absolute + 2 > view.byteLength) return result;
    const count = get16(absolute);
    for (let i = 0; i < count; i++) {
      const entry = absolute + 2 + i * 12;
      if (entry + 12 > view.byteLength) break;
      const tag = get16(entry);
      const type = get16(entry + 2);
      const itemCount = get32(entry + 4);
      result[tag] = readValue(entry, type, itemCount);
    }
    return result;
  }

  const ifd0 = readIfd(get32(tiffStart + 4));
  const exif = ifd0[0x8769] ? readIfd(ifd0[0x8769]) : {};
  const gps = ifd0[0x8825] ? readIfd(ifd0[0x8825]) : {};
  const latitude = gps[2] && Array.isArray(gps[2]) ? gps[2][0] + gps[2][1] / 60 + gps[2][2] / 3600 : null;
  const longitude = gps[4] && Array.isArray(gps[4]) ? gps[4][0] + gps[4][1] / 60 + gps[4][2] / 3600 : null;
  return {
    make: ifd0[0x010f] || '', model: ifd0[0x0110] || '', camera: [ifd0[0x010f], ifd0[0x0110]].filter(Boolean).join(' '),
    lens: exif[0xa434] || '', focal: exif[0x920a] ? `${Number(exif[0x920a].toFixed(1))} mm` : '',
    aperture: exif[0x829d] ? `f/${Number(exif[0x829d].toFixed(1))}` : '', shutter: exif[0x829a] ? fraction(exif[0x829a]) : '',
    iso: exif[0x8827] ? `ISO ${exif[0x8827]}` : '', capturedAt: exif[0x9003] || '',
    lat: latitude ? (gps[1] === 'S' ? -latitude : latitude) : null, lng: longitude ? (gps[3] === 'W' ? -longitude : longitude) : null
  };
}

function compressImage(file, maxSize = 1600, quality = .82) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onerror = () => reject(reader.error);
    reader.onload = () => {
      const image = new Image();
      image.onerror = () => reject(new Error('图片无法读取'));
      image.onload = () => {
        const scale = Math.min(1, maxSize / Math.max(image.naturalWidth, image.naturalHeight));
        const canvas = document.createElement('canvas');
        canvas.width = Math.round(image.naturalWidth * scale);
        canvas.height = Math.round(image.naturalHeight * scale);
        canvas.getContext('2d').drawImage(image, 0, 0, canvas.width, canvas.height);
        resolve(canvas.toDataURL('image/jpeg', quality));
      };
      image.src = reader.result;
    };
    reader.readAsDataURL(file);
  });
}

async function handlePhotoFile(file) {
  if (!file) return;
  if (file.size > 30 * 1024 * 1024) { showToast('图片不能超过 30 MB'); return; }
  try {
    const [buffer, dataUrl] = await Promise.all([file.arrayBuffer(), compressImage(file)]);
    const exif = file.type === 'image/jpeg' ? extractExif(buffer) : {};
    uploadDraft = { dataUrl, exif };
    const zone = document.querySelector('#upload-zone');
    zone.classList.add('has-image');
    zone.innerHTML = `<img src="${dataUrl}" alt="上传预览"><input id="photo-input" type="file" accept="image/jpeg,image/png,image/webp,image/heic"><label class="secondary-button replace-image" for="photo-input">更换照片</label>`;
    zone.querySelector('#photo-input').addEventListener('change', event => handlePhotoFile(event.target.files[0]));
    const keys = ['camera', 'lens', 'focal', 'aperture', 'shutter', 'iso'];
    keys.forEach(key => { const input = document.querySelector(`[name="${key}"]`); if (input && exif[key]) input.value = exif[key]; });
    const status = document.querySelector('#exif-status');
    const count = keys.filter(key => exif[key]).length;
    status.textContent = count ? `已从照片识别 ${count} 项参数，请确认是否准确。${exif.lat ? '检测到 GPS，地点仍需由你确认公开范围。' : ''}` : '照片中没有可用 EXIF，请手动补充需要分享的参数。';
    document.querySelectorAll('.progress span')[1]?.classList.add('done');
    showToast(count ? `已识别 ${count} 项拍摄参数` : '未识别到 EXIF，可手动填写');
  } catch (error) {
    showToast(error.message || '图片读取失败');
  }
}

function wirePublishForm() {
  const form = document.querySelector('#publish-form');
  const input = form.querySelector('#photo-input');
  input.addEventListener('change', event => handlePhotoFile(event.target.files[0]));
  form.querySelector('[data-save-draft]').addEventListener('click', () => showToast('草稿已暂存于当前页面'));
  form.addEventListener('submit', event => {
    event.preventDefault();
    if (!uploadDraft?.dataUrl) { showToast('请先选择照片'); return; }
    const data = new FormData(form);
    const isAssignment = form.dataset.assignment === 'true';
    const original = isAssignment ? postById(form.dataset.originalId) : null;
    const metadata = {
      camera: data.get('camera'), lens: data.get('lens'), focal: data.get('focal'), aperture: data.get('aperture'),
      shutter: data.get('shutter'), iso: data.get('iso'), capturedAt: uploadDraft.exif.capturedAt || '',
      source: Object.keys(uploadDraft.exif).some(key => uploadDraft.exif[key]) ? 'confirmed' : 'manual'
    };
    const id = `${isAssignment ? 'a' : 'p'}${Date.now()}`;
    const post = isAssignment ? {
      id, type: 'assignment', originalId: original.id, author: state.currentUser.name, authorId: 'me', city: state.currentUser.city, avatar: state.currentUser.avatar,
      title: `${original.title} · 复刻作业`, description: data.get('notes') || '完成了一次复刻练习。', image: uploadDraft.dataUrl, createdAt: new Date().toISOString(), likes: 0,
      location: { name: data.get('locationName') || original.location?.name || '地点未公开', city: original.location?.city || state.currentUser.city, privacy: data.get('locationPrivacy') },
      metadata, reused: data.get('reused'), adjusted: data.get('adjusted'), notes: data.get('notes'), recommended: false
    } : {
      id, type: 'original', author: state.currentUser.name, authorId: 'me', city: state.currentUser.city, avatar: state.currentUser.avatar,
      title: data.get('title'), description: data.get('description') || '分享一张新的摄影作品。', image: uploadDraft.dataUrl, createdAt: new Date().toISOString(), likes: 0,
      tags: [], allowRemake: data.get('allowRemake') === 'on',
      location: { name: data.get('locationName') || '地点未公开', city: state.currentUser.city, privacy: data.get('locationPrivacy'), lat: uploadDraft.exif.lat, lng: uploadDraft.exif.lng },
      metadata, shootingNotes: data.get('shootingNotes'), editingNotes: data.get('editingNotes')
    };
    state.posts.unshift(post);
    state.comments[id] = [];
    if (isAssignment && !state.plans.includes(original.id)) state.plans.push(original.id);
    saveState();
    document.querySelectorAll('.progress span').forEach(item => item.classList.add('done'));
    showToast(isAssignment ? '作业发布成功，已关联原作' : '作品发布成功');
    setTimeout(() => { location.hash = isAssignment ? `compare/${id}` : `detail/${id}`; }, 450);
  });
}

document.addEventListener('click', event => {
  const like = event.target.closest('[data-like]');
  if (like) {
    const id = like.dataset.like;
    state.likes = isLiked(id) ? state.likes.filter(item => item !== id) : [...state.likes, id];
    saveState(); render(); return;
  }
  const plan = event.target.closest('[data-plan]');
  if (plan) {
    const id = plan.dataset.plan;
    state.plans = isPlanned(id) ? state.plans.filter(item => item !== id) : [...state.plans, id];
    saveState(); showToast(isPlanned(id) ? '已加入拍摄计划' : '已从计划移除'); render(); return;
  }
  const follow = event.target.closest('[data-follow]');
  if (follow) {
    const id = follow.dataset.follow;
    state.follows = state.follows.includes(id) ? state.follows.filter(item => item !== id) : [...state.follows, id];
    saveState(); render(); return;
  }
  const mapPin = event.target.closest('[data-map-pin]');
  if (mapPin) { selectedMapPostId = mapPin.dataset.mapPin; renderMap(); return; }
  const mapOpen = event.target.closest('[data-open-map]');
  if (mapOpen) { selectedMapPostId = mapOpen.dataset.openMap; location.hash = 'map'; return; }
  const postButton = event.target.closest('[data-open-post]');
  if (postButton) {
    const post = postById(postButton.dataset.openPost);
    location.hash = post.type === 'assignment' ? `compare/${post.id}` : `detail/${post.id}`;
    return;
  }
  const reset = event.target.closest('[data-reset-demo]');
  if (reset && confirm('恢复初始演示数据？你发布的本地内容将被清除。')) {
    state = initialState(); saveState(); showToast('已恢复演示数据'); render();
  }
});

document.addEventListener('submit', event => {
  const form = event.target.closest('[data-comment-form]');
  if (!form) return;
  event.preventDefault();
  const data = new FormData(form);
  const text = String(data.get('comment') || '').trim();
  if (!text) return;
  const id = form.dataset.commentForm;
  state.comments[id] ||= [];
  state.comments[id].push({ id: `c${Date.now()}`, author: state.currentUser.name, avatar: state.currentUser.avatar, text });
  saveState(); showToast('评论已发布'); render();
});

document.querySelector('#search-button').addEventListener('click', () => {
  if (getRoute().name !== 'home') location.hash = 'home';
  searchPanel.hidden = !searchPanel.hidden;
  if (!searchPanel.hidden) setTimeout(() => searchInput.focus(), 0);
});
searchInput.addEventListener('input', event => { searchQuery = event.target.value; if (getRoute().name === 'home') renderHome(); });
backButton.addEventListener('click', () => history.length > 1 ? history.back() : location.assign('#home'));
window.addEventListener('hashchange', render);
render();
