# Codexify

`codexify.sh`, OpenAI Codex CLI oturumlarini `tmux` icinde proje bazli yoneten interaktif bir Bash aracidir.

Proje, tek bir klasor yapisina bagli olmadan calisacak sekilde tasarlanmistir. Varsayilan olarak `/opt/web` ve `/opt/web-projects` altini dener; isterseniz menuden farkli bir proje root klasoru tanimlayip bunu kalici olarak kaydedebilirsiniz.

## Neler Yapar

- Proje root klasorundeki alt klasorleri proje olarak listeler
- Secilen proje icin `tmux` icinde bir Codex oturumu baslatir
- Taslak prompt kaydetme ve tek tusla gonderme akisi sunar
- Otomatik gonderici ile ayni promptu belirli araliklarla tekrar yollar
- `/status`, log, snapshot ve oturum yonetimini menuden sunar
- Script kapanirken aktif Codex oturumunu da kapatir

## Gereksinimler

- `bash`
- `tmux`
- `git`
- `ripgrep`
- `codex`

Beklenen araclarin listesi icin `requirements.txt` dosyasina bakin.

## Kurulum

```bash
chmod +x setup.sh
./setup.sh
```

`setup.sh`, Debian veya Ubuntu tabanli sistemlerde temel paketleri kurmayi dener. `codex` CLI sisteminizde kurulu degilse manuel olarak kurup `PATH` icine eklemeniz gerekir.

## Kullanim

```bash
./codexify.sh
```

Ilk acilista tipik akis:

1. `Proje/Oturum` menusu altindan gerekirse `Proje root klasoru` secilir.
2. `Proje sec` ile aktif proje secilir.
3. `Oturumu baslat` ile ilgili proje icin Codex oturumu acilir.
4. `Prompt/Otomasyon` menusu altindan varsayilan, inceleme, test veya ozel bir prompt kaydedilip gonderilir.

## Proje Root Klasoru

Bu ayar `tmux` veya proje seciminden bagimsizdir ve kalici olarak saklanir.

- Ornek root: `/opt/web-projects`
- Ornek root: `/srv/projects`
- Ornek root: `/home/user/workspaces`

Secilen root altindaki birinci seviye klasorler proje olarak listelenir.

## Otomatik Gonderim

`Prompt/Otomasyon` menusu altindan:

- taslak prompt kaydedilebilir
- ayni taslak manuel olarak gonderilebilir
- otomatik gonderici baslatilip durdurulabilir
- script logu ve auto sender logu okunabilir

Otomatik gonderim sadece aktif bir Codex oturumu varken calisir.

## Tmux Notu

Oturuma baglanmak icin menuden `Oturuma baglan` secenegini kullanabilirsiniz.

Tmux ekranindan ayrilmak icin:

```bash
Ctrl+b
d
```

Bu sadece `detach` yapar. Oturumu tamamen sonlandirmak icin menuden `Oturumu kapat` secin veya scriptten `Q` ile cikin.

## Dogrulama

```bash
./verify.sh
```

Bu komut:

- scriptler icin `bash -n` calistirir
- `shellcheck` kuruluysa lint calistirir
- `tests/test_codexify.sh` ile temel Bash unit testlerini kosar

## GitHub

Bu proje public paylasim hedefiyle duzenlenmistir. GitHub'a acmadan once su adimlari tamamlayin:

1. `README.md` ve `CHANGELOG.md` guncel olsun.
2. `verify.sh` basariyla gecsin.
3. Gerekirse kendi ortam klasorlerinize gore `Proje root klasoru` secenegini kullanin.

GitHub CLI veya uygun bir token mevcutsa repo `codexify` adi ile kolayca yayinlanabilir.
