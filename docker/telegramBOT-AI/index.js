const TelegramBot = require('node-telegram-bot-api');
const OpenAI = require('openai');

const token = process.env.TELEGRAM_BOT_TOKEN;
if (!token) {
  console.error("ERROR: TELEGRAM_BOT_TOKEN tidak ditemukan!");
  process.exit(1);
}
const bot = new TelegramBot(token, { polling: true });

const baseURL = process.env.ROUTER_BASE_URL ? process.env.ROUTER_BASE_URL.trim() : '';
const apiKey = process.env.ROUTER_API_KEY;
const targetModel = process.env.ROUTER_MODEL || 'fm/claude-3-5-sonnet';

console.log(`Bot AI Asisten Penulis berhasil berjalan...`);

// Menangkap error global
process.on('unhandledRejection', (reason, promise) => {
  console.error('⚠️ Terjadi Unhandled Rejection di: ', promise, ' alasan: ', reason);
});
process.on('uncaughtException', (error) => {
  console.error('⚠️ Terjadi Uncaught Exception: ', error);
});

// --- FITUR BARU: PERINTAH RESET CHAT (/newchat atau /reset) ---
bot.onText(/\/newchat|\/reset/, (msg) => {
  const chatId = msg.chat.id;
  
  // Jika nanti Anda mengembangkan sistem memori/array chat history, 
  // di sinilah tempat untuk menghapus array history tersebut berdasarkan chatId.
  
  bot.sendMessage(chatId, '🔄 **Sesi obrolan berhasil di-reset!**\nMari mulai topik baru. Ada yang bisa saya bantu untuk tulisan Anda?');
});

// Logika pesan reguler
bot.on('message', async (msg) => {
  const chatId = msg.chat.id;
  const text = msg.text;

  if (!text) return;

  // Jika pesan berupa perintah slash, abaikan fungsi chat reguler ini
  if (text.startsWith('/')) return;

  bot.sendChatAction(chatId, 'typing');

  try {
    const openai = new OpenAI({
      apiKey: apiKey,
      baseURL: baseURL
    });

    const response = await openai.chat.completions.create({
      model: targetModel,
      messages: [{ role: 'user', content: text }],
    });

    const reply = response.choices[0].message.content;
    bot.sendMessage(chatId, reply);
    
  } catch (error) {
    console.error('🚨 ERROR PADA JALUR 9ROUTER/OPENAI:', error.message);
    bot.sendMessage(chatId, 'Maaf, gagal mendapatkan respons dari server AI internal.');
  }
});
