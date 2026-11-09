# Ottenimento e organizzazione dati DB OHDSI


## Cosa fa

1. Scarica dal DB tutti i pazienti con le loro misurazioni (Cobb angle, Riss sign, Rib hump, ATR, Trace, ecc.) e osservazioni (fisioterapia, tipo di corsetto, punteggi SRS, diagnosi), organizzando i dati per data;
2. Trasforma i dati grezzi in un dataframe esportabile;
4. Applica una serie di filtri di inclusione e produce i dati per l'analisi.

## File

- `data_processing.py` — connessione al DB, classe `Paziente`/`Visita` e funzioni di utility.
- `main.ipynb` — Carica i dati, li filtra e esporta.

## Requisiti

- Python 3, con installate le librerie:

```
nump
pandas
matplotlib
psycopg
```

- L'indirizzo del server con un ip whitelistato.

## Cose da fare prima dell'esecuzione:

Modificare i percorsi: il main legge e scrive CSV con percorsi assoluti i quali vanno cambiati con i propri.

Modificare in `get_all_data` in `data_processing.py` l'indirizzo del server.


## Filtri applicati:

In ordine, dopo il caricamento:

- si tolgono le righe con Riss sign > 100 (in caso si vogliano fare analisi con uno specifico Riss);
- si tolgono i corsetti non specificati;
- Si prendono solo le pazienti femmine;
- deve esserci almeno un dato di Cobb angle nelle visite;
- prima visita prima dei 15 anni;
- diagnosi di scoliosi idiopatica;
- più di 4 visite;
- solo corsetti very rigid (si tolgono rigidi e flessibili);
- deve esserci almeno una seduta di fisioterapia;
- niente sequenze No→Sì→No→Sì su fisioterapia e corsetto (pazienti che stoppano e riprendono due volte).




# Analisi statistica dati OHDSI (MATLAB)

## Cosa fa

1. Carica i dati pre-filtrati (`matrice_half_filtered.csv`) e normalizza i tempi di terapia e l'angolo di Cobb per poter confrontare pazienti diversi sulla stessa scala;
2. Raggruppa i pazienti seguendo le linee guida SRS per poi dividerli secondo le ore di utilizzo del corsetto;
3. Applica un modello misto non-lineare (PLME) che ripulisce i dati dai vantaggi o svantaggi iniziali dei pazienti in modo da isolare l'andamento effettivo della terapia scelta;
4. Utilizza l'Indice di Pearson (per la fase acuta) ed il T-Test (per il plateau) per valutare l'efficacia del trattamento;
5. Esporta i risultati ottenuti in un file Excel.

## File

- `Codice_PLME_T.m` — script principale con ciclo di calcolo, clustering, modello LME e plot.
- `matrice_half_filtered.csv` — dataset di partenza (generato dall'elaborazione Python).


## Function

- `[Tb] = regression(X, y, t)`
   Input: 
    - `X`: vettore delle tempistiche;
    - `y`: vettore degli angoli di Cobb;
    - `t`: stringa di testo utilizzata per assegnare il titolo al grafico.

  Output:
    - `Tb`: tabella contenente i dati reali ed i dati calcolati dal modello.

  Descrizione:
    - Esegue una regressione lineare globale sull'intero dataset.

- `[Tb, best_model, pearson_r, pearson_p, target_out, mu_out, ptest_out] = regression_piecewise_lme(Tab_dati, titolo, max_segments, dirpath, file_ridotto)`

   Input:
    - `Tab_dati`: tabella contenente i dati isolati e ripuliti dal rumore;
    - `titolo`: stringa contenente il titolo formattato;
    - `max_segments`: massimo numero di segmenti;
    - `dirpath` e `file_ridotto`: percorsi di destinazione e nome del file per il salvataggio automatico dell'immagine in PNG.

   Output:
    - `Tb`: tabella contenente la Y grezza e la Y predetta;
    - `best_model`: il modello statistico `fitlme` migliore ottenuto;
    - `pearson_r` e `pearson_p`, `target_out`, `mu_out` e `ptest_out`: vettori per l'estrazione dati su Excel.

   Descrizione:
    - Scompone il periodo di terapia evidenziando i cambi di pendenza, ripulisce i dati dalle differenze individuali iniziali e applica i test di Pearson ed il T-Test per misurare l'efficacia del corsetto.

## Algoritmi e metodi principali

- Gaussian Mixture Models (GMM): algortimo che raggruppa i pazienti in alta e bassa compliance in base al massimo numero di ore di utilizzo del corsetto per separare .
- Piecewise Linear Mixed-Effects (PLME): algoritmo che suddivide il tempo in cui il paziente è stato in cura spezzandolo in vari segmenti  ripuliti dalla differenza individuale iniziale (Random Intercept).
- Indice di Pearson: calcolo della correlazione e della pendenza sul primo tratto per analizzare la casualità della diminuizione dell'angolo di Cobb.
- T-Test: test applicato ai segmenti di plateau successivi al primo per verificare che la curva scoliotica rimanga stabile una volta dismesso il corsetto.

## Requisiti

- MATLAB, con installati i seguenti toolboxes:

    Statistics and Machine Learning Toolbox
    
necessario per l'utilizzo delle funzioni fitlme, fitgmdist, rmoutliers.

## Cose da fare prima dell'esecuzione:

- Lo script `.m` e il dataset `.csv` vanno mantenuti all'interno della stessa cartella, poichè il codice usa percorsi relativi. Successivamente creerà in autonomia la cartella per i file di output in quella posizione.

- Assicurarsi che il file Excel di output(`Risultati_Efficacia_Corsetto_Aggiornati.xlsx`) sia chiuso, poichè se aperto, MATLAB non riusce a sovrascriverlo e va in errore.

## Passaggi dell'analisi:

In ordine, dopo il caricamento:

- normalizza il tempo in un range 0-1 (dove 1 = 8 anni), e il Cobb viene trasformato in variazione percentuale rispetto alla prima visita;
- viene estratto il Risseriniziale, il Cobb iniziale ed il valore massimo di ore di corsetto prescritte;
- i pazienti vengono divisi in 16 profili utilizzando il livello di calcificazione ossea (Risser 0-1, 2-3, 4-5, 0-3) e la severità della curva scoliotica (Lieve, Moderata, Severa);
- per ogni profilo, si usa il GMM (Gaussian Mixture Model) sulle ore di utilizzo del corsetto per separare chi ha una bassa compliance (Sub 1) da chi ha un'alta compliance (Sub 2);
- si determinano i breakpoints della curva, ponendo un massimo di 3 segmenti per evitare di frammentare i dati ed inseguire il rumore radiografico;
- si sottrae lo scarto individuale di ogni paziente dai dati grezzi così da isolare la risposta effettiva alla terapia;
- si calcola l'indice di Pearson e l'errore (RMSE) sul primo tratto di discesa;
- si calcola il valore di Target raggiunto e si fa il T-Test sul plateau per verificare se la correzione persiste anche dopo la rimozione del corsetto.
