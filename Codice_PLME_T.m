% ===== INIZIALIZZAZIONE E CARICAMENTO DATI =====
close all
clear all 
clc
T = readtable('matrice_half_filtered.csv'); % Carica il dataset dal file CSV e lo salva nella tabella 'T'
rissMax = max(T.RissSign); % Trova il valore massimo dello stadio Risser nel dataset per usarlo come fattore di normalizzazione

% Creo cartella per le figure (Generazione dinamica nella cartella corrente)
dirpath = fullfile(pwd, 'figures_CODICE_PLME-T');
if ~exist(dirpath,'dir')
    mkdir(dirpath); % Se non esiste, crea la cartella 'figures_CODICE_PLME-T' per salvare i plot
end

% ===== CALCOLO DEL DELTA ETÀ MASSIMO =====
deltaEtaMax = 8;

% ===== PREPARAZIONE MATRICE NORMALIZZATA =====
n = 0; % Inizializza un contatore per i pazienti analizzati (usato poi per limitare le stampe grafiche di debug)
T_tot = []; % Inizializza la tabella vuota che conterrà tutti i dati dei pazienti normalizzati
for i = unique(T.id)' % Avvia un ciclo for iterando su ogni identificativo univoco (id) dei pazienti
    T_temp = T(T.id==double(i),:); % Estrae dalla tabella principale 'T' solo le righe relative al paziente corrente 'i'
    
    % --- IDENTIFICAZIONE DEL PERIODO CON CORSETTO ---
    index = find(T_temp.No_Brace==0); % Trova gli indici delle righe in cui il paziente sta attivamente indossando il corsetto (0 = lo indossa)
    if isempty(index) % Se l'array degli indici è vuoto...
        continue; % ...salta questo paziente e passa al successivo (non ha mai messo il corsetto)
    end
    
    if index(1) > 1 % Se la prima visita in cui indossa il corsetto NON è la primissima visita in assoluto...
        index = [index(1)-1; index]; % ...aggiunge all'array degli indici anche la visita immediatamente precedente (la 'baseline' pre-corsetto)
    end
    
    if not(index(end) == height(T_temp)) % Se l'ultima visita col corsetto NON è l'ultima riga dello storico del paziente...
        index = [index; index(end)+1]; % ...aggiunge la visita immediatamente successiva (per vedere il mantenimento post-svezzamento)
    end
    
    T_brace = T_temp(index,:); % Isola lo storico terapeutico effettivo del paziente usando gli indici appena ricalcolati
    
    % --- NORMALIZZAZIONE DEI DATI ---
    t_norm = []; 
    riss_norm = []; 
    cobb_norm = []; 
    
    for j = 1:height(T_temp) % Itera su tutte le righe della tabella del paziente
        t_norm = [t_norm; (T_temp.eta(j) - T_temp.eta(1))/deltaEtaMax]; % Calcola il tempo trascorso dalla visita 1 e lo divide per 8 anni (normalizzazione 0-1)
        riss_norm = [riss_norm; T_temp.RissSign(j)/rissMax]; % Divide il Risser corrente per il Risser massimo (normalizzazione 0-1)
        cobb_norm = [cobb_norm; (T_temp.CobbAngle(j)-T_temp.CobbAngle(1))/T_temp.CobbAngle(1)]; % Calcola la variazione % del Cobb rispetto alla visita 1 (tutti partono da Y=0)
    end
    
    id = repmat(i, height(T_temp), 1); % Crea una colonna contenente l'ID del paziente ripetuto per tutte le sue righe
    eta = T_temp.eta; % Estrae l'età in forma assoluta
    
    Tab_norm = table(id, eta, t_norm, riss_norm, cobb_norm); % Crea una tabella normalizzata per il singolo paziente
    T_tot = [T_tot; Tab_norm]; % Accoda la tabella del paziente a quella globale (T_tot)
    
    n = n+1;
    if n < 11 % Se siamo nei primi 10 pazienti processati...
         plot_single(T_temp) % ...chiama la funzione di plotting base per visualizzare lo storico grezzo (solo a scopo di debug visivo iniziale)
    end
end
T_tot = T_tot(T_tot.t_norm <= 1, :); % Filtro globale di sicurezza: mantiene solo i record che rientrano in 8 anni (t_norm <= 1)

% =========================================================================
% --- LIVELLO 1: ESTRAZIONE FEATURES ---
% =========================================================================
disp("==== LIVELLO 1: ESTRAZIONE FEATURES E PROFILAZIONE ====")
lista_pazienti = unique(T_tot.id); % Estrae la lista definitiva degli ID unici presenti nel dataset purificato
num_pazienti = length(lista_pazienti);
features_pazienti = zeros(num_pazienti, 3); % Inizializza una matrice N_pazienti x 3 per salvare i predittori base [Risser, Ore, Cobb]
for p = 1:num_pazienti
    T_paz = T(T.id == double(lista_pazienti(p)), :); % Isola i dati grezzi del paziente 'p'
    f_risser = T_paz.RissSign(1); % Estrae il segno di Risser alla primissima visita (baseline)
    
    ore_array = T_paz.Corsetto_ore_gg; % Estrae l'intero array delle ore di corsetto prescritte in tutte le visite
    f_ore = max(ore_array, [], 'omitnan'); % Calcola il picco massimo di ore (esclude i NaN), bypassando la riduzione fisiologica dello svezzamento
    if isempty(f_ore) || isnan(f_ore), f_ore = 0; end % Se non ci sono dati sulle ore, assegna 0 como default per evitare crash
    
    f_cobb = T_paz.CobbAngle(1); % Estrae l'angolo di Cobb geometrico alla primissima visita
    features_pazienti(p, :) = [f_risser, f_ore, f_cobb]; % Salva la triade di feature nella matrice
end

% =========================================================================
% --- DEFINIZIONE STRATEGICA DEI PROFILI CLINICI ---
% =========================================================================
profili = { % Crea un 'cell array' multidimensionale che funge da dizionario logico
    % --- 1. RISSER 0-1 ---
    'Risser 0-1', 'Lieve (10-30°)', @(r,c) r<=1 & c>=10 & c<30; 
    'Risser 0-1', 'Moderata (30-45°)', @(r,c) r<=1 & c>=30 & c<=45; 
    'Risser 0-1', 'Severa (>45°)', @(r,c) r<=1 & c>45; 
    'Risser 0-1', 'Tutte le Gravita (>10°)', @(r,c) r<=1 & c>=10; 
    
    % --- 2. RISSER 2-3 ---
    'Risser 2-3', 'Lieve (10-30°)', @(r,c) r>=2 & r<=3 & c>=10 & c<30; 
    'Risser 2-3', 'Moderata (30-45°)', @(r,c) r>=2 & r<=3 & c>=30 & c<=45; 
    'Risser 2-3', 'Severa (>45°)', @(r,c) r>=2 & r<=3 & c>45; 
    'Risser 2-3', 'Tutte le Gravita (>10°)', @(r,c) r>=2 & r<=3 & c>=10; 
    
    % --- 3. RISSER 4-5 ---
    'Risser 4-5', 'Lieve (10-30°)', @(r,c) r>=4 & c>=10 & c<30; 
    'Risser 4-5', 'Moderata (30-45°)', @(r,c) r>=4 & c>=30 & c<=45; 
    'Risser 4-5', 'Severa (>45°)', @(r,c) r>=4 & c>45; 
    'Risser 4-5', 'Tutte le Gravita (>10°)', @(r,c) r>=4 & c>=10; 
    
    % --- 4. SUPER-GRUPPO: RISSER 0-3 (Fase di Crescita Attiva) ---
    'Risser 0-3', 'Lieve (10-30°)', @(r,c) r<=3 & c>=10 & c<30; 
    'Risser 0-3', 'Moderata (30-45°)', @(r,c) r<=3 & c>=30 & c<=45;
    'Risser 0-3', 'Severa (>45°)', @(r,c) r<=3 & c>45; 
    'Risser 0-3', 'Tutte le Gravita (>10°)', @(r,c) r<=3 & c>=10; 
};
Risultati_Finali = {}; % Inizializza un cell array vuoto che raccoglierà i risultati di regressione di tutti i cluster

% =========================================================================
% --- LIVELLO 2: GMM E REGRESSIONE SUI NUOVI PROFILI ---
% =========================================================================
for idx_prof = 1:size(profili, 1) % Itera riga per riga sul dizionario 'profili' (16 iterazioni)
    nome_risser = profili{idx_prof, 1}; % Estrae il nome testuale del Risser
    nome_cobb = profili{idx_prof, 2}; % Estrae il nome testuale della gravità
    filtro_fun = profili{idx_prof, 3}; % Estrae la funzione anonima logica per il filtraggio
    
    idx_paz_scacchiera = find(filtro_fun(features_pazienti(:,1), features_pazienti(:,3))); % Usa la funzione logica per trovare le righe in 'features_pazienti' che combaciano
    num_paz_scacchiera = length(idx_paz_scacchiera); % Conta quanti pazienti sono caduti in questa "casella"
    nome_casella = sprintf('%s | %s', nome_risser, nome_cobb); % Costruisce la stringa con il titolo completo della casella
    
    if num_paz_scacchiera < 6 % Se ci sono meno di 6 pazienti in questo profilo...
        continue; % ...salta l'analisi perché il GMM andrebbe in crash per mancanza di dati
    end
    
    fprintf('\n\n======================================================\n');
    fprintf(' ANALISI PROFILO: %s (Pazienti totali: %d)\n', nome_casella, num_paz_scacchiera);
    fprintf('======================================================\n');
    
    dati_ore = features_pazienti(idx_paz_scacchiera, 2); % Estrae SOLO la colonna delle 'Ore' (colonna 2) per i pazienti del profilo corrente
    rng(42); % Fissa il seed del generatore di numeri casuali per rendere il clustering GMM sempre riproducibile
    opzioni = statset('MaxIter', 1000); % Aumenta le iterazioni massime concesse all'ottimizzatore statistico
    
    try
        warning('off', 'all'); % Disabilita i warning temporaneamente per non sporcare la console
        modello_gmm = fitgmdist(dati_ore, 2, 'RegularizationValue', 0.05, 'Replicates', 5, 'Options', opzioni); % Cerca 2 gaussiane (cluster) nell'array delle ore per separare chi lo usa tanto da chi lo usa poco
        sub_clusters = cluster(modello_gmm, dati_ore); % Assegna ogni paziente al cluster 1 o al cluster 2
        warning('on', 'all'); % Riabilita i warning
    catch
        disp('  -> Dati ore troppo omogenei. Analizzo come gruppo unico.'); % Se l'algoritmo fallisce (es. tutti hanno prescrizioni di 18 ore)
        sub_clusters = ones(num_paz_scacchiera, 1); % Forza tutti i pazienti nell'unico cluster "1"
    end
    
    if max(sub_clusters) > 1 % Se ha trovato effettivamente due cluster distinti...
        media_ore_1 = mean(dati_ore(sub_clusters == 1)); % Calcola la media delle ore del gruppo 1
        media_ore_2 = mean(dati_ore(sub_clusters == 2)); % Calcola la media delle ore del gruppo 2
        if media_ore_1 > media_ore_2 % Se il gruppo 1 ha casualmente ore maggiori del gruppo 2 (inversione non voluta)
            sub_clusters(sub_clusters == 1) = 99; % Salva temporaneamente i pazienti del cluster 1 come '99'
            sub_clusters(sub_clusters == 2) = 1; % Sposta i pazienti del cluster 2 al cluster 1
            sub_clusters(sub_clusters == 99) = 2; % Sposta i pazienti '99' al cluster 2 (Riordino: 1 = Poche ore, 2 = Molte ore)
        end
    end
    
    for sc = 1:max(sub_clusters) % Itera all'interno dei sottogruppi appena creati (Sub 1 e, se esiste, Sub 2)
        paz_sc = lista_pazienti(idx_paz_scacchiera(sub_clusters == sc)); % Recupera gli ID esatti dei pazienti assegnati a questo Sub-Cluster
        num_paz_sc = length(paz_sc); % Conta i pazienti in questo specifico Sub-Cluster
        
        if num_paz_sc < 3 % Se il sottogruppo ha meno di 3 pazienti...
            continue; % ...è clinicamente e matematicamente irrilevante, quindi lo salta
        end
        
        med_ore = mean(features_pazienti(idx_paz_scacchiera(sub_clusters == sc), 2), 'omitnan'); % Calcola la media precisa delle ore per il titolo grafico
        med_cobb = mean(features_pazienti(idx_paz_scacchiera(sub_clusters == sc), 3), 'omitnan'); % Calcola la media precisa del Cobb iniziale
        
        idx_visite = ismember(T_tot.id, paz_sc); % Crea una maschera logica: seleziona in T_tot TUTTE E SOLE le righe di visita dei pazienti del sub-cluster
        X_cluster = T_tot.t_norm(idx_visite); % Estrae il vettore del Tempo Normalizzato per le visite selezionate
        y_cluster = T_tot.cobb_norm(idx_visite); % Estrae il vettore del Cobb Normalizzato per le visite
        id_cluster = T_tot.id(idx_visite); % Estrae il vettore degli ID (serve al modello Misto per il Random Intercept)
        
        [y_pulito, idx_outliers] = rmoutliers(y_cluster); % Identifica ed elimina eventuali visite anomale (outliers) dalla variabile Y
        X_pulito = X_cluster(~idx_outliers); % Rimuove le corrispondenti righe dall'asse X
        id_pulito = id_cluster(~idx_outliers); % Rimuove le corrispondenti righe dagli ID
        
        Tab_pulita = table(X_pulito, y_pulito, id_pulito, 'VariableNames', {'t_norm', 'cobb_norm', 'id'}); % Ricompone la tabella dati depurata per passarla all'ottimizzatore LME
        
        titolo_grafico = sprintf('%s | Sub %d (Paz: %d | Ore: %.1f | Cobb reale: %.1f°)', ... % Costruisce la stringa che sarà il Titolo del plot e del file PNG
                           nome_casella, sc, num_paz_sc, med_ore, med_cobb);
        disp(titolo_grafico); % Stampa a schermo il titolo elaborato
        
        % STRATEGIA SICUREZZA SALVATAGGIO: Genera un nome file privo di punti decimali
        nome_risser_clean = regexprep(nome_risser, '[ \|:°\(\)><\*?"\s]+', '_');
        nome_cobb_clean = regexprep(nome_cobb, '[ \|:°\(\)><\*?"\s]+', '_');
        nome_file_ridotto = sprintf('%s_%s_Sub%d.png', nome_risser_clean, nome_cobb_clean, sc);
        
        % CHIAMATA AL MOTORE CORE: Riceve in output anche i risultati del Test di Affidabilità per Excel
        [~, ~, pearson_r, pearson_p, target_out, mu_out, ptest_out] = regression_piecewise_lme(Tab_pulita, titolo_grafico, 3, dirpath, nome_file_ridotto);
        
        r_val = NaN; 
        p_val = NaN; 
        tgt_val = NaN; 
        mu_val = NaN; 
        p_test_val = NaN; % Inizializza a NaN per sicurezza
        
        if ~isempty(pearson_r) % Prende la correlazione del primo segmento (fase di attacco acuta)
            r_val = pearson_r(1); 
            p_val = pearson_p(1); 
        end
        
        if ~isempty(ptest_out) && length(ptest_out) >= 2 % Estrae i dati del Plateau (Segmento 2) per l'Excel
            tgt_val = target_out(2);
            mu_val = mu_out(2);
            p_test_val = ptest_out(2);
        end
        
        etichetta_compliance = 'basse ore iniziali (Sub 1)'; % Imposta di default la stringa testuale per la scarsa compliance
        if sc == 2, etichetta_compliance = 'alte ore iniziali (Sub 2)'; end % Se è il Sub-cluster 2, sovrascrive
        
        % Inserisce la riga completa (inclusi i dati del T-test) nell'array globale per Excel
        Risultati_Finali(end+1, :) = {nome_risser, nome_cobb, etichetta_compliance, num_paz_sc, med_ore, med_cobb, r_val, p_val, tgt_val, mu_val, p_test_val};
    end
end
% =========================================================================
% --- 1. ESPORTAZIONE TABELLA IN EXCEL ---
% =========================================================================
% Definisce le intestazioni AGGIORNATE delle colonne per il file Excel, includendo il Test di Affidabilità
Nomi_Colonne = {'Gruppo_Risser', 'Gravita_Cobb', 'Compliance', 'Num_Pazienti', 'Ore_Medie', 'Cobb_Medio', 'Pearson_r_Acuta', 'P_Value_Acuta', 'Target_Plateau', 'Media_Mu_Plateau', 'P_Test'};
T_export = cell2table(Risultati_Finali, 'VariableNames', Nomi_Colonne); % Converte il 'cell array' aggregato in un oggetto Table formattato
nome_file_excel = 'Risultati_Efficacia_Corsetto_Aggiornati.xlsx'; % Assegna il nome al file Excel
writetable(T_export, fullfile(dirpath, nome_file_excel)); % Salva il file Excel direttamente all'interno della cartella dedicata su OneDrive
fprintf('\n\n+++ ANALISI COMPLETATA: I dati sono stati salvati nel file "%s" +++\n\n', fullfile(dirpath, nome_file_excel)); % Messaggio di successo nella Command Window

% =========================================================================
% --- 2. GENERAZIONE DEI GRAFICI A BARRE (4 FINESTRE, 4 COLONNE) ---
% =========================================================================
risser_da_disegnare = {'Risser 0-1', 'Risser 2-3', 'Risser 4-5', 'Risser 0-3'}; % Array con le categorie principali di Risser per generare 4 finestre separate
cobb_labels = {'Lieve (10-30°)', 'Moderata (30-45°)', 'Severa (>45°)', 'Tutte le Gravita (>10°)'}; % Asse X (etichette dei 4 macro-gruppi di Cobb)
for r = 1:length(risser_da_disegnare) % Cicla per generare i 4 grandi plot a barre raggruppate
    risser_attuale = risser_da_disegnare{r}; % Isola il grado Risser corrente
    T_risser = T_export(strcmp(T_export.Gruppo_Risser, risser_attuale), :); % Filtra la grande tabella Excel, tenendo solo le righe del Risser corrente
    
    if isempty(T_risser) % Se non c'è nessun dato per questo Risser (es. filtro vuoto)
        continue; 
    end
    
    matrice_r = NaN(4, 2); % Inizializza matrice 4x2 riempita di NaN: 4 righe (i livelli di gravità Cobb) x 2 colonne (Sub 1 e Sub 2)
    
    for c = 1:4 % Itera per posizionare i dati estratti dall'Excel esattamente nelle giuste caselle della matrice grafica
        cobb_attuale = cobb_labels{c};
        
        % Cerca il Pearson (r) per Bassa Compliance (Sub 1) per questa gravità
        idx_sub1 = strcmp(T_risser.Gravita_Cobb, cobb_attuale) & contains(T_risser.Compliance, 'basse ore iniziali');
        if any(idx_sub1), matrice_r(c, 1) = T_risser.Pearson_r_Acuta(idx_sub1); end % Lo assegna alla Colonna 1
        
        % Cerca il Pearson (r) per Alta Compliance (Sub 2) per questa gravità
        idx_sub2 = strcmp(T_risser.Gravita_Cobb, cobb_attuale) & contains(T_risser.Compliance, 'alte ore iniziali');
        if any(idx_sub2), matrice_r(c, 2) = T_risser.Pearson_r_Acuta(idx_sub2); end % Lo assegna alla Colonna 2
    end
    
    % Generazione Finestra Grafica
    figure('Name', sprintf('Efficacia Corsetto - %s', risser_attuale), 'Position', [100, 100, 900, 500]); % Crea finestra dimensionata 900x500
    b = bar(matrice_r, 'grouped', 'FaceColor', 'flat'); % Genera le barre accoppiate leggendo la matrice 4x2
    
    % Codifica cromatica manuale (RGB) delle barre
    b(1).CData = repmat([0.85 0.32 0.09], 4, 1); % Colonna 1 (Sub 1 - Bassa): Arancio/Rosso ruggine
    b(2).CData = repmat([0.0 0.44 0.74], 4, 1);  % Colonna 2 (Sub 2 - Alta): Blu accademico
    
    % Posizionamento delle etichette (numeri) in cima alle barre
    for k = 1:2 % Cicla le due categorie (rosse e blu)
        xtips = b(k).XEndPoints; % Calcola le coordinate X al centro di ogni barra
        ytips = b(k).YEndPoints; % Calcola l'altezza massima (Y) di ogni barra
        labels = string(round(b(k).YData, 2)); % Arrotonda il dato a 2 decimali e lo converte in stringa
        labels(ismissing(labels) | labels == "NaN") = ""; % Rimuove le stringhe NaN inestetiche se la barra è vuota
        text(xtips, ytips, labels, 'HorizontalAlignment', 'center', ... % Disegna il testo in cima alla barra
            'VerticalAlignment', 'bottom', 'FontWeight', 'bold', 'FontSize', 10);
    end
    
    % Stile, Titoli, Assi e Legenda
    set(gca, 'XTickLabel', cobb_labels, 'FontSize', 10, 'FontWeight', 'bold'); % Nomina le etichette sull'asse X
    ylabel('Indice di Pearson (r) del Primo Tratto', 'FontSize', 12, 'FontWeight', 'bold'); % Etichetta Asse Y
    title(sprintf('Impatto delle Ore Iniziali sul Successo Terapeutico\nGruppo: %s', risser_attuale), 'FontSize', 14); % Titolo maggiore
    legend('basse ore iniziali', 'alte ore iniziali (> 21 ore)', 'Location', 'SouthEast'); % Legenda collocata in basso a destra
    grid on; % Attiva la griglia di sfondo per facilitare la lettura
    ylim([min([matrice_r(:); -0.8]) - 0.1, max([matrice_r(:); 0.2]) + 0.1]); % Auto-bilancia dinamicamente i limiti dell'asse Y in base ai dati
    
    % Salvataggio della figura in PNG nell'OneDrive
    nome_barre_sicuro = sprintf('Istogramma_Gruppo_Risser_%d.png', r);
    saveas(gcf, fullfile(dirpath, nome_barre_sicuro)); 
end

% ===== ANALISI DEI DATI GLOBALI =====
% Questa sezione esegue la regressione lineare globale per fornire il dato comparativo e dimostrare la necessità del nuovo sistema LME
X = [T_tot.t_norm]; % Ricostruisce il grande array X con tutte le tempistiche
y = [T_tot.cobb_norm]; % Ricostruisce il grande array Y con tutti gli angoli Cobb
[y_pulito, indici_outliers] = rmoutliers(y); % Pulisce massivamente gli outliers statistici
X_pulito = X(~indici_outliers);
fprintf('\n\n==== Regressione lineare (GLOBALE SENZA OUTLIERS) ====\n'); 
fprintf('Punti totali: %d | Outliers rimossi: %d | Punti tenuti: %d\n', length(y), sum(indici_outliers), length(y_pulito)); % Logga a video le statistiche di pulizia globali
    
regression(X_pulito, y_pulito, 'Globale Pulita '); % Chiama l'helper "regression" (Modello Lineare Base) per generare il fit aspecifico

% ==============================================================================
% ===================== DEFINIZIONE DELLE FUNZIONI =============================
% ==============================================================================
function plot_single(T_temp)
% Funzione Helper: Crea un plot di visualizzazione basico (X=età, Y=Cobb Geometrico) per debug rapido dei primissimi pazienti
     T_no_brace=T_temp(T_temp.No_Brace==1,:); % Isola le misurazioni senza corsetto
     figure
     plot(T_temp.eta, T_temp.CobbAngle, '*-', 'MarkerSize', 25) % Disegna le misurazioni con corsetto
     hold on 
     plot(T_no_brace.eta, T_no_brace.CobbAngle, 'r.', 'MarkerSize', 50); % Sovrascrive (in rosso) le misurazioni senza corsetto
end

function [Tb] = regression(X,y,t)
% Funzione Helper: Esegue una classica Regressione Lineare Multipla (fitlm) implementando l'Hold-out Cross-Validation
    cv = cvpartition(length(y), 'HoldOut', 0.2); % Partiziona i dati trattenendo il 20% come set di Test, il restante 80% è Train
    X_train = X(cv.training, :); y_train = y(cv.training); % Estrae matrici di Train
    X_test = X(cv.test, :); y_test = y(cv.test); % Estrae matrici di Test
    
    mdl = fitlm(X_train, y_train); % Fitta il modello Lineare Classico sui dati di Training
    y_pred_test = predict(mdl, X_test); % Usa il modello ottenuto per fare previsioni sui dati Test invisibili
    
    r = corr(y_test, y_pred_test); % Calcola l'Indice di Pearson basato sulle predizioni
    n = length(y_test); % Dimensione del set
    t_stat = r * sqrt((n-2)/(1-r^2)); % Calcola il t-statistic
    p_value = 2 * (1 - tcdf(abs(t_stat), n-2)); % Ricava il p-value tramite distribuzione di t-Student
    
    fprintf('Coefficiente di Pearson (test set): %.4f\n', r); % Logga il Pearson a video
    fprintf('p-value: %.2e\n', p_value); % Logga il p-value
    
    % Uniforma le lunghezze dei vettori (Train e Test) riempiendo lo svantaggio con NaN per formare una colonna omogenea per la Table
    max_rows = max([size(X_train,1), size(y_train,1), size(X_test,1), size(y_test,1), size(y_pred_test,1)]);
    X_train_padded = [X_train; NaN(max_rows - size(X_train,1), 1)];
    y_train_padded = [y_train; NaN(max_rows - size(y_train,1), 1)];
    X_test_padded  = [X_test;  NaN(max_rows - size(X_test,1),  1)];
    y_test_padded  = [y_test;  NaN(max_rows - size(y_test,1),  1)];
    y_pred_test_padded = [y_pred_test; NaN(max_rows - size(y_pred_test,1), 1)];
    
    % Genera la tabella strutturata da restituire al chiamante
    Tb = table(X_train_padded, y_train_padded, X_test_padded, y_test_padded, y_pred_test_padded, ...
               'VariableNames', {'X_train','y_train','X_test','y_test','y_pred_test'});
               
    rmse = sqrt(mean((y_test - y_pred_test).^2)); % Root Mean Squared Error sulle differenze predizione/realtà
    fprintf('RMSE sul test set: %.4f\n', rmse); % Stampa l'Errore logico RMS a video
    
    % Crea il plot grafico del fit globale
    figure;
    scatter(X,y); hold on; grid on; % Punti nuvola
    [sorted_X_test, idx] = sort(X_test(:,1)); % Ordina la x in ordine crescente (serve per tracciare una linea continua perfetta)
    sorted_y_pred_test = y_pred_test(idx); % Allinea la y predetta in accordo al riordino delle x
    plot(sorted_X_test, sorted_y_pred_test, 'w-', 'LineWidth', 2); % Disegna la spezzata
    title([t ' Angolo di Cobb vs Tempo'], 'Interpreter', 'none'); % Aggiunge il titolo della figura
end

function [Tb, best_model, pearson_r, pearson_p, target_out, mu_out, ptest_out] = regression_piecewise_lme(Tab_dati, titolo, max_segments, dirpath, file_ridotto)
% IL MOTORE CORE DELLA RICERCA: Modello Misto Non-Lineare (Piecewise LME)
    
    % Inizializzazioni di sicurezza aggiunte per il corretto Export verso Excel
    target_out = []; 
    mu_out = []; 
    ptest_out = [];

    % --- 1. HARD-CAPPING CLINICO ---
    if max_segments > 3 % Condizione di sicurezza stringente contro overfitting matematico
        max_segments = 3; % Forza a non oltrepassare la natura biologica (massimo discesa, plateau, e lieve svezzamento)
    end
    
    Tab_dati = sortrows(Tab_dati, 't_norm'); % Dispone i dati in ordine cronologico rigoroso per far convergere l'ottimizzatore
    x = Tab_dati.t_norm; % Vettore Predittore (Tempo X)
    y = Tab_dati.cobb_norm; % Vettore Risposta (Cobb Y)
    
    min_points_segment = 5; % Richiede che ogni segmento calcolato possieda almeno 5 visite radiografiche (previene segmenti basati su rumore)
    best_bic = Inf; % Inizializza il Bayesian Information Criterion al valore Massimo/Infinito (più è basso, migliore è il modello)
    best_model = []; % Vuoto in attesa della LME
    best_breaks = []; % Vuoto in attesa del Breakpoint
    best_Tab = []; % Vuoto in attesa della Tabella dati formattata per quel breakpoint
    
    % --- 2. RICERCA DEL MODELLO (Ottimizzazione tra 1, 2 e 3 segmenti) ---
    for k = 1:max_segments % Cicla i test: k=1 calcola retta lineare, k=2 cerca 1 ginocchio a V, k=3 cerca la conformazione a Z
        num_breaks = k - 1; % Traduce il numero dei segmenti in numero dei ginocchi (gomiti spezzata)
        T_fit = Tab_dati; % Ricopia i dati per elaborazione
        formula = 'cobb_norm ~ 1 + t_norm'; % Base logica matematica LME: VariabileY = intercetta + pendenza_base*VariabileX
        
        if num_breaks > 0 % Se cerco modelli spezzati (>1 segmento)...
            q = linspace(0, 1, num_breaks+2); % Crea i punti di divisione temporale equidistanti tra 0 e 1 (quantile)
            breaks = quantile(x, q); % Identifica i "tagli" sui valori x reali osservati
            breaks = breaks(2:end-1); % Estrae esclusivamente il posizionamento matematico dei nodi centrali (i breakpoints / ginocchi)
            
            % Validazione logica dei segmenti
            segment_limits = [min(x); breaks(:); max(x)]; % Estremi dell'ascissa
            valid = true; % Variabile booleana di sicurezza
            for s = 1:length(segment_limits)-1 % Conta empiricamente quante radiografie (punti) cadono nel segmento
                if s == length(segment_limits)-1
                    idx = x >= segment_limits(s) & x <= segment_limits(s+1);
                else
                    idx = x >= segment_limits(s) & x < segment_limits(s+1);
                end
                if sum(idx) < min_points_segment % Se i punti sono sotto soglia '5'
                    valid = false; % Rigetta l'ipotesi di spezzata, non calcola
                    break;
                end
            end
            if ~valid
                continue; % Interrompe l'analisi di questi segmenti e cerca un'alternativa con ginocchio spostato o modello menos complesso
            end
            
            % --- 3. CREAZIONE CERNIERE (Hinges) ---
            % L'algoritmo attiva funzioni matematiche "cerniera" (valori zero prima del nodo, pendenze dopo il nodo)
            for b = 1:length(breaks)
                varName = sprintf('Hinge%d', b); % Crea un nome univoco dinamico per la colonna cerniera, es. Hinge1
                T_fit.(varName) = max(0, x - breaks(b)); % Applicazione Hinge Function: Max(0, (X - nodo)). Restituisce pendenza o 0.
                formula = [formula, ' + ', varName]; % Aggiunge matematicamente la variabile all'equazione testuale per l'algoritmo FitLME
            end
        else
            breaks = []; % Nessun ginocchio: mantiene il modello lineare di default
        end
        
        % --- 4. RANDON INTERCEPT (Effetto Casuale del Paziente) ---
        formula = [formula, ' + (1 | id)']; % Istruzione Mista LME: Ricalcola l'intercetta basandola sulla differenza intrinseca del paziente 'id'
        
        try
            warning('off', 'stats:classreg:regr:lmeutils:StandardLinearMixedModel:Message_PerfectFit'); % Spegne il log warning fastidioso su fit perfetto
            mdl = fitlme(T_fit, formula); % Il motore MATLAB elabora l'enorme iterazione matematica dell'equazione LME
            warning('on', 'stats:classreg:regr:lmeutils:StandardLinearMixedModel:Message_PerfectFit'); % Ripristina
            
            bic = mdl.ModelCriterion.BIC; % Estrae il punteggio BIC (Bayesian Information Criterion). Bilancia precisione dell'errore (R^2) vs complessità numerica
            if bic < best_bic % Se questo modello ha battuto il record minimo precedente
                best_bic = bic; % Aggiorna il record
                best_model = mdl; % Sovrascrive il modello vincente
                best_breaks = breaks; % Salva il punto cronologico preciso del gomito
                best_Tab = T_fit; % Salva la griglia
            end
        catch
            continue; % Se il motore LME va in overflow numerico, salta alla prossima iterazione
        end
    end
    
    if isempty(best_model) % Se tutte e tre le complessità falliscono
        disp('  Errore LME: Impossibile fittare il modello su questo gruppo.'); % Impossibile dedurre matematica (es. troppi pochi punti/tanta deviazione)
        Tb = []; pearson_r = []; pearson_p = []; 
        return;
    end
    
    % --- 5. ESTRAZIONE E PURIFICAZIONE CORRELAZIONI ---
    y_pred_fixed = predict(best_model, best_Tab, 'Conditional', false); % 'Fixed Effects Only': Tira la linea bianca del trend globale ignorando il posizionamento altimetrico dei pazienti reali.
    
    %% ===== CORRELAZIONI SUI SINGOLI TRATTI (LME ADJUSTED) =====
    y_full = predict(best_model); % Previsione ibrida totale (somma la spezzata al Random Intercept individuale del paziente)
    y_fixed = predict(best_model, 'Conditional', false); % Previsione nuda della Pendenza aspecifica (Trend Globale)
    random_effects_contribution = y_full - y_fixed; % Isolamento algebrico: Estrae letteralmente quanto "peso/rumore" portava di svantaggio quel paziente preciso
    
    y_purificata = y - random_effects_contribution; % Allineamento: Sottrae ai dati grezzi tutto lo scarto individuale, forzando tutti i pazienti a poggiare geometricamente sullo stesso tracciato
    
    segment_limits = [min(x); best_breaks(:); max(x)]; % Limiti calcolati
    pearson_r_raw = []; pearson_r_adj = []; pearson_p_adj = []; % Resetta
    
    % Pre-inizializzazione output Excel
    target_out = NaN(1, length(segment_limits)-1);
    mu_out = NaN(1, length(segment_limits)-1);
    ptest_out = NaN(1, length(segment_limits)-1);
    
    for s = 1:length(segment_limits)-1 % Esamina i segmenti uno per uno per stampare la 'r' su ognuno
        if s == length(segment_limits)-1
            idx = x >= segment_limits(s) & x <= segment_limits(s+1);
        else
            idx = x >= segment_limits(s) & x < segment_limits(s+1);
        end
        x_seg = x(idx); % Estrae le X (ascisse del segmento)
        y_seg_raw = y(idx); % Estrae le Y grezze (ordinate, prima del purificatore LME)
        y_seg_adj = y_purificata(idx); % Estrae le Y Modificate/Adjusted (la purezza isolata dall'LME)
        
        if length(x_seg) >= 2 && length(unique(x_seg)) > 1 % Requisito: Almeno 2 coordinate per tracciare una linea e calcolare R
            r_raw = corr(x_seg, y_seg_raw, 'Type', 'Pearson'); % Calcola l'R di pearson primitivo e falso
            [r_adj, pval_adj] = corr(x_seg, y_seg_adj, 'Type', 'Pearson'); % Calcola l'R di Pearson PURIFICATO per certificare la reale risposta all'indossamento e restituisce la probabilità p
        else
            r_raw = NaN; r_adj = NaN; pval_adj = NaN;
        end
        pearson_r_raw = [pearson_r_raw, r_raw]; % Memorizza
        pearson_r_adj = [pearson_r_adj, r_adj]; % Memorizza il target definitivo
        pearson_p_adj = [pearson_p_adj, pval_adj]; % Memorizza il target probabilistico 
    end
    
    Tb = table(y, y_pred_fixed, 'VariableNames', {'y', 'y_pred_fixed'}); % Ricompone griglia
    Tb.X = x;
    
    % --- 6. PLOTTING VISUALE E REPORTISTICA ---
    figure; hold on; % Apro finestra e blocco lo svuotamento
    scatter(x, y, 20, [0.7 0.7 0.7], 'filled'); % Stampa Nuvola rumore primario in Grigio (#A9A9A9) per rendere visivo lo scarto dei pazienti
    scatter(x, y_purificata, 40, 'b', 'filled'); % Stampa Nuvola LME (Purificata) in forte Blu per evidenziare i pazienti allineati
    
    [x_sorted, sort_idx] = sort(x); % Ordina ascisse
    y_pred_sorted = y_pred_fixed(sort_idx); % Assegna a Ordinate
    plot(x_sorted, y_pred_sorted, 'r-', 'LineWidth', 3); % Traccia una spessa linea rossa che evidenzia il puro andamento asettico del trattamento
    
    for i = 1:length(best_breaks)
        xline(best_breaks(i), '--r', 'LineWidth', 1.5); % Disegna stanghetta verticale rossa nel punto radiografico del Gomito (es: passaggio da acuta a svezzamento)
    end
    
    % IDENTIFICAZIONE TARGET DELLA COSTANTE (Fine primo segmento) - FIX PER INTERP1
    if ~isempty(best_breaks)
        x_bp1 = best_breaks(1);
        [x_unici, indici_unici] = unique(x_sorted);
        y_fixed_ordinato = y_fixed(sort_idx);
        y_target = interp1(x_unici, y_fixed_ordinato(indici_unici), x_bp1);
    else
        y_target = 0; % Sicurezza se il modello risulta totalmente lineare
    end
    
    % --- STAMPA SU TERMINALE DEI RISULTATI ---
    fprintf('  Modello LME scelto: %d segmenti (BIC: %.2f)\n', length(best_breaks)+1, best_bic);
    if ~isempty(best_breaks)
        fprintf('  Breakpoints: '); disp(best_breaks');
    end
    fprintf('  --- DETTAGLIO SEGMENTI ---\n');
    
    % === AGGIORNAMENTO BOX ETICHETTA: METODO IBRIDO ===
    for s = 1:length(segment_limits)-1
        if s == length(segment_limits)-1
            idx = x >= segment_limits(s) & x <= segment_limits(s+1);
        else
            idx = x >= segment_limits(s) & x < segment_limits(s+1);
        end
        x_seg = x(idx);
        y_seg_raw = y(idx); % I dati grezzi originali (grigi)
        y_seg_adj = y_purificata(idx); % I dati purificati dall'LME (blu)
        
        if length(x_seg) >= 2 && ~isnan(pearson_r_adj(s))
            if s == 1
                % ==============================================
                % SEGMENTO 1 (ACUTO): Pearson Classico e RMSE
                % ==============================================
                coeffs_adj = polyfit(x_seg, y_seg_adj, 1); 
                xx_seg = linspace(min(x_seg), max(x_seg), 20); 
                yy_seg_adj = polyval(coeffs_adj, xx_seg); 
                plot(xx_seg, yy_seg_adj, 'k--', 'LineWidth', 1); % Tratteggia retta d'appoggio nera
                
                y_pred_adj = polyval(coeffs_adj, x_seg); 
                rmse_adj = sqrt(mean((y_seg_adj - y_pred_adj).^2)); % RMSE Purificato
                
                coeffs_raw = polyfit(x_seg, y_seg_raw, 1);
                y_pred_raw = polyval(coeffs_raw, x_seg);
                rmse_raw = sqrt(mean((y_seg_raw - y_pred_raw).^2)); % RMSE Grezzo
                
                % Output su Terminale
                fprintf('  Segmento %d (Acuta):\n', s);
                fprintf('    Pearson r = %.4f\n', pearson_r_adj(s));
                fprintf('    p-value   = %.2e\n', pearson_p_adj(s));
                fprintf('    RMSE_pur  = %.4f\n', rmse_adj);
                fprintf('    RMSE_grez = %.4f\n', rmse_raw);
                
                % Output su Grafico
                text(mean(x_seg), mean(y_seg_adj) + 0.20, ... 
                     sprintf('r = %.2f\np = %.2e\nRMSE_p = %.3f\nRMSE_g = %.3f', pearson_r_adj(s), pearson_p_adj(s), rmse_adj, rmse_raw), ...
                     'HorizontalAlignment', 'center', 'BackgroundColor', 'w', 'FontSize', 8, 'FontWeight', 'bold');
            else
                % ==============================================
                % SEGMENTI SUCCESSIVI (PLATEAU): T-Test (Costante)
                % ==============================================
                plot([min(x_seg), max(x_seg)], [y_target, y_target], '--', 'Color', [0 0.8 0], 'LineWidth', 1.5); % Tratteggia Target
                
                mu_seg = mean(y_seg_adj);
                [~, p_ttest] = ttest(y_seg_adj, y_target);
                
                % Memorizza risultati per Output funzione / Export Excel
                target_out(s) = y_target;
                mu_out(s) = mu_seg;
                ptest_out(s) = p_ttest;
                
                % Calcolo comunque gli RMSE per non perdere dati storici
                coeffs_adj = polyfit(x_seg, y_seg_adj, 1); 
                y_pred_adj = polyval(coeffs_adj, x_seg); 
                rmse_adj = sqrt(mean((y_seg_adj - y_pred_adj).^2)); 
                
                coeffs_raw = polyfit(x_seg, y_seg_raw, 1);
                y_pred_raw = polyval(coeffs_raw, x_seg);
                rmse_raw = sqrt(mean((y_seg_raw - y_pred_raw).^2)); 
                
                % Output su Terminale
                fprintf('  Segmento %d (Mantenimento):\n', s);
                fprintf('    Target    = %.4f\n', y_target);
                fprintf('    Media(Mu) = %.4f\n', mu_seg);
                fprintf('    p-Test    = %.4f\n', p_ttest);
                fprintf('    RMSE_pur  = %.4f\n', rmse_adj);
                fprintf('    RMSE_grez = %.4f\n', rmse_raw);
                
                % Output su Grafico
                text(mean(x_seg), y_target + 0.22, ... 
                     sprintf('Mu = %.2f | Tgt = %.2f\np-Test = %.2f\nRMSE_p = %.3f\nRMSE_g = %.3f', mu_seg, y_target, p_ttest, rmse_adj, rmse_raw), ...
                     'HorizontalAlignment', 'center', 'BackgroundColor', 'w', 'FontSize', 8, 'FontWeight', 'bold', 'EdgeColor', [0 0.8 0]);
            end
        end
    end
    fprintf('\n'); % Spazio finale nel terminale per ordinare i gruppi
    
    grid on; % Attiva griglia prospettica
    title(titolo, 'Interpreter', 'none'); % Assegna il nome (ignorando interpretazioni testuali latex fastidiose, tipo '_')
    xlabel('Tempo Terapia (Normalizzato)'); % Nomenclatura X
    ylabel('Variazione Cobb Angle'); % Nomenclatura Y
    legend('Dati Grezzi', 'Dati Purificati LME', 'Trend Terapia', 'Location', 'best'); % Genera la leggenda estetica
    
    % --- SISTEMA DI SALVATAGGIO SICURO CON NOME PASSATO ---
    saveas(gcf, fullfile(dirpath, file_ridotto)); 
    
    % Output Function Principale
    pearson_r = pearson_r_adj; % Associa risultato LME puro nell'Output Return della Main Function
    pearson_p = pearson_p_adj; % Associa p-Value puro nell'Output Return
    fprintf('  ---> Correlazione Grezza (Ignora LME): r = %.4f\n', pearson_r_raw(1)); % Feedback del paradosso
    fprintf('  ---> Correlazione LME (Trend Puro): r = %.4f (p-value = %.2e)\n', pearson_r_adj(1), pearson_p_adj(1)); % Risultato d'eccellenza in verde
end