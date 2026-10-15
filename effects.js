(() => {
  const storageKey = 'qingxu-click-effects';
  const defaults = { enabled: true, sound: 'chime', volume: 35 };
  let settings = { ...defaults };
  let audioContext;

  try {
    settings = { ...defaults, ...JSON.parse(localStorage.getItem(storageKey) || '{}') };
  } catch {}

  const toggle = document.getElementById('effectSettingsToggle');
  const panel = document.getElementById('effectSettingsPanel');
  const enabled = document.getElementById('effectEnabled');
  const sound = document.getElementById('effectSound');
  const volume = document.getElementById('effectVolume');
  const volumeValue = document.getElementById('effectVolumeValue');

  function saveSettings() {
    try { localStorage.setItem(storageKey, JSON.stringify(settings)); } catch {}
  }

  function syncControls() {
    enabled.checked = Boolean(settings.enabled);
    sound.value = settings.sound;
    volume.value = String(settings.volume);
    volumeValue.textContent = settings.volume + '%';
  }

  function spawnHeart(x, y) {
    const heart = document.createElement('span');
    heart.className = 'click-heart';
    heart.textContent = '💗';
    heart.style.left = x + 'px';
    heart.style.top = y + 'px';
    heart.style.setProperty('--heart-drift', (Math.random() * 56 - 28) + 'px');
    heart.style.setProperty('--heart-size', (24 + Math.random() * 14) + 'px');
    document.body.appendChild(heart);
    window.setTimeout(() => heart.remove(), 1100);
  }

  function tone(frequency, endFrequency, startAt, duration, wave, peak) {
    const oscillator = audioContext.createOscillator();
    const gain = audioContext.createGain();
    oscillator.type = wave;
    oscillator.frequency.setValueAtTime(frequency, startAt);
    if (endFrequency) oscillator.frequency.exponentialRampToValueAtTime(endFrequency, startAt + duration);
    gain.gain.setValueAtTime(0.0001, startAt);
    gain.gain.exponentialRampToValueAtTime(Math.max(0.0002, peak), startAt + 0.012);
    gain.gain.exponentialRampToValueAtTime(0.0001, startAt + duration);
    oscillator.connect(gain);
    gain.connect(audioContext.destination);
    oscillator.start(startAt);
    oscillator.stop(startAt + duration + 0.02);
  }

  async function playSound() {
    if (!settings.enabled || Number(settings.volume) <= 0) return;
    try {
      const AudioContextClass = window.AudioContext || window.webkitAudioContext;
      if (!AudioContextClass) return;
      audioContext ||= new AudioContextClass();
      if (audioContext.state === 'suspended') await audioContext.resume();
      const now = audioContext.currentTime;
      const loudness = Math.min(0.22, Number(settings.volume) / 100 * 0.22);
      if (settings.sound === 'heartbeat') {
        tone(210, 150, now, 0.11, 'sine', loudness);
        tone(185, 135, now + 0.13, 0.14, 'sine', loudness * 0.8);
      } else if (settings.sound === 'pop') {
        tone(620, 260, now, 0.12, 'triangle', loudness);
      } else {
        tone(880, 740, now, 0.20, 'sine', loudness);
        tone(1175, 980, now + 0.035, 0.22, 'sine', loudness * 0.48);
      }
    } catch {}
  }

  toggle.addEventListener('click', () => {
    panel.hidden = !panel.hidden;
    toggle.setAttribute('aria-expanded', String(!panel.hidden));
  });

  enabled.addEventListener('change', () => {
    settings.enabled = enabled.checked;
    saveSettings();
  });
  sound.addEventListener('change', () => {
    settings.sound = sound.value;
    saveSettings();
  });
  volume.addEventListener('input', () => {
    settings.volume = Number(volume.value);
    volumeValue.textContent = settings.volume + '%';
    saveSettings();
  });

  document.addEventListener('click', event => {
    if (!event.isTrusted || !(event.target instanceof Element)) return;
    spawnHeart(event.clientX, event.clientY);
    playSound();
  });

  syncControls();
})();


