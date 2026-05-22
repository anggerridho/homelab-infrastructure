const express = require('express');
const { exec } = require('child_process');

const PORT = process.env.PORT || 3000;
const API_KEY = process.env.API_KEY;
const AUTO_STOP_MINUTES = parseInt(process.env.AUTO_STOP_MINUTES || 60, 10);
const ALERT_SERVICE_URL = process.env.ALERT_SERVICE_URL || 'http://alert-service:3001/api/alert';

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
let tailscaleTimer = null;

app.use((req, res, next) => {
    const key = req.headers['x-api-key'] || req.query.api_key;
    if (!key || key !== API_KEY) {
        return res.status(401).json({ error: 'Unauthorized' });
    }
    next();
});

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

// --- ENDPOINT: START TAILSCALE (Dengan Durasi Dinamis) ---
app.get('/api/tailscale/start', async (req, res) => {
    try {
        // Ambil input secara aman
        const inputMinutes = req.query.minutes || req.body?.minutes;
        
        // Validasi ketat: jika input ada dan merupakan angka, parse ke integer. Jika tidak, paksa 60.
        const autoStopMinutes = (inputMinutes && !isNaN(inputMinutes)) ? parseInt(inputMinutes, 10) : 60;

        const deployCmd = "cd /data && export $(grep -v '^#' .env | xargs) && docker stack deploy -c tailscale-stack.yaml homelab";
        await runCommand(deployCmd);
        
        if (tailscaleTimer) {
            clearTimeout(tailscaleTimer);
            console.log('Timer auto-stop Tailscale diperbarui.');
        }
        
        const timeoutMs = autoStopMinutes * 60 * 1000;
        tailscaleTimer = setTimeout(async () => {
            console.log(`Menjalankan auto-stop Tailscale setelah ${autoStopMinutes} menit.`);
            try {
                await runCommand(process.env.STOP_COMMAND || 'docker service scale homelab_tailscale=0');
                console.log('Tailscale berhasil dihentikan (auto-stop).');
            } catch (err) {}
        }, timeoutMs);

        console.log(`Tailscale started. Will auto-stop in ${autoStopMinutes} minutes.`);
        res.json({ message: `Tailscale started. Will auto-stop in ${autoStopMinutes} minutes.` });
    } catch (err) {
        // Tambahkan log ini agar jika ada error lain, Anda bisa tahu detailnya via Docker logs/Telegram
        originalError('Error detail pada start-endpoint:', err);
        res.status(500).json({ error: 'Failed to start Tailscale' });
    }
});

// --- ENDPOINT BARU: STOP TAILSCALE MANUAL ---
app.get('/api/tailscale/stop', async (req, res) => {
    try {
        console.log('Menerima perintah manual untuk menghentikan Tailscale.');
        await runCommand(process.env.STOP_COMMAND || 'docker service scale homelab_tailscale=0');
        
        // Matikan timer jika tailscale dimatikan secara manual
        if (tailscaleTimer) {
            clearTimeout(tailscaleTimer);
            tailscaleTimer = null;
            console.log('Timer auto-stop dibatalkan karena dihentikan manual.');
        }
        
        console.log('Tailscale berhasil dihentikan (manual).');
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
});
