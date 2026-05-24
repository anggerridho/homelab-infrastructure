const express = require('express');
const TelegramBot = require('node-telegram-bot-api');

const app = express();
const PORT = process.env.PORT || 3001;
const API_KEY = process.env.API_KEY;
const TELEGRAM_TOKEN = process.env.TELEGRAM_TOKEN;
const TELEGRAM_CHAT_ID = process.env.TELEGRAM_CHAT_ID;

// Inisialisasi Telegram Bot Mode Polling
const bot = new TelegramBot(TELEGRAM_TOKEN, { polling: true });

app.use(express.json());

const getTimestamp = () => `[${new Date().toISOString().replace('T', ' ').split('.')[0]}]`;

// === LISTENER PERINTAH DARI TELEGRAM ===

// 1. Perintah Start Tailscale (Contoh di chat: /start_tailscale atau /start_tailscale 120)
bot.onText(/\/start_tailscale(?: (.+))?/, async (msg, match) => {
    const chatId = msg.chat.id;
    // KEAMANAN: Pastikan hanya Chat ID Anda yang bisa mengeksekusi!
    if (chatId.toString() !== TELEGRAM_CHAT_ID) return; 

    const minutes = match[1] ? match[1] : 60; // Default 60 jika tidak diisi
    bot.sendMessage(chatId, `⏳ Sedang menyalakan Tailscale (${minutes} Menit)...`);

    try {
        // Tembak service api-manager secara internal
        const response = await fetch(`http://api-manager:3000/api/tailscale/start?api_key=${API_KEY}&minutes=${minutes}`);
        const data = await response.json();
        bot.sendMessage(chatId, `✅ ${data.message}`);
    } catch (err) {
        bot.sendMessage(chatId, `❌ Gagal menyalakan: ${err.message}`);
    }
});

// 2. Perintah Stop Manual Tailscale (Contoh di chat: /stop_tailscale)
bot.onText(/\/stop_tailscale/, async (msg) => {
    const chatId = msg.chat.id;
    if (chatId.toString() !== TELEGRAM_CHAT_ID) return;

    bot.sendMessage(chatId, `⏳ Mematikan Tailscale secara manual...`);
    try {
        const response = await fetch(`http://api-manager:3000/api/tailscale/stop?api_key=${API_KEY}`);
        const data = await response.json();
        bot.sendMessage(chatId, `✅ ${data.message}`);
    } catch (err) {
        bot.sendMessage(chatId, `❌ Gagal mematikan: ${err.message}`);
    }
});

// 3. Perintah Start Samba (Contoh di chat: /start_samba atau /start_samba 120)
bot.onText(/\/start_samba(?: (.+))?/, async (msg, match) => {
    const chatId = msg.chat.id;
    if (chatId.toString() !== TELEGRAM_CHAT_ID) return;

    const minutes = match[1] ? match[1] : 60; // Default 60 menit
    bot.sendMessage(chatId, `⏳ Sedang menyalakan Samba (${minutes} Menit)...`);

    try {
        const response = await fetch(`http://api-manager:3000/api/samba/start?api_key=${API_KEY}&minutes=${minutes}`);
        const data = await response.json();
        bot.sendMessage(chatId, `✅ ${data.message}`);
    } catch (err) {
        bot.sendMessage(chatId, `❌ Gagal menyalakan Samba: ${err.message}`);
    }
});

// 4. Perintah Stop Manual Samba (Contoh di chat: /stop_samba)
bot.onText(/\/stop_samba/, async (msg) => {
    const chatId = msg.chat.id;
    if (chatId.toString() !== TELEGRAM_CHAT_ID) return;

    bot.sendMessage(chatId, `⏳ Mematikan Samba secara manual...`);
    try {
        const response = await fetch(`http://api-manager:3000/api/samba/stop?api_key=${API_KEY}`);
        const data = await response.json();
        bot.sendMessage(chatId, `✅ ${data.message}`);
    } catch (err) {
        bot.sendMessage(chatId, `❌ Gagal mematikan Samba: ${err.message}`);
    }
});

// === ENDPOINT ALERT UNTUK DARI LUAR ===
app.use((req, res, next) => {
    const key = req.headers['x-api-key'] || req.query.api_key;
    if (!key || key !== API_KEY) return res.status(401).json({ error: 'Unauthorized' });
    next();
});

app.all('/api/alert', async (req, res) => {
    const text = req.body.text || req.query.text;
    const type = req.body.type || req.query.type || 'INFO';
    if (!text) return res.status(400).json({ error: 'Parameter text dibutuhkan.' });

    let emoji = '🔔';
    if (type.toUpperCase() === 'ERROR') emoji = '🚨';
    if (type.toUpperCase() === 'LOG') emoji = 'ℹ️';

    console.log(`${getTimestamp()} Meneruskan log ke Telegram...`);
    
    // Kirim menggunakan instance bot
    bot.sendMessage(TELEGRAM_CHAT_ID, `${emoji} <b>${type.toUpperCase()}:</b>\n<pre>${text}</pre>`, { parse_mode: 'HTML' });
    res.json({ message: 'Alert sent' });
});

app.listen(PORT, () => {
    console.log(`${getTimestamp()} Alert Service (Bot Polling) berjalan di port ${PORT}`);
});
