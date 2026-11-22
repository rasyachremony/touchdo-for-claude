# TouchDo for Claude

Limit Claude, sesi Claude Code yang lagi jalan, dan to-do list, langsung di Touch Bar MacBook Pro.

**[English](README.md)**

```
 ✳ Max   5h   ███░░░░░░░  30% ↻04:10      ● Benerin bug login  24m
   5x    Week ██░░░░░░░░  17% ↻Sab 13:00  ● Tulis test          3m      ‹ ☑² ☕ 🎙  ☀ 🔊
```

> Tidak resmi. Bukan buatan Anthropic dan tidak berafiliasi dengan mereka. "Claude" adalah merek dagang Anthropic. Logo
> di bar diambil dari aplikasi Claude yang terpasang di Mac kamu, jadi tidak ada logo mereka di proyek ini.

## Fiturnya

- **Limit Claude di paling kiri.** Bar 5 jam dan mingguan plus jam reset. Hijau, kuning mulai 50%, merah mulai 80%.
- **Plan kamu** (Pro, Max 5x…) dan **sesi Claude Code yang lagi kerja**, lengkap dengan lamanya.
- **Minggir waktu kamu ngetik.** Begitu ada tombol ditekan (kecuali shortcut ⌘ dan ⌃), Touch Bar asli dan saran ketik muncul lagi. Satu detik
  setelah berhenti, limitnya balik.
- **To-do dengan deadline.** Tambah, edit, centang, hapus dari Touch Bar atau menu bar. Warnanya menunjukkan seberapa
  dekat deadline, angka merah menunjukkan yang belum selesai.
- **Kirim to-do ke Claude Code** lewat tombol pesawat kertas *(eksperimental, lihat di bawah)*.
- **Tahan mic buat ngomong ke Claude**, atau ketuk dua kali biar tetap nyala sampai diketuk lagi.
- **☕ Mac nyala terus**, sendiri atau lewat [Insomnia](https://github.com/krishhgg/Insomnia) 0.2.0 ke atas (laptop ditutup pun tetap jalan).

## Yang dibutuhkan

- MacBook Pro dengan Touch Bar **dan tombol Esc fisik** (16 inci 2019, 13 inci 2020 ke atas), macOS 13 ke atas. Baru dites
  di macOS 27.0.1. Model yang Esc-nya ada di Touch Bar (2016–2019) tidak didukung, karena bar limit menutupi Esc.
- Xcode command line tools: `xcode-select --install`
- [Claude Code](https://claude.com/claude-code) buat limit dan sesi, dan aplikasi Claude buat voice dan pesawat kertas.
  To-do dan ☕ tidak butuh keduanya.

## Cara pasang

1. Ambil kodenya lalu build. Ini memasang `~/Applications/TouchDo.app` dan menyalakannya tiap login.

   ```bash
   git clone https://github.com/rasyachremony/touchdo-for-claude.git
   cd touchdo-for-claude
   ./build.sh
   ```

2. Izinkan Accessibility: **System Settings → Privacy & Security → Accessibility**, lalu nyalakan **TouchDo**.
   Kalau belum ada di daftar, tekan **+** dan pilih `TouchDo.app` dari folder Applications di folder home kamu. Sebelum
   diizinkan, limitnya belum muncul karena TouchDo tidak tahu kamu sedang ngetik atau tidak.

3. Di **System Settings → Keyboard → Touch Bar Settings**, set "Touch Bar shows" ke **App Controls** dan nyalakan
   **Show Control Strip**.

4. Khusus voice: di pengaturan aplikasi Claude, set shortcut dikte Quick Entry ke **⌃⌥⌘D**, atau ganti
   `pressClaudeShortcut` di `main.swift` sesuai shortcut kamu lalu jalankan `./build.sh` lagi.

5. Opsional: bar langsung ikut tiap balasan Claude Code. Tempel isi [statusline-usage.sh](statusline-usage.sh) ke
   [script status line](https://code.claude.com/docs/en/statusline) kamu.

## Cara pakai

| Lakukan ini | Untuk |
|---|---|
| Tap tombol ☑ ☕ 🎙 di Control Strip | buka TouchDo |
| Tap **+**, ketik, Return, pilih tanggal | tambah to-do (Esc buat batal) |
| Tap sebuah to-do | jalankan di Claude Code, selesai, edit, tanggal, hapus |
| Tahan 🎙 / ketuk dua kali 🎙 | ngomong selama ditahan / tetap nyala sampai diketuk lagi |
| Tap ☕, pilih waktunya | Mac nyala terus |
| Klik ikon checklist di menu bar | lihat limit, tambah atau edit to-do pakai mouse |

Waktu ngetik to-do, shortcut biasa tetap jalan: ⌘A, ⌘C, ⌘X, ⌘V, ⌘Z, ⌥⌫, ⌘⌫, ⇧ dengan panah, ⌃A, ⌃E, ⌃K.

### Pesawat kertas (eksperimental)

Membuka sesi Claude Code baru dengan to-do sudah terisi, lalu menekan Return sekali saja, dan hanya kalau teks yang persis
sama ada di kotak sesi baru dengan Claude di depan. **Sesinya jalan dengan folder dan mode izin yang lagi dipilih di
Claude**, dan file yang masih terlampir di sana ikut terkirim. Kalau kata terakhirnya mengandung `@` atau diawali
`/`, teksnya cuma diisi, tidak dikirim. Kalau ada yang tidak cocok atau pengirimannya tidak bisa dipastikan, TouchDo
berbunyi; cek dulu di Claude sebelum kirim sendiri.

## Apa yang dibaca dan biayanya

TouchDo sendiri tidak mengirim data ke mana pun. Yang dibaca:

- `~/.claude/sessions/*.json` buat sesi yang jalan, dan `~/.claude.json`, yang diurai cuma bagian plan-nya.
- Tombol keyboard: waktu diam cuma tahu *ada* tombol ditekan (dan apakah ⌘ atau ⌃ ditahan), biar bisa minggir. Isi ketikan hanya dibaca waktu kamu
  mengetik to-do, dan tidak di kolom password.
- Jendela Claude lewat Accessibility, hanya setelah kamu tap pesawat kertas.
- Kalau Insomnia jalan: versinya, serta `session.json` dan `config.json` di `~/Library/Application Support/Insomnia`.
- Clipboard, hanya waktu kamu menekan ⌘V saat mengetik to-do.

Kalau kamu login dengan plan Claude dan data limit sudah berumur lima menit, TouchDo menjalankan satu permintaan kecil
`claude -p` (Haiku, tanpa tools, tidak disimpan), lalu mengulanginya tiap lima menit sampai ada yang memperbarui limitnya.
**Tiap kali itu memakai sekitar 1.100 token input dari plan kamu**, jadi bisa sampai 288 kali (sekitar 320.000 token) sehari
kalau Mac terus menyala, dan bisa memulai jendela 5 jam baru waktu kamu tidak memakai Claude. Hanya langkah 5 yang membuat
sesi kamu sendiri memperbarui limit, jadi tanpa itu permintaan ini tetap jalan waktu kamu memakai Claude Code. Buat
mematikannya, ubah `autoRefresh` di `main.swift` jadi `.infinity` lalu jalankan `./build.sh` lagi; setelah itu bar butuh
langkah 5.

To-do kamu tersimpan di `~/Library/Application Support/io.github.rasyachremony.TouchDo/todos.json`.

## Perlu diketahui

- Memakai API Touch Bar privat dari Apple, jadi update macOS bisa merusaknya. Kalau API-nya hilang, TouchDo berhenti sendiri.
- File sesi, plan dan limit adalah milik Claude Code, bukan API resmi. Kalau berubah, bagian itu jadi kosong.
- Build-nya ditandatangani ad hoc, dan izin Accessibility terikat ke bundle id supaya tetap berlaku setelah build ulang.
  Program lain di Mac kamu yang ditandatangani dengan id yang sama juga dapat izin itu. Kalau itu penting buat kamu,
  ubah baris `codesign` di `build.sh`: ganti `--sign -` dengan `--sign "Sertifikat Kamu"` dan hapus seluruh argumen `-r=...`
  (kalau dibiarkan, izinnya tetap terikat ke id saja). Build ulang, lalu hapus TouchDo dari daftar Accessibility dan
  tambahkan lagi.

## Kalau ada masalah

| Masalah | Solusi |
|---|---|
| Bar di paling kiri tidak muncul | Cek langkah 2. Kalau TouchDo sudah nyala di sana, hapus dengan **−** lalu tambah lagi. |
| Bar menampilkan "–" | Login dulu di Claude Code (API key tidak punya limit plan). TouchDo mencari `claude` di `~/.local/bin`, `~/.claude/local`, `/opt/homebrew/bin` dan `/usr/local/bin`; kalau `which claude` menunjuk ke tempat lain, jalankan `mkdir -p ~/.local/bin && ln -s "$(which claude)" ~/.local/bin/claude`, atau lakukan langkah 5. Lalu tunggu sampai lima menit. |
| Mic tidak jalan | Buka Claude, tunggu lima detik, dan cek shortcut di langkah 4. |
| Mic jadi terbalik | Shortcut-nya toggle. Matikan dikte lewat mic TouchDo, bukan di Claude, dan matikan dulu sebelum build ulang atau uninstall. |
| Tombolnya hilang dari Control Strip | `launchctl kickstart -k gui/$(id -u)/io.github.rasyachremony.TouchDo` |

## Hapus

```bash
./build.sh uninstall
```

To-do kamu tetap disimpan. Hapus juga TouchDo dari daftar Accessibility, dan baris `statusline-usage.sh` dari script status
line kamu kalau pernah ditempel.
