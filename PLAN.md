# Plan

Bu dosya mevcut eksikleri ve gelistirilebilecek alanlari izlemek icin tutulur.

## Oncelikli

- `versions/` altindaki eski scriptler halen `todo.md` referansi tasiyor. Ya arxiv olduklari net bicimde ayrilmali ya da toplu sekilde `PLAN.md` uyumlu hale getirilmeli.
- `tmux` ve `codex` bagimliliklari gercek terminal acmadan test edilebilmeli. Sahte binary veya fixture tabanli bash testleri gerekli.
- Dashboard `clear` ve interaktif menu akisi uzerine kurulu. TTY olmayan ortamlarda veya script otomasyonunda sade CLI modu onceliklendirilmeli.

## Son Yapilanlar

- `tmux paste-buffer -p` kullanimindan kaynaklanabilen bracketed paste regresyonu giderildi; prompt gonderimi plain `paste-buffer` yoluna alindi.
- Bash unit testleri `paste-buffer -p` kullanimini regresyon olarak yakalayacak sekilde genisletildi.

## Islevsel Eksikler

- Gorev dosyasi adi sabit yazilmis durumda. `PLAN.md` varsayilan olmali ama gerekirse config veya argumanla degistirilebilmeli.
- Menu islemleri yalnizca interaktif kullanimla calisiyor. `--project`, `--prompt`, `--send-draft`, `--status` gibi CLI argumanlari eklenmeli.
- `BASE_DIR_CANDIDATES` sabit kodlanmis. Farkli makine ve klasor yapilarinda ortam degiskeni veya config dosyasi ile ezilebilmeli.
- Dashboard sadece dosya var/yok gosteriyor. `PLAN.md` icin son degisiklik zamani veya aktif madde sayisi gibi daha anlamli ozetler eklenebilir.
- `setup.sh` su an Debian/Ubuntu odakli. macOS, Fedora ve apt olmayan sistemler icin ek kurulum yolu gerekiyor.
- `requirements.txt` sistem bagimliliklarini isim listesi olarak tutuyor. Surumlenmis ve platform bazli gereksinim formati netlestirilmeli.
- Proje `git` reposu degilse script bunu acik soylemiyor; repo durumu ve GitHub'a ilk yukleme adimlari icin yardimci komutlar eklenebilir.

## Teknik Riskler

- Hazir ekran tespiti Codex arayuzu degisirse kolayca bozulabilir. Regex yerine daha kontrollu bir durum makinesi veya configurable pattern listesi kullanilmali.
- `clear` kullanan arayuz non-interactive ortamlarda zayif davraniyor. TTY yoksa sade metin modu olmali.
- `log.txt` proje klasorune yaziliyor. Yazma izni olmayan projeler icin fallback log dizini gerekli.
- Auto sender tek pid dosyasi ile yonetiliyor. Coklu instance veya ayni proje icin paralel kullanimda cakisma riski var.
- `setup.sh` icindeki `sudo apt-get` akisi sifresiz/sudo'suz ortamlarda durabilir; non-interactive ve yetkisiz senaryo icin fallback davranis tanimlanmali.

## Bakim ve Kalite

- Ayarlar tek dosyada toplanmali. Ornek: `codexify.conf` ile promptlar, timeout degerleri ve proje kok dizinleri.
- Surum numarasi, arsivleme ve yayin notlari tek akistan uretilmeli; `versions/` klasoru manuel kopya mantigindan cikmali.
- Kritik fonksiyonlar icin daha net hata siniflari ve standart kullanici mesajlari tanimlanmali.
- `verify.sh` sadece sentaks ve opsiyonel `shellcheck` yapiyor. `tmux`/`codex` akislarini fixture veya mock ile test eden gercek regresyon testleri eksik.
