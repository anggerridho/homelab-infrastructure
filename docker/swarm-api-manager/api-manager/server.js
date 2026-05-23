const express = require('express');
const { exec } = require('child_process');
const fs = require('fs'); 
const path = require('path');

const PORT = process.env.PORT || 3000;
const API_KEY = process.env.API_KEY;
// Hapus AUTO_STOP_MINUTES dari sini karena sudah dinamis di dalam endpoint
const ALERT_SERVICE_URL = process.env.ALERT_SERVICE_URL || 'http://alert-service:3001/api/alert';
const STATE_FILE = '/state/tailscale_timer.json'; // Lokasi file ingatan

// --- OVERRIDE LOG UNTUK HIT ALERT SERVICE ---
const originalLog = console.log;
const originalError = console.error;

const getTimestamp = () => {
    return `[${new Date().toISOString().replace('T', ' ').split('.')[0]}]`;
};

// Fungsi helper hit alert-service internal
const forwardToAlertService = (text, type) => {
    fetch(`${ALERT_SERVICE_URL}?api_key=${API_KEY}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ text, type })
    }).catch(err => {
        originalError(getTimestamp(), `[Gagal forward ke Alert Service]:`, err.message);
    });
};

console.log = function () {
    const args = Array.from(arguments);
    const msg = args.join(' ');
    originalLog.apply(console, [getTimestamp(), ...args]);
    forwardToAlertService(msg, 'LOG');
};

console.error = function () {
    const args = Array.from(arguments);
    const msg = args.join(' ');
    originalError.apply(console, [getTimestamp(), ...args]);
    forwardToAlertService(msg, 'ERROR');
};
// --- END OVERRIDE ---

const app = express();

// Tambahkan ini agar req.body?.minutes bisa terbaca jika via POST
app.use(express.json()); 

let tailscaleTimer = null;

// Middleware Auth
app.use((req, res, next) => {
    const key = req.headers['x-api-key'] || req.query.api_key;
    if (!key || key !== API_KEY) {
        return res.status(401).json({ error: 'Unauthorized' });
    }
    next();
});

// Helper command eksekusi
const runCommand = (cmd) => {
    return new Promise((resolve, reject) => {
        exec(cmd, (error, stdout, stderr) => {
            if (error) {
                console.error(`Command failed: ${cmd}\n${stderr}`);
                reject({ error: error.message, stderr });
            } else {
                resolve(stdout.trim());
            }
        });
    });
};

// --- LOGIKA MENGINGAT TIMER (BARU) ---

// Fungsi untuk mengeksekusi proses STOP secara seragam
const executeStop = async (reason) => {
    try {
        console.log(`Menghentikan Tailscale (${reason})...`);
        await runCommand(process.env.STOP_COMMAND || 'docker service scale homelab_tailscale=0');
        console.log('Tailscale berhasil dihentikan.');
        
        // Hapus file ingatan karena sudah berhasil di-stop
        if (fs.existsSync(STATE_FILE)) fs.unlinkSync(STATE_FILE);
    } catch (err) {
        console.error('Gagal saat mencoba menghentikan Tailscale.');
    }
};

// Fungsi recovery saat container restart
const checkPreviousStateOnStartup = () => {
    if (fs.existsSync(STATE_FILE)) {
        try {
            const data = JSON.parse(fs.readFileSync(STATE_FILE, 'utf8'));
            if (!data.stopTime) return;

            const now = Date.now();
            if (data.stopTime > now) {
                // Waktu belum habis, lanjutkan sisa timer
                const remainingMs = data.stopTime - now;
                const remainingMinutes = Math.round(remainingMs / 60000);
                
                console.log(`[RECOVERY] Menemukan jadwal auto-stop. Melanjutkan sisa waktu: ${remainingMinutes} menit.`);
                tailscaleTimer = setTimeout(() => executeStop('auto-stop dilanjutkan pasca-restart'), remainingMs);
            } else {
                // Waktu sudah habis saat server sedang mati
                console.log(`[RECOVERY] Jadwal auto-stop sudah terlewat selama server offline. Menghentikan sekarang.`);
                executeStop('auto-stop terlewat pasca-restart');
            }
        } catch (err) {
            originalError('Gagal membaca state file:', err);
        }
    }
};

// --- ENDPOINT: START TAILSCALE (Dengan Durasi Dinamis & State Save) ---
app.get('/api/tailscale/start', async (req, res) => {
    try {
        const inputMinutes = req.query.minutes || req.body?.minutes;
        const autoStopMinutes = (inputMinutes && !isNaN(inputMinutes)) ? parseInt(inputMinutes, 10) : 60;

        const deployCmd = "cd /data && export $(grep -v '^#' .env | xargs) && docker stack deploy -c tailscale-stack.yaml homelab";
        await runCommand(deployCmd);
        
        if (tailscaleTimer) {
            clearTimeout(tailscaleTimer);
            console.log('Timer auto-stop Tailscale diperbarui.');
        }
        
        // Simpan target waktu stop ke file json
        const timeoutMs = autoStopMinutes * 60 * 1000;
        const targetStopTime = Date.now() + timeoutMs;
        fs.writeFileSync(STATE_FILE, JSON.stringify({ stopTime: targetStopTime }));

        tailscaleTimer = setTimeout(() => executeStop('auto-stop'), timeoutMs);

        console.log(`Tailscale started. Will auto-stop in ${autoStopMinutes} minutes.`);
        res.json({ message: `Tailscale started. Will auto-stop in ${autoStopMinutes} minutes.` });
    } catch (err) {
        originalError('Error detail pada start-endpoint:', err);
        res.status(500).json({ error: 'Failed to start Tailscale' });
    }
});

// --- ENDPOINT BARU: STOP TAILSCALE MANUAL ---
app.get('/api/tailscale/stop', async (req, res) => {
    try {
        if (tailscaleTimer) {
            clearTimeout(tailscaleTimer);
            tailscaleTimer = null;
        }
        await executeStop('manual stop dari endpoint');
        res.json({ message: 'Tailscale stopped manually.' });
    } catch (err) {
        res.status(500).json({ error: 'Failed to stop Tailscale' });
    }
});

// --- ENDPOINT: HOUSEKEEPING ---
app.get('/api/housekeeping/start', async (req, res) => {
    try {
        console.log('Memulai proses housekeeping...');
        const cleanCmd = process.env.HOUSEKEEPING_CMD || 'find /housekeeping -type f -mtime +7 -delete';
        await runCommand(cleanCmd);
        console.log('Housekeeping selesai.');
        res.json({ message: 'Housekeeping executed.' });
    } catch (err) {
        res.status(500).json({ error: 'Failed to execute housekeeping' });
    }
});

app.listen(PORT, () => {
    originalLog(getTimestamp(), `Swarm API Manager running on port ${PORT}`);
    // Jalankan pengecekan memory saat aplikasi hidup
    checkPreviousStateOnStartup();
});
