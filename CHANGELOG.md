# Changelog

Bu dosya `/opt/scripts` altindaki Codexify betiginin surum gecmisini tutar.

## [1.8] - 2026-03-22

### Added
- `update.sh` projeye eklendi ve ana menuye GitHub sync, pull ve push akislari baglandi.
- Script logu, auto sender logu ve tum loglari temizleme secenekleri eklendi.
- Ana menuye Codexify gelistirme onerilerini gosteren "Gelistirme Listeleri" ekrani eklendi.
- Bash tabanli unit test ortami eklendi; prompt dogrulama akisi `verify.sh` icinden calistirilir hale getirildi.

### Changed
- Otomatik gonderim her turda taslaktaki guncel promptu yeniden okuyacak sekilde guncellendi.
- Ana menu ve prompt/otomasyon menusu daha az satir kullanacak sekilde sadeleştirildi.
- Prompt yapistirma dogrulamasi, eski pane gecmisindeki ayni metni yeni yapistirma sanmayacak sekilde snapshot karsilastirmali hale getirildi.
- Prompt yapistirma akisi `tmux paste-buffer` plain moduna alinerek bracketed paste yan etkileri kaldirildi.

### Removed
- "Son promptu tekrar gonder" secenegi kaldirildi.

### Fixed
- Otomatik gonderimde veya ayni prompt tekrarlandiginda, gecmiste gorunen ayni imza nedeniyle yanlislikla `Enter` basilip `/transcripts` benzeri gecersiz komutlarin gonderilmesine yol acan yanlis pozitif durum giderildi.
- Snapshot'ta yalnizca `~` gorunmesine yol acabilen `tmux paste-buffer -p` kaynakli yapistirma bozulmasi giderildi.

## [1.7] - 2026-03-22

### Added
- `setup.sh`, `requirements.txt`, `verify.sh`, `README.md`, `.gitignore`, `.editorconfig` ve GitHub Actions dogrulama akisi eklendi.

### Changed
- Dashboard icindeki tekrarli `Kisa Bilgi` bolumu kaldirildi; oturuma baglanis bilgisi sadece gerekli akista birakildi.
- `/status` gonderimi normal prompt akisiyla ayni dogrulamali mekanizmaya tasindi.

### Fixed
- Menu uzerinden `/status` komutunun ilk denemede gonderilmemesi sorunu giderildi.

## [1.6] - 2026-03-22

### Added
- `versions/` klasoru olusturuldu ve `codexify1.1.sh` - `codexify1.5.sh` arsivlendi.
- `CHANGELOG.md` ve `PLAN.md` eklendi.
- Otomatik gonderim icin ayri auto log sifirlama ve daha net hata kayitlari eklendi.

### Changed
- Final giris noktasi `codexify.sh`, `1.5` tabani uzerinden profesyonel kullanim icin yenilendi.
- Prompt gonderimi dogrulama mantigi sertlestirildi; prompt ekranda gorulmeden `Enter` gonderilmiyor.
- Prompt gondermeden once giris alani sifirlaniyor; yarim kalmis satirlarla cakisma riski azaltildi.
- `pane_snapshot` kapsami buyutuldu; hazir ekran ve prompt gorunurlugu kontrolu daha dayanikli hale getirildi.
- `start_auto_sender` parametre ve taslak kontrolu guclendirildi.
- Dashboard ve yardim metinleri final davranisi yansitacak sekilde guncellendi.

### Fixed
- Otomatik gonderimde prompt dogrulanamadigi halde bos veya eksik komutun `Enter` ile gonderilmesi engellendi.
- Auto sender baslatilirken bos/okunamayan taslak prompt ile devam edilmesi engellendi.
- Baslangic modu icin gecersiz degerlerin arka planda hatali calismaya yol acmasi engellendi.

## [1.5] - Arsivlendi
- Gelismis dashboard, taslak prompt yapisi ve dogrulamali gonderim mantiginin ilk genis surumu.

## [1.4] - Arsivlendi
- Menu yapisi alt menulere ayrildi, izleme ve otomasyon akislari genisletildi.

## [1.3] - Arsivlendi
- Taslak prompt mantigi ve degisiklik ozeti loglama eklendi.

## [1.2] - Arsivlendi
- Renkli arayuz, review/test promptlari ve daha guclu dashboard yapisi eklendi.

## [1.1] - Arsivlendi
- `todo.md` odakli ilk coklu prompt taslagi ve proje bazli log yapisi eklendi.
