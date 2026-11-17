# Verifica VoiceOver

Da fare su iPhone fisico con iOS 26. Spunta ogni riga e annota l'annuncio reale se è diverso dall'atteso.

## Preparazione
Nei comandi sostituisci `NOME_IPHONE` con il nome mostrato da `flutter devices`.

1. In **Impostazioni > Accessibilità > Abbreviazioni** scegli VoiceOver, così lo attivi con tre clic del tasto laterale.
2. Avvia l'esempio:

```bash
cd ~/Documents/personale/overglass/example && flutter run --profile -d "NOME_IPHONE"
```

Gesti: scorri a destra o a sinistra con un dito per spostarti, tocca due volte per attivare, disegna una Z con due dita per tornare indietro.

## Scenari

| # | Azione | Atteso | Esito | Note |
| --- | --- | --- | --- | --- |
| 1 | Da Home, tocca la barra in alto e scorri a destra fino in fondo | Ordine: barra superiore, contenuto, tab. Nessun elemento è saltato o letto due volte | ☐ | |
| 2 | Vai sulla tab Search | Legge etichetta, ruolo, posizione e il badge 3 | ☐ | |
| 3 | Tocca due volte Search | La tab risulta selezionata e il contenuto diventa Search | ☐ | |
| 4 | Tocca due volte Show dialog | Il fuoco va nel dialog. Le barre non sono raggiungibili | ☐ | |
| 5 | Tocca due volte Close | Il fuoco torna sulla schermata e le barre sono di nuovo raggiungibili | ☐ | |
| 6 | Tocca due volte More | Il menu si apre e legge ogni voce. Native sheet è annunciata come distruttiva, se iOS lo fa | ☐ | |
| 7 | Scegli Native alert, poi Confirm | Legge titolo, messaggio e pulsanti. In Home compare `Last: Alert ok` | ☐ | |
| 8 | Scegli Native sheet, poi Delete | Il foglio si legge e la scelta arriva. In Home compare `Last: Sheet delete` | ☐ | |
| 9 | Scegli Open detail | Il pulsante indietro è leggibile e la nuova barra sostituisce la vecchia | ☐ | |
| 10 | Vai sul campo Search notes e scrivi | Il campo è annunciato e il testo compare nella pagina | ☐ | |
| 11 | Tocca due volte il pulsante indietro | Torna a Home e il fuoco non resta su un elemento scomparso | ☐ | |
| 12 | Su Open detail disegna la Z con due dita | Torna a Home. Se non succede nulla, segnalalo | ☐ | |
| 13 | Scegli UIKit modal | Le barre sotto il modale non sono raggiungibili | ☐ | |
| 14 | Tocca due volte Dismiss modal | Le barre tornano raggiungibili | ☐ | |
| 15 | Scegli Plain page | Le barre di Home non sono raggiungibili | ☐ | |
| 16 | Vai sulla tab Profile | Il titolo grande è letto una sola volta | ☐ | |
| 17 | Ruota in orizzontale e ripeti lo scenario 1 | Stesso ordine, nessun elemento perso | ☐ | |

## Impostazioni di sistema
Ripeti gli scenari 1, 2 e 4 con ciascuna opzione attiva, in **Impostazioni > Accessibilità**.

| Opzione | Atteso | Esito | Note |
| --- | --- | --- | --- |
| Riduci trasparenza | Le barre diventano più opache e restano leggibili | ☐ | |
| Aumenta contrasto | Barre e icone restano leggibili | ☐ | |
| Testo in grassetto | La tab bar aggiorna il testo | ☐ | |
| Dimensione testo al massimo | Tieni premuta una tab: compare il riquadro ingrandito | ☐ | |
| Riduci movimento | I cambi pagina restano utilizzabili | ☐ | |

## Punto da guardare per primo
Lo scenario 1 è il più a rischio. Le barre vivono in una vista separata da quella di Flutter, quindi iOS potrebbe leggere prima tutto il contenuto e poi le barre. Se accade, scrivimi l'ordine che senti.
