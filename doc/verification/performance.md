# Verifica delle prestazioni

Da fare su iPhone fisico. Confronta la stessa lista in tre versioni: `plain` (senza barre), `overglass` e `lgr` (`liquid_glass_renderer`).

## Prima di iniziare
Nei comandi sostituisci `NOME_IPHONE` con il nome mostrato da `flutter devices`.

- Scegli il team in `example/ios/Runner.xcworkspace`. Gli script lo riusano.
- iPhone sbloccato, collegato via cavo, freddo, modalità risparmio energetico disattivata, altre app chiuse.
- Instruments non deve essere aperto mentre gli script registrano.

## 1. Tempi di Flutter
```bash
cd ~/Documents/personale/overglass/benchmark && ./run_frames.sh "NOME_IPHONE"
```
Stampa una tabella con tempi di build e raster. Misura solo il lavoro di Flutter, quindi non include il vetro disegnato da iOS. Il vetro di `overglass` qui non costa nulla per costruzione, mentre quello di `lgr` è incluso.

## 2. Hitch e consumo con Instruments: sconsigliato sul telefono di tutti i giorni

**Attenzione:** queste registrazioni hanno lasciato diversi GB in "Dati di sistema" su un iPhone 15 Pro, e lo spazio non si è liberato a fine prova. Lo script si rifiuta di partire senza `ACCEPT_DEVICE_STORAGE=1`. Usalo solo su un dispositivo con molto spazio libero, meglio se dedicato ai test, e riavvialo tra una prova e l'altra.

```bash
cd ~/Documents/personale/overglass/benchmark && ACCEPT_DEVICE_STORAGE=1 ./run_instruments.sh "NOME_IPHONE" "Animation Hitches" 12
```

Misura anche il lavoro di iOS sul vetro. Servono almeno 2,5 GB liberi sul Mac. Per il consumo usa il modello `"Power Profiler"` al posto di `"Animation Hitches"`.

## Risultati finora (iPhone 15 Pro, iOS 26.1, Flutter 3.47.9)

| Prova | Senza barre | `overglass` | `liquid_glass_renderer` |
| --- | --- | --- | --- |
| Raster medio, una prova | 0,57 ms | 0,52 ms | 1,60 ms |
| Raster p99, una prova | 0,88 ms | 0,77 ms | 3,20 ms |
| Hitch, prova A (20 s) | 0 | 6 (66,7 ms) | 0 |
| Hitch, prova B (20 s) | 3 (41,7 ms) | 3 (25,0 ms) | non registrato |

Le prove sono troppo poche per un confronto: non sostengono che una soluzione sia più leggera di un'altra.

## Come leggere i risultati
- Ripeti ogni misura almeno 3 volte e lascia raffreddare il telefono tra una serie e l'altra.
- L'iPhone 15 Pro arriva a 120 Hz, quindi un fotogramma ha 8,3 ms. Guarda soprattutto p90, p99 e gli hitch: il contatore "over budget" può usare una soglia di 16,7 ms.
- Nel README scrivi che `overglass` è più leggero solo se lo mostrano gli hitch del punto 2.
- `liquid_glass_renderer` è una versione sperimentale e usa Flutter GPU in anteprima: citalo con versione e data della prova.
- Incollami gli output: li confronto e aggiorno il README.
