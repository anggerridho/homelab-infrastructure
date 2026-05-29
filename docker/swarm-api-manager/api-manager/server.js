const express = require('express');
const { exec } = require('child_process');
const fs = require('fs'); 
const path = require('path');

const PORT = process.env.PORT || 3000;
const API_KEY = process.env.API_KEY;
const ALERT_SERVICE_URL = process.env.ALERT_SERVICE_URL || 'http://alert-service:3001/api/alert';

// --- VARIABEL STATE & TIMER ---
const STATE_FILE = '/state/tailscale_timer.json'; 
const SAMBA_STATE_FILE = '/state/samba_timer.json'; 
const ROUTER9_STATE_FILE = '/state/9router_timer.json';
const FORTICLIENT_STATE_FILE = '/state/forticlient_timer.json';

let tailscaleTimer = null;
let sambaTimer = null;
let router9Timer = null;
let forticlientTimer = null;

// --- OVERRIDE LOG UNTUK HIT ALERT SERVICE ---
const originalLog = console.log;
const originalError = console.error;

const getTimestamp = () => `[${new Date().toISOString().replace('T', ' ').split('.')[0]}]`;

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
    originalLog.apply(console, [getTimestamp(), ...args]);
    forwardToAlertService(args.join(' '), 'LOG');
};

console.error = function () {
    const args = Array.from(arguments);
    originalError.apply(console, [getTimestamp(), ...args]);
    forwardToAlertService(args.join(' '), 'ERROR');
};

const app = express();
app.use(express.json()); 

app.use((req, res, next) => {
    const key = req.headers['x-api-key'] || req.query.api_key;
    if (!key || key !== API_KEY) return res.status(401).json({ error: 'Unauthorized' });
    next();
});

const runCommand = (cmd) => {
    return new Promise((resolve, reject) => {
        exec(cmd, (error, stdout, stderr) => {
            if (error) {
                console.error(`Command failed: ${cmd}\n${stderr}`);
                reject({ error: error.message, stderr });
            } else resolve(stdout.trim());
        });
    });
};

// ==========================================
// FUNGSI HELPER UNIVERSAL UNTUK SEMUA SERVICE
// ==========================================
const checkStateOnStartup = (stateFile, timerRef, stopFunction, serviceName) => {
    if (fs.existsSync(stateFile)) {
        try {
            const data = JSON.parse(fs.readFileSync(stateFile, 'utf8'));
            if (!data.stopTime) return;

            const now = Date.now();
            if (data.stopTime > now) {
                const remainingMs = data.stopTime - now;
                const remainingMinutes = Math.round(remainingMs / 60000);
                console.log(`[RECOVERY] Jadwal auto-stop ${serviceName} dilanjutkan: ${remainingMinutes} menit.`);
                return setTimeout(() => stopFunction('auto-stop dilanjutkan'), remainingMs);
            } else {
                console.log(`[RECOVERY] Jadwal auto-stop ${serviceName} sudah terlewat. Menghentikan sekarang.`);
                stopFunction('auto-stop terlewat pasca-restart');
            }
        } catch (err) {
            originalError(`Gagal membaca state file ${serviceName}:`, err);
        }
    }
    return null;
};

// ==========================================
// 1. TAILSCALE
// ==========================================
const executeTailscaleStop = async (reason) => {
    try {
        console.log(`Menghentikan Tailscale (${reason})...`);
        await runCommand(process.env.STOP_COMMAND || 'docker service scale homelab_tailscale=0');
        console.log('Tailscale dihentikan.');
        if (fs.existsSync(STATE_FILE)) fs.unlinkSync(STATE_FILE);
    } catch (err) {}
};

app.get('/api/tailscale/start', async (req, res) => {
    try {
        const inputMinutes = req.query.minutes || req.body?.minutes;
        const autoStopMinutes = (inputMinutes && !isNaN(inputMinutes)) ? parseInt(inputMinutes, 10) : 60;

        await runCommand("cd /data && export $(grep -v '^#' .env | xargs) && docker stack deploy -c tailscale-stack.yaml homelab");
        if (tailscaleTimer) clearTimeout(tailscaleTimer);
        
        const timeoutMs = autoStopMinutes * 60 * 1000;
        fs.writeFileSync(STATE_FILE, JSON.stringify({ stopTime: Date.now() + timeoutMs }));
        tailscaleTimer = setTimeout(() => executeTailscaleStop('auto-stop'), timeoutMs);

        console.log(`Tailscale started. Auto-stop in ${autoStopMinutes} minutes.`);
        res.json({ message: `Tailscale started. Auto-stop in ${autoStopMinutes} minutes.` });
    } catch (err) {
        res.status(500).json({ error: 'Failed to start Tailscale' });
    }
});

app.get('/api/tailscale/stop', async (req, res) => {
    try {
        if (tailscaleTimer) { clearTimeout(tailscaleTimer); tailscaleTimer = null; }
        await executeTailscaleStop('manual stop');
        res.json({ message: 'Tailscale stopped manually.' });
    } catch (err) { res.status(500).json({ error: 'Failed' }); }
});

// ==========================================
// 2. SAMBA
// ==========================================
const executeSambaStop = async (reason) => {
    try {
        console.log(`Menghentikan Samba (${reason})...`);
        await runCommand(process.env.SAMBA_STOP_COMMAND || 'docker service scale homelab_samba=0');
        console.log('Samba dihentikan.');
        if (fs.existsSync(SAMBA_STATE_FILE)) fs.unlinkSync(SAMBA_STATE_FILE);
    } catch (err) {}
};

app.get('/api/samba/start', async (req, res) => {
    try {
        const inputMinutes = req.query.minutes || req.body?.minutes;
        const autoStopMinutes = (inputMinutes && !isNaN(inputMinutes)) ? parseInt(inputMinutes, 10) : 60;

        await runCommand("cd /samba && sh deploy.sh");
        if (sambaTimer) clearTimeout(sambaTimer);
        
        const timeoutMs = autoStopMinutes * 60 * 1000;
        fs.writeFileSync(SAMBA_STATE_FILE, JSON.stringify({ stopTime: Date.now() + timeoutMs }));
        sambaTimer = setTimeout(() => executeSambaStop('auto-stop'), timeoutMs);

        console.log(`Samba started. Auto-stop in ${autoStopMinutes} minutes.`);
        res.json({ message: `Samba started. Auto-stop in ${autoStopMinutes} minutes.` });
    } catch (err) { res.status(500).json({ error: 'Failed' }); }
});

app.get('/api/samba/stop', async (req, res) => {
    try {
        if (sambaTimer) { clearTimeout(sambaTimer); sambaTimer = null; }
        await executeSambaStop('manual stop');
        res.json({ message: 'Samba stopped manually.' });
    } catch (err) { res.status(500).json({ error: 'Failed' }); }
});

// ==========================================
// 3. 9ROUTER
// ==========================================
const executeRouter9Stop = async (reason) => {
    try {
        console.log(`Menghentikan 9router (${reason})...`);
        await runCommand(process.env.ROUTER9_STOP_COMMAND || 'docker service scale homelab_9router=0');
        console.log('9router dihentikan.');
        if (fs.existsSync(ROUTER9_STATE_FILE)) fs.unlinkSync(ROUTER9_STATE_FILE);
    } catch (err) {}
};

app.get('/api/9router/start', async (req, res) => {
    try {
        const inputMinutes = req.query.minutes || req.body?.minutes;
        const autoStopMinutes = (inputMinutes && !isNaN(inputMinutes)) ? parseInt(inputMinutes, 10) : 60;

        await runCommand("cd /9router && sh deploy.sh");
        if (router9Timer) clearTimeout(router9Timer);
        
        const timeoutMs = autoStopMinutes * 60 * 1000;
        fs.writeFileSync(ROUTER9_STATE_FILE, JSON.stringify({ stopTime: Date.now() + timeoutMs }));
        router9Timer = setTimeout(() => executeRouter9Stop('auto-stop'), timeoutMs);

        console.log(`9router started. Auto-stop in ${autoStopMinutes} minutes.`);
        res.json({ message: `9router started. Auto-stop in ${autoStopMinutes} minutes.` });
    } catch (err) { res.status(500).json({ error: 'Failed' }); }
});

app.get('/api/9router/stop', async (req, res) => {
    try {
        if (router9Timer) { clearTimeout(router9Timer); router9Timer = null; }
        await executeRouter9Stop('manual stop');
        res.json({ message: '9router stopped manually.' });
    } catch (err) { res.status(500).json({ error: 'Failed' }); }
});

// ==========================================
// 4. FORTICLIENT
// ==========================================
const executeForticlientStop = async (reason) => {
    try {
        console.log(`Menghentikan Forticlient (${reason})...`);
        await runCommand(process.env.FORTICLIENT_STOP_COMMAND || 'cd /forticlient && docker-compose down');
        console.log('Forticlient dihentikan.');
        if (fs.existsSync(FORTICLIENT_STATE_FILE)) fs.unlinkSync(FORTICLIENT_STATE_FILE);
    } catch (err) {}
};

app.get('/api/forticlient/start', async (req, res) => {
    try {
        const inputMinutes = req.query.minutes || req.body?.minutes;
        const autoStopMinutes = (inputMinutes && !isNaN(inputMinutes)) ? parseInt(inputMinutes, 10) : 60;

        await runCommand("cd /forticlient && sh deploy.sh");
        if (forticlientTimer) clearTimeout(forticlientTimer);
        
        const timeoutMs = autoStopMinutes * 60 * 1000;
        fs.writeFileSync(FORTICLIENT_STATE_FILE, JSON.stringify({ stopTime: Date.now() + timeoutMs }));
        forticlientTimer = setTimeout(() => executeForticlientStop('auto-stop'), timeoutMs);

        console.log(`Forticlient started. Auto-stop in ${autoStopMinutes} minutes.`);
        res.json({ message: `Forticlient started. Auto-stop in ${autoStopMinutes} minutes.` });
    } catch (err) { res.status(500).json({ error: 'Failed' }); }
});

app.get('/api/forticlient/stop', async (req, res) => {
    try {
        if (forticlientTimer) { clearTimeout(forticlientTimer); forticlientTimer = null; }
        await executeForticlientStop('manual stop');
        res.json({ message: 'Forticlient stopped manually.' });
    } catch (err) { res.status(500).json({ error: 'Failed' }); }
});

// ==========================================
// HOUSEKEEPING & START SERVER
// ==========================================
app.get('/api/housekeeping/start', async (req, res) => {
    try {
        console.log('Memulai proses housekeeping...');
        await runCommand(process.env.HOUSEKEEPING_CMD || 'find /housekeeping -type f -mtime +7 -delete');
        res.json({ message: 'Housekeeping executed.' });
    } catch (err) { res.status(500).json({ error: 'Failed' }); }
});

app.listen(PORT, () => {
    originalLog(getTimestamp(), `Swarm API Manager running on port ${PORT}`);
    
    // Jalankan semua fungsi recovery
    tailscaleTimer = checkStateOnStartup(STATE_FILE, tailscaleTimer, executeTailscaleStop, 'Tailscale');
    sambaTimer = checkStateOnStartup(SAMBA_STATE_FILE, sambaTimer, executeSambaStop, 'Samba');
    router9Timer = checkStateOnStartup(ROUTER9_STATE_FILE, router9Timer, executeRouter9Stop, '9router');
    forticlientTimer = checkStateOnStartup(FORTICLIENT_STATE_FILE, forticlientTimer, executeForticlientStop, 'Forticlient');
});