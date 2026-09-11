# Survivor Leveling & Advancement [B42]

Dapatkan poin dengan meningkatkan keterampilan, lalu gunakan untuk keterampilan pilihanmu. SLA menambahkan Level Penyintas dan Poin Peningkatan ke panel Keterampilan biasa, sambil mempertahankan perkembangan alami. Ingin sebagian kemajuanmu selamat dari keputusan buruk berikutnya? Pewarisan level opsional membuat karakter berikutnya menerima persentase Level Penyintasmu beserta poin baru untuk digunakan.

Mendukung pemain tunggal, multipemain, layar terbagi, dan kontroler. Tanpa dependensi wajib.

## Cara kerja peningkatan

XP dari keterampilan yang didukung juga menaikkan Level Penyintas. Setiap Level Penyintas memberi satu Poin Peningkatan, atau AP. Gunakan AP melalui tombol **+** di samping keterampilan. Secara bawaan, tiga Slot Peningkatan dapat terisi sekaligus. Melatih keterampilan yang ditingkatkan membebaskan slotnya saat kamu mengejar XP yang dilewati. XP tersebut juga dihitung menuju level keterampilan berikutnya.

Peningkatan terakhir hingga batas efektif keterampilan, biasanya dari level 9 ke 10, dianggap penguasaan penuh. Biayanya 2 AP dan membutuhkan 2 Slot Peningkatan kosong, lalu membebaskan semua slot aktif keterampilan itu. Jika batas Gabungan atau Per Keterampilan adalah 1, penguasaan hanya perlu 1 slot kosong, tetapi tetap berbiaya 2 AP. Mode Bebas tidak memerlukan slot dan tetap berbiaya 2 AP. Keterampilan pada batas efektifnya tidak menghasilkan XP Penyintas tambahan.

## Pertahankan kemajuan setelah meninggal

Aktifkan pewarisan Level Penyintas dan tentukan bagian yang diterima karakter berikutnya di dunia yang sama. Misalnya, meninggal pada Level Penyintas 20 dengan pewarisan 50% memberi karakter berikutnya Level Penyintas 10 dan 10 AP. Level keterampilan lama tidak disalin, sehingga kamu bebas memilih penggunaan poin warisan. Pewarisan bersifat opsional dan nonaktif secara bawaan.

## Pengaturan

- **Gabungan:** Semua keterampilan berbagi kumpulan Slot Peningkatan yang dapat diatur, dengan batas bawaan total 3 slot aktif.
- **Per Keterampilan:** Setiap keterampilan memiliki batas tersendiri yang dapat diatur. Keterampilan tambahan yang kompatibel memakai nilai bawaan, sedangkan keterampilan game dasar dapat diberi pengaturan khusus.
- **Bebas:** Menghapus batas Slot Peningkatan dan pembatasan pengejaran XP.
- Atur laju XP Penyintas tanpa mengubah XP keterampilan. Pilih apakah kebugaran, kekuatan, setiap keterampilan game dasar, dan keterampilan tambahan yang kompatibel ikut berkontribusi.
- Di Opsi Mod, aktifkan penanda peningkatan berkontras lebih tinggi atau persentase XP Penyintas pemain 1 pada jam digital.
- Mendukung semua bahasa standar dalam pengaturan bahasa Project Zomboid. Seluruh terjemahan dibuat sepenuhnya oleh AI. Laporkan jika ada teks keliru atau membingungkan.

**Catatan:** Berganti mode tidak mereset kemajuan yang tercatat. XP keterampilan alami yang diperoleh dalam mode Bebas tetap mengurangi sisa pengejaran biru yang tersimpan. Kembali ke Gabungan atau Per Keterampilan hanya memulihkan bagian yang masih tersisa.

## Menambahkan atau menghapus SLA

SLA dapat ditambahkan ke atau dihapus dari simpanan yang sudah ada. Keterampilan tetap terjaga, dan kemajuan lama tidak memberi Level Penyintas secara retroaktif. Menonaktifkan SLA menyembunyikan antarmukanya tetapi mempertahankan level keterampilan yang diperoleh dengan AP. Mengaktifkannya kembali memulihkan status SLA dan memperhitungkan perkembangan yang didukung selama SLA tidak aktif. Seperti setiap perubahan daftar mod, saya sangat menyarankan mencadangkan dunia berjalan yang penting bagimu.

## Server khusus dan hosting

Admin dapat memberi XP Penyintas atau level utuh ke profil yang sudah ada, baik daring maupun luring. Pemberian luring langsung berlaku. Hapus Peningkatan membebaskan slot tanpa mengembalikan AP atau mengubah XP keterampilan. Untuk karakter luring, penghapusan tertunda dan dapat dibatalkan sampai mereka tersambung kembali. Mengedit level melalui Statistik Pemain menghapus pencatatan keterampilan tersebut.

SLA memakai sistem simpanan biasa Project Zomboid. Pada server hosting dan khusus, aktifkan SaveWorldEveryMinutes dan matikan server secara normal.

## Kompatibilitas

- **Tidak kompatibel: [RPG Skills Systems B42 / RPGMenu](https://steamcommunity.com/sharedfiles/filedetails/?id=3666281346)**
- **Belum didukung: [Beyond Ten - Level 15 Skills](https://steamcommunity.com/sharedfiles/filedetails/?id=3765241705) dan [Seesaw Game](https://steamcommunity.com/sharedfiles/filedetails/?id=3515515643)**. Mod ini langsung mengganti aturan perkembangan yang diandalkan SLA.
- **Bergantung urutan pemuatan: [Detailed Skill Tooltips](https://steamcommunity.com/sharedfiles/filedetails/?id=3572846242)**. Muat SLA setelah Detailed Skill Tooltips untuk menambahkan teks pengejaran biru SLA ke tooltip keterampilan DST yang diperluas. Jika SLA dimuat lebih dulu, hanya teks tersebut yang tertimpa. Perkembangan Level Penyintas dan tooltip tombol + tetap berfungsi.
- **Diuji bersama: [Detailed Skill Tooltips](https://steamcommunity.com/sharedfiles/filedetails/?id=3572846242), [Toughness Skill](https://steamcommunity.com/sharedfiles/filedetails/?id=3545533939), dan [Show Skill XP Gain B42.20](https://steamcommunity.com/sharedfiles/filedetails/?id=3776490883)**. Kombinasi ini berjalan tanpa masalah saat diuji, tetapi kompatibilitas dengan setiap mod antarmuka atau keterampilan tambahan tidak dapat dijamin.
- Mod yang mengganti penanganan XP keterampilan, batas atau kurvanya, panel Keterampilan, menu pemain, atau tampilan jam digital dapat berbenturan. SLA menonaktifkan integrasi yang terdampak jika kaitan yang dibutuhkannya diganti. Keterampilan tambahan yang kompatibel memerlukan kurva XP yang dapat digunakan dan peristiwa XP yang didukung. Pengaturan keterampilan secara langsung atau jalur perkembangan tanpa peristiwa tersebut tidak menghasilkan XP Penyintas.

## Penggunaan AI

AI digunakan untuk menulis seluruh kode proyek ini. Konsep awal, arah desain, pengujian, penelusuran masalah, dan keputusan rilis adalah milik saya. Saya menghabiskan banyak waktu menguji SLA sendiri dan mengatasi masalah agar berfungsi sesuai tujuan. Jika kamu lebih suka tidak memakai mod yang dikembangkan dengan bantuan AI, saya memahami dan menghargai pilihan itu.

## Dukungan

- Donasi melalui [Ko-fi](https://ko-fi.com/skeptic043) bersifat opsional. Tidak ada fitur mod yang terkunci di balik pembayaran.

## Informasi mod

- Dikembangkan/diuji pada versi: 42.20.4
- Dependensi wajib: Tidak ada
- Lisensi: MIT
- [Kode sumber dan pelaporan masalah](https://github.com/Skeptic043/survivor-leveling-and-advancement)
