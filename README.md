# Cheat & Window Assistant (AutoHotkey v2)

Script otomasi Windows berbasis **AutoHotkey v2 (AHK v2)** modern yang dirancang untuk mengontrol window aplikasi (Google Gemini & VMware Workstation) serta mengunci input mouse & keyboard secara aman.

---

## ⚡ Fitur Utama

### 1. Hotkey Utama (Dual Mode OCR)
- **`Shift + Z` (Manual Mode)** : **Manual Drag Select (OCR) -> Tempel ke Gemini** (Tanpa layar gelap & tanpa kotak biru! Tarik area teks soal secara manual, teks otomatis dibaca dan langsung ditempel ke Gemini Transparan).
- **`Shift + X` (Auto-Detect Mode BARU)** : **Auto-Detect Soal (OpenCV) -> Tempel ke Gemini** (Berjalan 100% silent di background via `pythonw.exe` tanpa interaksi mouse & tanpa memicu *window blur* saat mendeteksi bounding box soal + pilihan ganda, lalu menjalankan OCR dan menempelkannya ke Gemini. Jika area soal gagal ditemukan, muncul *fallback notification* halus untuk beralih ke `Shift + Z`).
- **`Shift + A`** : Membuka **GUI Pengaturan / Control Panel** (selalu tampil di depan / `AlwaysOnTop`).
- **`Shift + F`** : **Toggle ON / OFF** untuk mengunci & membuka kunci mouse serta keyboard (atau tekan **`F12`** untuk darurat).

---

### 2. Sistem Penguncian Input (Toggle Lock: `Shift + F`)
- **Saat Lock AKTIF**:
  - **Kursor mouse TETAP BISA DIGERAKKAN bebas** di semua monitor.
  - **Semua klik mouse diblokir** (`LButton`, `RButton`, `MButton`, `WheelUp`, `WheelDown`, `XButton1`, `XButton2`, dsb.), sehingga tidak sengaja mengklik target di layar.
  - **Semua input keyboard diblokir total** menggunakan low-level `InputHook`, **KECUALI** kombinasi `Shift + A` (buka panel) dan `Shift + F` / `F12` (buka kunci).
  - Dilengkapi **indikator audio** (`SoundBeep` frekuensi tinggi 1200 Hz) dan notifikasi sistem (`TrayTip`).
- **Saat Lock NONAKTIF**:
  - Semua fungsi mouse dan keyboard kembali normal seperti sedia kala.
  - Dilengkapi **indikator audio** (`SoundBeep` frekuensi rendah 700 Hz) dan notifikasi sistem (`TrayTip`).

---

### 3. GUI Pengaturan (`Shift + A`)
- Tampilan modern dengan window **`+AlwaysOnTop`** agar selalu mudah diakses.
- **Slider Transparansi Gemini**: Mengatur tingkat opasitas antara **50 s.d. 255** (dengan live preview).
- **Checkbox Opsi**:
  - *"Buka Gemini Transparan (Chrome App Mode)"*
  - *"Pin VMware (Always on Top)"*
- **Tombol "Simpan & Terapkan"**: Menerapkan pengaturan secara instan ke window target dan menyimpan konfigurasi ke file `config.ini`.

---

### 4. Penanganan Window Aplikasi
- **Google Gemini**:
  - Otomatis mendeteksi path Google Chrome di sistem.
  - Menjalankan Gemini dalam mode mandiri: `chrome.exe --app=https://gemini.google.com`.
  - Mengatur jendela Gemini menjadi **Always on Top** dan menerapkan **tingkat transparansi** sesuai nilai slider.
- **VMware Workstation**:
  - Otomatis mendeteksi proses `ahk_exe vmware.exe`.
  - Menyematkan window VMware agar selalu berada di paling depan (**Always on Top**) jika opsi dicentang.
  - Memiliki background timer yang otomatis menjaga VMware tetap ter-pin saat dibuka.

---

## 📁 Struktur File

- **`cheat_assistant.ahk`**: Script utama AutoHotkey v2 (siap dijalankan langsung atau di-compile).
- **`compile.bat`**: Skrip otomatis untuk mengompilasi `.ahk` menjadi `.exe` menggunakan Ahk2Exe.
- **`config.ini`**: File penyimpanan konfigurasi otomatis (terbentuk saat pengaturan disimpan).
- **`README.md`**: Dokumentasi lengkap penggunaan.

---

## 🛠️ Cara Menjalankan & Mengompilasi ke .EXE

### Cara 1: Menjalankan Langsung (.ahk)
1. Pastikan komputer telah terinstal [AutoHotkey v2](https://www.autohotkey.com/).
2. Klik dua kali pada file `cheat_assistant.ahk`.
3. Ikon script akan muncul di System Tray (sudut kanan bawah taskbar).

### Cara 2: Compile ke File Mandiri (.exe)
1. **Otomatis via Batch File**:
   - Jalankan `compile.bat`.
   - Jika compiler `Ahk2Exe` terdeteksi di sistem, file `cheat_assistant.exe` akan langsung dibuat di folder yang sama.
2. **Manual via Ahk2Exe GUI**:
   - Buka program **Ahk2Exe** (bisa dicari di menu Start Windows).
   - Di kolom **Source (script file)**: Pilih `cheat_assistant.ahk`.
   - Di kolom **Destination (.exe file)**: Tentukan lokasi file output (misal: `cheat_assistant.exe`).
   - Di kolom **Base File (.bin)**: Pilih `AutoHotkey64.exe` (v2).
   - Klik **Convert**.
   - Selesai! File `.exe` dapat dijalankan di komputer Windows mana pun tanpa perlu menginstal AutoHotkey.

