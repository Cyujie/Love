const ROOM_THEMES = {
  warm: {
    title: '暖调舒适',
    intro: '用柔和光线、触感舒服的床品和少量绿植，营造放松的两人小空间。',
    tasks: [
      ['warm-light', '床头加一盏暖光灯，尽量选择可调亮度的灯泡'],
      ['soft-textile', '换上两人都喜欢的床品和柔软靠枕'],
      ['curtain', '按作息选择遮光窗帘或轻薄纱帘'],
      ['scent', '试试无火香薰或香薰机，先确认双方都喜欢气味'],
      ['plant', '在采光处放一盆好打理的绿植']
    ]
  },
  wood: {
    title: '原木简约',
    intro: '保留清爽动线，用木色、收纳和自然织物让房间更整洁耐看。',
    tasks: [
      ['wood-bedside', '用同色系床头柜或壁挂层板收纳小物'],
      ['neutral-textile', '选米白、浅灰或亚麻质感的床品'],
      ['warm-light', '增加一盏不刺眼的床头暖光灯'],
      ['plant', '选一盆适合房间光照条件的绿植'],
      ['storage', '用收纳盒整理充电线、书和日常用品']
    ]
  },
  memory: {
    title: '纪念展示',
    intro: '留一面小小的回忆墙，展示合照、旅行纪念物和一起完成的小目标。',
    tasks: [
      ['photo-wall', '挑 3 到 5 张合照，统一相框颜色后再上墙'],
      ['memory-shelf', '用一层小置物架展示旅行纪念物'],
      ['spot-light', '给照片或纪念角加一盏柔和的小灯'],
      ['wish-board', '留一块小白板，写下最近想一起完成的事'],
      ['rotation', '每隔一阵子一起更换展示内容']
    ]
  }
};

const ROOM_SIZE_IDEAS = {
  small: '小房间优先留出床边通道：考虑壁挂收纳、床下收纳和折叠边桌，避免挡住门窗。',
  medium: '普通卧室可以把床边照明、双人收纳和一个阅读角分成三个小区域。',
  large: '宽敞卧室可以增加双人阅读角或投影休闲区，同时保留清晰的进出动线。'
};

const ROOM_BUDGET_IDEAS = {
  low: '先从灯泡、枕套、相框和收纳盒等小件开始，慢慢调整。',
  medium: '先确定灯光与床品，再按需要添置窗帘、床头柜或展示架。',
  high: '可以分阶段升级床头照明、窗帘、收纳和休闲区，先量尺寸再购买。'
};

let roomPlan = { theme: 'warm', size: 'medium', budget: 'medium', checked: [] };
let locationSharing = false;
let locationUploadTimer = null;
let locationRefreshTimer = null;
let locationChannel = null;

function readRoomPlanForm() {
  return {
    theme: $('roomTheme').value,
    size: $('roomSize').value,
    budget: $('roomBudget').value,
    checked: Array.isArray(roomPlan.checked) ? roomPlan.checked : []
  };
}

function renderRoomPlan() {
  roomPlan = readRoomPlanForm();
  const theme = ROOM_THEMES[roomPlan.theme] || ROOM_THEMES.warm;
  const tasks = theme.tasks;
  $('roomPreview').innerHTML = `<strong>${escapeHtml(theme.title)} · ${escapeHtml({small:'小房间',medium:'普通卧室',large:'宽敞卧室'}[roomPlan.size]||'普通卧室')}</strong><br>${escapeHtml(theme.intro)}<br>${escapeHtml(ROOM_SIZE_IDEAS[roomPlan.size]||ROOM_SIZE_IDEAS.medium)}<br>${escapeHtml(ROOM_BUDGET_IDEAS[roomPlan.budget]||ROOM_BUDGET_IDEAS.medium)}`;
  $('roomChecklist').innerHTML = tasks.map(([id,label]) => `<label><input type="checkbox" data-room-task="${id}" ${roomPlan.checked.includes(id)?'checked':''}><span>${escapeHtml(label)}</span></label>`).join('');
}

async function loadRoomPlan() {
  if (!couple) return;
  const { data, error } = await coupleSupabaseClient.from('couple_room_plans').select('plan,updated_at').eq('couple_id', couple.id).maybeSingle();
  if (error) {
    $('roomPlanStatus').textContent = '共享方案暂时无法读取：' + error.message;
    return;
  }
  const saved = data?.plan || {};
  roomPlan = {
    theme: ROOM_THEMES[saved.theme] ? saved.theme : 'warm',
    size: ['small','medium','large'].includes(saved.size) ? saved.size : 'medium',
    budget: ['low','medium','high'].includes(saved.budget) ? saved.budget : 'medium',
    checked: Array.isArray(saved.checked) ? saved.checked.filter(x => typeof x === 'string') : []
  };
  $('roomTheme').value = roomPlan.theme;
  $('roomSize').value = roomPlan.size;
  $('roomBudget').value = roomPlan.budget;
  renderRoomPlan();
  $('roomPlanStatus').textContent = data?.updated_at ? `共同方案已同步 · ${new Date(data.updated_at).toLocaleString('zh-CN',{month:'numeric',day:'numeric',hour:'2-digit',minute:'2-digit'})}` : '选好想法后保存，另一半就能看到。';
}

$('roomTheme').addEventListener('change', () => { renderRoomPlan(); $('roomPlanStatus').textContent = '方案有更改，保存后会同步给另一半。'; });
$('roomSize').addEventListener('change', () => { renderRoomPlan(); $('roomPlanStatus').textContent = '方案有更改，保存后会同步给另一半。'; });
$('roomBudget').addEventListener('change', () => { renderRoomPlan(); $('roomPlanStatus').textContent = '方案有更改，保存后会同步给另一半。'; });
$('roomChecklist').addEventListener('change', event => {
  if (!event.target.matches('[data-room-task]')) return;
  const id = event.target.dataset.roomTask;
  roomPlan.checked = Array.from($('roomChecklist').querySelectorAll('[data-room-task]:checked'), input => input.dataset.roomTask);
  $('roomPlanStatus').textContent = '清单有更改，保存后会同步给另一半。';
});
$('roomPlanForm').addEventListener('submit', async event => {
  event.preventDefault();
  if (!couple || !user) { $('roomPlanStatus').textContent = '请先登录并配对，再保存共同方案。'; return; }
  const plan = readRoomPlanForm();
  const { error } = await coupleSupabaseClient.from('couple_room_plans').upsert({ couple_id: couple.id, plan, updated_by: user.id, updated_at: new Date().toISOString() }, { onConflict: 'couple_id' });
  if (error) { $('roomPlanStatus').textContent = '保存失败：' + error.message; return; }
  roomPlan = plan;
  $('roomPlanStatus').textContent = '已保存，另一半打开「共同生活」就能看到。';
});

function setLocationStatus(message, isError = false) {
  $('locationStatus').textContent = message;
  $('locationStatus').className = 'location-status' + (isError ? ' error' : '');
}

function locationErrorMessage(error) {
  if (error?.code === 1) return '浏览器未授权位置权限。可以在地址栏的站点权限里允许定位，再点一次开始共享。';
  if (error?.code === 2) return '暂时无法取得位置，请检查设备定位服务后重试。';
  if (error?.code === 3) return '定位超时了，稍后会再试一次。';
  return error?.message || '定位暂时不可用。';
}

function requestAndShareLocation(expectedUserId, expectedCoupleId) {
  if (!locationSharing || !navigator.geolocation) return;
  navigator.geolocation.getCurrentPosition(async position => {
    if (!locationSharing || !user || user.id !== expectedUserId || !couple || couple.id !== expectedCoupleId) return;
    const round = value => Math.round(value * 10000) / 10000;
    const payload = {
      user_id: expectedUserId,
      couple_id: expectedCoupleId,
      latitude: round(position.coords.latitude),
      longitude: round(position.coords.longitude),
      accuracy_m: Math.min(100000, Math.max(0, Math.round(position.coords.accuracy || 0))),
      updated_at: new Date().toISOString()
    };
    const { error } = await coupleSupabaseClient.from('couple_locations').upsert(payload, { onConflict: 'user_id' });
    if (error) { setLocationStatus('位置无法同步：' + error.message, true); return; }
    setLocationStatus('正在共享。网页打开期间约每 30 秒更新；停止后会删除当前坐标。');
    await loadSharedLocations();
  }, error => {
    if (error?.code === 1) {
      locationSharing = false;
      clearInterval(locationUploadTimer);
      locationUploadTimer = null;
    }
    setLocationStatus(locationErrorMessage(error), true);
  }, { enableHighAccuracy: true, maximumAge: 15000, timeout: 20000 });
}

async function startLocationSharing() {
  if (!user || !couple) { setLocationStatus('请先登录并配对，再开启位置共享。', true); return; }
  if (!$('locationConsent').checked) { setLocationStatus('请先勾选位置共享说明，确认后再开始。', true); return; }
  if (!navigator.geolocation) { setLocationStatus('当前浏览器不支持定位，请使用支持定位的浏览器并开启设备定位。', true); return; }
  if (locationSharing) return;
  locationSharing = true;
  setLocationStatus('正在请求浏览器定位权限…');
  const owner = user.id, pair = couple.id;
  requestAndShareLocation(owner, pair);
  clearInterval(locationUploadTimer);
  locationUploadTimer = setInterval(() => requestAndShareLocation(owner, pair), 30000);
}

async function stopLocationSharing(silent = false) {
  locationSharing = false;
  clearInterval(locationUploadTimer);
  locationUploadTimer = null;
  if (user && couple) {
    const { error } = await coupleSupabaseClient.from('couple_locations').delete().eq('user_id', user.id).eq('couple_id', couple.id);
    if (error && !silent) { setLocationStatus('停止失败：' + error.message, true); return; }
  }
  if (!silent) setLocationStatus('已停止共享，并删除了你的当前坐标。');
  await loadSharedLocations();
}

function formatLocationAge(updatedAt) {
  const seconds = Math.max(0, Math.floor((Date.now() - new Date(updatedAt).getTime()) / 1000));
  if (seconds < 30) return '刚刚更新';
  if (seconds < 60) return `${seconds} 秒前更新`;
  return `${Math.floor(seconds / 60)} 分钟前更新`;
}

async function loadSharedLocations() {
  if (!couple || !user) { $('sharedLocations').innerHTML = '<div class="empty">配对后可以查看彼此主动分享的最新位置。</div>'; return; }
  const coupleId = couple.id;
  const { data, error } = await coupleSupabaseClient.from('couple_locations').select('user_id,latitude,longitude,accuracy_m,updated_at').eq('couple_id', coupleId);
  if (error) { $('sharedLocations').innerHTML = `<div class="empty">位置暂时无法读取：${escapeHtml(error.message)}</div>`; return; }
  const fresh = (data || []).filter(row => Date.now() - new Date(row.updated_at).getTime() < 120000);
  if (!fresh.length) { $('sharedLocations').innerHTML = '<div class="empty">目前没有正在分享的位置。双方各自开启后，这里才会显示。</div>'; return; }
  $('sharedLocations').innerHTML = fresh.map(row => {
    const label = row.user_id === user.id ? '你的位置' : '另一半的位置';
    const lat = Number(row.latitude).toFixed(4), lon = Number(row.longitude).toFixed(4);
    const mapUrl = `https://www.openstreetmap.org/?mlat=${encodeURIComponent(lat)}&mlon=${encodeURIComponent(lon)}#map=16/${encodeURIComponent(lat)}/${encodeURIComponent(lon)}`;
    return `<div class="location-card"><strong>${label}</strong><small>${formatLocationAge(row.updated_at)} · 精度约 ${Math.round(row.accuracy_m)} 米</small><a class="location-link" href="${mapUrl}" target="_blank" rel="noopener noreferrer">在 OpenStreetMap 查看大致位置 ↗</a></div>`;
  }).join('');
}

function startLocationRefresh() {
  if (!couple) return;
  clearInterval(locationRefreshTimer);
  loadSharedLocations();
  locationRefreshTimer = setInterval(loadSharedLocations, 10000);
}

$('startLocation').addEventListener('click', startLocationSharing);
$('stopLocation').addEventListener('click', () => stopLocationSharing());
document.addEventListener('couple-space-ready', () => {
  loadRoomPlan();
  startLocationRefresh();
});
window.addEventListener('pagehide', () => {
  locationSharing = false;
  clearInterval(locationUploadTimer);
});
renderRoomPlan();
if (couple) { loadRoomPlan(); startLocationRefresh(); }
