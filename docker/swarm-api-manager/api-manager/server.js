const express = require('express');
const { exec } = require('child_process');
const fs = require('fs'); 
const path = require('path');

const PORT = process.env.PORT || 3000;
const API_KEY = process.env.API_KEY;
const ALERT_SERVICE_URL = process.env.ALERT_SERVICE_URL || 'http://alert-service:3001/api/alert';

// --- VARIABEL STATE & TIMER ---
const STATE_FILE = '/state/tailscale_timer.json'; // Lokasi file ingatan Tailscale
const SAMBA_STATE_FILE = '/state/samba_timer.json'; // Lokasi file ingatan Samba

let tailscaleTimer = null;
let sambaTimer = null;

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

// ==========================================
// LOGIKA TAILSCALE
// ==========================================

const executeStop = async (reason) => {
    try {
        console.log(`Menghentikan Tailscale (${reason})...`);
        await runCommand(process.env.STOP_COMMAND || 'docker service scale homelab_tailscale=0');
        console.log('Tailscale berhasil dihentikan.');
        
        if (fs.existsSync(STATE_FILE)) fs.unlinkSync(STATE_FILE);
    } catch (err) {
        console.error('Gagal saat mencoba menghentikan Tailscale.');
    }
};

const checkPreviousStateOnStartup = () => {
    if (fs.existsSync(STATE_FILE)) {
        try {
            const data = JSON.parse(fs.readFileSync(STATE_FILE, 'utf8'));
            if (!data.stopTime) return;

            const now = Date.now();
            if (data.stopTime > now) {
                const remainingMs = data.stopTime - now;
                const remainingMinutes = Math.round(remainingMs / 60000);
                
                console.log(`[RECOVERY] Menemukan jadwal auto-stop Tailscale. Melanjutkan sisa waktu: ${remainingMinutes} menit.`);
                tailscaleTimer = setTimeout(() => executeStop('auto-stop dilanjutkan pasca-restart'), remainingMs);
            } else {
                console.log(`[RECOVERY] Jadwal auto-stop Tailscale sudah terlewat selama server offline. Menghentikan sekarang.`);
                executeStop('auto-stop terlewat pasca-restart');
            }
        } catch (err) {
            originalError('Gagal membaca state file Tailscale:', err);
        }
    }
};

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
        
        const timeoutMs = autoStopMinutes * 60 * 1000;
        const targetStopTime = Date.now() + timeoutMs;
        fs.writeFileSync(STATE_FILE, JSON.stringify({ stopTime: targetStopTime }));

        tailscaleTimer = setTimeout(() => executeStop('auto-stop'), timeoutMs);

        console.log(`Tailscale started. Will auto-stop in ${autoStopMinutes} minutes.`);
        res.json({ message: `Tailscale started. Will auto-stop in ${autoStopMinutes} minutes.` });
    } catch (err) {
        originalError('Error detail pada tailscale start:', err);
        res.status(500).json({ error: 'Failed to start Tailscale' });
    }
});

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

// ==========================================
// LOGIKA SAMBA
// ==========================================

const executeSambaStop = async (reason) => {
    try {
        console.log(`Menghentikan Samba (${reason})...`);
        // SEKARANG DINAMIS: Membaca SAMBA_STOP_COMMAND dari env, fallback ke perintah scale
        const stopCmd = process.env.SAMBA_STOP_COMMAND || 'docker service scale homelab_samba=0';
        await runCommand(stopCmd);
        console.log('Samba berhasil dihentikan.');
        
        if (fs.existsSync(SAMBA_STATE_FILE)) fs.unlinkSync(SAMBA_STATE_FILE);
    } catch (err) {
        console.error('Gagal saat mencoba menghentikan Samba.');
    }
};

const checkSambaStateOnStartup = () => {
    if (fs.existsSync(SAMBA_STATE_FILE)) {
        try {
            const data = JSON.parse(fs.readFileSync(SAMBA_STATE_FILE, 'utf8'));
            if (!data.stopTime) return;

            const now = Date.now();
            if (data.stopTime > now) {
                const remainingMs = data.stopTime - now;
                const remainingMinutes = Math.round(remainingMs / 60000);
                
                console.log(`[RECOVERY] Menemukan jadwal auto-stop Samba. Melanjutkan: ${remainingMinutes} menit.`);
                sambaTimer = setTimeout(() => executeSambaStop('auto-stop dilanjutkan'), remainingMs);
            } else {
                console.log(`[RECOVERY] Jadwal auto-stop Samba sudah terlewat. Menghentikan sekarang.`);
                executeSambaStop('auto-stop terlewat pasca-restart');
            }
        } catch (err) {
            originalError('Gagal membaca state file Samba:', err);
        }
    }
};

app.get('/api/samba/start', async (req, res) => {
    try {
        const inputMinutes = req.query.minutes || req.body?.minutes;
        const autoStopMinutes = (inputMinutes && !isNaN(inputMinutes)) ? parseInt(inputMinutes, 10) : 60;

        // Pindah ke folder samba dan eksekusi deploy.sh
        const deployCmd = "cd /samba && sh deploy.sh";
        await runCommand(deployCmd);
        
        if (sambaTimer) {
            clearTimeout(sambaTimer);
            console.log('Timer auto-stop Samba diperbarui.');
        }
        
        const timeoutMs = autoStopMinutes * 60 * 1000;
        const targetStopTime = Date.now() + timeoutMs;
        fs.writeFileSync(SAMBA_STATE_FILE, JSON.stringify({ stopTime: targetStopTime }));

        sambaTimer = setTimeout(() => executeSambaStop('auto-stop'), timeoutMs);

        console.log(`Samba started. Will auto-stop in ${autoStopMinutes} minutes.`);
        res.json({ message: `Samba started. Will auto-stop in ${autoStopMinutes} minutes.` });
    } catch (err) {
        originalError('Error detail pada samba start:', err);
        res.status(500).json({ error: 'Failed to start Samba' });
    }
});

app.get('/api/samba/stop', async (req, res) => {
    try {
        if (sambaTimer) {
            clearTimeout(sambaTimer);
            sambaTimer = null;
        }
        await executeSambaStop('manual stop dari endpoint');
        res.json({ message: 'Samba stopped manually.' });
    } catch (err) {
        res.status(500).json({ error: 'Failed to stop Samba' });
    }
});

// ==========================================
// HOUSEKEEPING
// ==========================================

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

// ==========================================
// START SERVER
// ==========================================

app.listen(PORT, () => {
    originalLog(getTimestamp(), `Swarm API Manager running on port ${PORT}`);
    // Pengecekan recovery saat aplikasi hidup
    checkPreviousStateOnStartup();
    checkSambaStateOnStartup();
});
