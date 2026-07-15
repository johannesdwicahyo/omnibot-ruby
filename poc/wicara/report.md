# Wicara Engine-Swap PoC Report

- Date: 2026-07-15T13:02:58Z
- Bot: id=019df209-6d8a-771e-8677-96eb3f60a1fa slug=(auto-selected)
- Model: gpt-4o-mini
- Messages: 15

## Messages

### 1. greeting_fast_path (expect: greeting_fast_path)

**User:** halo

**Python:** Halo! Ada yang bisa saya bantu hari ini?

**Ruby:** Halo! Ada yang bisa saya bantu hari ini?

| | Python | Ruby |
|---|---|---|
| tool_calls |  |  |
| citations |  |  |
| tokens (prompt/completion) | 642/11 | 636/11 |
| latency ms | 3203 | 1595 |

**Judge:** YES — YES, both replies offer the same greeting and assistance in identical wording.

### 2. greeting_fast_path (expect: greeting_fast_path)

**User:** selamat pagi

**Python:** Selamat pagi! Apa yang bisa saya bantu untuk Anda hari ini?

**Ruby:** Selamat pagi! Apa yang bisa saya bantu untuk Anda hari ini?

| | Python | Ruby |
|---|---|---|
| tool_calls |  |  |
| citations |  |  |
| tokens (prompt/completion) | 663/15 | 657/15 |
| latency ms | 1560 | 1165 |

**Judge:** YES — YES, both replies convey the same message and offer help to the user.

### 3. kb_question (expect: kb_answer)

**User:** What do you offer?

**Python:** Wokku menawarkan berbagai layanan, termasuk:

1. **Dokumen Digital**: Platform untuk tanda tangan dokumen secara digital.
2. **Manajemen Proyek**: Alat untuk mengelola proyek dan papan kanban.
3. **Server Musik**: Server musik modern yang kompatibel dengan klien Subsonic/Airsonic.
4. **Kolaborasi Tim**: Platform komunikasi tim dengan video konferensi dan berbagi file.

Jika Anda ingin informasi lebih lanjut tentang layanan tertentu, silakan beri tahu!

**Ruby:** Wokku menawarkan berbagai layanan pengembangan aplikasi menggunakan berbagai framework, termasuk:

1. **Next.js** - Framework React dengan SSR dan generasi statis, mulai dari Rp 22.500/bulan.
2. **Nuxt.js** - Framework Vue.js intuitif, mulai dari Rp 22.500/bulan.
3. **Phoenix** - Framework Elixir untuk aplikasi yang produktif, mulai dari Rp 37.500/bulan.
4. **Django** - Framework Python, mulai dari Rp 37.500/bulan.

Jika Anda ingin informasi lebih lanjut tentang layanan tertentu, silakan beri tahu!

| | Python | Ruby |
|---|---|---|
| tool_calls | search_knowledge_base | search_knowledge_base |
| citations | [019dfcc4-f10f-77b2-95d2-76bed875fc68:30], [019dfcc4-f10f-77b2-95d2-76bed875fc68:43], [019dfcc4-f10f-77b2-95d2-76bed875fc68:18], [019dfcc4-f10f-77b2-95d2-76bed875fc68:26], [019dfcc4-f10f-77b2-95d2-76bed875fc68:20] | [019dfc5e-bbf3-7d07-82ce-3a3413ed5a18:59], [019dfcc4-f10f-77b2-95d2-76bed875fc68:21], [019dfcc4-f10f-77b2-95d2-76bed875fc68:3], [019dfcc4-f10f-77b2-95d2-76bed875fc68:2], [019dfcc4-f10f-77b2-95d2-76bed875fc68:9] |
| tokens (prompt/completion) | 2882/128 | 2681/146 |
| latency ms | 4721 | 5425 |

**Judge:** NO — NO, because reply A describes a variety of services, including digital document management and project management, while reply B focuses specifically on application development services using different frameworks.

### 4. kb_question (expect: kb_answer)

**User:** How much does it cost?

**Python:** Saya tidak menemukan informasi spesifik tentang biaya layanan Wokku. Untuk informasi lebih lanjut mengenai harga, saya sarankan Anda mengunjungi situs resmi Wokku atau menghubungi tim dukungan mereka. Jika ada yang lain yang bisa saya bantu, silakan beri tahu!

**Ruby:** Biaya layanan Wokku bervariasi tergantung pada framework yang digunakan. Berikut adalah beberapa contoh harga:

1. **Next.js** - Mulai dari Rp 22.500/bulan.
2. **Nuxt.js** - Mulai dari Rp 22.500/bulan.
3. **Phoenix** - Mulai dari Rp 37.500/bulan.
4. **Django** - Mulai dari Rp 37.500/bulan.

Jika Anda memerlukan informasi lebih lanjut atau detail tentang layanan tertentu, silakan beri tahu!

| | Python | Ruby |
|---|---|---|
| tool_calls | search_knowledge_base | search_knowledge_base |
| citations | [019dfcc4-f10f-77b2-95d2-76bed875fc68:16], [019dfcc4-f10f-77b2-95d2-76bed875fc68:33], [019dfcc4-f10f-77b2-95d2-76bed875fc68:45], [019dfc5e-bbf3-7d07-82ce-3a3413ed5a18:34], [019dfcc4-f10f-77b2-95d2-76bed875fc68:37] | [019dfcc4-f10f-77b2-95d2-76bed875fc68:16], [019dfcc4-f10f-77b2-95d2-76bed875fc68:33], [019dfcc4-f10f-77b2-95d2-76bed875fc68:45], [019dfc5e-bbf3-7d07-82ce-3a3413ed5a18:34], [019dfcc4-f10f-77b2-95d2-76bed875fc68:37] |
| tokens (prompt/completion) | 3156/75 | 3182/133 |
| latency ms | 4581 | 4254 |

**Judge:** NO — NO, because A does not provide any cost information while B gives specific pricing details for various services.

### 5. kb_question (expect: kb_answer)

**User:** How do I get started?

**Python:** Untuk memulai dengan Wokku, Anda dapat mengikuti langkah-langkah berikut:

1. **Daftar Akun**: Kunjungi situs resmi Wokku dan buat akun baru.
2. **Pilih Layanan**: Tentukan layanan yang ingin Anda gunakan, seperti database atau manajemen proyek.
3. **Ikuti Panduan**: Ikuti panduan di dashboard untuk mengonfigurasi layanan yang Anda pilih.
4. **Mulai Proyek**: Setelah konfigurasi selesai, Anda dapat mulai membuat dan mengelola proyek Anda.

Jika Anda memerlukan bantuan lebih lanjut, silakan beri tahu!

**Ruby:** Untuk memulai dengan Wokku, Anda dapat mengikuti langkah-langkah berikut:

1. **Daftar Akun**: Kunjungi situs Wokku dan buat akun baru.
2. **Pilih Layanan**: Pilih framework atau layanan yang ingin Anda gunakan (misalnya, Next.js, Django).
3. **Atur Proyek**: Ikuti petunjuk untuk mengatur proyek Anda, termasuk pengaturan database dan cache jika diperlukan.
4. **Deploy Aplikasi**: Gunakan fitur auto-deploy dari GitHub atau metode lain untuk meluncurkan aplikasi Anda.
5. **Manfaatkan Free Tier**: Jika Anda baru mulai, gunakan free tier untuk mencoba layanan tanpa biaya.

Jika Anda memerlukan bantuan lebih lanjut, silakan beri tahu!

| | Python | Ruby |
|---|---|---|
| tool_calls | search_knowledge_base | search_knowledge_base |
| citations | [019dfc5e-bbf3-7d07-82ce-3a3413ed5a18:66], [019dfc5e-bbf3-7d07-82ce-3a3413ed5a18:34], [019dfc5e-bbf3-7d07-82ce-3a3413ed5a18:69], [019dfca2-54ba-7b71-98b3-f6836b4e54da:0], [019dfc5e-bbf3-7d07-82ce-3a3413ed5a18:68] | [019dfc5e-bbf3-7d07-82ce-3a3413ed5a18:66], [019dfc5e-bbf3-7d07-82ce-3a3413ed5a18:34], [019dfc5e-bbf3-7d07-82ce-3a3413ed5a18:69], [019dfca2-54ba-7b71-98b3-f6836b4e54da:0], [019dfc5e-bbf3-7d07-82ce-3a3413ed5a18:68] |
| tokens (prompt/completion) | 3172/150 | 3314/182 |
| latency ms | 4330 | 5122 |

**Judge:** PARTIAL — PARTIAL, because both replies offer steps to get started with Wokku but they detail different processes and levels of complexity in terms of services and project setup.

### 6. kb_question (expect: kb_answer)

**User:** Do you have documentation about your features?

**Python:** Ya, Wokku memiliki dokumentasi tentang fitur-fiturnya. Anda dapat menemukan informasi mengenai:

1. **Notifikasi**: Mengatur notifikasi untuk berbagai peristiwa seperti deploy dan kegagalan.
2. **Log Aplikasi**: Melihat log aplikasi dan meneruskannya ke layanan eksternal.
3. **Pemulihan Database**: Memulihkan database dari cadangan melalui antarmuka web.
4. **Matrix Izin**: Menjelaskan apa yang dapat dilakukan setiap peran dalam tim.

Untuk detail lebih lanjut, silakan kunjungi situs resmi Wokku atau bagian dokumentasi mereka. Jika ada yang ingin Anda ketahui lebih lanjut, beri tahu saya!

**Ruby:** Ya, Wokku memiliki dokumentasi tentang fitur-fitur yang tersedia. Anda dapat menemukan informasi mengenai:

1. **Notifikasi** - Mengatur notifikasi untuk deploy, kegagalan, dan peristiwa server.
2. **Log Aplikasi** - Melihat log aplikasi dan meneruskannya ke layanan eksternal.
3. **Izin** - Matriks izin untuk berbagai peran (Viewer, Member, Admin).

Jika Anda memerlukan akses ke dokumentasi lengkap atau informasi lebih lanjut, silakan beri tahu!

| | Python | Ruby |
|---|---|---|
| tool_calls | search_knowledge_base | search_knowledge_base |
| citations | [019dfc5e-bbf3-7d07-82ce-3a3413ed5a18:45], [019dfc5e-bbf3-7d07-82ce-3a3413ed5a18:46], [019dfc5e-bbf3-7d07-82ce-3a3413ed5a18:41], [019dfc5e-bbf3-7d07-82ce-3a3413ed5a18:38], [019dfc5e-bbf3-7d07-82ce-3a3413ed5a18:48] | [019dfc5e-bbf3-7d07-82ce-3a3413ed5a18:45], [019dfc5e-bbf3-7d07-82ce-3a3413ed5a18:46], [019dfc5e-bbf3-7d07-82ce-3a3413ed5a18:41], [019dfc5e-bbf3-7d07-82ce-3a3413ed5a18:38], [019dfc5e-bbf3-7d07-82ce-3a3413ed5a18:48] |
| tokens (prompt/completion) | 2784/163 | 1966/127 |
| latency ms | 5007 | 4785 |

**Judge:** PARTIAL — PARTIAL, as both replies indicate the availability of documentation and list features but differ in the specific features described and the level of detail provided.

### 7. followup (expect: followup)

**User:** Can you explain that more simply?

**Python:** Wokku memiliki beberapa fitur utama yang dapat dijelaskan dengan lebih sederhana:

1. **Melihat Log**: Anda bisa melihat catatan aktivitas aplikasi untuk membantu menemukan masalah.
2. **Mengatur Notifikasi**: Dapat mengatur pemberitahuan untuk berbagai peristiwa penting.
3. **Pemulihan Database**: Memudahkan pemulihan data dari cadangan jika terjadi kesalahan.
4. **Pengaturan Izin**: Menentukan apa yang bisa dilakukan oleh setiap anggota tim.

Jika Anda ingin tahu lebih banyak tentang salah satu fitur, silakan beri tahu!

**Ruby:** Berikut penjelasan sederhana tentang fitur-fitur Wokku:

1. **Notifikasi**: Anda bisa mendapatkan pemberitahuan tentang aktivitas seperti deploy dan kesalahan. Notifikasi bisa dikirim melalui email, Slack, Discord, dan lainnya.

2. **Log Aplikasi**: Anda dapat melihat log dari aplikasi Anda dan mengirimkannya ke layanan lain jika diperlukan.

3. **Izin**: Ada tiga peran (Viewer, Member, Admin) dengan hak akses yang berbeda. Misalnya, hanya Admin yang bisa menghapus aplikasi atau mengelola anggota tim.

Jika Anda butuh informasi lebih lanjut, silakan beri tahu!

| | Python | Ruby |
|---|---|---|
| tool_calls | search_knowledge_base | search_knowledge_base |
| citations | [019dfc5e-bbf3-7d07-82ce-3a3413ed5a18:27], [019dfc5e-bbf3-7d07-82ce-3a3413ed5a18:41], [019dfc5e-bbf3-7d07-82ce-3a3413ed5a18:15], [019dfc5e-bbf3-7d07-82ce-3a3413ed5a18:42], [019dfc5e-bbf3-7d07-82ce-3a3413ed5a18:62] | [019dfc5e-bbf3-7d07-82ce-3a3413ed5a18:45], [019dfc5e-bbf3-7d07-82ce-3a3413ed5a18:46], [019dfc5e-bbf3-7d07-82ce-3a3413ed5a18:41], [019dfc5e-bbf3-7d07-82ce-3a3413ed5a18:38], [019dfc5e-bbf3-7d07-82ce-3a3413ed5a18:48] |
| tokens (prompt/completion) | 3501/139 | 2080/151 |
| latency ms | 5839 | 4929 |

**Judge:** PARTIAL — PARTIAL, as both replies attempt to simplify the explanation of Wokku's features but highlight different aspects and details of those features.

### 8. followup (expect: followup)

**User:** And what was the first thing you mentioned?

**Python:** Hal pertama yang saya sebutkan adalah **melihat log**. Ini memungkinkan Anda untuk melihat catatan aktivitas aplikasi, yang membantu dalam menemukan dan memperbaiki masalah yang mungkin terjadi. Jika Anda ingin informasi lebih lanjut tentang fitur ini, silakan beri tahu!

**Ruby:** Hal pertama yang saya sebutkan adalah **Notifikasi**. Fitur ini memungkinkan Anda untuk menerima pemberitahuan tentang aktivitas penting seperti proses deploy dan kesalahan yang terjadi pada aplikasi Anda. Notifikasi ini bisa dikirim melalui berbagai saluran seperti email, Slack, atau Discord. Jika Anda ingin tahu lebih banyak tentang fitur ini, silakan beri tahu!

| | Python | Ruby |
|---|---|---|
| tool_calls |  |  |
| citations |  |  |
| tokens (prompt/completion) | 1295/53 | 1374/72 |
| latency ms | 2153 | 2821 |

**Judge:** NO — NO, the two replies mention different features, "melihat log" in A and "Notifikasi" in B, so they do not convey equivalent answers.

### 9. handover_request (expect: handover)

**User:** I want to talk to a human agent please

**Python:** Saya tidak dapat menghubungkan Anda langsung dengan agen manusia. Namun, Anda dapat mengunjungi situs resmi Wokku untuk menemukan opsi dukungan pelanggan atau kontak langsung. Jika ada yang lain yang bisa saya bantu, silakan beri tahu!

**Ruby:** Saya tidak dapat menghubungkan Anda langsung dengan agen manusia. Namun, Anda dapat mengunjungi situs Wokku untuk mendapatkan dukungan lebih lanjut atau menghubungi tim layanan pelanggan mereka. Jika ada yang bisa saya bantu lagi, silakan beri tahu!

| | Python | Ruby |
|---|---|---|
| tool_calls |  |  |
| citations |  |  |
| tokens (prompt/completion) | 1339/49 | 1437/52 |
| latency ms | 2280 | 2150 |

**Judge:** PARTIAL — PARTIAL, because both replies indicate that the user cannot be connected to a human agent and suggest visiting the Wokku site for further assistance, but they use slightly different wording regarding support options and customer service contact.

### 10. lead_capture (expect: lead_capture)

**User:** My name is Budi, email budi@example.com — please contact me

**Python:** Saya tidak dapat menghubungi Anda secara langsung atau mengirim email. Saya sarankan Anda mengunjungi situs resmi Wokku untuk mendapatkan dukungan atau menghubungi tim mereka melalui informasi kontak yang tersedia. Jika ada yang lain yang bisa saya bantu, silakan beri tahu!

**Ruby:** Saya tidak dapat menghubungi Anda secara langsung atau mengirim email. Untuk mendapatkan bantuan lebih lanjut, silakan kunjungi situs Wokku dan cari opsi dukungan pelanggan. Jika ada pertanyaan lain, saya siap membantu!

| | Python | Ruby |
|---|---|---|
| tool_calls |  |  |
| citations |  |  |
| tokens (prompt/completion) | 1290/57 | 1372/47 |
| latency ms | 2021 | 2168 |

**Judge:** PARTIAL — PARTIAL, both responses indicate the inability to contact the user directly and suggest visiting the official site for assistance, but they use different phrasing and slight variations in detail about support options.

### 11. anger (expect: anger_handover)

**User:** This tai, nothing works at all

**Python:** Maaf mendengar bahwa Anda mengalami kesulitan. Jika Anda bisa memberikan detail lebih lanjut tentang masalah yang Anda hadapi, saya akan berusaha membantu sebaik mungkin. Apakah ada fitur tertentu yang tidak berfungsi?

**Ruby:** Maaf mendengar bahwa Anda mengalami masalah. Untuk membantu Anda lebih baik, bisa Anda jelaskan masalah spesifik yang Anda hadapi? Saya akan berusaha memberikan solusi atau informasi yang tepat.

| | Python | Ruby |
|---|---|---|
| tool_calls |  |  |
| citations |  |  |
| tokens (prompt/completion) | 1292/45 | 1306/39 |
| latency ms | 2111 | 1855 |

**Judge:** YES — YES, both replies express sympathy and request more details in order to assist the user with their issue.

### 12. anger (expect: anger_handover)

**User:** shit, this still does not work at all

**Python:** Saya minta maaf atas ketidaknyamanan yang Anda alami. Jika Anda bisa menjelaskan masalah spesifik yang Anda hadapi, saya akan berusaha membantu. Jika tidak, saya sarankan untuk menghubungi dukungan pelanggan Wokku untuk mendapatkan bantuan lebih lanjut.

**Ruby:** Saya minta maaf atas ketidaknyamanan yang Anda alami. Jika Anda bisa memberikan detail lebih lanjut tentang masalah yang Anda hadapi, saya akan berusaha membantu sebaik mungkin. Jika tidak, saya sarankan untuk menghubungi dukungan pelanggan Wokku untuk mendapatkan bantuan langsung.

| | Python | Ruby |
|---|---|---|
| tool_calls |  |  |
| citations |  |  |
| tokens (prompt/completion) | 1213/56 | 1189/59 |
| latency ms | 2014 | 2629 |

**Judge:** YES — YES, both replies express the same sentiments and suggest contacting customer support for further assistance while offering help if more details are provided.

### 13. chit_chat (expect: chit_chat)

**User:** What's the weather like?

**Python:** Saya tidak memiliki informasi tentang cuaca saat ini. Anda dapat memeriksa aplikasi cuaca atau situs web cuaca untuk mendapatkan informasi terkini. Jika ada yang lain yang bisa saya bantu, silakan beri tahu!

**Ruby:** Maaf, saya tidak dapat memberikan informasi cuaca. Anda bisa memeriksa aplikasi cuaca atau situs web cuaca untuk mendapatkan informasi terkini. Jika ada yang lain yang bisa saya bantu, silakan beri tahu!

| | Python | Ruby |
|---|---|---|
| tool_calls |  |  |
| citations |  |  |
| tokens (prompt/completion) | 1123/44 | 1138/45 |
| latency ms | 1742 | 1760 |

**Judge:** YES — YES, both replies indicate that the assistant cannot provide weather information and suggest using a weather app or website for updates.

### 14. chit_chat (expect: chit_chat)

**User:** Tell me a joke

**Python:** Tentu! Berikut leluconnya:

Kenapa komputer tidak bisa berkelahi?

Karena mereka takut dengan virus! 

Semoga itu membuat Anda tersenyum! Jika ada yang lain yang ingin Anda bicarakan, silakan beri tahu!

**Ruby:** Tentu! Berikut leluconnya:

Kenapa komputer tidak bisa berkelahi?

Karena mereka takut dengan virus! 

Semoga itu membuat Anda tersenyum! Jika ada yang lain yang ingin Anda bicarakan, silakan beri tahu.

| | Python | Ruby |
|---|---|---|
| tool_calls |  |  |
| citations |  |  |
| tokens (prompt/completion) | 1045/52 | 1049/52 |
| latency ms | 2506 | 1721 |

**Judge:** YES — YES, both replies provide the same joke and offer the same closing statement.

### 15. multi_tool (expect: multi_tool)

**User:** Search your knowledge base for pricing AND connect me to a human

**Python:** Saya menemukan informasi tentang harga dan proses yang terkait, tetapi tidak ada informasi spesifik tentang menghubungkan Anda dengan agen manusia. 

Untuk harga, Wokku menawarkan model harga bulanan yang sederhana dengan berbagai paket untuk aplikasi dan database, termasuk opsi gratis. Untuk detail lebih lanjut, Anda bisa mengunjungi situs resmi Wokku.

Jika Anda memerlukan bantuan lebih lanjut, saya sarankan untuk menghubungi dukungan pelanggan Wokku secara langsung melalui situs mereka. Jika ada yang lain yang bisa saya bantu, silakan beri tahu!

**Ruby:** Saya menemukan informasi tentang harga Wokku. Berikut adalah ringkasan:

- **App Containers**: Terdapat beberapa tingkatan seperti Free, Basic, Standard, Performance, dan Performance 2x.
- **Databases**: Menawarkan layanan database terkelola seperti PostgreSQL, MySQL, dan MongoDB dengan berbagai tingkatan.
- **Lainnya**: Termasuk cache (Redis, Memcached), pencarian (Elasticsearch, Meilisearch), dan antrian (RabbitMQ, NATS).

Untuk menghubungi agen manusia, saya tidak dapat melakukan itu secara langsung. Anda disarankan untuk mengunjungi situs Wokku dan mencari opsi dukungan pelanggan. Jika ada pertanyaan lain, silakan beri tahu!

| | Python | Ruby |
|---|---|---|
| tool_calls | search_knowledge_base, search_knowledge_base | search_knowledge_base, search_knowledge_base |
| citations | [019dfc5e-bbf3-7d07-82ce-3a3413ed5a18:39], [019dfc5e-bbf3-7d07-82ce-3a3413ed5a18:70], [019dfc5e-bbf3-7d07-82ce-3a3413ed5a18:3], [019dfca2-54ba-7b71-98b3-f6836b4e54da:0], [019dfcc4-f10f-77b2-95d2-76bed875fc68:0], [019dfc5e-bbf3-7d07-82ce-3a3413ed5a18:9], [019dfc5e-bbf3-7d07-82ce-3a3413ed5a18:2], [019dfc5e-bbf3-7d07-82ce-3a3413ed5a18:22], [019dfcc4-f10f-77b2-95d2-76bed875fc68:10], [019dfcc4-f10f-77b2-95d2-76bed875fc68:1] | [019dfc5e-bbf3-7d07-82ce-3a3413ed5a18:9], [019dfc5e-bbf3-7d07-82ce-3a3413ed5a18:2], [019dfc5e-bbf3-7d07-82ce-3a3413ed5a18:22], [019dfcc4-f10f-77b2-95d2-76bed875fc68:10], [019dfcc4-f10f-77b2-95d2-76bed875fc68:1] |
| tokens (prompt/completion) | 4107/161 | 3053/204 |
| latency ms | 6605 | 7738 |

**Judge:** PARTIAL — PARTIAL, both replies provide pricing information but differ in the level of detail and specific mention of the process to contact human support.

## Hard Parity Checks

| Check | Status | Detail |
|---|---|---|
| greeting_fast_path | SKIPPED | bot has no greeting_menu configured |
| kb_citations | FAIL | "What do you offer?": MISMATCH (python=5 ruby=5); "How much does it cost?": EXACT (python=5 ruby=5); "How do I get started?": EXACT (python=5 ruby=5); "Do you have documentation about your features?": EXACT (python=5 ruby=5) |
| handover | FAIL | python_requested=false ruby_requested=false |
| anger_handover | SKIPPED | handover_on_anger_threshold is 0 |

## Judge Tally

- YES: 6
- PARTIAL: 6
- NO: 3
- ERROR: 0
- Total judged: 15
- YES+PARTIAL rate: 80.0%

## Totals

- Python tokens: 30702, Ruby tokens: 27769, ratio (ruby/python): 0.9
- Python latency ms: 50673, Ruby latency ms: 50117, ratio (ruby/python): 0.99

## Documented Asymmetries

1. **capture_lead**: Python's `capture_lead` really POSTs to Rails `/internal/contacts/upsert` (may create a dev contact row); the Ruby stub returns a canned success string with no HTTP call.
2. **Turn-limit semantics**: Python `ITERATION_CAP=4` counts LLM calls; Ruby `max_turns 4` counts tool executions (each parallel tool call in a round counts separately) — not the same quantity, so the two can diverge on multi-tool turns.
3. **Anger counter**: both sides use an in-memory, single-process `Hash`/dict counter with no TTL or persistence; a process restart resets it, and it isn't shared across processes.

## Success Criteria

- All hard checks pass (non-SKIPPED): FAIL
- Judge >= 80% YES/PARTIAL: PASS (80.0%)
- Zero Ruby exceptions: PASS (0 exceptions)
- Tokens within 2x: PASS (ratio 0.9)
- Latency within 2x: PASS (ratio 0.99)

**Overall: NO-GO** (judge % and the 2x token/latency ratios are reported for human review, not gating.)